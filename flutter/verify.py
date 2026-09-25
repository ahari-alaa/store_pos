#!/usr/bin/env python3
"""Static checks for the Flutter project.

There is no Dart SDK in this environment, so `flutter analyze` cannot be
run. This recovers the subset of its checks that matter most for
hand-written UI code: unresolved relative imports, unbalanced delimiters,
and — the big one — references to design-system members that do not
exist (`AppSpacing.huge`, `colors.borderr`, `context.text.heading`).
"""
import os
import re
import sys

LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'flutter_src', 'lib')

errors = []
warnings = []


def dart_files():
    for dirpath, _, names in os.walk(LIB):
        for n in sorted(names):
            if n.endswith('.dart'):
                yield os.path.join(dirpath, n)


def strip_code(src):
    """Remove comments and string literals so scans see real code only."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                i += 1
            i += 2
        elif c in '"\'':
            # triple quote?
            if src[i:i + 3] in ('"""', "'''"):
                q = src[i:i + 3]
                i += 3
                while i < n and src[i:i + 3] != q:
                    i += 2 if src[i] == '\\' else 1
                i += 3
            else:
                q = c
                i += 1
                out.append(' ')
                while i < n and src[i] != q:
                    if src[i] == '\\':
                        i += 1
                    if src[i] == '\n':
                        break
                    i += 1
                i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)


# ---------------------------------------------------------------- imports
for path in dart_files():
    src = open(path, encoding='utf-8').read()
    code = strip_code(src)
    rel = os.path.relpath(path, LIB)
    for m in re.finditer(r"import\s+'([^']+)'", src):
        target = m.group(1)
        if target.startswith(('package:', 'dart:')):
            continue
        # skip imports that appear inside doc comments
        line_start = src.rfind('\n', 0, m.start()) + 1
        if src[line_start:m.start()].lstrip().startswith('///'):
            continue
        resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
        if not os.path.exists(resolved):
            errors.append(f'{rel}: unresolved import {target!r}')

# ------------------------------------------------------------- delimiters
for path in dart_files():
    code = strip_code(open(path, encoding='utf-8').read())
    rel = os.path.relpath(path, LIB)
    for open_c, close_c, name in (('(', ')', 'paren'), ('{', '}', 'brace'), ('[', ']', 'bracket')):
        depth = 0
        for ch in code:
            if ch == open_c:
                depth += 1
            elif ch == close_c:
                depth -= 1
                if depth < 0:
                    errors.append(f'{rel}: unbalanced {name} (extra {close_c!r})')
                    break
        if depth > 0:
            errors.append(f'{rel}: unbalanced {name} ({depth} unclosed {open_c!r})')

# -------------------------------------------------- design-system members
def members_of(filename, classname):
    src = open(os.path.join(LIB, 'core', 'design', filename), encoding='utf-8').read()
    body = src[src.index(f'class {classname}'):]
    return set(re.findall(r'static\s+const\s+\w+(?:<[^>]+>)?\s+(\w+)\s*=', body)) | \
           set(re.findall(r'static\s+(?:final\s+)?\w+(?:<[^>]+>)?\s+(\w+)\s*\(', body))


TOKENS = {
    'AppSpacing': members_of('design_tokens.dart', 'AppSpacing'),
    'AppRadius': members_of('design_tokens.dart', 'AppRadius'),
    'AppSizes': members_of('design_tokens.dart', 'AppSizes'),
    'AppDurations': members_of('design_tokens.dart', 'AppDurations'),
}

shadow_src = open(os.path.join(LIB, 'core', 'design', 'app_shadows.dart'), encoding='utf-8').read()
TOKENS['AppShadows'] = set(re.findall(r'static\s+(?:const\s+)?[\w<>, ]+?\s(\w+)\s*(?:=|\()', shadow_src))

color_src = open(os.path.join(LIB, 'core', 'design', 'app_color_scheme.dart'), encoding='utf-8').read()
color_body = color_src[color_src.index('class AppColorScheme'):color_src.index('const AppColorScheme(')]
COLOR_MEMBERS = set(re.findall(r'final\s+Color\s+(\w+);', color_body))
COLOR_MEMBERS |= {'statusColor', 'statusSurface', 'copyWith', 'lerp'}

