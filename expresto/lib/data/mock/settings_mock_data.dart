import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/models/settings_data.dart';
import 'package:flutter/material.dart';

final SettingsData settingsMockData = SettingsData(
  userName: 'Adrija Rajeev',
  userSubtitle: 'Age 21 · ISL',
  profileAccuracy: 92,
  lastCalibrated: 'Last calibrated 2 weeks ago',
  emergencyContacts: [
    EmergencyContact(
      icon: Icons.person_outline,
      name: 'Mom',
      phone: '+91-9876-543210',
      iconBgColor: AppColors.emergency.withValues(alpha: 0.15),
    ),
    EmergencyContact(
      icon: Icons.person_outline,
      name: 'Dad',
      phone: '+91-9876-543211',
      iconBgColor: AppColors.warning.withValues(alpha: 0.15),
    ),
  ],
  emergencyThreshold: 0.65,
  panicSensitivity: 'Medium',
  alertsEnabled: true,
  practiceHintsEnabled: true,
  marketingEnabled: false,
  signLanguage: 'Sign Language',
  signLanguageSubtitle: 'Indian Sign Language',
  signLanguageCode: 'ISL',
  region: 'Region',
  regionSubtitle: 'Emergency: 100 (India)',
  regionCode: 'IN',
);
