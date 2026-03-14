import 'dart:async';
import 'package:expresto/core/ml/bayesian_urgency_engine.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/emergency_mock_data.dart';
import 'package:expresto/models/emergency_session_data.dart';
import 'package:expresto/pages/bystander.dart';
import 'package:expresto/pages/silent_emergency.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:expresto/core/api_client.dart';
import 'package:expresto/core/sign_recognizer.dart';

// ---------------------------------------------------------------------------
// GraphQL strings
// ---------------------------------------------------------------------------

const _kTriggerEmergencyMutation = r'''
  mutation TriggerEmergency($callId: ID!) {
    triggerEmergency(callId: $callId) {
      id
      status
      peakUrgencyScore
    }
  }
''';

const _kSendMessageMutation = r'''
  mutation SendMessage($callId: ID!, $text: String!) {
    sendMessage(callId: $callId, text: $text) {
      id
      text
      sentAt
    }
  }
''';

const _kOperatorMessageSubscription = r'''
  subscription OperatorMessageReceived($callId: ID!) {
    operatorMessageReceived(callId: $callId) {
      messageId
      callId
      text
      sentAt
    }
  }
''';

// ---------------------------------------------------------------------------
// Data model for a chat message
// ---------------------------------------------------------------------------

class _ChatMessage {
  final String text;
  final bool isUser; // false = AI/operator
  final DateTime time;

  _ChatMessage({required this.text, required this.isUser, required this.time});
}

// ---------------------------------------------------------------------------
// Transcript entry model
// ---------------------------------------------------------------------------

class _TranscriptEntry {
  final String text;
  final _TranscriptKind kind;
  final DateTime time;
  _TranscriptEntry({
    required this.text,
    required this.kind,
    required this.time,
  });
}