text_src = open(os.path.join(LIB, 'core', 'design', 'app_text_styles.dart'), encoding='utf-8').read()
TEXT_MEMBERS = set(re.findall(r'final\s+TextStyle\s+(\w+);', text_src))
TEXT_MEMBERS |= {'copyWith', 'lerp'}

for path in dart_files():
    code = strip_code(open(path, encoding='utf-8').read())
    rel = os.path.relpath(path, LIB)

    for cls, members in TOKENS.items():
        if not members:
            warnings.append(f'verifier: no members parsed for {cls}')
            continue
        for m in re.finditer(rf'\b{cls}\.(\w+)', code):
            if m.group(1) == '_':
                continue  # private constructor, e.g. AppSpacing._()
            if m.group(1) not in members:
                errors.append(f'{rel}: {cls}.{m.group(1)} does not exist')

    # `context.colors.x` / a local named `colors`
    for m in re.finditer(r'\bcolors\.(\w+)', code):
        if m.group(1) not in COLOR_MEMBERS:
            errors.append(f'{rel}: colors.{m.group(1)} is not an AppColorScheme member')
    # Only check `context.text.x`: a bare `text` is a very common local
    # variable name (a String, a palette colour) and would be all noise.
    for m in re.finditer(r'\bcontext\.text\.(\w+)', code):
        if m.group(1) not in TEXT_MEMBERS:
            errors.append(f'{rel}: context.text.{m.group(1)} is not an AppTextStyles member')
    # `final text = context.text;` then `text.x` — resolve that case.
    if re.search(r'\b(?:final|var)\s+text\s*=\s*context\.text\b', code):
        for m in re.finditer(r'(?<![\w.])text\.(\w+)', code):
            if m.group(1) not in TEXT_MEMBERS:
                errors.append(f'{rel}: text.{m.group(1)} is not an AppTextStyles member')

# ---------------------------------------------- design-system import check
NEEDS_DS = re.compile(r'\b(AppSpacing|AppRadius|AppSizes|AppDurations|AppShadows)\.|context\.colors|context\.text')
for path in dart_files():
    src = open(path, encoding='utf-8').read()
    code = strip_code(src)
    rel = os.path.relpath(path, LIB)
    if rel.startswith(os.path.join('core', 'design')):
        continue
    if NEEDS_DS.search(code):
        if 'design_system.dart' not in src and 'design_tokens.dart' not in src \
                and 'app_color_scheme.dart' not in src:
            errors.append(f'{rel}: uses design-system symbols but does not import it')

# ------------------------------------------- legacy AppColors import check
# Removing the `app_colors.dart` import from a partially-migrated file
# while a stale `AppColors.x` reference survives further down is exactly
# the mistake the compiler would catch and this script otherwise would
# not.
for path in dart_files():
    src = open(path, encoding='utf-8').read()
    code = strip_code(src)
    rel = os.path.relpath(path, LIB)
    if rel.endswith(os.path.join('theme', 'app_colors.dart')):
        continue
    if re.search(r'\bAppColors\.', code) and 'app_colors.dart' not in src:
        n = len(re.findall(r'\bAppColors\.', code))
        errors.append(f'{rel}: {n} reference(s) to AppColors but no import of app_colors.dart')

# --------------------------------------------------- translation key check
tr_src = open(os.path.join(LIB, 'core', 'l10n', 'translations.dart'), encoding='utf-8').read()
KEYS = set(re.findall(r"^\s*'([\w.]+)':\s*\{", tr_src, re.M))
for path in dart_files():
    src = open(path, encoding='utf-8').read()
    rel = os.path.relpath(path, LIB)
    for m in re.finditer(r"\btrRead?\(\s*ref\s*,\s*'([\w.]+)'\s*\)", src):
        if m.group(1) not in KEYS:
            errors.append(f'{rel}: translation key {m.group(1)!r} is not defined '
                          f'(would render as the raw key)')

