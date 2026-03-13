import 'dart:async';

import 'package:camera/camera.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/live_call_mock_data.dart';
import 'package:expresto/models/live_call_data.dart';
import 'package:flutter/material.dart';

class LiveCallPage extends StatefulWidget {
  const LiveCallPage({super.key});

  @override
  State<LiveCallPage> createState() => _LiveCallPageState();
}

class _LiveCallPageState extends State<LiveCallPage> {
  CameraController? _cameraController;
  Future<void>? _cameraInitialization;
  String? _cameraError;
  late final Timer _callTimer;
  Duration _elapsed = Duration.zero;
  bool _isMuted = true;
  bool _isVideoOff = true;
  bool _showLocalAsMain = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraController?.dispose();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _cameraError = 'No camera available on this device.');
        return;
      }

      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      final initialization = controller.initialize();

      setState(() {
        _cameraController = controller;
        _cameraInitialization = initialization;
        _cameraError = null;
      });

      await initialization;
      if (!mounted) return;
      setState(() {});
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError =
            '${error.code}: ${error.description ?? 'Unable to access the camera.'}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Unable to start the live camera preview.\n$error';
      });
    }
  }

  @override
  void dispose() {
    _callTimer.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString();
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    const data = liveCallMockData;
    final callTime = _formatDuration(_elapsed);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF090B10), Color(0xFF040507)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
            child: Column(
              children: [
                _LiveCallHeader(
                  data: data,
                  onEnd: () => Navigator.pop(context),
                ),
                const SizedBox(height: 12),
                Expanded(
                  flex: 2,
                  child: _CameraStage(
                    data: data,
                    controller: _cameraController,
                    initialization: _cameraInitialization,
                    error: _cameraError,
                    isVideoOff: _isVideoOff,
                    showLocalAsMain: _showLocalAsMain,
                    onSwapFeeds: () {
                      setState(() {
                        _showLocalAsMain = !_showLocalAsMain;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(flex: 1, child: _TranscriptPanel(data: data)),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    callTime,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _CallControlsRow(
                  isMuted: _isMuted,
                  isVideoOff: _isVideoOff,
                  onToggleMute: () {
                    setState(() {
                      _isMuted = !_isMuted;
                    });
                  },
                  onToggleVideo: () {
                    setState(() {
                      _isVideoOff = !_isVideoOff;
                    });
                  },
                  onEndCall: () => Navigator.pop(context),
                  onOpenChat: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chat panel comes next.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  onMore: () {
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: AppColors.panel,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      builder: (context) {
                        return SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Call Options',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.volume_up_rounded,
                                    color: AppColors.textPrimary,
                                  ),
                                  title: const Text(
                                    'Speaker output',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Mock setting',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(context),
                                ),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.report_problem_rounded,
                                    color: AppColors.warning,
                                  ),
                                  title: const Text(
                                    'Report translation issue',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveCallHeader extends StatelessWidget {
  const _LiveCallHeader({required this.data, required this.onEnd});

  final LiveCallData data;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Call with ${data.contactName}',
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.w900,
        letterSpacing: -1,
      ),
    );
  }
}

class _CameraStage extends StatelessWidget {
  const _CameraStage({
    required this.data,
    required this.controller,
    required this.initialization,
    required this.error,
    required this.isVideoOff,
    required this.showLocalAsMain,
    required this.onSwapFeeds,
  });

  final LiveCallData data;
  final CameraController? controller;
  final Future<void>? initialization;
  final String? error;
  final bool isVideoOff;
  final bool showLocalAsMain;
  final VoidCallback onSwapFeeds;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF0B4A8C)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF031226), Color(0xFF020915)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: showLocalAsMain
                ? (isVideoOff
                      ? const _LiveCameraStatus(message: 'Camera is off')
                      : _LiveCameraFeed(
                          controller: controller,
                          initialization: initialization,
                          error: error,
                        ))
                : const _RemoteVideoPlaceholder(),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.24),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fiber_manual_record_rounded,
                      color: AppColors.blue,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      data.cameraLabel,
                      style: const TextStyle(
                        color: Color(0xFF49A2FF),
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!showLocalAsMain)
            const Center(
              child: Icon(
                Icons.person_rounded,
                color: Color(0xFF6DB6FF),
                size: 82,
              ),
            ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, right: 14),
              child: _FeedOverlay(
                showLocalPreview: !showLocalAsMain,
                controller: controller,
                initialization: initialization,
                error: error,
                isVideoOff: isVideoOff,
                onTap: onSwapFeeds,
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.only(right: 14, bottom: 14),
              child: _AvatarPiP(),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteVideoPlaceholder extends StatelessWidget {
  const _RemoteVideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071629), Color(0xFF030913), Color(0xFF0A2238)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 36,
            left: 24,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: const Color(0x221E90FF),
                borderRadius: BorderRadius.circular(46),
              ),
            ),
          ),
          Positioned(
            right: 32,
            bottom: 40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0x141E90FF),
                borderRadius: BorderRadius.circular(60),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedOverlay extends StatelessWidget {
  const _FeedOverlay({
    required this.showLocalPreview,
    required this.controller,
    required this.initialization,
    required this.error,
    required this.isVideoOff,
    required this.onTap,
  });

  final bool showLocalPreview;
  final CameraController? controller;
  final Future<void>? initialization;
  final String? error;
  final bool isVideoOff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 92,
        height: 126,
        decoration: BoxDecoration(
          color: const Color(0xFF111722),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF275B92), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showLocalPreview)
                (isVideoOff
                    ? const _LiveCameraStatus(message: 'Off')
                    : _LiveCameraFeed(
                        controller: controller,
                        initialization: initialization,
                        error: error,
                      ))
              else
                const _RemoteVideoPlaceholder(),
              Container(color: Colors.black.withValues(alpha: 0.12)),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Swap',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarPiP extends StatelessWidget {
  const _AvatarPiP();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D28).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F62A8), width: 2),
      ),
      child: const Center(
        child: Icon(
          Icons.interpreter_mode_rounded,
          color: AppColors.textPrimary,
          size: 30,
        ),
      ),
    );
  }
}

