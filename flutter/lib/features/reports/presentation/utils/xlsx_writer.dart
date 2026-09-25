import 'dart:convert';
import 'dart:typed_data';

/// Minimal, dependency-free .xlsx writer (multi-sheet, bold header cells,
/// 2-decimal money cells). An .xlsx is a ZIP of small XML files; this writes
/// them with the ZIP "stored" method (no compression), which every
/// spreadsheet application reads. Deliberately tiny: no shared strings
/// (text is written inline), no formulas, no merged cells.

/// One cell. A plain `String` / `num` / `null` can be used directly in a
/// row; use these constructors when a style is needed.
class XlsxCell {
  final Object? value;
  final bool bold;

  /// Number shown with two decimals (`0.00`).
  final bool money;

  const XlsxCell(this.value, {this.bold = false, this.money = false});
  const XlsxCell.header(String text) : this(text, bold: true);
  const XlsxCell.money(num value, {bool bold = false}) : this(value, bold: bold, money: true);
}

class XlsxSheet {
  final String name;
  final List<List<Object?>> rows;

  const XlsxSheet(this.name, this.rows);
}

class XlsxWriter {
  XlsxWriter._();

  static const _sheetNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _relNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const _pkgRelNs = 'http://schemas.openxmlformats.org/package/2006/relationships';

  static Uint8List build(List<XlsxSheet> sheets) {
    assert(sheets.isNotEmpty);
    final names = _uniqueNames(sheets.map((s) => s.name).toList());

    final files = <String, List<int>>{};
    files['[Content_Types].xml'] = utf8.encode(_contentTypes(sheets.length));
    files['_rels/.rels'] = utf8.encode(_rootRels());
    files['xl/workbook.xml'] = utf8.encode(_workbook(names));
    files['xl/_rels/workbook.xml.rels'] = utf8.encode(_workbookRels(sheets.length));
    files['xl/styles.xml'] = utf8.encode(_styles());
    for (var i = 0; i < sheets.length; i++) {
      files['xl/worksheets/sheet${i + 1}.xml'] = utf8.encode(_sheet(sheets[i]));
    }
    return _zipStored(files);
  }

  // ---- XML parts -----------------------------------------------------

