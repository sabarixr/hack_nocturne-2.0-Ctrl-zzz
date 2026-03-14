import 'dart:async';
import 'dart:math' as math;

import 'face_recognizer.dart';
import 'hand_recognizer.dart';

// ---------------------------------------------------------------------------
// Calibration baseline profile (loaded from CalibrationEngine)
// ---------------------------------------------------------------------------

class CalibrationBaseline {
  /// Mean signing speed during calm baseline recording
  final double calmSigningSpeed;

  /// Mean tremor level during calm baseline recording
  final double calmTremorLevel;

  /// Mean per-class emotion probabilities during calm baseline
  final Map<String, double> calmEmotionMean;

  /// Std-dev of per-class emotion probabilities during calm baseline
  final Map<String, double> calmEmotionStd;

  const CalibrationBaseline({
    required this.calmSigningSpeed,
    required this.calmTremorLevel,
    required this.calmEmotionMean,
    required this.calmEmotionStd,
  });

  /// Flat neutral baseline (used when no calibration has been performed)
  static CalibrationBaseline get neutral => CalibrationBaseline(
    calmSigningSpeed: 0.5,
    calmTremorLevel: 0.05,
    calmEmotionMean: {
      'neutral': 0.7,
      'happy': 0.1,
      'sad': 0.05,
      'surprise': 0.05,
      'afraid': 0.02,
      'disgust': 0.02,
      'angry': 0.06,
    },
    calmEmotionStd: {
      'neutral': 0.15,
      'happy': 0.08,
      'sad': 0.04,
      'surprise': 0.04,
      'afraid': 0.02,
      'disgust': 0.02,
      'angry': 0.05,
    },
  );

  Map<String, dynamic> toJson() => {
    'calmSigningSpeed': calmSigningSpeed,
    'calmTremorLevel': calmTremorLevel,
    'calmEmotionMean': calmEmotionMean,
    'calmEmotionStd': calmEmotionStd,
  };

