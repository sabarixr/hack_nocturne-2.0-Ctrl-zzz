// ignore_for_file: avoid_print
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/pages/practice.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen lesson page for a single ISL sign.
///
/// Plays the demo video from [sign.demoVideoUrl] if available.
/// Shows key points and a "Try It" guide (camera practice area kept
/// simple — no ML running here, just explanatory UI).
class LessonPage extends StatefulWidget {
  final SignEntry sign;

  const LessonPage({super.key, required this.sign});

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _videoError = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final url = widget.sign.demoVideoUrl;
    if (url.isEmpty) return;

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController = controller;

      await controller.initialize();
      controller.setLooping(true);
      controller.addListener(_onVideoUpdate);

      if (mounted) {
        setState(() => _videoReady = true);
      }
    } catch (e) {
      print('[LessonPage] video init error: $e');
      if (mounted) setState(() => _videoError = true);
    }
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    final playing = _videoController?.value.isPlaying ?? false;
    if (playing != _isPlaying) setState(() => _isPlaying = playing);
  }

  void _togglePlay() {
    final ctrl = _videoController;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
  }

  void _replay() {
    _videoController?.seekTo(Duration.zero);
    _videoController?.play();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sign = widget.sign;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, sign),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildVideoArea(sign),
                  const SizedBox(height: 12),
                  _buildKeyPoints(sign),
                  const SizedBox(height: 12),
                  _buildTryItPanel(sign),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, SignEntry sign) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              '${sign.label.toUpperCase()} — Sign Lesson',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.shellBorder),
              ),
              child: const Text(
                'Exit',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Video demonstration area ───────────────────────────────────────────────

  Widget _buildVideoArea(SignEntry sign) {
    return Container(
      height: 230,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
        color: const Color(0xFF020617),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video or fallback icon
          if (_videoReady && _videoController != null)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _videoError
                      ? Icons.broken_image_rounded
                      : Icons.sign_language_rounded,
                  size: 56,
                  color: AppColors.blue.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  _videoError
                      ? 'Video unavailable'
                      : sign.demoVideoUrl.isEmpty
                      ? 'No demo video'
                      : 'Loading…',
                  style: TextStyle(
                    color: AppColors.blue.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),

          // Controls overlay
          if (_videoReady)
            Positioned(
              bottom: 12,
              child: Row(
                children: [
                  _demoBtn(Icons.replay_rounded, 'Replay', onTap: _replay),
                  const SizedBox(width: 8),
                  _demoBtn(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    _isPlaying ? 'Pause' : 'Play',
                    onTap: _togglePlay,
                  ),
                ],
              ),
            ),

          // Sign label badge
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                sign.label.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.blue,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          // Critical badge
          if (sign.isCritical)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.emergencyDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.emergencyBorder),
                ),
                child: const Text(
                  'CRITICAL',
                  style: TextStyle(
                    color: AppColors.emergency,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _demoBtn(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── Key points ────────────────────────────────────────────────────────────

  Widget _buildKeyPoints(SignEntry sign) {
    if (sign.keyPoints.isEmpty && sign.description.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'KEY POINTS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          if (sign.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              sign.description,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
          if (sign.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...sign.keyPoints.map(
              (point) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, color: AppColors.blue, size: 7),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        point,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Try It panel ──────────────────────────────────────────────────────────

  Widget _buildTryItPanel(SignEntry sign) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.front_hand_outlined,
                color: AppColors.textPrimary,
                size: 16,
              ),
              SizedBox(width: 8),
              Text(
                'YOUR TURN',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0D14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.15),
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.videocam_rounded,
                  color: AppColors.success,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  'Practice "${sign.label.toUpperCase()}" in\nthe Emergency page with live detection',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _replay,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.shellBorder,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Replay Demo',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Next Sign',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