  static String _contentTypes(int sheetCount) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
      ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    for (var i = 1; i <= sheetCount; i++) {
      b.write('<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    b.write('</Types>');
    return b.toString();
  }

  static String _rootRels() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="$_pkgRelNs">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static String _workbook(List<String> names) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<workbook xmlns="$_sheetNs" xmlns:r="$_relNs"><sheets>');
    for (var i = 0; i < names.length; i++) {
      b.write('<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    }
    b.write('</sheets></workbook>');
    return b.toString();
  }

  static String _workbookRels(int sheetCount) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="$_pkgRelNs">');
    for (var i = 1; i <= sheetCount; i++) {
      b.write('<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>');
    }
    b.write('<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
    b.write('</Relationships>');
    return b.toString();
  }

  // Style ids used by [_sheet]: 0 normal, 1 bold, 2 money, 3 bold money.
  static String _styles() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="$_sheetNs">'
      '<fonts count="2">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="4">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="2" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';

  static String _sheet(XlsxSheet sheet) {
    // Column widths from the longest text in each column (capped).
    final widths = <int, int>{};
    for (final row in sheet.rows) {
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        final raw = cell is XlsxCell ? cell.value : cell;
        if (raw == null) continue;
        final length = raw is num ? raw.toStringAsFixed(2).length : '$raw'.length;
        if (length > (widths[c] ?? 0)) widths[c] = length;
      }
    }

    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="$_sheetNs">');
    if (widths.isNotEmpty) {
      b.write('<cols>');
      final columns = widths.keys.toList()..sort();
      for (final c in columns) {
        final w = (widths[c]! + 3).clamp(8, 52);
        b.write('<col min="${c + 1}" max="${c + 1}" width="$w" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        final value = cell is XlsxCell ? cell.value : cell;
        if (value == null) continue;
        final bold = cell is XlsxCell && cell.bold;
        final money = cell is XlsxCell && cell.money;
        final ref = '${_columnName(c)}${r + 1}';
        if (value is num) {
          final style = money ? (bold ? 3 : 2) : (bold ? 1 : 0);
          final number = value is int ? '$value' : value.toStringAsFixed(2);
          b.write('<c r="$ref" s="$style"><v>$number</v></c>');
        } else {
          final style = bold ? 1 : 0;
          b.write('<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_esc('$value')}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  // ---- helpers -------------------------------------------------------

  /// 0 -> A, 25 -> Z, 26 -> AA ...
  static String _columnName(int index) {
    var n = index + 1;
    final letters = <int>[];
    while (n > 0) {
      final rem = (n - 1) % 26;
      letters.add(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return String.fromCharCodes(letters.reversed);
  }

  /// XML-escapes and drops characters XML 1.0 cannot carry.
  static String _esc(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      final legal = rune == 0x9 ||
          rune == 0xA ||
          rune == 0xD ||
          (rune >= 0x20 && rune <= 0xD7FF) ||
          (rune >= 0xE000 && rune <= 0xFFFD) ||
          (rune >= 0x10000 && rune <= 0x10FFFF);
      if (!legal) continue;
      switch (rune) {
        case 0x26:
          out.write('&amp;');
          break;
        case 0x3C:
          out.write('&lt;');
          break;
        case 0x3E:
          out.write('&gt;');
          break;
        case 0x22:
          out.write('&quot;');
          break;
        case 0x27:
          out.write('&apos;');
          break;
        default:
          out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  /// Excel sheet names: max 31 chars, none of `[]:*?/\`, unique.
  static List<String> _uniqueNames(List<String> raw) {
    final used = <String>{};
    final result = <String>[];
    for (final name in raw) {
      var clean = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
      if (clean.isEmpty) clean = 'Feuille';
      if (clean.length > 31) clean = clean.substring(0, 31);
      var candidate = clean;
      var n = 2;
      while (used.contains(candidate.toLowerCase())) {
        final suffix = ' $n';
        candidate = '${clean.substring(0, clean.length > 31 - suffix.length ? 31 - suffix.length : clean.length)}$suffix';
        n++;
      }
      used.add(candidate.toLowerCase());
      result.add(candidate);
    }
    return result;
  }

  // ---- ZIP (stored, no compression) -----------------------------------

  static final List<int> _crcTable = () {
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    return table;
  }();

  static int _crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final byte in data) {
      c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static void _u16(BytesBuilder b, int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
  }

  static void _u32(BytesBuilder b, int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
    b.addByte((v >> 16) & 0xFF);
    b.addByte((v >> 24) & 0xFF);
  }

  static Uint8List _zipStored(Map<String, List<int>> files) {
    const dosTime = 0; // 00:00:00
    const dosDate = 33; // 1980-01-01
    const utf8Flag = 0x0800;

    final out = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    var entries = 0;

    files.forEach((name, data) {
      final nameBytes = utf8.encode(name);
      final crc = _crc32(data);
      final offset = out.length;

      // Local file header
      _u32(out, 0x04034b50);
      _u16(out, 20);
      _u16(out, utf8Flag);
      _u16(out, 0); // method: stored
      _u16(out, dosTime);
      _u16(out, dosDate);
      _u32(out, crc);
      _u32(out, data.length);
      _u32(out, data.length);
      _u16(out, nameBytes.length);
      _u16(out, 0);
      out.add(nameBytes);
      out.add(data);

      // Central directory header
      _u32(central, 0x02014b50);
      _u16(central, 20);
      _u16(central, 20);
      _u16(central, utf8Flag);
      _u16(central, 0);
      _u16(central, dosTime);
      _u16(central, dosDate);
      _u32(central, crc);
      _u32(central, data.length);
      _u32(central, data.length);
      _u16(central, nameBytes.length);
      _u16(central, 0);
      _u16(central, 0);
      _u16(central, 0);
      _u16(central, 0);
      _u32(central, 0);
      _u32(central, offset);
      central.add(nameBytes);
      entries++;
    });

    final centralOffset = out.length;
    final centralBytes = central.toBytes();
    out.add(centralBytes);

    // End of central directory
    _u32(out, 0x06054b50);
    _u16(out, 0);
    _u16(out, 0);
    _u16(out, entries);
    _u16(out, entries);
    _u32(out, centralBytes.length);
    _u32(out, centralOffset);
    _u16(out, 0);

    return out.toBytes();
  }
}
