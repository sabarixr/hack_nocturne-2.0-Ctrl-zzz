import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/call_history_mock_data.dart';
import 'package:expresto/models/call_history_data.dart';
import 'package:expresto/pages/view_transcript.dart';
import 'package:flutter/material.dart';

class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage({super.key});

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  CallHistoryType? _selectedType;

  @override
  Widget build(BuildContext context) {
    const data = callHistoryMockData;
    final entries = data.entries
        .where((entry) => _selectedType == null || entry.type == _selectedType)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF090B10), Color(0xFF040507)],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.bar_chart_rounded,
                    color: AppColors.textPrimary,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    data.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.home_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: data.filters.map((filter) {
                    final isSelected =
                        filter.type == _selectedType ||
                        (filter.type == null && _selectedType == null);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedType = filter.type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.emergency
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.emergency
                                  : AppColors.shellBorder,
                            ),
                          ),
                          child: Text(
                            filter.label,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              ...entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _HistoryCard(entry: entry),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final CallHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final leadingIcon = entry.type == CallHistoryType.emergency
        ? Icons.notification_important_rounded
        : Icons.call_rounded;
    final leadingColor = entry.type == CallHistoryType.emergency
        ? AppColors.emergency
        : AppColors.textMuted;
    final badgeBackground = entry.type == CallHistoryType.emergency
        ? const Color(0xFF173722)
        : const Color(0xFF123662);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: entry.type == CallHistoryType.emergency
              ? AppColors.emergencyBorder
              : AppColors.shellBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(leadingIcon, color: leadingColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badgeBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  entry.badgeLabel,
                  style: TextStyle(
                    color: entry.badgeColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            entry.dateTimeLabel,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
          ),
          const SizedBox(height: 12),
          ...entry.metadata.map(
            (meta) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      meta.label,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    meta.value,
                    style: TextStyle(
                      color: meta.valueColor ?? const Color(0xFFD3D8E6),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: entry.actions
                .map(
                  (label) => OutlinedButton(
                    onPressed: () {
                      if (label == 'View Transcript') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ViewTranscriptPage(entry: entry),
                          ),
                        );
                        return;
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$label coming next.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      side: const BorderSide(color: AppColors.shellBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(label),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
