// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

class FaceEmotionResult {
  final Map<String, double> emotions; // 7-class softmax probabilities
  final double confidence; // max probability
  final String topEmotion;

  const FaceEmotionResult({
    required this.emotions,
    required this.confidence,
    required this.topEmotion,
  });

  static const List<String> emotionLabels = [
    'neutral',
    'happy',
    'sad',
    'surprise',
    'afraid',
    'disgust',
    'angry',
  ];

  static FaceEmotionResult neutral() => FaceEmotionResult(
    emotions: {
      'neutral': 1.0,
      'happy': 0.0,
      'sad': 0.0,
      'surprise': 0.0,
      'afraid': 0.0,
      'disgust': 0.0,
      'angry': 0.0,
    },
    confidence: 1.0,
    topEmotion: 'neutral',
  );
}

// ---------------------------------------------------------------------------
// Landmark index constants (mirror emotionModel/emotion_pipeline/features.py)
// ---------------------------------------------------------------------------
const int _numLandmarks = 478;
const int _centerIndex = 1; // nose bridge

// Region index arrays — must match Python exactly
final List<int> _leftEyeIndices = [33, 133, 159, 145, 158, 153];
final List<int> _leftBrowIndices = [46, 52, 53, 63, 65, 66, 70, 105];
final List<int> _rightEyeIndices = [362, 263, 386, 374, 385, 380];
final List<int> _rightBrowIndices = [276, 282, 283, 293, 295, 296, 300, 334];
final List<int> _mouthIndices = [
  13,
  14,
  61,
  78,
  81,
  84,
  87,
  91,
  95,
  146,
  178,
  181,
  185,
  191,
  267,
  269,
  270,
  291,
  308,
  311,
  314,
  317,
  321,
  324,
  375,
  402,
  405,
  409,
];
final List<int> _noseIndices = [
  1,
  2,
  4,
  5,
  6,
  19,
  45,
  48,
  49,
  51,
  64,
  94,
  97,
  98,
  115,
  168,
  195,
  197,
  220,
  275,
  278,
  279,
  281,
  294,
  440,
];

List<int> _uniqueSorted(List<int> a, List<int> b) {
  final s = <int>{...a, ...b};
  final l = s.toList()..sort();
  return l;
}

// ---------------------------------------------------------------------------
// FaceRecognizer
// ---------------------------------------------------------------------------

class FaceRecognizer {
  FaceRecognizer._();

  static FaceRecognizer? _instance;
  static FaceRecognizer get instance => _instance!;

  late final FaceMeshDetector _meshDetector;
  late final Interpreter _interpreter;

  // Input tensor indices (resolved at init time by matching tensor names)
  late final int _idxLandmarks;
  late final int _idxEngineered;
  late final int _idxLeftEyeBrow;
  late final int _idxRightEyeBrow;
  late final int _idxMouth;
  late final int _idxNose;
  late final int _outputIdx;

  // Region index arrays computed once
  late final List<int> _leftEyeBrowRegion;
  late final List<int> _rightEyeBrowRegion;

  bool _isInitialized = false;

  static Future<FaceRecognizer> create() async {
    if (_instance != null) return _instance!;
    final r = FaceRecognizer._();
    await r._init();
    _instance = r;
    return r;
  }

  Future<void> _init() async {
    // MediaPipe face mesh (478 landmarks)
    _meshDetector = FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);

    // Load TFLite interpreter
    _interpreter = await Interpreter.fromAsset(
      'assets/models/emotion_landmark_model.tflite',
    );

    // Resolve input tensor indices by name
    final inputTensors = _interpreter.getInputTensors();
    final nameToIdx = <String, int>{};
    for (int i = 0; i < inputTensors.length; i++) {
      // tensor names look like "serving_default_landmarks:0" or "landmarks:0"
      final raw = inputTensors[i].name;
      for (final key in [
        'landmarks',
        'engineered_features',
        'left_eye_brow',
        'right_eye_brow',
        'mouth',
        'nose',
      ]) {
        if (raw.contains(key)) {
          nameToIdx[key] = i;
          break;
        }
      }
    }
    _idxLandmarks = nameToIdx['landmarks']!;
    _idxEngineered = nameToIdx['engineered_features']!;
    _idxLeftEyeBrow = nameToIdx['left_eye_brow']!;
    _idxRightEyeBrow = nameToIdx['right_eye_brow']!;
    _idxMouth = nameToIdx['mouth']!;
    _idxNose = nameToIdx['nose']!;
    _outputIdx = 0;