enum _TranscriptKind { sign, userMessage }

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
  String? _callId;
  bool _isStartingCall = true;
  SignRecognizerService? _recognizer;
  StreamSubscription<QueryResult>? _callUpdateSub;
  StreamSubscription<QueryResult>? _operatorMsgSub;
  StreamSubscription<UrgencyUpdate>? _urgencyUpdateSub;

  List<String> _localDetectedSigns = [];
  bool _faceDetected = false;
  bool _handDetected = false;
  EmergencySessionData _sessionData = emergencyMockData;

  // Chat state
  final List<_ChatMessage> _messages = [];
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  bool _sendingMsg = false;
  bool _triggeringEmergency = false;

  // Transcript — live log of detected signs + user messages
  final List<_TranscriptEntry> _transcript = [];
  final ScrollController _transcriptScroll = ScrollController();
  // Debounce: avoid spamming transcript with the same sign every frame
  String _lastLoggedSign = '';
  DateTime _lastSignLogTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _cameraGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _initializeCamera();
    _startEmergencyCall();
  }

  @override
  void dispose() {
    _callUpdateSub?.cancel();
    _operatorMsgSub?.cancel();
    _urgencyUpdateSub?.cancel();
    _recognizer?.stopProcessing();
    _cameraController?.dispose();
    _cameraGlowController.dispose();
    _msgController.dispose();
    _chatScroll.dispose();
    _transcriptScroll.dispose();
    super.dispose();
  }

  // ── Urgency stream from ML ──────────────────────────────────────────────

  void _subscribeToLocalUrgency() {
    if (_recognizer == null) return;
    _urgencyUpdateSub?.cancel();
    _urgencyUpdateSub = _recognizer!.urgencyStream.listen((update) {
      if (!mounted) return;
      final percent = (update.urgencyScore * 100).clamp(0, 100).toInt();
      final bars = _buildUrgencyBars(update.urgencyScore);
      setState(() {
        _localDetectedSigns = update.detectedSigns;
        _faceDetected = update.faceDetected;
        _handDetected = update.handDetected;
        _sessionData = _sessionData.copyWith(
          urgencyPercent: percent,
          urgencyBars: bars,
          urgencyStatus: _urgencyLabel(update.urgencyScore),
        );
      });
      // Log new signs to transcript (debounced: same sign max once per 3s)
      for (final sign in update.detectedSigns) {
        final now = DateTime.now();
        if (sign != _lastLoggedSign ||
            now.difference(_lastSignLogTime).inSeconds >= 3) {
          _lastLoggedSign = sign;
          _lastSignLogTime = now;
          _addTranscriptEntry(sign.toUpperCase(), _TranscriptKind.sign);
        }
      }
    });
  }

  List<int> _buildUrgencyBars(double score) {
    final filled = (score * 9).round().clamp(0, 9);
    return List.generate(9, (i) => i < filled ? 7 : 1);
  }

  String _urgencyLabel(double score) {
    if (score >= 0.85) return 'CRITICAL';
    if (score >= 0.60) return 'HIGH';
    if (score >= 0.35) return 'ELEVATED';
    if (score >= 0.10) return 'LOW';
    return 'MONITORING';
  }

  // ── Call update subscription (WS) ──────────────────────────────────────

  void _listenToCallUpdates() {
    if (_callId == null) return;
    _callUpdateSub = ApiClient.client.value
        .subscribe(
          SubscriptionOptions(
            document: gql(r'''
        subscription EmergencyCallUpdated($callId: ID!) {
          emergencyCallUpdated(callId: $callId) {
            callId
            status
            peakUrgencyScore
            emergencyType
          }
        }
      '''),
            variables: {'callId': _callId},
          ),
        )
        .listen((result) {
          if (!mounted || result.hasException || result.data == null) return;
          final update = result.data!['emergencyCallUpdated'];
          if (update == null) return;
          final double score =
              (update['peakUrgencyScore'] as num?)?.toDouble() ?? 0.0;
          final int percent = (score * 100).clamp(0, 100).toInt();
          final String status = update['status'] ?? 'Unknown';
          setState(() {
            _sessionData = _sessionData.copyWith(
              urgencyPercent: percent,
              urgencyBars: _buildUrgencyBars(score),
              callState: status,
              urgencyStatus: _urgencyLabel(score),
            );
          });
        });
  }

  // ── Operator message subscription (WS) ─────────────────────────────────

  void _listenToOperatorMessages() {
    if (_callId == null) return;
    _operatorMsgSub = ApiClient.client.value
        .subscribe(
          SubscriptionOptions(
            document: gql(_kOperatorMessageSubscription),
            variables: {'callId': _callId},
          ),
        )
        .listen((result) {
          if (!mounted || result.hasException || result.data == null) return;
          final ev = result.data!['operatorMessageReceived'];
          if (ev == null) return;
          final text = ev['text'] as String? ?? '';
          if (text.isEmpty) return;
          // Skip messages the user sent themselves (backend echoes them back
          // via operator.message, but we already added them optimistically).
          if (text.startsWith('[USER]')) return;
          _addMessage(text, isUser: false);
        });
  }

  void _addMessage(String text, {required bool isUser}) {
    setState(() {
      _messages.add(
        _ChatMessage(text: text, isUser: isUser, time: DateTime.now()),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addTranscriptEntry(String text, _TranscriptKind kind) {
    if (!mounted) return;
    setState(() {
      _transcript.add(
        _TranscriptEntry(text: text, kind: kind, time: DateTime.now()),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_transcriptScroll.hasClients) {
        _transcriptScroll.animateTo(
          _transcriptScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Start call ──────────────────────────────────────────────────────────

  Future<void> _startEmergencyCall() async {
    try {
      final result = await ApiClient.client.value.mutate(
        MutationOptions(
          document: gql(r'''
          mutation StartCall {
            startCall(input: {
              emergencyType: "General"
            }) {
              id
              status
            }
          }
        '''),
        ),
      );
      if (mounted) {
        setState(() {
          _callId = result.data?['startCall']['id'];
          _isStartingCall = false;
        });
        if (_callId != null) {
          if (_cameraController != null) {
            _recognizer = SignRecognizerService(callId: _callId!);
            await _recognizer!.startProcessing(_cameraController!);
            _subscribeToLocalUrgency();
          }
          _listenToCallUpdates();
          _listenToOperatorMessages();
        }
      }
    } catch (e) {
      print("Failed to start call: $e");
      if (mounted) setState(() => _isStartingCall = false);
    }
  }

  // ── Camera init ─────────────────────────────────────────────────────────

  Future<void> _initializeCamera() async {
    try {
      await _cameraController?.dispose();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera available on this device.');
        return;
      }
      final selectedCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
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
      if (_callId != null && _recognizer == null) {
        _recognizer = SignRecognizerService(callId: _callId!);
        await _recognizer!.startProcessing(_cameraController!);
        _subscribeToLocalUrgency();
      }
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError =
            '${error.code}: ${error.description ?? 'Unable to access the camera.'}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _cameraError = 'Unable to start the live camera preview.\n$error',
      );
    }
  }

  // ── SOS: force urgency 100 ──────────────────────────────────────────────

  Future<void> _triggerSOS() async {
    if (_callId == null || _triggeringEmergency) return;
    setState(() => _triggeringEmergency = true);
    try {
      await ApiClient.client.value.mutate(
        MutationOptions(
          document: gql(_kTriggerEmergencyMutation),
          variables: {'callId': _callId},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      setState(() {
        _sessionData = _sessionData.copyWith(
          urgencyPercent: 100,
          urgencyStatus: 'CRITICAL',
          urgencyBars: List.filled(9, 7),
        );
      });
    } catch (e) {
      print('[SOS] error: $e');
    } finally {
      if (mounted) setState(() => _triggeringEmergency = false);
    }
  }

  // ── Send typed message ──────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _callId == null || _sendingMsg) return;
    _msgController.clear();
    _addMessage(text, isUser: true);
    _addTranscriptEntry(text, _TranscriptKind.userMessage);
    setState(() => _sendingMsg = true);
    try {
      await ApiClient.client.value.mutate(
        MutationOptions(
          document: gql(_kSendMessageMutation),
          variables: {'callId': _callId, 'text': text},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
    } catch (e) {
      print('[sendMessage] error: $e');
    } finally {
      if (mounted) setState(() => _sendingMsg = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final data = _sessionData;

    if (_isStartingCall) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.emergency),
        ),
      );
    }

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
              final cameraHeight = constraints.maxHeight * 0.44;
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
                        callId: _callId,
                        onEndCall: () => Navigator.pop(context),
                        faceDetected: _faceDetected,
                        handDetected: _handDetected,
                        onSOS: _triggerSOS,
                        triggeringEmergency: _triggeringEmergency,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _UrgencyPanel(
                              data: data,
                              detectedSigns: _localDetectedSigns,
                            ),
                            const SizedBox(height: 10),
                            // AI / Operator messages panel
                            _MessagesPanel(
                              messages: _messages,
                              scrollController: _chatScroll,
                            ),
                            const SizedBox(height: 10),
                            // Typed message input
                            _MessageInputBar(
                              controller: _msgController,
                              sending: _sendingMsg,
                              onSend: _sendMessage,
                            ),
                            const SizedBox(height: 10),
                            _TranscriptPanel(
                              transcript: _transcript,
                              scrollController: _transcriptScroll,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _BottomActionButton(
                                    icon: Icons.groups_rounded,
                                    label: 'Bystander',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const BystanderPage(),
                                      ),
                                    ),
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

// ---------------------------------------------------------------------------
// Camera Panel
// ---------------------------------------------------------------------------

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.animation,
    required this.data,
    required this.cameraController,
    required this.cameraInitialization,
    required this.cameraError,
    required this.callId,
    required this.onEndCall,
    required this.faceDetected,
    required this.handDetected,
    required this.onSOS,
    required this.triggeringEmergency,
  });

  final Animation<double> animation;
  final EmergencySessionData data;
  final CameraController? cameraController;
  final Future<void>? cameraInitialization;
  final String? cameraError;
  final String? callId;
  final VoidCallback onEndCall;
  final bool faceDetected;
  final bool handDetected;
  final VoidCallback onSOS;
  final bool triggeringEmergency;

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
          // gradient overlay
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
          // camera hint
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                data.cameraHint,
                style: const TextStyle(
                  color: Color(0xFF15DF6D),
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          // face frame
          Center(
            child: Container(
              width: 140,
              height: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF13C86C), width: 2),
              ),
            ),
          ),
          // avatar
          const Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: 12),
              child: _AvatarPreview(),
            ),
          ),
          // detection badges
          Positioned(
            bottom: 68,
            left: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetectionBadge(label: 'FACE', detected: faceDetected),
                const SizedBox(width: 6),
                _DetectionBadge(label: 'HAND', detected: handDetected),
              ],
            ),
          ),
          // bottom buttons row: Silent | SOS | End Call
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  // Silent
                  FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SilentEmergencyPage(callId: callId),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF202532),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(90, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Silent',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // SOS button
                  Expanded(
                    child: FilledButton(
                      onPressed: triggeringEmergency ? null : onSOS,
                      style: FilledButton.styleFrom(
                        backgroundColor: triggeringEmergency
                            ? AppColors.emergencyDeep
                            : AppColors.emergency,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: AppColors.emergencyBorder.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ),
                      child: triggeringEmergency
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.warning_rounded, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'SOS',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // End Call
                  FilledButton(
                    onPressed: onEndCall,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1C1F2B),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(90, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFF3A3E52)),
                      ),
                    ),
                    child: const Text(
                      'End',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Messages Panel (AI/Operator advice)
// ---------------------------------------------------------------------------

class _MessagesPanel extends StatelessWidget {
  const _MessagesPanel({
    required this.messages,
    required this.scrollController,
  });
  final List<_ChatMessage> messages;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.support_agent_rounded,
                color: Color(0xFF1CFF8A),
                size: 14,
              ),
              const SizedBox(width: 6),
              const Text(
                'AI RESPONSE',
                style: TextStyle(
                  color: Color(0xFF1CFF8A),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (messages.isEmpty)
                const Text(
                  'Waiting for analysis...',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
            ],
          ),
          if (messages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                controller: scrollController,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final msg = messages[i];
                  return _ChatBubble(message: msg);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.blue.withValues(alpha: 0.18)
              : const Color(0xFF0B2A15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUser
                ? AppColors.blue.withValues(alpha: 0.4)
                : const Color(0xFF096E3E).withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          message.text.replaceFirst(RegExp(r'^\[USER\] '), ''),
          style: TextStyle(
            color: isUser ? AppColors.textPrimary : const Color(0xFFB6F5D0),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message Input Bar
// ---------------------------------------------------------------------------

class _MessageInputBar extends StatelessWidget {
  const _MessageInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            color: AppColors.textMuted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Type a message to operator...',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => onSend(),
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: sending ? AppColors.shellBorder : AppColors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: sending
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Urgency Panel
// ---------------------------------------------------------------------------

class _UrgencyPanel extends StatelessWidget {
  const _UrgencyPanel({required this.data, required this.detectedSigns});

  final EmergencySessionData data;
  final List<String> detectedSigns;

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
          if (detectedSigns.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: detectedSigns
                  .map(
                    (sign) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F1D29),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.emergency.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        sign.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.emergency,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transcript Panel
// ---------------------------------------------------------------------------

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({
    required this.transcript,
    required this.scrollController,
  });
  final List<_TranscriptEntry> transcript;
  final ScrollController scrollController;

  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: _GlassPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.content_paste_rounded,
                  color: AppColors.teal,
                  size: 14,
                ),
                const SizedBox(width: 8),
                const Text(
                  'TRANSCRIPT',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(width: 8),
                if (transcript.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${transcript.length}',
                      style: const TextStyle(
                        color: AppColors.teal,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Body
            if (transcript.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Waiting for signs...',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  controller: scrollController,
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: transcript.length,
                  itemBuilder: (context, index) {
                    final entry = transcript[index];
                    final isSign = entry.kind == _TranscriptKind.sign;
                    final iconData = isSign
                        ? Icons.sign_language_rounded
                        : Icons.chat_bubble_outline_rounded;
                    final color = isSign ? AppColors.teal : AppColors.blue;
                    final textColor = isSign
                        ? AppColors.teal
                        : AppColors.textPrimary;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fmt(entry.time),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(iconData, color: color, size: 13),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              entry.text,
                              style: TextStyle(color: textColor, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Misc widgets (unchanged visual)
// ---------------------------------------------------------------------------

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D28).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF36354C), width: 2),
      ),
      child: const Center(
        child: Icon(
          Icons.interpreter_mode_rounded,
          color: AppColors.textPrimary,
          size: 28,
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
    if (error != null) return _CameraStatus(message: error!);
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

class _DetectionBadge extends StatelessWidget {
  const _DetectionBadge({required this.label, required this.detected});
  final String label;
  final bool detected;

  @override
  Widget build(BuildContext context) {
    final dotColor = detected ? AppColors.teal : AppColors.textMuted;
    final textColor = detected ? AppColors.teal : AppColors.textMuted;
    final bgColor = detected
        ? AppColors.teal.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.45);
    final borderColor = detected
        ? AppColors.teal.withValues(alpha: 0.4)
        : AppColors.shellBorder.withValues(alpha: 0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
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
