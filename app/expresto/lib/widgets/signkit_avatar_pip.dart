import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class SignKitAvatarPiP extends StatefulWidget {
  const SignKitAvatarPiP({
    super.key,
    required this.assetPath,
    this.predictedSign,
  });

  final String assetPath;
  final String? predictedSign;

  @override
  State<SignKitAvatarPiP> createState() => _SignKitAvatarPiPState();
}

class _SignKitAvatarPiPState extends State<SignKitAvatarPiP> {
  static const _convertUrl = 'https://sign-kit.vercel.app/sign-kit/convert';

  WebViewController? _controller;
  bool _pageLoaded = false;
  String? _lastSpokenText;

  bool get _supportsWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    if (_supportsWebView) {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) async {
              _pageLoaded = true;
              await _prepareRemotePage();
              await _syncSpeech(force: true);
            },
          ),
        )
        ..loadRequest(Uri.parse(_convertUrl));

      if (controller.platform is AndroidWebViewController) {
        AndroidWebViewController.enableDebugging(true);
        (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }

      _controller = controller;
    }
  }

  @override
  void didUpdateWidget(covariant SignKitAvatarPiP oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pageLoaded) {
      _syncSpeech();
    }
  }

  Future<void> _prepareRemotePage() async {
    final controller = _controller;
    if (controller == null) return;

    await controller.runJavaScript(r'''
      (() => {
        const styleId = 'flutter-signkit-overlay-style';
        if (!document.getElementById(styleId)) {
          const style = document.createElement('style');
          style.id = styleId;
          style.textContent = `
            html, body {
              margin: 0 !important;
              padding: 0 !important;
              width: 100vw !important;
              height: 100vh !important;
              overflow: hidden !important;
              background: #0b1118 !important;
            }
            body * {
              box-sizing: border-box !important;
            }
            .col-md-3, .col-md-2,
            nav, footer, .navbar, .bot-label,
            img.bot-image, .label-style,
            button:not(.keep-signkit-start),
            textarea:not(.keep-signkit-input),
            .space-between {
              display: none !important;
            }
            .container-fluid, .container-fluid > .row, .col-md-7, #canvas {
              margin: 0 !important;
              padding: 0 !important;
              width: 100vw !important;
              height: 100vh !important;
              max-width: none !important;
              flex: 0 0 100% !important;
            }
            #canvas canvas {
              width: 100vw !important;
              height: 100vh !important;
              display: block !important;
            }
          `;
          document.head.appendChild(style);
        }

        const markElements = () => {
          const textareas = Array.from(document.querySelectorAll('textarea'));
          const editable = textareas.filter((element) => !element.readOnly);
          const input = editable[editable.length - 1];
          if (input) {
            input.classList.add('keep-signkit-input');
          }

          const buttons = Array.from(document.querySelectorAll('button'));
          const startButtons = buttons.filter((button) =>
            button.textContent && button.textContent.toLowerCase().includes('start animations')
          );
          const startButton = startButtons[startButtons.length - 1];
          if (startButton) {
            startButton.classList.add('keep-signkit-start');
          }
        };

        markElements();
        const observer = new MutationObserver(() => markElements());
        observer.observe(document.body, { childList: true, subtree: true });

        window.flutterSignKitOverlay = {
          setTextAndAnimate(text) {
            const textareas = Array.from(document.querySelectorAll('textarea'));
            const editable = textareas.filter((element) => !element.readOnly);
            const input = editable[editable.length - 1];
            const buttons = Array.from(document.querySelectorAll('button'));
            const startButtons = buttons.filter((button) =>
              button.textContent && button.textContent.toLowerCase().includes('start animations')
            );
            const startButton = startButtons[startButtons.length - 1];

            if (!input || !startButton) {
              return false;
            }

            input.focus();
            const descriptor = Object.getOwnPropertyDescriptor(
              window.HTMLTextAreaElement.prototype,
              'value',
            );
            if (descriptor && descriptor.set) {
              descriptor.set.call(input, text);
            } else {
              input.value = text;
            }
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
            startButton.click();
            return true;
          },
        };
      })();
    ''');
  }

  Future<void> _syncSpeech({bool force = false}) async {
    final controller = _controller;
    if (controller == null) return;

    final phrase = widget.predictedSign?.trim();
    if (phrase == null || phrase.isEmpty) return;
    if (!force && _lastSpokenText == phrase) return;

    _lastSpokenText = phrase;
    final escaped = phrase
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', ' ');

    await controller.runJavaScript(
      "window.flutterSignKitOverlay && window.flutterSignKitOverlay.setTextAndAnimate('$escaped');",
    );
  }

  Widget _buildWebView() {
    final controller = _controller;
    if (controller == null) {
      return const ColoredBox(
        color: Color(0xFF0F1620),
        child: Center(
          child: Icon(
            Icons.interpreter_mode_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final params = AndroidWebViewWidgetCreationParams(
        controller: controller.platform,
        displayWithHybridComposition: true,
      );
      return WebViewWidget.fromPlatformCreationParams(params: params);
    }

    return WebViewWidget(controller: controller);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildWebView(),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1F62A8), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

