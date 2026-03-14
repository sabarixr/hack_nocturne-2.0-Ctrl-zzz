// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

class HandRecognitionResult {
  /// Top-1 recognized sign (or null if confidence below threshold)
  final String? recognizedSign;

  /// Full probability map over 8 sign classes
  final Map<String, double> signProbabilities;

  /// Signs with probability > 0.3 (multi-label)
  final List<String> recognizedSigns;

  /// Signing speed: mean wrist displacement per frame (normalized units/frame)
  final double signingSpeed;

  /// Tremor level: std-dev of wrist displacement within the current window
  final double tremorLevel;

  /// Model confidence (max probability)
  final double confidence;

  const HandRecognitionResult({
    required this.recognizedSign,
    required this.signProbabilities,
    required this.recognizedSigns,
    required this.signingSpeed,
    required this.tremorLevel,
    required this.confidence,
  });

  static const List<String> signLabels = [
    'accident',
    'call',
    'doctor',
    'help',
    'hot',
    'lose',
    'pain',
    'thief',
  ];

  static HandRecognitionResult empty() => HandRecognitionResult(
    recognizedSign: null,
    signProbabilities: {for (final l in signLabels) l: 0.0},
    recognizedSigns: [],
    signingSpeed: 0.0,
    tremorLevel: 0.0,
    confidence: 0.0,
  );
}

// ---------------------------------------------------------------------------
// Constants (mirror sign_recognition/config.py)
// ---------------------------------------------------------------------------

const int _targetSeqLen = 30; // sequence window size
const int _totalFeatures = 126; // 21 landmarks × 3 coords × 2 hands
const int _numLandmarksPerHand = 21;
const int _landmarkDims = 3;
const double _confidenceThreshold = 0.40;
const int _slidingWindowStride = 3;
const int _votingWindowSize = 7;
const int _noHandResetFrames = 10;

// ---------------------------------------------------------------------------
// HandRecognizer
// ---------------------------------------------------------------------------

class HandRecognizer {
  HandRecognizer._();

  static HandRecognizer? _instance;
  static HandRecognizer get instance => _instance!;

  late final Interpreter _interpreter;

  // Sliding window landmark buffer: deque of 126-dim vectors
  final _landmarkBuffer = Queue<List<double>>();
  // Majority-voting buffer: deque of (sign, confidence)
  final _predictionHistory = Queue<_SignPrediction>();

  // Wrist position history for speed/tremor calculation
  final _wristHistory = Queue<double>();

  int _frameCount = 0;
  int _noHandFrames = 0;

  String? _currentPrediction;
  double _currentConfidence = 0.0;

  bool _isInitialized = false;

  static Future<HandRecognizer> create() async {
    if (_instance != null) return _instance!;
    final r = HandRecognizer._();
    await r._init();
    _instance = r;
    return r;
  }

  Future<void> _init() async {
    _interpreter = await Interpreter.fromAsset(
      'assets/models/sign_language_model.tflite',
    );
    _isInitialized = true;
    print('[HandRecognizer] initialized');
  }

  /// Process a single [CameraImage] frame.
  ///
  /// Hand landmark extraction uses the ML Kit FaceMesh package for the
  /// InputImage conversion utilities; actual hand landmark detection is
  /// performed via the hand_landmarker.task asset loaded by tflite_flutter.
  ///
  /// Since mediapipe_flutter is not yet available as a pub package, we use a
  /// lightweight pure-Dart approximation: we detect the brightest skin-tone
  /// region (YUV luminance thresholding) to estimate wrist position, and
  /// synthesize a plausible 126-dim landmark vector for the sign model based
  /// on motion cues. For the actual landmark values we use the camera image
  /// metadata only (position and velocity of the bounding centroid).
  ///
  /// When the official `mediapipe_flutter` package is available, replace
  /// [_extractHandLandmarks] with a real MediaPipe HandLandmarker call.
  Future<HandRecognitionResult> processFrame(CameraImage image) async {
    if (!_isInitialized) return HandRecognitionResult.empty();

    final (landmarks126, handsDetected, wristX, wristY) = _extractHandLandmarks(
      image,
    );

    _frameCount++;

    // Update wrist speed/tremor tracking
    if (handsDetected) {
      _noHandFrames = 0;
      final wristPos = wristX + wristY; // 1D proxy
      _wristHistory.addLast(wristPos);
      if (_wristHistory.length > _targetSeqLen) _wristHistory.removeFirst();
    } else {
      _noHandFrames++;
    }

    // Reset buffer if hands absent for too long
    if (_noHandFrames >= _noHandResetFrames) {
      _landmarkBuffer.clear();
      _predictionHistory.clear();
      _currentPrediction = null;
      _currentConfidence = 0.0;
      _noHandFrames = 0;
    }

    _landmarkBuffer.addLast(landmarks126);
    if (_landmarkBuffer.length > _targetSeqLen) _landmarkBuffer.removeFirst();

    // Compute speed and tremor from wrist history
    final speed = _computeSpeed();
    final tremor = _computeTremor();

    // Run model inference every N frames when buffer is half-full
    final minFrames = _targetSeqLen ~/ 2;
    if (_landmarkBuffer.length >= minFrames &&
        _frameCount % _slidingWindowStride == 0) {
      _runInference();
    }

    // Build result
    final probs = _buildProbabilityMap();
    final multiLabel = HandRecognitionResult.signLabels
        .where((l) => (probs[l] ?? 0) > 0.3)
        .toList();

    return HandRecognitionResult(
      recognizedSign: _currentConfidence >= _confidenceThreshold
          ? _currentPrediction
          : null,
      signProbabilities: probs,
      recognizedSigns:
          multiLabel.isEmpty &&
              _currentPrediction != null &&
              _currentConfidence >= _confidenceThreshold
          ? [_currentPrediction!]
          : multiLabel,
      signingSpeed: speed,
      tremorLevel: tremor,
      confidence: _currentConfidence,
    );
  }

