import 'package:flutter/material.dart';

class HomeDashboardData {
  const HomeDashboardData({
    required this.appTitle,
    required this.userName,
    required this.profileStatus,
    required this.profileStatusColor,
    required this.profileStatusBackground,
    required this.heroTag,
    required this.heroTitle,
    required this.heroDescription,
    required this.heroButtonLabel,
    required this.quickActions,
    required this.stats,
  });

  final String appTitle;
  final String userName;
  final String profileStatus;
  final Color profileStatusColor;
  final Color profileStatusBackground;
  final String heroTag;
  final String heroTitle;
  final String heroDescription;
  final String heroButtonLabel;
  final List<HomeQuickAction> quickActions;
  final List<HomeStat> stats;
}

class HomeQuickAction {
  const HomeQuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.routeKey,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String routeKey;
}

class HomeStat {
  const HomeStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;
}
