import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/models/home_dashboard_data.dart';
import 'package:flutter/material.dart';

class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.stat, required this.isLast});

  final HomeStat stat;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final valueColor = stat.highlight
        ? AppColors.success
        : AppColors.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: AppColors.divider),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stat.label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 16),
            ),
          ),
          Text(
            stat.value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
