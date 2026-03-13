import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/silent_mode_mock_data.dart';
import 'package:expresto/models/silent_mode_data.dart';
import 'package:flutter/material.dart';

class SilentEmergencyPage extends StatefulWidget {
  const SilentEmergencyPage({super.key});

  @override
  State<SilentEmergencyPage> createState() => _SilentEmergencyPageState();
}

class _SilentEmergencyPageState extends State<SilentEmergencyPage> {
  int _tapCount = 0;
  DateTime? _lastTap;

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
                    _CameraStatusCard(label: data.cameraStatus),
                    const SizedBox(height: 18),
                    _StatusPanel(items: data.statusItems),
                    const SizedBox(height: 18),
                    _HapticPanel(data: data),
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
  const _CameraStatusCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF11151E)),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF202632),
            fontSize: 19,
            letterSpacing: 1.2,
          ),
        ),
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
  const _HapticPanel({required this.data});

  final SilentModeData data;

  @override
  Widget build(BuildContext context) {
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
          ...data.haptics.map((item) {
            final color = item.isDanger
                ? AppColors.emergency
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
                        fontWeight: item.isDanger
                            ? FontWeight.w700
                            : FontWeight.w500,
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
