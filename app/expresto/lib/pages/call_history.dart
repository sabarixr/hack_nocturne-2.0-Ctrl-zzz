// ignore_for_file: avoid_print
import 'dart:async';

import 'package:expresto/core/api_client.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/models/call_history_data.dart';
import 'package:expresto/pages/view_transcript.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

// ─── GraphQL ────────────────────────────────────────────────────────────────

const _kCallHistoryQuery = r'''
  query CallHistory($limit: Int, $offset: Int) {
    callHistory(limit: $limit, offset: $offset) {
      id
      status
      emergencyType
      peakUrgencyScore
      outcome
      startedAt
      endedAt
    }
  }
''';

// ─── Page ───────────────────────────────────────────────────────────────────

class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage({super.key});

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  CallHistoryType? _selectedType;

  bool _loading = true;
  String? _error;
  List<CallHistoryEntry> _entries = [];

  static const _filters = <CallHistoryFilter>[
    CallHistoryFilter(label: 'All', type: null),
    CallHistoryFilter(label: 'Emergency', type: CallHistoryType.emergency),
    CallHistoryFilter(label: 'Live Calls', type: CallHistoryType.live),
  ];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  // ── Fetch ──────────────────────────────────────────────────────────────

  Future<void> _fetchHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ApiClient.client.value.query(
        QueryOptions(
          document: gql(_kCallHistoryQuery),
          variables: const {'limit': 50, 'offset': 0},
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );

      if (result.hasException) {
        final msg =
            result.exception?.graphqlErrors.firstOrNull?.message ??
            result.exception.toString();
        setState(() {
          _loading = false;
          _error = msg;
        });
        return;
      }

      final raw = result.data?['callHistory'] as List<dynamic>? ?? [];
      final entries = raw.map(_parseEntry).toList();

      setState(() {
        _loading = false;
        _entries = entries;
      });
    } catch (e) {
      print('[CallHistory] fetch error: $e');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── Parse ──────────────────────────────────────────────────────────────

  static CallHistoryEntry _parseEntry(dynamic raw) {
    final map = raw as Map<String, dynamic>;

    final status = (map['status'] as String? ?? '').toLowerCase();
    final emergencyType = (map['emergencyType'] as String? ?? 'UNKNOWN');
    final peakUrgency = (map['peakUrgencyScore'] as num? ?? 0).toDouble();
    final outcome = (map['outcome'] as String? ?? '').trim();

    // Parse dates
    final startedAt = _parseDate(map['startedAt'] as String?);
    final endedAt = _parseDate(map['endedAt'] as String?);

    // Duration
    String durationLabel = '—';
    if (startedAt != null && endedAt != null) {
      final secs = endedAt.difference(startedAt).inSeconds;
      final m = secs ~/ 60;
      final s = secs % 60;
      durationLabel = '${m}m ${s.toString().padLeft(2, '0')}s';
    }

    // Date/time label
    final dateLabel = startedAt != null ? _formatDateTime(startedAt) : '—';

    // Badge
    final isEnded = status == 'ended';
    final badgeLabel = isEnded
        ? (outcome.isNotEmpty ? outcome : 'Ended')
        : _capitalise(status);
    final badgeColor = isEnded ? AppColors.success : AppColors.warning;

    // Urgency
    final urgencyPct = '${(peakUrgency * 100).toStringAsFixed(0)}%';
    final urgencyColor = peakUrgency >= 0.75
        ? AppColors.emergency
        : peakUrgency >= 0.5
        ? AppColors.warning
        : AppColors.success;

    final metadata = <CallHistoryMeta>[
      CallHistoryMeta(label: 'Type', value: _formatType(emergencyType)),
      CallHistoryMeta(label: 'Duration', value: durationLabel),
      CallHistoryMeta(
        label: 'Peak urgency',
        value: urgencyPct,
        valueColor: urgencyColor,
      ),
    ];

    return CallHistoryEntry(
      callId: map['id'] as String?,
      type: CallHistoryType.emergency,
      title: 'Emergency Call',
      dateTimeLabel: dateLabel,
      badgeLabel: badgeLabel,
      badgeColor: badgeColor,
      metadata: metadata,
      actions: const ['View Transcript', 'Share Report'],
    );
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  static String _formatDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} — $h:$min $ampm';
  }

  static String _formatType(String raw) {
    switch (raw.toUpperCase()) {
      case 'MEDICAL':
        return 'Medical';
      case 'FIRE':
        return 'Fire';
      case 'POLICE':
        return 'Police';
      case 'OTHER':
        return 'Other';
      default:
        return 'Unknown';
    }
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _entries
        .where((e) => _selectedType == null || e.type == _selectedType)
        .toList();

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
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.emergency),
                )
              : _error != null
              ? _buildError()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildFilters(),
                    const SizedBox(height: 10),
                    if (filtered.isEmpty) _buildEmpty(),
                    ...filtered.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _HistoryCard(entry: entry),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          Icons.bar_chart_rounded,
          color: AppColors.textPrimary,
          size: 28,
        ),
        const SizedBox(width: 8),
        const Text(
          'History',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        const Spacer(),
        // Refresh button
        IconButton(
          onPressed: _fetchHistory,
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textMuted),
        ),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.home_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filters.map((filter) {
          final isSelected =
              filter.type == _selectedType ||
              (filter.type == null && _selectedType == null);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedType = filter.type),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.emergency : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.emergency
                        : AppColors.shellBorder,
                  ),
                ),
                child: Text(
                  filter.label,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.emergency,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load history',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _fetchHistory,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.shellBorder),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: const [
            Icon(Icons.history_rounded, color: AppColors.textMuted, size: 40),
            SizedBox(height: 12),
            Text(
              'No call history yet',
              style: TextStyle(color: AppColors.textMuted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── History card ────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final CallHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final leadingIcon = entry.type == CallHistoryType.emergency
        ? Icons.notification_important_rounded
        : Icons.call_rounded;
    final leadingColor = entry.type == CallHistoryType.emergency
        ? AppColors.emergency
        : AppColors.textMuted;
    final badgeBackground = entry.type == CallHistoryType.emergency
        ? const Color(0xFF173722)
        : const Color(0xFF123662);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: entry.type == CallHistoryType.emergency
              ? AppColors.emergencyBorder
              : AppColors.shellBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(leadingIcon, color: leadingColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badgeBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  entry.badgeLabel,
                  style: TextStyle(
                    color: entry.badgeColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            entry.dateTimeLabel,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
          ),
          const SizedBox(height: 12),
          ...entry.metadata.map(
            (meta) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      meta.label,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    meta.value,
                    style: TextStyle(
                      color: meta.valueColor ?? const Color(0xFFD3D8E6),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: entry.actions
                .map(
                  (label) => OutlinedButton(
                    onPressed: () {
                      if (label == 'View Transcript') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ViewTranscriptPage(entry: entry),
                          ),
                        );
                        return;
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$label coming next.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      side: const BorderSide(color: AppColors.shellBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(label),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