# ---------------------------------------------- tr() outside build check
# `tr(ref, k)` calls ref.watch, which Riverpod asserts against outside
# `build`. Inside an async method or an event handler it is a runtime
# crash, not a compile error, so nothing else would catch it. `trRead`
# is the ref.read variant and is always safe.
for path in dart_files():
    code = strip_code(open(path, encoding='utf-8').read())
    rel = os.path.relpath(path, LIB)
    for m in re.finditer(r'^\s*(?:Future<[^>]*>|void)\s+_?\w+\s*\([^;]*?\)\s*(?:async\s*)?\{',
                         code, re.M):
        if 'build(' in m.group(0):
            continue
        start = m.end() - 1
        depth, i = 0, start
        while i < len(code):
            if code[i] == '{':
                depth += 1
            elif code[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = code[start:i]
        if re.search(r'(?<!trRead)(?<![\w])tr\(\s*ref\s*,', body):
            name = m.group(0).strip().split('(')[0].split()[-1]
            errors.append(f'{rel}: tr(ref, ...) called inside {name}() — '
                          f'ref.watch outside build; use trRead()')

# --------------------------------------------- unresolved project symbol
# The pos_header.dart / AppUserMenu incident: a class was renamed
# (UserMenuButton) but one call site still referenced the old name
# (AppUserMenu). That is a real compile error ("type not found") that
# none of the checks above catch, because it is not an import problem,
# not a design-token problem, and not a delimiter problem — it is a
# symbol that simply does not exist anywhere in the project.
#
# Strategy: collect every class/enum/mixin/typedef/extension declared
# anywhere in lib/. Then scan for PascalCase identifiers used as a
# constructor call (`Foo(`) that are not declared locally. Most such
# identifiers are legitimate framework types (Text, Container, Icons,
# ...) that this script has no source for, so a curated whitelist absorbs
# those. What is left after the whitelist is almost always either a
# genuine framework/package type this whitelist doesn't happen to know,
# or an actual drift bug — so those are reported as warnings UNLESS the
# name closely resembles a real project class (one name contains the
# other), in which case it is almost certainly the same rename-drift
# mistake and is reported as an error. A private (`_Foo`) identifier not
# declared anywhere in the project is always an error: there is no
# external package it could legitimately come from.
CLASS_DECL = re.compile(
    r'^\s*(?:abstract\s+|final\s+|base\s+|sealed\s+)*'
    r'(?:class|mixin|enum|extension)\s+(\w+)', re.M)
TYPEDEF_DECL = re.compile(r'^\s*typedef\s+(\w+)\s*=', re.M)

PROJECT_TYPES = set()
for path in dart_files():
    src = open(path, encoding='utf-8').read()
    PROJECT_TYPES |= set(CLASS_DECL.findall(src))
    PROJECT_TYPES |= set(TYPEDEF_DECL.findall(src))

_whitelist_text = """
Text RichText TextSpan TextStyle TextAlign TextOverflow TextDirection
TextEditingController TextInputType TextInputAction TextInputFormatter
TextButton TextField TextFormField
Icon Icons IconData IconButton IconThemeData
Container Column Row Stack Positioned PositionedDirectional Expanded
Flexible Padding Center Align Alignment AlignmentDirectional SizedBox
ConstrainedBox BoxConstraints DecoratedBox BoxDecoration BoxShadow
BorderRadius Border BorderSide BorderRadiusGeometry RoundedRectangleBorder
Radius ClipRRect ClipRect ClipOval OverflowBox FittedBox BoxFit
Wrap Spacer AspectRatio IntrinsicHeight IntrinsicWidth
Scaffold AppBar Drawer BottomNavigationBar BottomNavigationBarItem
FloatingActionButton SnackBar SnackBarAction ScaffoldMessenger
SnackBarBehavior
ListView ListTile GridView SliverGrid SliverList CustomScrollView
SingleChildScrollView ScrollController ScrollPhysics
AlwaysScrollableScrollPhysics NeverScrollableScrollPhysics
Dialog AlertDialog SimpleDialog PopupMenuButton PopupMenuItem
PopupMenuDivider PopupMenuPosition
Material InkWell InkResponse GestureDetector MouseRegion Focus FocusNode
FocusScope KeyEventResult KeyDownEvent KeyUpEvent LogicalKeyboardKey
HardwareKeyboard RawKeyEvent
Theme ThemeData ThemeExtension ColorScheme Brightness Color Colors
ColorFilter LinearGradient RadialGradient Gradient
Divider VerticalDivider Tooltip Chip ChoiceChip FilterChip InputChip
Card ListBody Table TableRow DataTable DataColumn DataRow DataCell
CircularProgressIndicator LinearProgressIndicator RefreshIndicator
AnimatedContainer AnimatedOpacity AnimatedSwitcher AnimatedBuilder
AnimatedCrossFade AnimatedPositioned Curves Curve Tween Animation
AnimationController TickerProviderStateMixin SingleTickerProviderStateMixin
Hero Opacity Transform Matrix4 Offset Size Rect EdgeInsets
EdgeInsetsGeometry EdgeInsetsDirectional
Navigator MaterialPageRoute PageRouteBuilder Route RouteSettings
FormField Form FormState GlobalKey Key ValueKey ObjectKey UniqueKey
LayoutBuilder OrientationBuilder MediaQuery MediaQueryData Orientation
StatefulWidget StatelessWidget State Widget BuildContext InheritedWidget
ValueListenableBuilder ValueNotifier ChangeNotifier
DateFormat NumberFormat DateTime Duration DateTimeRange
FilledButton ElevatedButton OutlinedButton ButtonStyle
MaterialStateProperty WidgetStateProperty MaterialTapTargetSize
Checkbox Radio Switch Slider DropdownButton DropdownButtonFormField
DropdownMenuItem
CircleAvatar Image ImageProvider NetworkImage AssetImage MemoryImage
FileImage DecorationImage
FontWeight FontStyle FontFeature TextDecoration
StringBuffer Comparable Iterable Iterator Map List Set String Object
Exception Error StackTrace Future Stream Completer
ConsumerWidget ConsumerStatefulWidget ConsumerState Consumer
StateNotifier StateNotifierProvider Provider ProviderScope
FutureProvider StreamProvider AsyncValue AsyncNotifier
GoRouter GoRoute ShellRoute GoRouterState
Uuid MultipartFile MultipartRequest MediaType
Printing Document Pdf PdfPageFormat
FilePicker FilePickerResult PlatformFile
FlutterSecureStorage
Uri Random
Locale Paint Canvas Path CustomPainter CustomPaint PaintingStyle
StrokeCap StrokeJoin Shadow MaskFilter PathMetric TextPainter
FocusTraversalOrder NumericFocusOrder
"""
KNOWN_EXTERNAL = set(_whitelist_text.split())

# Private (`_Foo`) identifiers are deliberately NOT checked here: in
# Dart a leading underscore marks *any* private declaration — methods,
# functions and fields just as much as classes — and private method
# calls (`_load()`, `_onDigit()`, ...) vastly outnumber private widget
# classes in normal code. Trying to tell them apart from constructor
# calls by shape alone produced far more noise than signal. Public
# PascalCase names are unambiguous: a public identifier immediately
# followed by `(` is always either a type this script knows about
# (project or whitelist) or a constructor/static call on one it doesn't.
for path in dart_files():
    src = open(path, encoding='utf-8').read()
    code = strip_code(src)
    rel = os.path.relpath(path, LIB)

    for m in re.finditer(r'(?<![.\w])([A-Z]\w*)\s*\(', code):
        name = m.group(1)
        if name in PROJECT_TYPES or name in KNOWN_EXTERNAL:
            continue
        # Resemblance test for the rename-drift signature (AppUserMenu vs
        # UserMenuButton): require that one name be a *prefix or suffix*
        # of the other, not merely a substring anywhere — "Locale" is a
        # substring of "LocaleNotifier" but the two are unrelated types,
        # whereas the real bug's pair share a long common tail ("UserMenu")
        # or head. A short shared fragment (<=4 chars) is too easy to hit
        # by accident, so it's excluded via the length floor below.
        def resembles(a, b):
            short, long_ = (a, b) if len(a) <= len(b) else (b, a)
            if len(short) <= 4:
                return False
            return long_.startswith(short) or long_.endswith(short) or \
                short.startswith(long_) or short.endswith(long_)

        close = [t for t in PROJECT_TYPES if t != name and resembles(t, name)]
        if close:
            errors.append(f'{rel}: {name}(...) is undefined — did you mean '
                          f'{close[0]}? ({close[0]} is declared in the '
                          f'project, {name} is not)')
        else:
            warnings.append(f'{rel}: {name}(...) not declared in the '
                            f'project and not in the whitelist — verify '
                            f'this is a real external type')

# ------------------------------------------------------------------ report
print(f'Scanned {len(list(dart_files()))} Dart files, {len(KEYS)} translation keys.\n')
if warnings:
    print(f'--- {len(warnings)} warning(s) ---')
    for w in sorted(set(warnings))[:40]:
        print('  ', w)
    print()
if errors:
    print(f'--- {len(errors)} ERROR(S) ---')
    for e in sorted(set(errors)):
        print('  ', e)
    sys.exit(1)
print('No errors.')
