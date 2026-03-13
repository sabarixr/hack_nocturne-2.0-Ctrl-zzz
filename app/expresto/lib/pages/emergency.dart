import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/emergency_mock_data.dart';
import 'package:expresto/models/emergency_session_data.dart';
import 'package:expresto/pages/bystander.dart';
import 'package:expresto/pages/silent_emergency.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cameraGlowController;
  CameraController? _cameraController;
  Future<void>? _cameraInitialization;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _cameraGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraController?.dispose();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _cameraError = 'No camera available on this device.';
        });
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
      if (!mounted) {
        return;
      }
      setState(() {});
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraError =
            '${error.code}: ${error.description ?? 'Unable to access the camera.'}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraError = 'Unable to start the live camera preview.\n$error';
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _cameraGlowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const data = emergencyMockData;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 44,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 18,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
        ),
        title: const Text(
          'Active Call',
          style: TextStyle(
            color: AppColors.emergency,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF090B10), Color(0xFF040507)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cameraHeight = constraints.maxHeight * 0.53;

              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: cameraHeight,
                      child: _CameraPanel(
                        animation: _cameraGlowController,
                        data: data,
                        cameraController: _cameraController,
                        cameraInitialization: _cameraInitialization,
                        cameraError: _cameraError,
                        onEndCall: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _UrgencyPanel(data: data),
                            const SizedBox(height: 12),
                            _OperatorPanel(data: data),
                            const SizedBox(height: 12),
                            _ActionsPanel(data: data),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _BottomActionButton(
                                    icon: Icons.groups_rounded,
                                    label: 'Bystander',
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const BystanderPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.animation,
    required this.data,
    required this.cameraController,
    required this.cameraInitialization,
    required this.cameraError,
    required this.onEndCall,
  });

  final Animation<double> animation;
  final EmergencySessionData data;
  final CameraController? cameraController;
  final Future<void>? cameraInitialization;
  final String? cameraError;
  final VoidCallback onEndCall;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(animation.value);
        final glowColor =
            Color.lerp(const Color(0xFF0B5B37), const Color(0xFF1CFF8A), t) ??
            AppColors.success;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF0C7948)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF04191A), Color(0xFF03151B), Color(0xFF071114)],
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: 0.22),
                blurRadius: 34,
                spreadRadius: -3,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: _CameraFeed(
              controller: cameraController,
              initialization: cameraInitialization,
              error: cameraError,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.22),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.cameraHint,
                    style: const TextStyle(
                      color: Color(0xFF15DF6D),
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: Container(
              width: 160,
              height: 118,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF13C86C), width: 2),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: 12),
              child: _AvatarPreview(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SilentEmergencyPage(),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF202532),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(132, 54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'Silent',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: onEndCall,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emergency,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(148, 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'End Call',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D28).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF36354C), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.interpreter_mode_rounded,
          color: AppColors.textPrimary,
          size: 34,
        ),
      ),
    );
  }
}

class _CameraFeed extends StatelessWidget {
  const _CameraFeed({
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
      return _CameraStatus(message: error!);
    }

    if (controller == null || initialization == null) {
      return const _CameraStatus(message: 'Starting camera...');
    }

    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _CameraStatus(message: 'Starting camera...');
        }

        if (snapshot.hasError) {
          return _CameraStatus(
            message: 'Camera preview unavailable.\n${snapshot.error}',
          );
        }

        if (!controller!.value.isInitialized) {
          return const _CameraStatus(message: 'Camera preview unavailable.');
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

class _CameraStatus extends StatelessWidget {
  const _CameraStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF071114),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1CFF8A)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _UrgencyPanel extends StatelessWidget {
  const _UrgencyPanel({required this.data});

  final EmergencySessionData data;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      borderColor: AppColors.emergencyBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.urgencyLabel,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F1D29),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF4F59),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      data.urgencyStatus,
                      style: const TextStyle(
                        color: Color(0xFFFF4F59),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${data.urgencyPercent}%',
            style: const TextStyle(
              color: AppColors.emergency,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.urgencyBars
                  .map(
                    (bar) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          height: bar * 3.2,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8E3249),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _OperatorPanel extends StatelessWidget {
  const _OperatorPanel({required this.data});

  final EmergencySessionData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF096E3E)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF021B14), Color(0xFF03110D), Color(0xFF041810)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.support_agent_rounded,
                color: Color(0xFF1CFF8A),
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
                'OPERATOR RESPONSE',
                style: TextStyle(
                  color: Color(0xFF1CFF8A),
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 8),
                child: Icon(
                  Icons.emergency_rounded,
                  color: AppColors.textPrimary,
                  size: 26,
                ),
              ),
              Expanded(
                child: Text(
                  data.operatorTitle,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.timer_outlined,
                color: AppColors.textPrimary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                data.operatorEta,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel({required this.data});

  final EmergencySessionData data;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.task_alt_rounded,
                color: AppColors.success,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                data.actionsTitle,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(data.actions.length, (index) {
            final action = data.actions[index];
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: index == data.actions.length - 1
                      ? BorderSide.none
                      : const BorderSide(color: AppColors.divider),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Icon(
                      action.icon,
                      color: const Color(0xFFC9C9DA),
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      action.label,
                      style: const TextStyle(
                        color: Color(0xFFC9C9DA),
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BottomActionButton extends StatelessWidget {
  const _BottomActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.panelSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.shellBorder.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.textPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({this.borderColor, required this.child});

  final Color? borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? AppColors.shellBorder),
      ),
      child: child,
    );
  }
}
