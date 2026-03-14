// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import 'package:expresto/core/api_client.dart';
import 'package:expresto/core/ml/bayesian_urgency_engine.dart';
import 'package:expresto/core/ml/calibration_engine.dart';

// ---------------------------------------------------------------------------
// GraphQL mutation
// ---------------------------------------------------------------------------

const _kSubmitFrameMutation = r'''
  mutation SubmitFrame($input: SubmitFrameInput!) {
    submitFrame(input: $input) {
      recognizedSigns
      signConfidence
      handDetected
      faceDetected
      emotionNeutral
      emotionHappy
      emotionSad
      emotionSurprise
      emotionAfraid
      emotionDisgust
      emotionAngry
      signingSpeed
      tremorLevel
      urgencyScore
    }
  }
''';

// ---------------------------------------------------------------------------
// Isolate worker: convert CameraImage (YUV / BGRA) → JPEG bytes
//
// Runs entirely off the UI thread so the camera stream never stutters.
// ---------------------------------------------------------------------------

/// Message sent into the isolate.
class _EncodeRequest {
  final SendPort replyPort;
  final int width;
  final int height;
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final int format; // CameraImage.format.raw

  const _EncodeRequest({
    required this.replyPort,
    required this.width,
    required this.height,
    required this.planes,
    required this.bytesPerRow,
    required this.format,
  });
}

/// Top-level function (required for Isolate.spawn).
void _isolateEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((dynamic msg) {
    if (msg is _EncodeRequest) {
      try {
        final jpeg = _convertToJpeg(msg);
        msg.replyPort.send(jpeg);
      } catch (e) {
        msg.replyPort.send(null);
      }
    }
  });
}

/// Minimal YUV420 → JPEG via Flutter's built-in `encodeImageAsBytes`
/// (uses the `image` package approach but without any external dependency).
///
/// For Android: format is YUV420 (ImageFormat 35).
/// For iOS:     format is BGRA8888 (kCVPixelFormatType_32BGRA = 1111970369).
Uint8List? _convertToJpeg(_EncodeRequest req) {
  // BGRA8888 — iOS / some Android
  const int kBGRA8888 = 1111970369;
  // YUV_420_888 — most Android
  const int kYUV420 = 35;

  late Uint8List rgbaBytes;
  final w = req.width;
  final h = req.height;

  if (req.format == kBGRA8888) {
    // Plane 0 is BGRA, just swap B and R to get RGBA
    final src = req.planes[0];
    rgbaBytes = Uint8List(w * h * 4);
    for (int i = 0; i < w * h; i++) {
      final base = i * 4;
      rgbaBytes[base] = src[base + 2]; // R
      rgbaBytes[base + 1] = src[base + 1]; // G
      rgbaBytes[base + 2] = src[base]; // B
      rgbaBytes[base + 3] = 255; // A
    }
  } else {
    // Assume YUV_420_888 (Android default)
    final yPlane = req.planes[0];
    final uPlane = req.planes[1];
    final vPlane = req.planes[2];
    final uvRowStride = req.bytesPerRow[1];
    final uvPixelStride = req.planes.length > 2 ? 2 : 1;

    rgbaBytes = Uint8List(w * h * 4);
    int idx = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int yIndex = y * req.bytesPerRow[0] + x;
        final int uvIndex = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;

        final int Y = yPlane[yIndex] & 0xFF;
        final int U = (uPlane.length > uvIndex ? uPlane[uvIndex] & 0xFF : 128);
        final int V = (vPlane.length > uvIndex ? vPlane[uvIndex] & 0xFF : 128);

        final int r = (Y + 1.370705 * (V - 128)).clamp(0, 255).toInt();
        final int g = (Y - 0.698001 * (V - 128) - 0.337633 * (U - 128))
            .clamp(0, 255)
            .toInt();
        final int b = (Y + 1.732446 * (U - 128)).clamp(0, 255).toInt();

        rgbaBytes[idx++] = r;
        rgbaBytes[idx++] = g;
        rgbaBytes[idx++] = b;
        rgbaBytes[idx++] = 255;
      }
    }
  }

  // Encode as JPEG using Flutter's built-in codec (no external dep needed)
  // encodeImageAsBytes is not available synchronously, so we use a simple
  // BMP-style approach: write the raw RGBA as PNG via the ui.Image codec.
  // Actually the simplest zero-dep path: just use the raw bytes as-is
  // and let the server decode; but the server expects JPEG/base64.
  //
  // We use the `image` package approach reconstructed inline:
  // tiny JPEG encoder (quality 75) — pure Dart, no file I/O.
  return _encodeJpeg(rgbaBytes, w, h);
}

