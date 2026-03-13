import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/settings_mock_data.dart';
import 'package:expresto/models/settings_data.dart';
import 'package:expresto/pages/calibration.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool alertsEnabled = true;
  bool emergencyLocationSharingEnabled = true;
  bool practiceHintsEnabled = true;
  bool marketingEnabled = false;
  double thresholdValue = 0.65;

  String userName = 'User';
  String userSubtitle = '';
  int profileAccuracy = 0;
  String lastCalibrated = '';
  List<EmergencyContact> emergencyContacts = [];
  String panicSensitivity = 'Medium';
  String signLanguage = 'Sign Language';
  String signLanguageSubtitle = 'Indian Sign Language';
  String signLanguageCode = 'ISL';
  String region = 'Region';
  String regionSubtitle = 'Emergency: 100 (India)';
  String regionCode = 'IN';

  @override
  void initState() {
    super.initState();
    final data = settingsMockData;
    alertsEnabled = data.alertsEnabled;
    practiceHintsEnabled = data.practiceHintsEnabled;
    marketingEnabled = data.marketingEnabled;
    thresholdValue = data.emergencyThreshold;

    userName = data.userName;
    userSubtitle = data.userSubtitle;
    profileAccuracy = data.profileAccuracy;
    lastCalibrated = data.lastCalibrated;
    emergencyContacts = List.from(data.emergencyContacts);
    panicSensitivity = data.panicSensitivity;
    signLanguage = data.signLanguage;
    signLanguageSubtitle = data.signLanguageSubtitle;
    signLanguageCode = data.signLanguageCode;
    region = data.region;
    regionSubtitle = data.regionSubtitle;
    regionCode = data.regionCode;
  }

  @override
  Widget build(BuildContext context) {
    final data = SettingsData(
      userName: userName,
      userSubtitle: userSubtitle,
      profileAccuracy: profileAccuracy,
      lastCalibrated: lastCalibrated,
      emergencyContacts: emergencyContacts,
      emergencyThreshold: thresholdValue,
      panicSensitivity: panicSensitivity,
      alertsEnabled: alertsEnabled,
      practiceHintsEnabled: practiceHintsEnabled,
      marketingEnabled: marketingEnabled,
      signLanguage: signLanguage,
      signLanguageSubtitle: signLanguageSubtitle,
      signLanguageCode: signLanguageCode,
      region: region,
      regionSubtitle: regionSubtitle,
      regionCode: regionCode,
    );

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
                  _buildSectionHeader('PROFILE'),
                  _buildProfileCard(data),
                  const SizedBox(height: 24),

                  _buildSectionHeader('PERSONALIZATION'),
                  _buildPersonalizationCard(data),
                  const SizedBox(height: 24),

                  _buildSectionHeader('NOTIFICATIONS'),
                  _buildNotificationsCard(data),
                  const SizedBox(height: 24),

                  _buildSectionHeader('LANGUAGE & REGION'),
                  _buildLanguageCard(data),
                  const SizedBox(height: 24),

                  _buildBottomButtons(),
                  const SizedBox(height: 32),
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
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.shellBorder),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Settings',
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          letterSpacing: 1.5,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildProfileCard(SettingsData data) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.person_outline,
            iconBg: AppColors.blue.withValues(alpha: 0.15),
            title: data.userName,
            subtitle: data.userSubtitle,
            trailingText: 'Edit >',
            onTap: _showEditProfileDialog,
          ),
          Divider(color: AppColors.shellBorder, height: 1),
          _buildListTile(
            icon: Icons.track_changes,
            iconBg: AppColors.success.withValues(alpha: 0.15),
            title: 'Profile Accuracy',
            subtitle: data.lastCalibrated,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CalibrationPage(),
                ),
              );
            },
            trailingWidget: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '${data.profileAccuracy}%',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContactsCard(SettingsData data) {
    final contacts = data.emergencyContacts;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        children: [
          if (contacts.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: contacts.length,
                physics: contacts.length > 3
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                separatorBuilder: (context, index) =>
                    Divider(color: AppColors.shellBorder, height: 1),
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  return _buildListTile(
                    icon: contact.icon,
                    iconBg: contact.iconBgColor,
                    title: contact.name,
                    subtitle: contact.phone,
                    trailingText: '>',
                  );
                },
              ),
            ),
          if (contacts.isNotEmpty)
            Divider(color: AppColors.shellBorder, height: 1),
          GestureDetector(
            onTap: _showAddContactSheet,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '+ Add',
                      style: TextStyle(
                        color: AppColors.blue,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Add Contact',
                    style: TextStyle(
                      color: AppColors.blue,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalizationCard(SettingsData data) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Emergency Threshold',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Higher = less sensitive',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Low',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: AppColors.emergency,
                          inactiveTrackColor: AppColors.shellBorder,
                          thumbColor: Colors.white,
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                        ),
                        child: Slider(
                          value: thresholdValue,
                          onChanged: (val) {
                            setState(() {
                              thresholdValue = val;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'High',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(thresholdValue * 100 + 20).toInt()}%',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(color: AppColors.shellBorder, height: 1),
          _buildListTile(
            icon: Icons.bolt_outlined,
            iconBg: AppColors.warning.withValues(alpha: 0.15),
            title: 'Panic Sensitivity',
            subtitle: '',
            onTap: _showPanicSensitivityDialog,
            trailingWidget: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                data.panicSensitivity,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard(SettingsData data) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        children: [
          _buildSwitchTile(
            Icons.warning_amber_rounded,
            AppColors.emergency.withValues(alpha: 0.15),
            'Emergency alerts',
            alertsEnabled,
            (val) => setState(() => alertsEnabled = val),
          ),
          Divider(color: AppColors.shellBorder, height: 1),
          _buildSwitchTile(
            Icons.location_on_outlined,
            AppColors.blue.withValues(alpha: 0.15),
            'Emergency location sharing',
            emergencyLocationSharingEnabled,
            (val) => setState(() => emergencyLocationSharingEnabled = val),
          ),
          Divider(color: AppColors.shellBorder, height: 1),
          _buildSwitchTile(
            Icons.school_outlined,
            AppColors.blue.withValues(alpha: 0.15),
            'Practice reminders',
            practiceHintsEnabled,
            (val) => setState(() => practiceHintsEnabled = val),
          ),
          Divider(color: AppColors.shellBorder, height: 1),
          _buildSwitchTile(
            Icons.mail_outline_rounded,
            AppColors.shellBorder,
            'Marketing emails',
            marketingEnabled,
            (val) => setState(() => marketingEnabled = val),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCard(SettingsData data) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.sign_language_outlined,
            iconBg: AppColors.blue.withValues(alpha: 0.15),
            title: data.signLanguage,
            subtitle: data.signLanguageSubtitle,
            trailingText: '${data.signLanguageCode} >',
            onTap: () => _showLanguageRegionSheet(isLanguage: true),
          ),
          Divider(color: AppColors.shellBorder, height: 1),
          _buildListTile(
            icon: Icons.public_outlined,
            iconBg: AppColors.success.withValues(alpha: 0.15),
            title: data.region,
            subtitle: data.regionSubtitle,
            trailingText: '${data.regionCode} >',
            onTap: () => _showLanguageRegionSheet(isLanguage: false),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Row(
      children: [
        Expanded(child: _buildOutlineBtn('Privacy')),
        const SizedBox(width: 12),
        Expanded(child: _buildOutlineBtn('Log Out')),
      ],
    );
  }

  Widget _buildOutlineBtn(String text) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.shellBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    String? trailingText,
    Widget? trailingWidget,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.textPrimary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingWidget != null)
              trailingWidget
            else if (trailingText != null)
              Text(
                trailingText,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    IconData icon,
    Color iconBg,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppColors.textPrimary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.success,
            inactiveTrackColor: AppColors.shellBorder,
            inactiveThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: userName);
    final subtitleController = TextEditingController(text: userSubtitle);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Edit Profile',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.shellBorder),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subtitleController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Subtitle',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.shellBorder),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.blue),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  userName = nameController.text;
                  userSubtitle = subtitleController.text;
                });
                Navigator.pop(context);
              },
              child: const Text(
                'Save',
                style: TextStyle(
                  color: AppColors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddContactSheet() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add Emergency Contact',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.shellBorder),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.shellBorder),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (nameController.text.isNotEmpty &&
                        phoneController.text.isNotEmpty) {
                      setState(() {
                        emergencyContacts.add(
                          EmergencyContact(
                            icon: Icons.contact_phone_outlined,
                            name: nameController.text,
                            phone: phoneController.text,
                            iconBgColor: AppColors.success.withValues(
                              alpha: 0.15,
                            ),
                          ),
                        );
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text(
                    'Save Contact',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _showPanicSensitivityDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Panic Sensitivity',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['Low', 'Medium', 'High'].map((level) {
              return ListTile(
                title: Text(
                  level,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                trailing: panicSensitivity == level
                    ? const Icon(Icons.check, color: AppColors.warning)
                    : null,
                onTap: () {
                  setState(() => panicSensitivity = level);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showLanguageRegionSheet({required bool isLanguage}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final options = isLanguage
            ? [
                {
                  'title': 'Sign Language (ISL)',
                  'subtitle': 'Indian Sign Language',
                  'code': 'ISL',
                },
              ]
            : [
                {
                  'title': 'Region',
                  'subtitle': 'Emergency: 100 (India)',
                  'code': 'IN',
                },
              ];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isLanguage ? 'Select Language' : 'Select Region',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map((opt) {
                final currentCode = isLanguage ? signLanguageCode : regionCode;
                final isSelected = currentCode == opt['code'];

                return ListTile(
                  title: Text(
                    opt['subtitle']!,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.success)
                      : null,
                  onTap: () {
                    setState(() {
                      if (isLanguage) {
                        signLanguage = opt['title']!;
                        signLanguageSubtitle = opt['subtitle']!;
                        signLanguageCode = opt['code']!;
                      } else {
                        region = opt['title']!;
                        regionSubtitle = opt['subtitle']!;
                        regionCode = opt['code']!;
                      }
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
