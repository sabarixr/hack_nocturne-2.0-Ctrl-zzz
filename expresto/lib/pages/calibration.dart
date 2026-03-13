import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/data/mock/calibration_mock_data.dart';
import 'package:expresto/models/calibration_data.dart';
import 'package:expresto/widgets/camera_preview_widget.dart';
import 'package:flutter/material.dart';

class CalibrationPage extends StatelessWidget {
  const CalibrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = calibrationMockData;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, data),
            _buildProgressStrip(data),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildIntroCard(data),
                  const SizedBox(height: 12),
                  _buildStressSimulationCard(data),
                  const SizedBox(height: 12),
                  _buildDetectedChangesCard(data),
                  const SizedBox(height: 24),
                  _buildControlButtons(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, CalibrationData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
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
                    Icons.arrow_back,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.track_changes,
                color: AppColors.textPrimary,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'Calibration',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Text(
            '${data.currentStep} / ${data.totalSteps}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStrip(CalibrationData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Stress Simulation',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              Text(
                data.progressText,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.shellBorder,
              borderRadius: BorderRadius.circular(100),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: data.progress,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: const LinearGradient(
                    colors: [AppColors.emergency, AppColors.warning],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard(CalibrationData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Text(
        data.instructionText,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildStressSimulationCard(CalibrationData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          _buildAudioIndicator(data),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.shellBorder.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  data.signPromptLabel,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data.signWord,
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const CameraPreviewWidget(
            height: 100,
            fallbackText: 'CAMERA ACTIVE — RECOGNIZING',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                data.detectionStatusIcon,
                color: AppColors.success,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                data.detectionStatusText,
                style: const TextStyle(color: AppColors.success, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioIndicator(CalibrationData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(data.audioStateIcon, color: AppColors.warning, size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.audioStateText,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.audioBars
                    .map((height) => _buildAudioBar(height))
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioBar(double height) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.warning,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildDetectedChangesCard(CalibrationData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.changesCardTitle,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          ...data.detectedChanges.asMap().entries.map((entry) {
            final change = entry.value;
            final isLast = entry.key == data.detectedChanges.length - 1;
            return _buildChangeRow(
              change.label,
              change.value,
              change.valueColor,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChangeRow(
    String label,
    String value,
    Color valueColor, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.shellBorder),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Pause',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.shellBorder.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.shellBorder),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Skip Step',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
