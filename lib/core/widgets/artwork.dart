import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/media_url.dart';

/// Album/artist artwork with a graceful placeholder.
///
/// Artwork URLs are usually absent in a fresh catalogue, and they are always absent offline.
/// Rendering a deterministic gradient with the entity's initial means a list never shows a broken
/// image icon, and the same album always gets the same colour.
///
/// It is a `ConsumerWidget` for one reason: artwork URLs arrive from the API **relative** unless the
/// deployment configures a public base URL, and an image loader cannot resolve a relative path. See
/// [resolveMediaUrl].
class Artwork extends ConsumerWidget {
  const Artwork({
    super.key,
    required this.imageUrl,
    required this.seed,
    this.size = 56,
    this.borderRadius = 8,
    this.isCircle = false,
  });

  final String? imageUrl;

  /// Stable identity (song/album/artist id) used to pick the placeholder colour.
  final String seed;
  final double size;
  final double borderRadius;
  final bool isCircle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BorderRadius radius = BorderRadius.circular(isCircle ? size / 2 : borderRadius);
    final String? resolved =
        resolveMediaUrl(imageUrl, ref.watch(appConfigProvider).apiBaseUrl);

    final Widget placeholder = _Placeholder(seed: seed, size: size, label: _initial);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: (resolved == null || resolved.isEmpty)
            ? placeholder
            : CachedNetworkImage(
                imageUrl: resolved,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (BuildContext context, String url) => placeholder,
                errorWidget: (BuildContext context, String url, Object error) => placeholder,
              ),
      ),
    );
  }

  String get _initial {
    if (seed.isEmpty) {
      return '♪';
    }
    return seed.substring(0, 1).toUpperCase();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.seed, required this.size, required this.label});

  final String seed;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color base = AppColors.placeholderFor(seed, dark: dark);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[base, Color.lerp(base, Colors.black, dark ? 0.35 : 0.12)!],
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w700,
            color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}