  factory CalibrationBaseline.fromJson(Map<String, dynamic> json) {
    return CalibrationBaseline(
      calmSigningSpeed: (json['calmSigningSpeed'] as num).toDouble(),
      calmTremorLevel: (json['calmTremorLevel'] as num).toDouble(),
      calmEmotionMean: Map<String, double>.from(
        (json['calmEmotionMean'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      ),
      calmEmotionStd: Map<String, double>.from(
        (json['calmEmotionStd'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bayesian Urgency Engine
//
// Naive Bayes classifier with prior P(emergency) = 0.1
//
// Feature likelihoods P(feature | emergency) vs P(feature | normal):
//   - Deviant emotions (afraid, angry, sad, disgust, surprise) have high
//     likelihood under emergency; neutral/happy have low likelihood.
//   - Signing speed deviation from baseline: large deviation → emergency.
//   - Tremor deviation from baseline: elevated tremor → emergency.
//   - High-urgency signs (help, pain, doctor, accident) → emergency.
//   - Calibration deviation: z-score of current emotion vs calm baseline.
//
// Output: urgencyScore ∈ [0, 1] via StreamController
// ---------------------------------------------------------------------------

class UrgencyUpdate {
  final double urgencyScore;
  final String topEmotion;
  final List<String> detectedSigns;
  final double signingSpeed;
  final double tremorLevel;
  final Map<String, double> emotionProbabilities;
  final bool faceDetected;
  final bool handDetected;

  const UrgencyUpdate({
    required this.urgencyScore,
    required this.topEmotion,
    required this.detectedSigns,
    required this.signingSpeed,
    required this.tremorLevel,
    required this.emotionProbabilities,
    this.faceDetected = false,
    this.handDetected = false,
  });
}

class BayesianUrgencyEngine {
  // Prior probability of emergency state
  static const double _priorEmergency = 0.1;
  static const double _priorNormal = 0.9;

  // Emergency-indicating sign labels (high urgency)
  static const _emergencySigns = {
    'help',
    'pain',
    'doctor',
    'accident',
    'thief',
  };

  // Emotion weights for emergency likelihood
  // P(emotion | emergency) — higher weight = more indicative of emergency
  static const _emotionEmergencyWeight = {
    'neutral': 0.05,
    'happy': 0.02,
    'sad': 0.15,
    'surprise': 0.12,
    'afraid': 0.30,
    'disgust': 0.16,
    'angry': 0.20,
  };

  // P(emotion | normal)
  static const _emotionNormalWeight = {
    'neutral': 0.50,
    'happy': 0.20,
    'sad': 0.08,
    'surprise': 0.06,
    'afraid': 0.04,
    'disgust': 0.05,
    'angry': 0.07,
  };

  CalibrationBaseline _baseline;

  // Exponential smoothing of urgency score (α = 0.3)
  double _smoothedUrgency = 0.0;
  static const double _alpha = 0.3;

  // Stream controller
  final _controller = StreamController<UrgencyUpdate>.broadcast();
  Stream<UrgencyUpdate> get stream => _controller.stream;

  BayesianUrgencyEngine({CalibrationBaseline? baseline})
    : _baseline = baseline ?? CalibrationBaseline.neutral;

  void updateBaseline(CalibrationBaseline baseline) {
    _baseline = baseline;
  }

  /// Compute urgency from face + hand recognition results and emit to stream.
  UrgencyUpdate update(
    FaceEmotionResult faceResult,
    HandRecognitionResult handResult, {
    bool faceDetected = false,
    bool handDetected = false,
  }) {
    final score = _computeUrgency(faceResult, handResult);

    // Exponential smoothing
    _smoothedUrgency = _alpha * score + (1 - _alpha) * _smoothedUrgency;
    final clampedScore = _smoothedUrgency.clamp(0.0, 1.0);

    final update = UrgencyUpdate(
      urgencyScore: clampedScore,
      topEmotion: faceResult.topEmotion,
      detectedSigns: handResult.recognizedSigns,
      signingSpeed: handResult.signingSpeed,
      tremorLevel: handResult.tremorLevel,
      emotionProbabilities: faceResult.emotions,
      faceDetected: faceDetected,
      handDetected: handDetected,
    );
    _controller.add(update);
    return update;
  }

  /// Bypass local Bayesian computation and use the server-computed urgency score
  /// directly. This is the preferred path when [SignRecognizerService] receives
  /// a [FrameMLResult] that already contains a server-side [urgency_score].
  UrgencyUpdate updateFromServer({
    required double serverUrgencyScore,
    required Map<String, double> emotions,
    required List<String> detectedSigns,
    required double signingSpeed,
    required double tremorLevel,
    required bool faceDetected,
    required bool handDetected,
  }) {
    // Apply the same exponential smoothing so the UI doesn't jump
    _smoothedUrgency =
        _alpha * serverUrgencyScore + (1 - _alpha) * _smoothedUrgency;
    final clampedScore = _smoothedUrgency.clamp(0.0, 1.0);

    final topEmotion = emotions.isEmpty
        ? 'neutral'
        : emotions.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    final urgencyUpdate = UrgencyUpdate(
      urgencyScore: clampedScore,
      topEmotion: topEmotion,
      detectedSigns: detectedSigns,
      signingSpeed: signingSpeed,
      tremorLevel: tremorLevel,
      emotionProbabilities: emotions,
      faceDetected: faceDetected,
      handDetected: handDetected,
    );
    _controller.add(urgencyUpdate);
    return urgencyUpdate;
  }

  double _computeUrgency(FaceEmotionResult face, HandRecognitionResult hand) {
    // -----------------------------------------------------------------------
    // 1. Emotion likelihood ratio (log domain for numerical stability)
    // -----------------------------------------------------------------------
    double logLikelihoodEmergency = 0.0;
    double logLikelihoodNormal = 0.0;

    for (final emotion in FaceEmotionResult.emotionLabels) {
      final prob = face.emotions[emotion] ?? 0.0;
      final pEmg = _emotionEmergencyWeight[emotion] ?? 0.05;
      final pNorm = _emotionNormalWeight[emotion] ?? 0.10;
      // Weight by observed probability
      logLikelihoodEmergency += prob * math.log(pEmg + 1e-9);
      logLikelihoodNormal += prob * math.log(pNorm + 1e-9);
    }

    // -----------------------------------------------------------------------
    // 2. Calibration deviation boost
    // -----------------------------------------------------------------------
    double deviationBoost = 0.0;
    for (final emotion in FaceEmotionResult.emotionLabels) {
      final observed = face.emotions[emotion] ?? 0.0;
      final meanBaseline = _baseline.calmEmotionMean[emotion] ?? 0.1;
      final stdBaseline = math.max(
        _baseline.calmEmotionStd[emotion] ?? 0.05,
        0.01,
      );
      final zScore = (observed - meanBaseline) / stdBaseline;
      // Negative emotions with positive z-score → boost emergency
      if ({'afraid', 'angry', 'sad', 'disgust', 'surprise'}.contains(emotion) &&
          zScore > 0) {
        deviationBoost += zScore * 0.05;
      }
    }
    deviationBoost = deviationBoost.clamp(0.0, 0.4);

    // -----------------------------------------------------------------------
    // 3. Signing speed deviation
    // -----------------------------------------------------------------------
    final speedDev = (hand.signingSpeed - _baseline.calmSigningSpeed).abs();
    final speedLikelihoodEmergency = _gaussianPdf(
      speedDev,
      mean: 0.4,
      std: 0.2,
    );
    final speedLikelihoodNormal = _gaussianPdf(speedDev, mean: 0.05, std: 0.15);
    logLikelihoodEmergency += math.log(speedLikelihoodEmergency + 1e-9);
    logLikelihoodNormal += math.log(speedLikelihoodNormal + 1e-9);

    // -----------------------------------------------------------------------
    // 4. Tremor deviation
    // -----------------------------------------------------------------------
    final tremorDev = (hand.tremorLevel - _baseline.calmTremorLevel).abs();
    final tremorLikelihoodEmergency = _gaussianPdf(
      tremorDev,
      mean: 0.15,
      std: 0.08,
    );
    final tremorLikelihoodNormal = _gaussianPdf(
      tremorDev,
      mean: 0.02,
      std: 0.05,
    );
    logLikelihoodEmergency += math.log(tremorLikelihoodEmergency + 1e-9);
    logLikelihoodNormal += math.log(tremorLikelihoodNormal + 1e-9);

    // -----------------------------------------------------------------------
    // 5. Emergency sign detection
    // -----------------------------------------------------------------------
    double signBoost = 0.0;
    for (final sign in hand.recognizedSigns) {
      if (_emergencySigns.contains(sign.toLowerCase())) {
        signBoost += 0.25 * hand.confidence;
      }
    }
    signBoost = signBoost.clamp(0.0, 0.5);

    // -----------------------------------------------------------------------
    // 6. Bayesian posterior
    // -----------------------------------------------------------------------
    final logPriorEmergency = math.log(_priorEmergency);
    final logPriorNormal = math.log(_priorNormal);

    final logPostEmergency = logPriorEmergency + logLikelihoodEmergency;
    final logPostNormal = logPriorNormal + logLikelihoodNormal;

    // Normalize via log-sum-exp
    final maxLog = math.max(logPostEmergency, logPostNormal);
    final posteriorEmergency =
        math.exp(logPostEmergency - maxLog) /
        (math.exp(logPostEmergency - maxLog) +
            math.exp(logPostNormal - maxLog));

    return (posteriorEmergency + deviationBoost + signBoost).clamp(0.0, 1.0);
  }

  double _gaussianPdf(double x, {required double mean, required double std}) {
    final z = (x - mean) / std;
    return (1.0 / (std * math.sqrt(2 * math.pi))) * math.exp(-0.5 * z * z);
  }

  void dispose() {
    _controller.close();
  }
}
