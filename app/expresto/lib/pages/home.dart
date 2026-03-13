import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/home_mock_data.dart';
import 'package:expresto/models/home_dashboard_data.dart';
import 'package:expresto/pages/profile.dart';
import 'package:expresto/pages/settings.dart';
import 'package:expresto/pages/emergency.dart';
import 'package:expresto/pages/bystander.dart';
import 'package:expresto/pages/call_history.dart';
import 'package:expresto/pages/practice.dart';
import 'package:expresto/pages/live_call.dart';
import 'package:expresto/widgets/home/feature_tile.dart';
import 'package:expresto/widgets/home/stat_row.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _handleQuickAction(BuildContext context, String routeKey) {
    switch (routeKey) {
      case 'bystander':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BystanderPage()),
        );
        break;
      case 'practice':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PracticePage()),
        );
        break;
      case 'live_call':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LiveCallPage()),
        );
        break;
      case 'history':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CallHistoryPage()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = homeMockData;

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
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              _TopBar(data: data),
              const SizedBox(height: 18),
              Text(
                'Hi, ${data.userName}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.3,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: data.profileStatusBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: data.profileStatusColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: data.profileStatusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data.profileStatus,
                        style: TextStyle(
                          color: data.profileStatusColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  final t = Curves.easeInOut.transform(_glowController.value);
                  final borderColor =
                      Color.lerp(
                        AppColors.emergencyBorder,
                        const Color(0xFFFF5A7B),
                        t,
                      ) ??
                      AppColors.emergencyBorder;
                  final glowColor =
                      Color.lerp(
                        const Color(0xFF7B0D28),
                        const Color(0xFFFF3158),
                        t,
                      ) ??
                      AppColors.emergency;
                  final outerGlowColor =
                      Color.lerp(
                        const Color(0xFF4A0718),
                        const Color(0xFFFF4D73),
                        t,
                      ) ??
                      AppColors.emergency;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: borderColor),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF3C0210),
                          Color(0xFF22030A),
                          Color(0xFF140307),
                        ],
                      ),
                      boxShadow: [
                        const BoxShadow(
                          color: Color(0x66A6062D),
                          blurRadius: 18,
                          spreadRadius: -10,
                          offset: Offset(0, 8),
                        ),
                        BoxShadow(
                          color: outerGlowColor.withValues(alpha: 0.42),
                          blurRadius: 58,
                          spreadRadius: 2,
                          offset: const Offset(0, 0),
                        ),
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.72),
                          blurRadius: 38,
                          spreadRadius: -1,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.heroTag,
                      style: const TextStyle(
                        color: Color(0xFFEC4E6F),
                        fontSize: 13,
                        letterSpacing: 2.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      data.heroTitle,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        height: 0.95,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(
                      width: 270,
                      child: Text(
                        'Instantly connects to emergency services with sign translation',
                        style: TextStyle(
                          color: Color(0xFFBD98A5),
                          fontSize: 16,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _EmergencyButton(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EmergencyPage(),
                          ),
                        );
                      },
                      label: data.heroButtonLabel,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              GridView.builder(
                itemCount: data.quickActions.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.18,
                ),
                itemBuilder: (context, index) {
                  final action = data.quickActions[index];
                  return FeatureTile(
                    action: action,
                    onTap: () => _handleQuickAction(context, action.routeKey),
                  );
                },
              ),
              const SizedBox(height: 22),
              ...List.generate(
                data.stats.length,
                (index) => StatRow(
                  stat: data.stats[index],
                  isLast: index == data.stats.length - 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.data});

  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            data.appTitle,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfilePage()),
            );
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.panel,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.shellBorder.withValues(alpha: 0.7),
              ),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            );
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.panel,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.shellBorder.withValues(alpha: 0.7),
              ),
            ),
            child: const Icon(
              Icons.settings,
              color: AppColors.textPrimary,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmergencyButton extends StatefulWidget {
  const _EmergencyButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  State<_EmergencyButton> createState() => _EmergencyButtonState();
}

class _EmergencyButtonState extends State<_EmergencyButton> {
  bool _isBright = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isBright = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pulseColor = _isBright
        ? const Color(0xFFFF6B88)
        : const Color(0xFFFF3158);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
          onEnd: () {
            if (mounted) {
              setState(() {
                _isBright = !_isBright;
              });
            }
          },
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [pulseColor.withValues(alpha: 0.98), pulseColor],
            ),
            boxShadow: [
              BoxShadow(
                color: pulseColor.withValues(alpha: _isBright ? 0.9 : 0.68),
                blurRadius: _isBright ? 34 : 24,
                spreadRadius: _isBright ? 2 : -2,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  height: 0.98,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
