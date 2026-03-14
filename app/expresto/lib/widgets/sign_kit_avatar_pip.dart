import 'package:expresto/core/theme/app_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class SignKitAvatarPiP extends StatelessWidget {
  const SignKitAvatarPiP({
    super.key,
    this.width = 78,
    this.height = 78,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.predictedSign,
    this.showStatusLabel = true,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;
  final String? predictedSign;
  final bool showStatusLabel;

  @override
  Widget build(BuildContext context) {
    final signLabel = (predictedSign == null || predictedSign!.trim().isEmpty)
        ? 'idle'
        : predictedSign!.trim().toUpperCase();

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D28).withValues(alpha: 0.94),
        borderRadius: borderRadius,
        border: Border.all(color: const Color(0xFF1F62A8), width: 2),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_supportsModelViewer)
              const ModelViewer(
                src: 'assets/avatars/xbot.glb',
                alt: 'Sign-Kit avatar',
                ar: false,
                autoRotate: true,
                cameraControls: true,
                disableZoom: true,
              )
            else
              const _AvatarUnsupportedFallback(),
            if (showStatusLabel)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Text(
                    signLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AvatarUnsupportedFallback extends StatelessWidget {
  const _AvatarUnsupportedFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C0F17),
      alignment: Alignment.center,
      child: const Icon(
        Icons.interpreter_mode_rounded,
        color: AppColors.textPrimary,
        size: 28,
      ),
    );
  }
}

bool get _supportsModelViewer =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