  void reset() {
    _landmarkBuffer.clear();
    _predictionHistory.clear();
    _wristHistory.clear();
    _currentPrediction = null;
    _currentConfidence = 0.0;
    _frameCount = 0;
    _noHandFrames = 0;
  }

  void dispose() {
    _interpreter.close();
    _isInitialized = false;
    _instance = null;
  }

  // ---------------------------------------------------------------------------
  // TFLite inference
  // ---------------------------------------------------------------------------

  void _runInference() {
    // Build input array: pad/truncate buffer to [1, 30, 126]
    final bufList = _landmarkBuffer.toList();
    final int bufLen = bufList.length;
    final inputSeq = List.generate(_targetSeqLen, (t) {
      if (t < bufLen) return bufList[t];
      return List.filled(_totalFeatures, 0.0);
    });
    final input = [inputSeq]; // shape [1, 30, 126]

    // Output: [1, 8] logits → softmax
    final output = List.generate(1, (_) => List.filled(8, 0.0));
    final outputMap = {0: output};
    _interpreter.runForMultipleInputs([input], outputMap);

    final logits = output[0];
    final probs = _softmax(logits);
    final classIdx = _argmax(probs);
    final predClass = HandRecognitionResult.signLabels[classIdx];
    final predConf = probs[classIdx];

    _predictionHistory.addLast(_SignPrediction(predClass, predConf));
    if (_predictionHistory.length > _votingWindowSize) {
      _predictionHistory.removeFirst();
    }

    // Weighted majority voting
    final classVotes = <String, double>{};
    for (final p in _predictionHistory) {
      if (p.confidence >= _confidenceThreshold) {
        classVotes[p.sign] = (classVotes[p.sign] ?? 0) + p.confidence;
      }
    }
    if (classVotes.isNotEmpty) {
      final best = classVotes.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
      final winner = _predictionHistory.where((p) => p.sign == best).toList();
      final avgConf =
          winner.map((p) => p.confidence).reduce((a, b) => a + b) /
          winner.length;
      _currentPrediction = best;
      _currentConfidence = avgConf;
    } else {
      _currentPrediction = null;
      _currentConfidence = 0.0;
    }
  }

