import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/models/practice_data.dart';
import 'package:flutter/material.dart';

final PracticeDashboardData practiceMockData = PracticeDashboardData(
  overallProgress: 73,
  currentStreak: 7,
  signsLearned: 38,
  totalSigns: 60,
  averageAccuracy: 89,
  categories: [
    const PracticeCategory(
      icon: Icons.warning_amber_rounded,
      title: 'Emergency Signs',
      subtitle: '18/20 learned',
      progress: 0.9,
      progressColor: AppColors.success,
      routeKey: 'lesson',
    ),
    const PracticeCategory(
      icon: Icons.local_hospital_outlined,
      title: 'Medical Vocabulary',
      subtitle: '12/25 learned',
      progress: 0.48,
      progressColor: AppColors.warning,
      routeKey: 'medical',
    ),
    const PracticeCategory(
      icon: Icons.local_fire_department,
      title: 'Fire & Safety',
      subtitle: '8/15 learned',
      progress: 0.53,
      progressColor: AppColors.warning,
      routeKey: 'fire',
    ),
    PracticeCategory(
      icon: Icons.track_changes,
      title: 'Personal Calibration',
      subtitle: 'Accuracy: 92% — Re-calibrate?',
      progress: 0.92,
      progressColor: AppColors.emergency,
      borderColor: AppColors.emergency.withValues(alpha: 0.3),
      iconBgColor: AppColors.emergency.withValues(alpha: 0.1),
      arrowColor: AppColors.emergency,
      routeKey: 'calibration',
    ),
  ],
);
