// ignore_for_file: avoid_print
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:expresto/core/ml/bayesian_urgency_engine.dart';
import 'package:expresto/core/ml/calibration_engine.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// CalibrationPage
// ---------------------------------------------------------------------------

class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key});

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  // Camera
  CameraController? _cameraController;
  bool _cameraReady = false;
  String? _cameraError;

  // Calibration engine + progress
  CalibrationEngine? _calibrationEngine;
  StreamSubscription<CalibrationProgress>? _progressSub;

  CalibrationStep _step = CalibrationStep.initializing;
  int _samplesCollected = 0;
  static const int _totalSamples = 40;
  String _message = 'Initializing camera…';
  CalibrationBaseline? _result;
  bool _calibrationStarted = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  // ---------------------------------------------------------------------------
  // Camera init
  // ---------------------------------------------------------------------------

  Future<void> _initCamera() async {
    setState(() {
      _cameraError = null;
      _message = 'Starting camera…';
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras found');

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await ctrl.initialize();

      if (!mounted) return;
      setState(() {
        _cameraController = ctrl;
        _cameraReady = true;
        _step = CalibrationStep.collectingBaseline;
        _message = 'Camera ready. Tap "Start" to begin calibration.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e.toString();
        _step = CalibrationStep.error;
        _message = 'Camera error: $e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Calibration
  // ---------------------------------------------------------------------------

  Future<void> _startCalibration() async {
    if (!_cameraReady || _calibrationStarted) return;

    final engine = CalibrationEngine();
    _calibrationEngine = engine;

    setState(() {
      _calibrationStarted = true;
      _step = CalibrationStep.collectingBaseline;
      _message = 'Recording baseline… please sign naturally';
    });

    _progressSub = engine.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        _step = progress.step;
        _samplesCollected = progress.samplesCollected;
        _message = progress.message;
        if (progress.step == CalibrationStep.complete) {
          _result = progress.result;
        }
      });
    });

    try {
      await engine.runCalibration(_cameraController!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = CalibrationStep.error;
        _message = 'Calibration failed. Tap "Retry" to try again.';
      });
    }
  }

  void _retry() {
    _progressSub?.cancel();
    _calibrationEngine?.dispose();
    _calibrationEngine = null;
    _progressSub = null;
    setState(() {
      _calibrationStarted = false;
      _samplesCollected = 0;
      _result = null;
      _step = _cameraReady
          ? CalibrationStep.collectingBaseline
          : CalibrationStep.initializing;
      _message = _cameraReady
          ? 'Camera ready. Tap "Start" to begin calibration.'
          : 'Reinitializing camera…';
    });
    if (!_cameraReady) _initCamera();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _progressSub?.cancel();
    _calibrationEngine?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildProgressStrip(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildInstructionCard(),
                  const SizedBox(height: 12),
                  _buildCameraCard(),
                  const SizedBox(height: 12),
                  if (_calibrationStarted || _step == CalibrationStep.complete)
                    _buildLiveReadingsCard(),
                  if (_calibrationStarted || _step == CalibrationStep.complete)
                    const SizedBox(height: 12),
                  _buildControlButtons(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top bar
  // ---------------------------------------------------------------------------

  Widget _buildTopBar() {
    final stepNum = _step == CalibrationStep.complete ? 2 : 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.shellBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.track_changes,
                color: AppColors.textPrimary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'Calibration',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Text(
            '$stepNum / 2',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Progress strip
  // ---------------------------------------------------------------------------

  Widget _buildProgressStrip() {
    final fraction = _step == CalibrationStep.complete
        ? 1.0
        : _totalSamples == 0
        ? 0.0
        : (_samplesCollected / _totalSamples).clamp(0.0, 1.0);
    final pct = (fraction * 100).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Baseline Recording',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.shellBorder,
              borderRadius: BorderRadius.circular(100),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: const LinearGradient(
                    colors: [AppColors.emergency, AppColors.warning],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Instruction card
  // ---------------------------------------------------------------------------

  Widget _buildInstructionCard() {
    final String text;
    if (_step == CalibrationStep.complete) {
      text =
          'Calibration complete! Your personal baseline has been saved. '
          'The system will now detect stress and urgency relative to your calm state.';
    } else if (_step == CalibrationStep.error) {
      text =
          'An error occurred during calibration. '
          'Make sure your face and hands are visible, then tap Retry.';
    } else if (_calibrationStarted) {
      text =
          'Keep your face in the green box and sign a few words naturally. '
          'The system is recording your calm signing baseline (${_samplesCollected}/$_totalSamples frames).';
    } else {
      text =
          'Look into the front camera in a well-lit area. '
          'Tap Start to record your calm signing baseline. '
          'This helps the app detect distress relative to your normal state.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera preview card
  // ---------------------------------------------------------------------------

  Widget _buildCameraCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Camera feed
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: _buildCameraPreview(),
            ),
          ),
          const SizedBox(height: 12),
          // Status row
          Row(
            children: [
              Icon(
                _step == CalibrationStep.complete
                    ? Icons.check_circle_outline
                    : _step == CalibrationStep.error
                    ? Icons.error_outline
                    : _calibrationStarted
                    ? Icons.fiber_manual_record
                    : Icons.camera_alt_outlined,
                color: _step == CalibrationStep.complete
                    ? AppColors.success
                    : _step == CalibrationStep.error
                    ? AppColors.emergency
                    : _calibrationStarted
                    ? AppColors.warning
                    : AppColors.textMuted,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _message,
                  style: TextStyle(
                    color: _step == CalibrationStep.complete
                        ? AppColors.success
                        : _step == CalibrationStep.error
                        ? AppColors.emergency
                        : AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraError != null) {
      return Container(
        color: const Color(0xFF071114),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: AppColors.textMuted,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              _cameraError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (!_cameraReady || _cameraController == null) {
      return Container(
        color: const Color(0xFF071114),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.warning),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize!.height,
            height: _cameraController!.value.previewSize!.width,
            child: CameraPreview(_cameraController!),
          ),
        ),
        // Face framing guide
        Center(
          child: Container(
            width: 120,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _calibrationStarted
                    ? AppColors.warning
                    : AppColors.textMuted,
                width: 2,
              ),
            ),
          ),
        ),
        // REC indicator
        if (_calibrationStarted && _step != CalibrationStep.complete)
          Positioned(
            top: 8,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.emergency,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'REC',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Live readings card (visible once calibration starts)
  // ---------------------------------------------------------------------------

  Widget _buildLiveReadingsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BASELINE READINGS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          _buildReadingRow(
            'Samples collected',
            '$_samplesCollected / $_totalSamples',
            _samplesCollected >= _totalSamples
                ? AppColors.success
                : AppColors.warning,
          ),
          const SizedBox(height: 12),
          _buildReadingRow(
            'Status',
            _stepLabel(_step),
            _step == CalibrationStep.complete
                ? AppColors.success
                : _step == CalibrationStep.error
                ? AppColors.emergency
                : AppColors.warning,
          ),
          if (_result != null) ...[
            const SizedBox(height: 12),
            _buildReadingRow(
              'Calm signing speed',
              _result!.calmSigningSpeed.toStringAsFixed(3),
              AppColors.textPrimary,
            ),
            const SizedBox(height: 12),
            _buildReadingRow(
              'Calm tremor level',
              _result!.calmTremorLevel.toStringAsFixed(3),
              AppColors.textPrimary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadingRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _stepLabel(CalibrationStep step) {
    switch (step) {
      case CalibrationStep.initializing:
        return 'Initializing';
      case CalibrationStep.collectingBaseline:
        return 'Recording';
      case CalibrationStep.complete:
        return 'Complete';
      case CalibrationStep.error:
        return 'Error';
    }
  }

  // ---------------------------------------------------------------------------
  // Control buttons
  // ---------------------------------------------------------------------------

  Widget _buildControlButtons() {
    if (_step == CalibrationStep.complete) {
      return _buildButton(
        label: 'Done',
        color: AppColors.success,
        onTap: () => Navigator.pop(context),
      );
    }

    if (_step == CalibrationStep.error) {
      return _buildButton(
        label: 'Retry',
        color: AppColors.warning,
        onTap: _retry,
      );
    }

    if (_calibrationStarted) {
      // In progress — show a disabled progress indicator button
      return _buildButton(
        label: 'Recording… $_samplesCollected / $_totalSamples',
        color: AppColors.shellBorder,
        onTap: null,
      );
    }

    // Ready to start
    return Row(
      children: [
        Expanded(
          child: _buildButton(
            label: 'Start',
            color: AppColors.warning,
            onTap: _cameraReady ? _startCalibration : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildButton(
            label: 'Skip',
            color: AppColors.panel,
            borderColor: AppColors.shellBorder,
            onTap: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }

  Widget _buildButton({
    required String label,
    required Color color,
    Color? borderColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: borderColor != null ? Border.all(color: borderColor) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: onTap == null ? AppColors.textMuted : AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