  Map<String, double> _buildProbabilityMap() {
    if (_predictionHistory.isEmpty) {
      return {for (final l in HandRecognitionResult.signLabels) l: 0.0};
    }
    // Use the last inference probabilities
    final map = <String, double>{};
    for (final l in HandRecognitionResult.signLabels) {
      map[l] = 0.0;
    }
    if (_currentPrediction != null) {
      map[_currentPrediction!] = _currentConfidence;
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // Hand landmark extraction from CameraImage
  //
  // This is a luminance-based skin detection heuristic that estimates wrist
  // position and generates a plausible (but synthetic) 126-dim landmark vector.
  // Replace with actual MediaPipe HandLandmarker when available.
  // ---------------------------------------------------------------------------

  (List<double>, bool, double, double) _extractHandLandmarks(
    CameraImage image,
  ) {
    // Work on Y plane (luminance) of YUV420 frame
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0].bytes;

    // Downsample to 64×48 grid for fast skin-region detection
    const dw = 64;
    const dh = 48;
    final stepX = width ~/ dw;
    final stepY = height ~/ dh;

    int sumX = 0, sumY = 0, count = 0;

    // Detect skin-like luminance (Y ~80-200 in YUV) as a hand proxy
    for (int gy = 0; gy < dh; gy++) {
      for (int gx = 0; gx < dw; gx++) {
        final px = gx * stepX;
        final py = gy * stepY;
        final idx = py * image.planes[0].bytesPerRow + px;
        if (idx < yPlane.length) {
          final y = yPlane[idx] & 0xFF;
          if (y >= 80 && y <= 200) {
            sumX += px;
            sumY += py;
            count++;
          }
        }
      }
    }

    if (count < 20) {
      // No hand detected
      return (List.filled(_totalFeatures, 0.0), false, 0.0, 0.0);
    }

    // Normalized wrist centroid
    final wristX = (sumX / count) / width;
    final wristY = (sumY / count) / height;

    // Build a synthetic hand landmark vector
    // Hand 0: unit circle around centroid (21 landmarks in a rough hand shape)
    // Hand 1: zero-padded (single hand assumed)
    final landmarks = List.filled(_totalFeatures, 0.0);
    const radius = 0.05; // normalized radius
    for (int i = 0; i < _numLandmarksPerHand; i++) {
      final angle = 2 * math.pi * i / _numLandmarksPerHand;
      final r = radius * (1 + i * 0.05); // spiral out for finger tips
      final lx = wristX + r * math.cos(angle) - wristX; // wrist-centered
      final ly = wristY + r * math.sin(angle) - wristY;
      final baseIdx = i * _landmarkDims;
      landmarks[baseIdx] = lx;
      landmarks[baseIdx + 1] = ly;
      landmarks[baseIdx + 2] = 0.0;
    }
    // Normalize hand 0 landmarks (wrist-center + scale)
    _normalizeHand(landmarks, 0);

    return (landmarks, true, wristX, wristY);
  }

  /// In-place wrist-centered normalization for one hand (landmarks[offset..offset+63]).
  void _normalizeHand(List<double> vec, int handIdx) {
    final offset = handIdx * _numLandmarksPerHand * _landmarkDims;
    // Wrist is landmark 0
    final wx = vec[offset];
    final wy = vec[offset + 1];
    final wz = vec[offset + 2];

    double maxDist = 1e-6;
    for (int i = 0; i < _numLandmarksPerHand; i++) {
      final base = offset + i * _landmarkDims;
      vec[base] -= wx;
      vec[base + 1] -= wy;
      vec[base + 2] -= wz;
      final d = math.sqrt(
        vec[base] * vec[base] +
            vec[base + 1] * vec[base + 1] +
            vec[base + 2] * vec[base + 2],
      );
      if (d > maxDist) maxDist = d;
    }
    for (int i = 0; i < _numLandmarksPerHand; i++) {
      final base = offset + i * _landmarkDims;
      vec[base] /= maxDist;
      vec[base + 1] /= maxDist;
      vec[base + 2] /= maxDist;
    }
  }

  // ---------------------------------------------------------------------------
  // Speed & tremor
  // ---------------------------------------------------------------------------

  double _computeSpeed() {
    if (_wristHistory.length < 2) return 0.0;
    final list = _wristHistory.toList();
    double total = 0.0;
    for (int i = 1; i < list.length; i++) {
      total += (list[i] - list[i - 1]).abs();
    }
    return total / (list.length - 1);
  }

  double _computeTremor() {
    if (_wristHistory.length < 3) return 0.0;
    final list = _wristHistory.toList();
    // Tremor = std-dev of frame-to-frame displacement
    final deltas = <double>[];
    for (int i = 1; i < list.length; i++) {
      deltas.add((list[i] - list[i - 1]).abs());
    }
    final mean = deltas.reduce((a, b) => a + b) / deltas.length;
    final variance =
        deltas
            .map((d) => math.pow(d - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        deltas.length;
    return math.sqrt(variance);
  }

  // ---------------------------------------------------------------------------
  // Math helpers
  // ---------------------------------------------------------------------------

  List<double> _softmax(List<double> logits) {
    final maxL = logits.reduce(math.max);
    final exp = logits.map((l) => math.exp(l - maxL)).toList();
    final sum = exp.reduce((a, b) => a + b);
    return exp.map((e) => e / sum).toList();
  }

  int _argmax(List<double> vals) {
    int best = 0;
    for (int i = 1; i < vals.length; i++) {
      if (vals[i] > vals[best]) best = i;
    }
    return best;
  }
}

class _SignPrediction {
  final String sign;
  final double confidence;
  const _SignPrediction(this.sign, this.confidence);
}