class _LiveCameraFeed extends StatelessWidget {
  const _LiveCameraFeed({
    required this.controller,
    required this.initialization,
    required this.error,
  });

  final CameraController? controller;
  final Future<void>? initialization;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return _LiveCameraStatus(message: error!);
    }
    if (controller == null || initialization == null) {
      return const _LiveCameraStatus(message: 'Starting camera...');
    }

    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LiveCameraStatus(message: 'Starting camera...');
        }
        if (snapshot.hasError) {
          return _LiveCameraStatus(
            message: 'Camera preview unavailable.\n${snapshot.error}',
          );
        }
        if (!controller!.value.isInitialized) {
          return const _LiveCameraStatus(
            message: 'Camera preview unavailable.',
          );
        }

        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller!.value.previewSize!.height,
            height: controller!.value.previewSize!.width,
            child: CameraPreview(controller!),
          ),
        );
      },
    );
  }
}

class _LiveCameraStatus extends StatelessWidget {
  const _LiveCameraStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF020915),
      alignment: Alignment.center,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      ),
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({required this.data});

  final LiveCallData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.chat_bubble_rounded,
                  color: AppColors.textMuted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  data.transcriptTitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...List.generate(data.messages.length, (index) {
              final item = data.messages[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == data.messages.length - 1 ? 0 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.speaker}  -  ${item.mode}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '"${item.message}"',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (item.confidenceLabel != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF24452E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_box_rounded,
                              color: item.statusColor,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              item.confidenceLabel!,
                              style: TextStyle(
                                color: item.statusColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (item.statusLabel != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: item.statusColor,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.statusLabel!,
                            style: TextStyle(
                              color: item.statusColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CallControlsRow extends StatelessWidget {
  const _CallControlsRow({
    required this.isMuted,
    required this.isVideoOff,
    required this.onToggleMute,
    required this.onToggleVideo,
    required this.onEndCall,
    required this.onOpenChat,
    required this.onMore,
  });

  final bool isMuted;
  final bool isVideoOff;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleVideo;
  final VoidCallback onEndCall;
  final VoidCallback onOpenChat;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    Widget button(
      IconData icon, {
      bool isPrimary = false,
      bool isActive = false,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: isPrimary ? 62 : 54,
          height: isPrimary ? 62 : 54,
          decoration: BoxDecoration(
            color: isPrimary
                ? AppColors.emergency
                : isActive
                ? AppColors.blue
                : const Color(0xFF1A1C25),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2B2F3D)),
          ),
          child: Icon(icon, color: Colors.white, size: isPrimary ? 28 : 24),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        button(
          isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          isActive: !isMuted,
          onTap: onToggleMute,
        ),
        button(
          isVideoOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          isActive: !isVideoOff,
          onTap: onToggleVideo,
        ),
        button(Icons.call_end_rounded, isPrimary: true, onTap: onEndCall),
        button(Icons.chat_bubble_rounded, onTap: onOpenChat),
        button(Icons.more_horiz_rounded, onTap: onMore),
      ],
    );
  }
}
