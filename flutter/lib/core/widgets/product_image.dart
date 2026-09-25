import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

import '../theme/app_colors.dart';

/// Clears Flutter's in-memory [imageCache].
///
/// [Image.network] (used here and in `ProductCard`) caches a *failed*
/// load by URL and won't retry it on its own even after the resource
/// becomes fetchable — e.g. if the backend wasn't serving `/uploads` yet,
/// or a file hadn't finished writing, the first time it was requested.
/// Without this, a photo that failed once stays a placeholder for the
/// rest of the app session, even after a pull-to-refresh, until a full
/// restart clears Flutter's in-memory cache.
///
/// A blanket `clear()` (rather than evicting one URL) is used because
/// `cacheWidth`/`cacheHeight` (used both here and in `ProductCard`) make
/// `Image` resolve through a `ResizeImage` wrapper, so the real cache key
/// isn't just `NetworkImage(url)` — evicting that exact key reliably
/// would mean replicating each call site's resize params. A full clear
/// is simpler and safe here since it only runs after an explicit
/// products (re)fetch, not on every rebuild.
///
/// Called every time product data is (re)fetched (see
/// `ProductsManageNotifier.refresh` and `productsProvider`) so a
/// previously-failed photo gets a genuine retry as soon as fresh data
/// comes in, without requiring the user to restart the app.
void clearProductImageCache() {
  imageCache.clear();
  imageCache.clearLiveImages();
}

/// Renders a product photo with a consistent loading/placeholder/error
/// story everywhere a product image shows up (management list, edit
/// dialog, ...). The POS grid's [ProductCard] intentionally keeps its own
/// inline `Image.network` since it already implements the same contract
/// with grid-specific styling (category color, `BoxFit.contain`).
///
/// Contract:
///   * `imageUrl == null || imageUrl.isEmpty` -> placeholder icon.
///   * still fetching                          -> small progress indicator.
///   * request fails / 404 / bad data          -> placeholder icon.
/// Never lets an `Image.network` failure escape as an uncaught exception
/// or a broken-image icon.
class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit fit;
  final IconData placeholderIcon;
  final Color? placeholderIconColor;
  final Color? backgroundColor;
  final double? iconSize;
  final int? cacheWidth;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.inventory_2_outlined,
    this.placeholderIconColor,
    this.backgroundColor,
    this.iconSize,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final bg = backgroundColor ?? AppColors.background;

    if (url == null || url.isEmpty) {
      return _placeholder(bg);
    }

    return Container(
      color: bg,
      child: Image.network(
        url,
        fit: fit,
        cacheWidth: cacheWidth,
        // Loading: small centered spinner instead of a blank/broken frame.
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: (iconSize ?? 20) * 0.7,
              height: (iconSize ?? 20) * 0.7,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: (placeholderIconColor ?? AppColors.textMuted).withOpacity(0.6),
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        (progress.expectedTotalBytes ?? 1)
                    : null,
              ),
            ),
          );
        },
        // Any failure (404, malformed URL, unreachable host, decode
        // error, ...) falls back to the placeholder instead of the
        // default broken-image icon or an uncaught exception. Logged via
        // debugPrint (visible in `flutter run`'s console / VS Code debug
        // console) so a real failure reason is diagnosable instead of
        // every failure looking identical from the UI.
        errorBuilder: (_, error, __) {
          debugPrint('ProductImage: failed to load "$url" -> $error');
          return _placeholder(bg);
        },
      ),
    );
  }

  Widget _placeholder(Color bg) {
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Icon(
        placeholderIcon,
        color: placeholderIconColor ?? AppColors.textMuted,
        size: iconSize ?? 20,
      ),
    );
  }
}
