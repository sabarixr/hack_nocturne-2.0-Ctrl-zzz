// ignore_for_file: avoid_print
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:expresto/core/ml/bayesian_urgency_engine.dart';
import 'package:expresto/core/sign_recognizer.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/silent_mode_mock_data.dart';
import 'package:expresto/models/silent_mode_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Silent emergency mode.
///
/// Receives the [callId] from the active emergency so the ML pipeline can
/// continue submitting frames to the operator dashboard.
///
/// Haptic patterns (triggered on urgency level transitions):
///   < 30%  → 1 short pulse  — "Message received"
///   30–60% → 2 short pulses — "Help dispatched"
///   60–85% → 3 short pulses — "Stay where you are"
///   > 85%  → long + short   — "DANGER — MOVE NOW"
class SilentEmergencyPage extends StatefulWidget {
  final String? callId;

  const SilentEmergencyPage({super.key, this.callId});

  @override
  State<SilentEmergencyPage> createState() => _SilentEmergencyPageState();
}

class _SilentEmergencyPageState extends State<SilentEmergencyPage> {
  // ── Triple-tap to exit ──────────────────────────────────────────────────
  int _tapCount = 0;
  DateTime? _lastTap;

  // ── Camera / ML ─────────────────────────────────────────────────────────
  CameraController? _camera;
  SignRecognizerService? _recognizer;
  StreamSubscription<UrgencyUpdate>? _urgencySub;

  // ── Current urgency level ───────────────────────────────────────────────
  _HapticLevel _currentLevel = _HapticLevel.none;
  String _statusText = 'CAMERA ACTIVE — MONITORING';
  bool _cameraReady = false;
  bool _faceDetected = false;
  bool _handDetected = false;

  // ── Vibration capability flag ────────────────────────────────────────────
  bool _canVibrate = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _checkVibration();
  }

  @override
  void dispose() {
    _urgencySub?.cancel();
    _recognizer?.stopProcessing();
    _camera?.dispose();
    super.dispose();
  }

  // ── Vibration ────────────────────────────────────────────────────────────

  Future<void> _checkVibration() async {
    final has = await Vibration.hasVibrator() ?? false;
    if (mounted) setState(() => _canVibrate = has);
  }

  /// Fire the haptic pattern corresponding to the current urgency level.
  Future<void> _vibrate(_HapticLevel level) async {
    if (!_canVibrate) {
      // Fallback to system haptic if vibration package unavailable
      HapticFeedback.heavyImpact();
      return;
    }
    switch (level) {
      case _HapticLevel.low:
        // 1 short pulse — "Message received"
        await Vibration.vibrate(duration: 120);
      case _HapticLevel.medium:
        // 2 short pulses — "Help dispatched"
        await Vibration.vibrate(pattern: [0, 120, 150, 120]);
      case _HapticLevel.high:
        // 3 short pulses — "Stay where you are"
        await Vibration.vibrate(pattern: [0, 120, 150, 120, 150, 120]);
      case _HapticLevel.critical:
        // Long + short — "DANGER — MOVE NOW"
        await Vibration.vibrate(pattern: [0, 600, 150, 180]);
      case _HapticLevel.none:
        break;
    }
  }

  // ── Camera initialisation ─────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.low, // silent mode — keep it power-efficient
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _camera = controller;
        _cameraReady = true;
      });

      // Start ML only if we have a callId
      final callId = widget.callId;
      if (callId != null) {
        _recognizer = SignRecognizerService(callId: callId);
        await _recognizer!.loadCalibration();
        await _recognizer!.startProcessing(controller);

        _urgencySub = _recognizer!.urgencyStream.listen(_onUrgencyUpdate);
        print('[SilentMode] ML pipeline started for call $callId');
      } else {
        print('[SilentMode] no callId — ML pipeline inactive');
      }
    } catch (e) {
      print('[SilentMode] camera init error: $e');
    }
  }

  // ── Urgency stream handler ────────────────────────────────────────────────

  void _onUrgencyUpdate(UrgencyUpdate update) {
    final score = update.urgencyScore;
    final newLevel = _HapticLevel.fromScore(score);

    // Only trigger haptic when level changes upward (avoid spam)
    if (newLevel.index > _currentLevel.index) {
      _vibrate(newLevel);
    }

    if (!mounted) return;
    setState(() {
      _currentLevel = newLevel;
      _statusText = _labelForLevel(newLevel, score);
      _faceDetected = update.faceDetected;
      _handDetected = update.handDetected;
    });
  }

  String _labelForLevel(_HapticLevel level, double score) {
    final pct = (score * 100).toStringAsFixed(0);
    switch (level) {
      case _HapticLevel.none:
        return 'CAMERA ACTIVE — MONITORING';
      case _HapticLevel.low:
        return 'SIGNAL SENT — $pct% URGENCY';
      case _HapticLevel.medium:
        return 'HELP DISPATCHED — $pct% URGENCY';
      case _HapticLevel.high:
        return 'STAY HIDDEN — $pct% URGENCY';
      case _HapticLevel.critical:
        return 'DANGER — MOVE NOW — $pct%';
    }
  }

  // ── Triple-tap exit ──────────────────────────────────────────────────────

  void _registerTap() {
    final now = DateTime.now();
    if (_lastTap == null ||
        now.difference(_lastTap!) > const Duration(seconds: 1)) {
      _tapCount = 0;
    }
    _lastTap = now;
    _tapCount += 1;

    if (_tapCount >= 3) {
      Navigator.pop(context);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const data = silentModeMockData;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _registerTap,
      child: Scaffold(
        backgroundColor: const Color(0xFF040507),
        body: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF07080C), Color(0xFF020304)],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SilentHeader(data: data),
                    const SizedBox(height: 16),
                    _BrightnessRow(label: data.brightnessLabel),
                    const SizedBox(height: 22),
                    _CameraStatusCard(
                      label: _statusText,
                      level: _currentLevel,
                      cameraReady: _cameraReady,
                      faceDetected: _faceDetected,
                      handDetected: _handDetected,
                    ),
                    const SizedBox(height: 18),
                    _StatusPanel(items: data.statusItems),
                    const SizedBox(height: 18),
                    _HapticPanel(data: data, activeLevel: _currentLevel),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        data.exitHint,
                        style: const TextStyle(
                          color: Color(0xFF4E5364),
                          fontSize: 14,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
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

// ── Urgency level enum ────────────────────────────────────────────────────────

enum _HapticLevel {
  none, // < 5%  — no signal yet
  low, // 5–30% — "Message received"
  medium, // 30–60% — "Help dispatched"
  high, // 60–85% — "Stay where you are"
  critical; // > 85% — "DANGER — MOVE NOW"

  static _HapticLevel fromScore(double score) {
    if (score >= 0.85) return _HapticLevel.critical;
    if (score >= 0.60) return _HapticLevel.high;
    if (score >= 0.30) return _HapticLevel.medium;
    if (score >= 0.05) return _HapticLevel.low;
    return _HapticLevel.none;
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SilentHeader extends StatelessWidget {
  const _SilentHeader({required this.data});

  final SilentModeData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              const Icon(
                Icons.do_not_disturb_alt,
                color: AppColors.textPrimary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                data.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFF11141B),
            foregroundColor: const Color(0xFF666D7C),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(data.cancelLabel),
        ),
      ],
    );
  }
}