// ---------------------------------------------------------------------------
// Tiny pure-Dart JPEG encoder (quality=75, no external package required)
// Based on the Independent JPEG Group's algorithm, simplified for 3-channel.
// ---------------------------------------------------------------------------

Uint8List _encodeJpeg(
  Uint8List rgba,
  int width,
  int height, {
  int quality = 75,
}) {
  // Use Flutter's compute-friendly path: write as raw bytes with JPEG header
  // via the dart:ui Image API. Since this runs in an Isolate we can't use
  // dart:ui. Instead we use the simplest possible approach: encode as a
  // minimal valid JPEG using pure math.
  //
  // For hackathon purposes we encode as PNG-ish raw bytes wrapped in a
  // pseudo-JPEG structure that MediaPipe / OpenCV on the server can handle.
  // The server does: cv2.imdecode(np.frombuffer(base64.b64decode(data), np.uint8), cv2.IMREAD_COLOR)
  // cv2.imdecode handles both JPEG and PNG automatically.
  //
  // So: encode as PNG using a minimal pure-Dart implementation.
  return _encodePng(rgba, width, height);
}

/// Minimal PNG encoder — pure Dart, no dart:ui required, works in Isolates.
/// Produces a valid grayscale-optional RGB PNG that cv2.imdecode can read.
Uint8List _encodePng(Uint8List rgba, int width, int height) {
  // PNG signature
  final sig = [137, 80, 78, 71, 13, 10, 26, 10];

  // IHDR chunk
  final ihdr = _pngChunk(
    'IHDR',
    _bytes([
      ..._u32(width),
      ..._u32(height),
      8, // bit depth
      2, // color type: RGB
      0, 0, 0, // compression, filter, interlace
    ]),
  );

  // IDAT chunk — filtered scanlines
  final scanlines = BytesBuilder();
  for (int y = 0; y < height; y++) {
    scanlines.addByte(0); // filter type: None
    for (int x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      scanlines.addByte(rgba[i]);
      scanlines.addByte(rgba[i + 1]);
      scanlines.addByte(rgba[i + 2]);
    }
  }
  final raw = scanlines.toBytes();
  final compressed = _zlibDeflate(raw);
  final idat = _pngChunk('IDAT', compressed);

  // IEND chunk
  final iend = _pngChunk('IEND', Uint8List(0));

  final out = BytesBuilder();
  out.add(sig);
  out.add(ihdr);
  out.add(idat);
  out.add(iend);
  return out.toBytes();
}

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);
List<int> _u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = type.codeUnits;
  final length = _u32(data.length);
  final crcData = [...typeBytes, ...data];
  final crc = _crc32(Uint8List.fromList(crcData));
  final out = BytesBuilder();
  out.add(length);
  out.add(typeBytes);
  out.add(data);
  out.add(_u32(crc));
  return out.toBytes();
}

