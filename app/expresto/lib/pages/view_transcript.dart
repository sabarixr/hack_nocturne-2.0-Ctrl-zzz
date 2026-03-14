import 'package:expresto/core/api_client.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/models/call_history_data.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

const String _kCallReport = r'''
  query CallReport($callId: ID!) {
    callReport(callId: $callId) {
      totalFrames
      peakUrgencyScore
      topRecognizedSigns
      durationSeconds
      outcome
      call {
        id
        status
        emergencyType
        startedAt
        endedAt
      }
    }
  }
''';

class _ReportData {
  const _ReportData({
    required this.totalFrames,
    required this.peakUrgencyScore,
    required this.topSigns,
    required this.durationSeconds,
    required this.outcome,
    required this.emergencyType,
  });

  final int totalFrames;
  final double peakUrgencyScore;
  final List<String> topSigns;
  final int? durationSeconds;
  final String outcome;
  final String emergencyType;
}

class ViewTranscriptPage extends StatefulWidget {
  const ViewTranscriptPage({super.key, required this.entry});

  final CallHistoryEntry entry;

  @override
  State<ViewTranscriptPage> createState() => _ViewTranscriptPageState();
}

class _ViewTranscriptPageState extends State<ViewTranscriptPage> {
  _ReportData? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    if (widget.entry.callId == null) {
      setState(() {
        _error = 'No call ID available for this entry.';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ApiClient.client.value.query(
        QueryOptions(
          document: gql(_kCallReport),
          variables: {'callId': widget.entry.callId!},
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (!mounted) return;
      if (result.hasException) {
        setState(() {
          _error = result.exception.toString();
          _loading = false;
        });
        return;
      }
      final raw = result.data?['callReport'];
      if (raw == null) {
        setState(() {
          _error = 'Report not available for this call.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _report = _ReportData(
          totalFrames: (raw['totalFrames'] as int?) ?? 0,
          peakUrgencyScore:
              (raw['peakUrgencyScore'] as num?)?.toDouble() ?? 0.0,
          topSigns: List<String>.from(raw['topRecognizedSigns'] as List? ?? []),
          durationSeconds: raw['durationSeconds'] as int?,
          outcome: raw['outcome'] as String? ?? '',
          emergencyType: raw['call']?['emergencyType'] as String? ?? 'UNKNOWN',
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
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
          const Text(
            'Call Report',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.teal),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.emergency,
                size: 40,
              ),
              const SizedBox(height: 12),
              const Text(
                'Could not load report',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _fetchReport,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final report = _report!;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 8),
        _buildMetaCard(),
        const SizedBox(height: 12),
        _buildStatsCard(report),
        const SizedBox(height: 12),
        if (report.topSigns.isNotEmpty) _buildSignsCard(report),
        if (report.topSigns.isNotEmpty) const SizedBox(height: 12),
        _buildOutcomeCard(report),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMetaCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.entry.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.entry.dateTimeLabel,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(_ReportData report) {
    String duration = '—';
    if (report.durationSeconds != null) {
      final m = report.durationSeconds! ~/ 60;
      final s = report.durationSeconds! % 60;
      duration = '${m}m ${s.toString().padLeft(2, '0')}s';
    }
    final urgencyPct = '${(report.peakUrgencyScore * 100).toStringAsFixed(0)}%';
    final urgencyColor = report.peakUrgencyScore >= 0.75
        ? AppColors.emergency
        : report.peakUrgencyScore >= 0.5
        ? AppColors.warning
        : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STATISTICS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 14),
          _statRow('Emergency Type', report.emergencyType),
          _divider(),
          _statRow('Duration', duration),
          _divider(),
          _statRowColored('Peak Urgency', urgencyPct, urgencyColor),
          _divider(),
          _statRow('Total Frames Sent', '${report.totalFrames}'),
        ],
      ),
    );
  }

  Widget _buildSignsCard(_ReportData report) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TOP DETECTED SIGNS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: report.topSigns
                .map(
                  (sign) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.teal.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      sign.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeCard(_ReportData report) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OUTCOME',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            report.outcome.isEmpty
                ? 'No outcome recorded for this call.'
                : report.outcome,
            style: TextStyle(
              color: report.outcome.isEmpty
                  ? AppColors.textMuted
                  : AppColors.textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRowColored(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(color: AppColors.divider, height: 1);
}
