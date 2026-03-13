import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/bystander_mock_data.dart';
import 'package:expresto/models/bystander_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BystanderPage extends StatefulWidget {
  const BystanderPage({super.key});

  @override
  State<BystanderPage> createState() => _BystanderPageState();
}

class _BystanderPageState extends State<BystanderPage> {
  late final TextEditingController _messageController;
  bool _showAvatar = true;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      text: bystanderMockData.operatorMessage,
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const data = bystanderMockData;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF090B10), Color(0xFF040507)],
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
              children: [
                _Header(
                  title: data.title,
                  onExit: () => Navigator.pop(context),
                ),
                const SizedBox(height: 16),
                _AlertStrip(message: data.alertMessage),
                const SizedBox(height: 14),
                _SummaryPanel(data: data),
                const SizedBox(height: 14),
                _InstructionsPanel(data: data),
                const SizedBox(height: 14),
                _QuickPhraseSection(
                  data: data,
                  onPhraseTap: (phrase) {
                    _messageController.text = phrase.label;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Queued: ${phrase.label}'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _MessageComposer(
                  controller: _messageController,
                  label: data.operatorLabel,
                  hintText: data.inputHint,
                  onSend: () {
                    FocusScope.of(context).unfocus();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Update sent to operator.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _AvatarPanel(
                  showAvatarLabel: data.showAvatarLabel,
                  value: _showAvatar,
                  onChanged: (value) => setState(() => _showAvatar = value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onExit});

  final String title;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.groups_rounded, color: AppColors.blue, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
        ),
        TextButton(
          onPressed: onExit,
          style: TextButton.styleFrom(
            backgroundColor: AppColors.panel,
            foregroundColor: AppColors.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Exit'),
        ),
      ],
    );
  }
}

class _AlertStrip extends StatelessWidget {
  const _AlertStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8A5810)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFB439),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.data});

  final BystanderData data;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      borderColor: AppColors.emergencyBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notification_important_rounded,
                color: AppColors.emergency,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                data.summaryTitle,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(data.summaryItems.length, (index) {
            final item = data.summaryItems[index];
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: index == data.summaryItems.length - 1
                      ? BorderSide.none
                      : const BorderSide(color: AppColors.divider),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    item.value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF153421),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_hospital_rounded,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.arrivalMessage,
                    style: const TextStyle(
                      color: Color(0xFF3AE06C),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionsPanel extends StatelessWidget {
  const _InstructionsPanel({required this.data});

  final BystanderData data;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.instructionsTitle,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(data.instructions.length, (index) {
            final number = index + 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        color: AppColors.emergency,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data.instructions[index],
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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

class _QuickPhraseSection extends StatelessWidget {
  const _QuickPhraseSection({required this.data, required this.onPhraseTap});

  final BystanderData data;
  final ValueChanged<BystanderQuickPhrase> onPhraseTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.quickPhrasesTitle,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            letterSpacing: 2.6,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: data.quickPhrases
              .map(
                (phrase) => _QuickPhraseChip(
                  phrase: phrase,
                  onTap: () => onPhraseTap(phrase),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _QuickPhraseChip extends StatelessWidget {
  const _QuickPhraseChip({required this.phrase, required this.onTap});

  final BystanderQuickPhrase phrase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (borderColor, icon, iconColor) = switch (phrase.sentiment) {
      QuickPhraseSentiment.positive => (
        const Color(0xFF32493A),
        Icons.check_box_rounded,
        AppColors.success,
      ),
      QuickPhraseSentiment.warning => (
        const Color(0xFF5A4620),
        Icons.warning_rounded,
        AppColors.warning,
      ),
      QuickPhraseSentiment.danger => (
        const Color(0xFF5E2830),
        Icons.notification_important_rounded,
        AppColors.emergency,
      ),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.panelSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                phrase.label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, color: iconColor, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.onSend,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: const Color(0xFF0C0F17),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.shellBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.shellBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.blue),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onSend,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPanel extends StatelessWidget {
  const _AvatarPanel({
    required this.showAvatarLabel,
    required this.value,
    required this.onChanged,
  });

  final String showAvatarLabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.shellBorder),
            ),
            child: const Icon(
              Icons.interpreter_mode_rounded,
              color: AppColors.textPrimary,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              showAvatarLabel,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.blue,
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.borderColor});

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor ?? AppColors.shellBorder),
      ),
      child: child,
    );
  }
}
