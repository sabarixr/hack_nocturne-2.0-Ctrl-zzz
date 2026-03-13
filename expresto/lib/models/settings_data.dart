import 'package:flutter/material.dart';

class EmergencyContact {
  final IconData icon;
  final String name;
  final String phone;
  final Color iconBgColor;

  const EmergencyContact({
    required this.icon,
    required this.name,
    required this.phone,
    required this.iconBgColor,
  });
}

class SettingsData {
  final String userName;
  final String userSubtitle;
  final int profileAccuracy;
  final String lastCalibrated;

  final List<EmergencyContact> emergencyContacts;

  final double emergencyThreshold;
  final String panicSensitivity;

  final bool alertsEnabled;
  final bool practiceHintsEnabled;
  final bool marketingEnabled;

  final String signLanguage;
  final String signLanguageSubtitle;
  final String signLanguageCode;

  final String region;
  final String regionSubtitle;
  final String regionCode;

  const SettingsData({
    required this.userName,
    required this.userSubtitle,
    required this.profileAccuracy,
    required this.lastCalibrated,
    required this.emergencyContacts,
    required this.emergencyThreshold,
    required this.panicSensitivity,
    required this.alertsEnabled,
    required this.practiceHintsEnabled,
    required this.marketingEnabled,
    required this.signLanguage,
    required this.signLanguageSubtitle,
    required this.signLanguageCode,
    required this.region,
    required this.regionSubtitle,
    required this.regionCode,
  });
}
