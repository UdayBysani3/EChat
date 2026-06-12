import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';

class FullScreenImageView extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const FullScreenImageView({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ObsidianMintColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: ObsidianMintColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Center(
          child: Hero(
            tag: heroTag,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => Center(
                  child: CircularProgressIndicator(
                    color: ObsidianMintColors.primary,
                  ),
                ),
                errorWidget: (context, url, error) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: ObsidianMintColors.error,
                      size: 48,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Failed to load image',
                      style: TextStyle(color: ObsidianMintColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
