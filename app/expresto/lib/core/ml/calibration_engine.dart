// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bayesian_urgency_engine.dart';
import 'face_recognizer.dart';
import 'hand_recognizer.dart';

// ---------------------------------------------------------------------------
// Calibration progress events
// ---------------------------------------------------------------------------

enum CalibrationStep { initializing, collectingBaseline, complete, error }

class CalibrationProgress {
  final CalibrationStep step;
  final int samplesCollected;
  final int totalSamples;
  final String message;
  final CalibrationBaseline? result; // non-null when step == complete

  const CalibrationProgress({
    required this.step,
    required this.samplesCollected,
    required this.totalSamples,
    required this.message,
    this.result,
  });

  double get fraction => totalSamples == 0
      ? 0.0
      : (samplesCollected / totalSamples).clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// CalibrationEngine
// ---------------------------------------------------------------------------

class CalibrationEngine {
  static const String _prefKey = 'calibration_profile_v1';
  static const int _targetSamples = 40; // ~40 frames at ~2s of calm signing

  final _progressController = StreamController<CalibrationProgress>.broadcast();
  Stream<CalibrationProgress> get progressStream => _progressController.stream;

  bool _running = false;
  bool _disposed = false;

  // Accumulated sample data
  final _signingSpeedSamples = <double>[];
  final _tremorSamples = <double>[];
  final _emotionSamples = <Map<String, double>>[];

  void _emit(CalibrationProgress p) {
    if (!_disposed) _progressController.add(p);
  }

  /// Run calibration against a live [CameraController].
  ///
  /// Collects [_targetSamples] frames of face + hand ML output, computes
  /// per-feature mean/std, saves to shared_preferences, and returns the
  /// [CalibrationBaseline].
  Future<CalibrationBaseline> runCalibration(CameraController camera) async {
    if (_running) throw StateError('Calibration already in progress');
    _running = true;

    _signingSpeedSamples.clear();
    _tremorSamples.clear();
    _emotionSamples.clear();

    _emit(
      CalibrationProgress(
        step: CalibrationStep.initializing,
        samplesCollected: 0,
        totalSamples: _targetSamples,
        message: 'Initializing face and hand detection...',
      ),
    );

    try {
      final faceRecognizer = await FaceRecognizer.create();
      final handRecognizer = await HandRecognizer.create();

      _emit(
        CalibrationProgress(
          step: CalibrationStep.collectingBaseline,
          samplesCollected: 0,
          totalSamples: _targetSamples,
          message: 'Please sign naturally. Recording your baseline...',
        ),
      );

      // Use a completer to await async frame collection
      final completer = Completer<void>();
      int framesProcessed = 0;
      bool streamStarted = false;

      camera.startImageStream((CameraImage image) async {
        if (_disposed || framesProcessed >= _targetSamples) {
          if (!completer.isCompleted) completer.complete();
          return;
        }

        // Process every 2nd frame to avoid overloading
        if (framesProcessed % 2 != 0) {
          framesProcessed++;
          return;
        }

        try {
          final faceResult =
              await faceRecognizer.processFrame(image) ??
              FaceEmotionResult.neutral();
          final handResult = await handRecognizer.processFrame(image);

          _signingSpeedSamples.add(handResult.signingSpeed);
          _tremorSamples.add(handResult.tremorLevel);
          _emotionSamples.add(Map<String, double>.from(faceResult.emotions));

          final collected = _emotionSamples.length;
          _emit(
            CalibrationProgress(
              step: CalibrationStep.collectingBaseline,
              samplesCollected: collected,
              totalSamples: _targetSamples,
              message: 'Recording baseline... ($collected/$_targetSamples)',
            ),
          );

          if (collected >= _targetSamples && !completer.isCompleted) {
            completer.complete();
          }
        } catch (e) {
          print('[CalibrationEngine] frame error: $e');
        }
        framesProcessed++;
      });
      streamStarted = true;

      // Wait for enough samples or 30s timeout
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );

      if (streamStarted) {
        try {
          await camera.stopImageStream();
        } catch (_) {}
      }

      // Build baseline from accumulated samples
      final baseline = _buildBaseline();

      // Persist to shared_preferences
      await _saveBaseline(baseline);

      _emit(
        CalibrationProgress(
          step: CalibrationStep.complete,
          samplesCollected: _emotionSamples.length,
          totalSamples: _targetSamples,
          message: 'Calibration complete!',
          result: baseline,
        ),
      );

      return baseline;
    } catch (e, st) {
      print('[CalibrationEngine] error: $e\n$st');
      _emit(
        CalibrationProgress(
          step: CalibrationStep.error,
          samplesCollected: _emotionSamples.length,
          totalSamples: _targetSamples,
          message: 'Calibration failed: $e',
        ),
      );
      rethrow;
    } finally {
      _running = false;
    }
  }

  CalibrationBaseline _buildBaseline() {
    if (_signingSpeedSamples.isEmpty) return CalibrationBaseline.neutral;

    final calmSpeed = _mean(_signingSpeedSamples);
    final calmTremor = _mean(_tremorSamples);

    final emotionMean = <String, double>{};
    final emotionStd = <String, double>{};

    for (final label in FaceEmotionResult.emotionLabels) {
      final vals = _emotionSamples.map((m) => m[label] ?? 0.0).toList();
      emotionMean[label] = _mean(vals);
      emotionStd[label] = math.max(_std(vals), 0.01);
    }

    return CalibrationBaseline(
      calmSigningSpeed: calmSpeed,
      calmTremorLevel: calmTremor,
      calmEmotionMean: emotionMean,
      calmEmotionStd: emotionStd,
    );
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  static Future<CalibrationBaseline?> loadBaseline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr == null) return null;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CalibrationBaseline.fromJson(map);
    } catch (e) {
      print('[CalibrationEngine] failed to load baseline: $e');
      return null;
    }
  }

  static Future<void> _saveBaseline(CalibrationBaseline baseline) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(baseline.toJson()));
      print('[CalibrationEngine] baseline saved');
    } catch (e) {
      print('[CalibrationEngine] failed to save baseline: $e');
    }
  }

  static Future<void> clearBaseline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // ---------------------------------------------------------------------------
  // Statistics helpers
  // ---------------------------------------------------------------------------

  double _mean(List<double> vals) {
    if (vals.isEmpty) return 0.0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double _std(List<double> vals) {
    if (vals.length < 2) return 0.0;
    final m = _mean(vals);
    final variance =
        vals.map((v) => math.pow(v - m, 2).toDouble()).reduce((a, b) => a + b) /
        vals.length;
    return math.sqrt(variance);
  }

  void dispose() {
    _disposed = true;
    _progressController.close();
  }
}