// CRC32 for PNG chunks
int _crc32(Uint8List data) {
  const poly = 0xEDB88320;
  final table = List<int>.generate(256, (i) {
    int c = i;
    for (int j = 0; j < 8; j++) {
      c = (c & 1) != 0 ? (poly ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });
  int crc = 0xFFFFFFFF;
  for (final b in data) {
    crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}

// Minimal zlib/deflate (store-only, no compression) — valid zlib stream
Uint8List _zlibDeflate(Uint8List data) {
  // zlib header: CMF=0x78 (deflate, window=32K), FLG computed for no dict
  const cmf = 0x78;
  const flg =
      0x01; // CMF*256+FLG must be divisible by 31: 0x7801 = 30721, 30721%31=0? 30721/31=991, 991*31=30721 yes
  final out = BytesBuilder();
  out.addByte(cmf);
  out.addByte(flg);

  // Non-compressed deflate blocks (BTYPE=00), max 65535 bytes each
  int offset = 0;
  while (offset < data.length) {
    final blockLen = (data.length - offset).clamp(0, 65535);
    final isLast = (offset + blockLen) >= data.length;
    out.addByte(isLast ? 0x01 : 0x00); // BFINAL + BTYPE=00
    // LEN (2 bytes LE) and NLEN (one's complement)
    out.addByte(blockLen & 0xFF);
    out.addByte((blockLen >> 8) & 0xFF);
    out.addByte((~blockLen) & 0xFF);
    out.addByte(((~blockLen) >> 8) & 0xFF);
    out.add(data.sublist(offset, offset + blockLen));
    offset += blockLen;
  }

  // Adler-32 checksum
  int s1 = 1, s2 = 0;
  for (final b in data) {
    s1 = (s1 + b) % 65521;
    s2 = (s2 + s1) % 65521;
  }
  final adler = (s2 << 16) | s1;
  out.add(_u32(adler));
  return out.toBytes();
}

// ---------------------------------------------------------------------------
// SignRecognizerService
// ---------------------------------------------------------------------------

/// Server-side ML sign recognizer using camera image stream.
///
/// Uses [CameraController.startImageStream] to capture frames at the camera's
/// native rate. Every [_kTargetFps] frames are throttled and sent to an
/// [Isolate] for JPEG encoding, then submitted via the `submitFrame` mutation
/// (fire-and-forget — no blocking await on the response).
///
/// Result is received asynchronously and fed into [BayesianUrgencyEngine]
/// which calls [updateFromServer] using the server's urgency_score directly.
class SignRecognizerService {
  final String callId;

  BayesianUrgencyEngine? _urgencyEngine;
  bool _capturing = false;
  CameraController? _controller;

  // Fire-and-forget guard: only one in-flight HTTP request at a time.
  // If the server is slower than our capture rate, frames are dropped
  // (better than queue pile-up).
  bool _processingFrame = false;

  // Target capture rate for the backend pipeline.
  // 20 fps = one frame every 50 ms.
  static const int _kTargetFps = 20;
  static const Duration _kFrameInterval = Duration(
    milliseconds: 1000 ~/ _kTargetFps,
  );
  DateTime _lastFrameSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Background isolate for JPEG encoding
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _isolateReceivePort;

  SignRecognizerService({required this.callId});

  // ---------------------------------------------------------------------------
  // Public stream
  // ---------------------------------------------------------------------------

  Stream<UrgencyUpdate> get urgencyStream =>
      _urgencyEngine?.stream ?? const Stream.empty();

  // ---------------------------------------------------------------------------
  // Calibration
  // ---------------------------------------------------------------------------

  Future<void> loadCalibration() async {
    final baseline = await CalibrationEngine.loadBaseline();
    if (baseline != null) {
      _urgencyEngine?.updateBaseline(baseline);
      print('[SignRecognizer] loaded calibration baseline');
    } else {
      print('[SignRecognizer] no saved baseline — using neutral default');
    }
  }

  // ---------------------------------------------------------------------------
  // Start / Stop
  // ---------------------------------------------------------------------------

  Future<void> startProcessing(CameraController controller) async {
    if (_capturing) return;

    print(
      '[SignRecognizer] starting image-stream ML pipeline @ ${_kTargetFps}fps',
    );

    final baseline = await CalibrationEngine.loadBaseline();
    _urgencyEngine = BayesianUrgencyEngine(baseline: baseline);
    _controller = controller;
    _capturing = true;

    await _spawnIsolate();

    controller.startImageStream(_onCameraImage);
  }

  Future<void> stopProcessing() async {
    if (!_capturing) return;
    _capturing = false;

    try {
      await _controller?.stopImageStream();
    } catch (_) {}

    _isolateReceivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    _isolateReceivePort = null;

    _urgencyEngine?.dispose();
    _urgencyEngine = null;
    _controller = null;
    print('[SignRecognizer] stopped');
  }

  // ---------------------------------------------------------------------------
  // Isolate management
  // ---------------------------------------------------------------------------

  Future<void> _spawnIsolate() async {
    _isolateReceivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _isolateEntry,
      _isolateReceivePort!.sendPort,
    );

    // First message is the isolate's SendPort
    final completer = Completer<SendPort>();
    _isolateReceivePort!.listen((msg) {
      if (!completer.isCompleted && msg is SendPort) {
        completer.complete(msg);
      }
      // After handshake, subsequent messages are ignored here;
      // individual encode requests carry their own reply ports.
    });
    _isolateSendPort = await completer.future;
  }

  // ---------------------------------------------------------------------------
  // Camera image stream callback (runs on UI thread, must be fast)
  // ---------------------------------------------------------------------------

  void _onCameraImage(CameraImage image) {
    if (!_capturing) return;

    // Throttle to target FPS
    final now = DateTime.now();
    if (now.difference(_lastFrameSent) < _kFrameInterval) return;

    // Drop if a frame is already being processed
    if (_processingFrame) return;

    _processingFrame = true;
    _lastFrameSent = now;

    // Copy plane data immediately (the CameraImage buffer may be reused)
    final planes = image.planes
        .map((p) => Uint8List.fromList(p.bytes))
        .toList();
    final bytesPerRow = image.planes.map((p) => p.bytesPerRow).toList();
    final width = image.width;
    final height = image.height;
    final format = image.format.raw;

    // Encode + submit entirely off the critical path
    _encodeAndSubmit(width, height, planes, bytesPerRow, format);
  }

  // ---------------------------------------------------------------------------
  // Encode in isolate then submit
  // ---------------------------------------------------------------------------

  Future<void> _encodeAndSubmit(
    int width,
    int height,
    List<Uint8List> planes,
    List<int> bytesPerRow,
    int format,
  ) async {
    try {
      final replyPort = ReceivePort();
      _isolateSendPort?.send(
        _EncodeRequest(
          replyPort: replyPort.sendPort,
          width: width,
          height: height,
          planes: planes,
          bytesPerRow: bytesPerRow,
          format: format,
        ),
      );

      final result = await replyPort.first;
      replyPort.close();

      if (result is! Uint8List) {
        print('[SignRecognizer] encode failed');
        return;
      }

      final frameData = base64Encode(result);
      // Fire-and-forget — do not await, so the next frame isn't blocked
      _submitFrame(frameData);
    } catch (e) {
      print('[SignRecognizer] encode/submit error: $e');
    } finally {
      _processingFrame = false;
    }
  }

  // ---------------------------------------------------------------------------
  // GraphQL submission (fire-and-forget)
  // ---------------------------------------------------------------------------

  Future<void> _submitFrame(String frameData) async {
    QueryResult result;
    try {
      result = await ApiClient.client.value.mutate(
        MutationOptions(
          document: gql(_kSubmitFrameMutation),
          variables: {
            'input': {'callId': callId, 'frameData': frameData},
          },
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
    } catch (e) {
      print('[SignRecognizer] submit error: $e');
      return;
    }

    if (result.hasException) {
      print('[SignRecognizer] GraphQL error: ${result.exception}');
      return;
    }

    final data = result.data?['submitFrame'] as Map<String, dynamic>?;
    if (data == null) return;

    _processMLResult(data);
  }

  // ---------------------------------------------------------------------------
  // Build UrgencyUpdate from server FrameMLResult
  // ---------------------------------------------------------------------------

  void _processMLResult(Map<String, dynamic> ml) {
    final engine = _urgencyEngine;
    if (engine == null) return;

    final serverUrgencyScore = (ml['urgencyScore'] as num?)?.toDouble() ?? 0.0;

    final emotions = <String, double>{
      'neutral': (ml['emotionNeutral'] as num?)?.toDouble() ?? 1.0,
      'happy': (ml['emotionHappy'] as num?)?.toDouble() ?? 0.0,
      'sad': (ml['emotionSad'] as num?)?.toDouble() ?? 0.0,
      'surprise': (ml['emotionSurprise'] as num?)?.toDouble() ?? 0.0,
      'afraid': (ml['emotionAfraid'] as num?)?.toDouble() ?? 0.0,
      'disgust': (ml['emotionDisgust'] as num?)?.toDouble() ?? 0.0,
      'angry': (ml['emotionAngry'] as num?)?.toDouble() ?? 0.0,
    };

    final rawSigns = ml['recognizedSigns'];
    final List<String> signs = rawSigns is List
        ? rawSigns.map((s) => s.toString().toLowerCase()).toList()
        : <String>[];

    final signingSpeed = (ml['signingSpeed'] as num?)?.toDouble() ?? 0.0;
    final tremorLevel = (ml['tremorLevel'] as num?)?.toDouble() ?? 0.0;
    final faceDetected = ml['faceDetected'] as bool? ?? false;
    final handDetected = ml['handDetected'] as bool? ?? false;

    engine.updateFromServer(
      serverUrgencyScore: serverUrgencyScore,
      emotions: emotions,
      detectedSigns: signs,
      signingSpeed: signingSpeed,
      tremorLevel: tremorLevel,
      faceDetected: faceDetected,
      handDetected: handDetected,
    );

    print(
      '[SignRecognizer] urgency=${serverUrgencyScore.toStringAsFixed(2)} '
      'signs=$signs hand=$handDetected face=$faceDetected',
    );
  }
}
