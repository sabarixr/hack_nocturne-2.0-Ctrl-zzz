import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/lesson_mock_data.dart';
import 'package:expresto/data/mock/practice_mock_data.dart';
import 'package:expresto/models/practice_data.dart';
import 'package:expresto/pages/calibration.dart';
import 'package:expresto/pages/lesson.dart';
import 'package:flutter/material.dart';

class PracticePage extends StatelessWidget {
  const PracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = practiceMockData;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildOverallProgress(data),
                  const SizedBox(height: 16),
                  ...data.categories.map(
                    (category) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildCategoryCard(context, category: category),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                Icons.school_outlined,
                color: AppColors.textPrimary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'Practice',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.shellBorder),
              ),
              child: const Icon(
                Icons.home_filled,
                color: AppColors.textMuted,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallProgress(PracticeDashboardData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overall Progress',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${data.overallProgress}%',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.shellBorder,
              borderRadius: BorderRadius.circular(100),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: data.overallProgress / 100,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: const LinearGradient(
                    colors: [AppColors.emergency, AppColors.warning],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem(
                Icons.local_fire_department,
                '${data.currentStreak} day streak',
              ),
              _buildStatItem(
                Icons.menu_book_outlined,
                '${data.signsLearned}/${data.totalSigns} signs',
              ),
              _buildStatItem(
                Icons.star_outline,
                '${data.averageAccuracy}% avg',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required PracticeCategory category,
  }) {
    return GestureDetector(
      onTap: () {
        if (category.routeKey == 'lesson') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LessonPage(data: lessonMockDataHELP),
            ),
          );
        } else if (category.routeKey == 'medical') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LessonPage(data: lessonMockDataAMBULANCE),
            ),
          );
        } else if (category.routeKey == 'fire') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LessonPage(data: lessonMockDataFIRE),
            ),
          );
        } else if (category.routeKey == 'calibration') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CalibrationPage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${category.title} comes next.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: category.borderColor ?? AppColors.shellBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: category.iconBgColor ?? AppColors.shellBorder,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                category.icon,
                size: 24,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    category.subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 4,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.shellBorder,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: category.progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: category.progressColor,
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Icon(
              Icons.chevron_right,
              color: category.arrowColor ?? AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textMuted, size: 14),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}