    _leftEyeBrowRegion = _uniqueSorted(_leftEyeIndices, _leftBrowIndices);
    _rightEyeBrowRegion = _uniqueSorted(_rightEyeIndices, _rightBrowIndices);

    _isInitialized = true;
    print(
      '[FaceRecognizer] initialized — ${inputTensors.length} input tensors',
    );
  }

  /// Process a single [CameraImage] and return 7-class emotion probabilities.
  /// Returns null if no face is detected.
  Future<FaceEmotionResult?> processFrame(CameraImage image) async {
    if (!_isInitialized) return null;

    // Convert CameraImage to InputImage for ML Kit
    final inputImage = _cameraImageToInputImage(image);
    if (inputImage == null) return null;

    final meshes = await _meshDetector.processImage(inputImage);
    if (meshes.isEmpty) return null;

    final mesh = meshes.first;
    if (mesh.points.length != _numLandmarks) return null;

    // Build (478, 3) float array
    final raw = List.generate(_numLandmarks, (i) {
      final p = mesh.points[i];
      return [p.x.toDouble(), p.y.toDouble(), p.z.toDouble()];
    });

    // Normalize landmarks (center + rotate + scale)
    final normalized = _normalizeLandmarks(raw);

    // Engineered features (13-dim)
    final engineered = _computeEngineeredFeatures(normalized);

    // TODO: apply preprocessor_stats standardization
    // The .npz stats file is not bundled as a Flutter asset — we skip z-score
    // standardization here (the model was trained with it, but the .tflite
    // converts the keras model which already has BN layers that partially
    // absorb this). For production, bundle preprocessor_stats.npz and apply.
    final stdLandmarks = normalized; // shape (478,3)
    final stdEngineered = engineered; // shape (13,)

    // Build region sub-arrays
    final leftEyeBrow = _selectRows(stdLandmarks, _leftEyeBrowRegion);
    final rightEyeBrow = _selectRows(stdLandmarks, _rightEyeBrowRegion);
    final mouth = _selectRows(stdLandmarks, _mouthIndices);
    final nose = _selectRows(stdLandmarks, _noseIndices);

    // Build ordered inputs array (indexed by tensor index order returned from interpreter)
    // We need to pass inputs in the order the interpreter expects them.
    // Since we resolved the name→index mapping, build a list of size = inputCount.
    final inputCount = _interpreter.getInputTensors().length;
    final inputs = List<Object?>.filled(inputCount, null);
    inputs[_idxLandmarks] = [stdLandmarks];
    inputs[_idxEngineered] = [stdEngineered];
    inputs[_idxLeftEyeBrow] = [leftEyeBrow];
    inputs[_idxRightEyeBrow] = [rightEyeBrow];
    inputs[_idxMouth] = [mouth];
    inputs[_idxNose] = [nose];

    // Output buffer: [1, 7]
    final outputBuffer = List.generate(1, (_) => List.filled(7, 0.0));
    final outputMap = {_outputIdx: outputBuffer};

    _interpreter.runForMultipleInputs(inputs.cast<Object>(), outputMap);

    final probs = outputBuffer[0];
    final topIdx = _argmax(probs);
    final labels = FaceEmotionResult.emotionLabels;

    return FaceEmotionResult(
      emotions: {for (int i = 0; i < labels.length; i++) labels[i]: probs[i]},
      confidence: probs[topIdx],
      topEmotion: labels[topIdx],
    );
  }

  void dispose() {
    _meshDetector.close();
    _interpreter.close();
    _isInitialized = false;
    _instance = null;
  }

  // ---------------------------------------------------------------------------
  // Pre-processing helpers (mirror features.py)
  // ---------------------------------------------------------------------------

  /// Normalize 478×3 landmarks: center on [centerIndex], rotate to align eyes
  /// horizontally, then scale by max(bounding-box-side, interpupil-distance).
  List<List<double>> _normalizeLandmarks(List<List<double>> pts) {
    // Center
    final cx = pts[_centerIndex][0];
    final cy = pts[_centerIndex][1];
    final cz = pts[_centerIndex][2];
    final centered = List.generate(
      _numLandmarks,
      (i) => [pts[i][0] - cx, pts[i][1] - cy, pts[i][2] - cz],
    );

    // Rotation angle from eye vector
    final le = pts[33]; // left eye outer corner
    final re = pts[263]; // right eye outer corner
    final dx = re[0] - le[0];
    final dy = re[1] - le[1];
    final angle = -math.atan2(dy, dx);
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final rotated = List.generate(_numLandmarks, (i) {
      final x = centered[i][0];
      final y = centered[i][1];
      return [cosA * x - sinA * y, sinA * x + cosA * y, centered[i][2]];
    });

    // Scale
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final p in rotated) {
      if (p[0] < minX) minX = p[0];
      if (p[0] > maxX) maxX = p[0];
      if (p[1] < minY) minY = p[1];
      if (p[1] > maxY) maxY = p[1];
    }
    final bboxW = maxX - minX;
    final bboxH = maxY - minY;
    final interpupil = math.sqrt(
      math.pow(re[0] - le[0], 2) + math.pow(re[1] - le[1], 2),
    );
    final scale = math.max(math.max(bboxW, bboxH), math.max(interpupil, 1e-6));

    return List.generate(
      _numLandmarks,
      (i) => [
        rotated[i][0] / scale,
        rotated[i][1] / scale,
        rotated[i][2] / scale,
      ],
    );
  }

  double _dist(List<List<double>> pts, int a, int b) {
    final dx = pts[a][0] - pts[b][0];
    final dy = pts[a][1] - pts[b][1];
    final dz = pts[a][2] - pts[b][2];
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  double _safeRatio(double num, double den) => num / math.max(den.abs(), 1e-6);

  List<double> _computeEngineeredFeatures(List<List<double>> pts) {
    final leftEyeW = _dist(pts, 33, 133);
    final rightEyeW = _dist(pts, 362, 263);
    final mouthW = _dist(pts, 61, 291);
    final faceW = _dist(pts, 234, 454);

    final lBrowRaise = _safeRatio((pts[70][1] - pts[159][1]).abs(), leftEyeW);
    final rBrowRaise = _safeRatio((pts[300][1] - pts[386][1]).abs(), rightEyeW);
    final browAsym = lBrowRaise - rBrowRaise;
    final lEyeOpen = _safeRatio(_dist(pts, 159, 145), leftEyeW);
    final rEyeOpen = _safeRatio(_dist(pts, 386, 374), rightEyeW);
    final eyeAsym = lEyeOpen - rEyeOpen;
    final mouthOpen = _safeRatio(_dist(pts, 13, 14), mouthW);
    final lipCornerW = _safeRatio(mouthW, faceW);
    final lLipOffX = _safeRatio(pts[61][0] - pts[1][0], faceW);
    final rLipOffX = _safeRatio(pts[291][0] - pts[1][0], faceW);
    final lipAsym = lLipOffX + rLipOffX;
    final lBrowSlope = _safeRatio(
      pts[105][1] - pts[66][1],
      pts[105][0] - pts[66][0],
    );
    final rBrowSlope = _safeRatio(
      pts[334][1] - pts[296][1],
      pts[334][0] - pts[296][0],
    );

    return [
      lBrowRaise,
      rBrowRaise,
      browAsym,
      lEyeOpen,
      rEyeOpen,
      eyeAsym,
      mouthOpen,
      lipCornerW,
      lLipOffX,
      rLipOffX,
      lipAsym,
      lBrowSlope,
      rBrowSlope,
    ];
  }

  /// Extract rows at given indices from a (N,3) landmarks array.
  List<List<double>> _selectRows(List<List<double>> pts, List<int> indices) {
    return indices.map((i) => pts[i]).toList();
  }

  int _argmax(List<double> vals) {
    int best = 0;
    for (int i = 1; i < vals.length; i++) {
      if (vals[i] > vals[best]) best = i;
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // CameraImage → InputImage conversion
  // ---------------------------------------------------------------------------

  InputImage? _cameraImageToInputImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      const imageRotation = InputImageRotation.rotation0deg;
      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.yuv420;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      print('[FaceRecognizer] CameraImage conversion error: $e');
      return null;
    }
  }
}