class _BrightnessRow extends StatelessWidget {
  const _BrightnessRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '*  $label',
            style: const TextStyle(
              color: Color(0xFF4B5160),
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          width: 70,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF0E1117),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.centerLeft,
          child: Container(
            width: 12,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF8F97A8),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraStatusCard extends StatelessWidget {
  const _CameraStatusCard({
    required this.label,
    required this.level,
    required this.cameraReady,
    this.faceDetected = false,
    this.handDetected = false,
  });

  final String label;
  final _HapticLevel level;
  final bool cameraReady;
  final bool faceDetected;
  final bool handDetected;

  @override
  Widget build(BuildContext context) {
    final borderColor = level == _HapticLevel.critical
        ? AppColors.emergency.withValues(alpha: 0.6)
        : level == _HapticLevel.high
        ? AppColors.warning.withValues(alpha: 0.4)
        : const Color(0xFF11151E);

    final textColor = level == _HapticLevel.critical
        ? AppColors.emergency
        : level == _HapticLevel.high
        ? AppColors.warning
        : const Color(0xFF202632);

    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  cameraReady
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  color: textColor,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    letterSpacing: 1.2,
                    fontWeight: level.index >= _HapticLevel.high.index
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (cameraReady)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF25D24F),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          if (cameraReady)
            Positioned(
              bottom: 10,
              left: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SilentDetectionBadge(label: 'FACE', detected: faceDetected),
                  const SizedBox(width: 6),
                  _SilentDetectionBadge(label: 'HAND', detected: handDetected),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SilentDetectionBadge extends StatelessWidget {
  const _SilentDetectionBadge({required this.label, required this.detected});

  final String label;
  final bool detected;

  @override
  Widget build(BuildContext context) {
    final dotColor = detected ? AppColors.teal : const Color(0xFF4B5160);
    final textColor = detected ? AppColors.teal : const Color(0xFF4B5160);
    final bgColor = detected
        ? AppColors.teal.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.5);
    final borderColor = detected
        ? AppColors.teal.withValues(alpha: 0.35)
        : const Color(0xFF1C2130);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.items});

  final List<SilentStatusItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF07090D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF121723)),
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final color = item.isAccent
              ? const Color(0xFF25D24F)
              : AppColors.textPrimary;
          final labelStyle = TextStyle(
            color: color,
            fontSize: item.isAccent ? 22 : 16,
            fontWeight: item.isAccent ? FontWeight.w900 : FontWeight.w700,
            height: item.isAccent ? 1.0 : 1.1,
            letterSpacing: item.isAccent ? -0.5 : 0,
          );

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: index == items.length - 1
                    ? BorderSide.none
                    : const BorderSide(color: Color(0xFF181D28)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.showDot)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF25D24F),
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                else if (item.icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      item.icon!,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                  )
                else
                  const SizedBox(width: 0),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: labelStyle,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _HapticPanel extends StatelessWidget {
  const _HapticPanel({required this.data, required this.activeLevel});

  final SilentModeData data;
  final _HapticLevel activeLevel;

  @override
  Widget build(BuildContext context) {
    // Map haptic items to levels in order
    final levels = [
      _HapticLevel.low,
      _HapticLevel.medium,
      _HapticLevel.high,
      _HapticLevel.critical,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF07090D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF121723)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.hapticTitle,
            style: const TextStyle(
              color: Color(0xFF4B5160),
              fontSize: 12,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 18),
          ...data.haptics.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final isActive = i < levels.length && levels[i] == activeLevel;
            final color = item.isDanger
                ? AppColors.emergency
                : isActive
                ? AppColors.teal
                : const Color(0xFF7B8292);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 66,
                    child: Text(
                      item.pattern,
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: item.isDanger || isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isActive)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.teal,
                        shape: BoxShape.circle,
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
