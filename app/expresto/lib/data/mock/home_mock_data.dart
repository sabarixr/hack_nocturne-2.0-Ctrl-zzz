import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/models/home_dashboard_data.dart';
import 'package:flutter/material.dart';

const HomeDashboardData homeMockData = HomeDashboardData(
  appTitle: 'EXPRESTO',
  userName: 'Adrija',
  heroTag: 'EMERGENCY',
  heroTitle: 'SOS Call',
  heroDescription:
      'Instantly connects to emergency services with sign translation',
  heroButtonLabel: 'EMERGENCY\nCALL',
  quickActions: <HomeQuickAction>[
    HomeQuickAction(
      title: 'Live Call',
      subtitle: 'Video with translation',
      icon: Icons.call_rounded,
      accent: AppColors.textMuted,
      routeKey: 'live_call',
    ),
    HomeQuickAction(
      title: 'Practice',
      subtitle: 'Learn emergency signs',
      icon: Icons.school_rounded,
      accent: AppColors.warning,
      routeKey: 'practice',
    ),
    HomeQuickAction(
      title: 'History',
      subtitle: 'Past calls & reports',
      icon: Icons.bar_chart_rounded,
      accent: Color(0xFF9CD2FF),
      routeKey: 'history',
    ),
    HomeQuickAction(
      title: 'Bystander',
      subtitle: 'Help someone nearby',
      icon: Icons.groups_rounded,
      accent: AppColors.blue,
      routeKey: 'bystander',
    ),
  ],
);
