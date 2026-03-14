// ignore_for_file: avoid_print
import 'dart:async';

import 'package:expresto/core/api_client.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/pages/lesson.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:image_picker/image_picker.dart';

// ─── GraphQL ────────────────────────────────────────────────────────────────

const _kSignDatabaseQuery = r'''
  query SignDatabase($category: String) {
    signDatabase(category: $category) {
      id
      label
      category
      description
      demoVideoUrl
      keyPoints
      difficultyLevel
      isCritical
    }
  }
''';

// ─── Hardcoded sign data (8 real model classes) ──────────────────────────────

class SignEntry {
  final String id;
  final String label;
  final String category;
  final String description;
  final String demoVideoUrl;
  final List<String> keyPoints;
  final String difficultyLevel;
  final bool isCritical;

  const SignEntry({
    required this.id,
    required this.label,
    required this.category,
    required this.description,
    required this.demoVideoUrl,
    required this.keyPoints,
    required this.difficultyLevel,
    required this.isCritical,
  });

  factory SignEntry.fromJson(Map<String, dynamic> j) => SignEntry(
    id: j['id'] as String,
    label: j['label'] as String,
    category: j['category'] as String? ?? '',
    description: j['description'] as String? ?? '',
    demoVideoUrl: j['demoVideoUrl'] as String? ?? '',
    keyPoints:
        (j['keyPoints'] as List<dynamic>?)?.map((e) => e as String).toList() ??
        [],
    difficultyLevel: j['difficultyLevel'] as String? ?? 'BEGINNER',
    isCritical: j['isCritical'] as bool? ?? false,
  );
}

/// The 8 real model classes, always available offline.
const List<SignEntry> _kLocalSigns = [
  SignEntry(
    id: 'help',
    label: 'HELP',
    category: 'Emergency',
    description: 'Open palm raised — universal distress signal',
    demoVideoUrl: '',
    keyPoints: [
      'Extend all 5 fingers wide',
      'Palm facing forward (away from body)',
      'Raise arm to shoulder height or above',
    ],
    difficultyLevel: 'BEGINNER',
    isCritical: true,
  ),
  SignEntry(
    id: 'pain',
    label: 'PAIN',
    category: 'Medical',
    description: 'Index and middle fingers together, pointing to pain area',
    demoVideoUrl: '',
    keyPoints: [
      'Index + middle fingers extended and touching',
      'Ring and pinky curled into palm',
      'Thumb tucked across palm',
    ],
    difficultyLevel: 'BEGINNER',
    isCritical: true,
  ),
  SignEntry(
    id: 'doctor',
    label: 'DOCTOR',
    category: 'Medical',
    description: 'D-handshape — index up, thumb touches middle fingertip',
    demoVideoUrl: '',
    keyPoints: [
      'Index finger pointing straight up',
      'Thumb tip touches middle fingertip',
      'Ring and pinky loosely curled',
    ],
    difficultyLevel: 'INTERMEDIATE',
    isCritical: true,
  ),
  SignEntry(
    id: 'call',
    label: 'CALL',
    category: 'Communication',
    description: 'Shaka / phone hand — pinky and thumb extended',
    demoVideoUrl: '',
    keyPoints: [
      'Thumb extended outward to the side',
      'Pinky extended upward',
      'Index, middle, ring fingers curled in',
    ],
    difficultyLevel: 'BEGINNER',
    isCritical: false,
  ),
  SignEntry(
    id: 'accident',
    label: 'ACCIDENT',
    category: 'Emergency',
    description: 'Devil horns — index and pinky extended',
    demoVideoUrl: '',
    keyPoints: [
      'Index finger extended upward',
      'Pinky finger extended upward',
      'Middle and ring fingers curled in',
    ],
    difficultyLevel: 'INTERMEDIATE',
    isCritical: false,
  ),
  SignEntry(
    id: 'thief',
    label: 'THIEF',
    category: 'Crime',
    description: 'O-shape — all fingertips close to thumb tip',
    demoVideoUrl: '',
    keyPoints: [
      'All four fingers curved inward',
      'All fingertips touch the thumb tip',
      'Form a clear circular O-shape',
    ],
    difficultyLevel: 'INTERMEDIATE',
    isCritical: false,
  ),
  SignEntry(
    id: 'hot',
    label: 'HOT',
    category: 'Environment',
    description: 'Fisted hand — all fingers curled into a tight fist',
    demoVideoUrl: '',
    keyPoints: [
      'All four fingers folded into palm',
      'Thumb wrapped over the front of fingers',
      'Firm, tight fist raised to chest height',
    ],
    difficultyLevel: 'BEGINNER',
    isCritical: false,
  ),
  SignEntry(
    id: 'lose',
    label: 'LOSE',
    category: 'General',
    description: '2+ fingers extended loosely — general distress fallback',
    demoVideoUrl: '',
    keyPoints: [
      'Extend two or more fingers outward',
      'Keep them loosely spread or together',
      'Hold hand at a visible, relaxed height',
    ],
    difficultyLevel: 'BEGINNER',
    isCritical: false,
  ),
];

// ─── Page ────────────────────────────────────────────────────────────────────

class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  bool _loading = false;
  String? _error;
  List<SignEntry> _signs = List<SignEntry>.from(_kLocalSigns);
  String? _selectedCategory;
  bool _fetchedFromBackend = false;

  @override
  void initState() {
    super.initState();
    // Try to enrich from backend, but don't block on it
    _tryFetchFromBackend();
  }

  Future<void> _tryFetchFromBackend() async {
    try {
      final result = await ApiClient.client.value.query(
        QueryOptions(
          document: gql(_kSignDatabaseQuery),
          variables: {
            if (_selectedCategory != null) 'category': _selectedCategory,
          },
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );

      if (result.hasException || result.data == null) return;

      final raw = result.data?['signDatabase'] as List<dynamic>? ?? [];
      if (raw.isEmpty) return;

      if (mounted) {
        setState(() {
          _signs = raw
              .map((e) => SignEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          _fetchedFromBackend = true;
        });
      }
    } catch (e) {
      print('[PracticePage] backend fetch skipped: $e');
      // Silently fall back to local data — already populated
    }
  }

  Future<void> _refreshSigns() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiClient.client.value.query(
        QueryOptions(
          document: gql(_kSignDatabaseQuery),
          variables: {
            if (_selectedCategory != null) 'category': _selectedCategory,
          },
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );

      if (result.hasException) {
        final msg =
            result.exception?.graphqlErrors.firstOrNull?.message ??
            result.exception.toString();
        if (mounted)
          setState(() {
            _loading = false;
            _error = msg;
          });
        return;
      }

      final raw = result.data?['signDatabase'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _loading = false;
          if (raw.isNotEmpty) {
            _signs = raw
                .map((e) => SignEntry.fromJson(e as Map<String, dynamic>))
                .toList();
            _fetchedFromBackend = true;
          }
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  // ── Video upload ──────────────────────────────────────────────────────────

  Future<void> _pickAndUploadVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );

    if (picked == null || !mounted) return;

    final fileName = picked.name;
    _showUploadBottomSheet(fileName, picked.path);
  }

  void _showUploadBottomSheet(String fileName, String filePath) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _UploadSheet(fileName: fileName, filePath: filePath),
    );
  }

  // ── Category filter ───────────────────────────────────────────────────────

  List<String> get _categories {
    final cats = _signs.map((s) => s.category).toSet().toList()..sort();
    return cats;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            if (_signs.isNotEmpty) _buildCategoryFilter(),
            Expanded(child: _buildBody(context)),
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
            children: const [
              Icon(
                Icons.school_outlined,
                color: AppColors.textPrimary,
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                'Learn Signs',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Row(
            children: [
              // Upload video button
              GestureDetector(
                onTap: _pickAndUploadVideo,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.video_call_rounded,
                    color: AppColors.blue,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!_loading)
                IconButton(
                  onPressed: _refreshSigns,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textMuted,
                  ),
                  tooltip: 'Sync from server',
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
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final cats = _categories;
    if (cats.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _CategoryChip(
            label: 'All',
            selected: _selectedCategory == null,
            onTap: () => setState(() => _selectedCategory = null),
          ),
          ...cats.map(
            (cat) => _CategoryChip(
              label: cat,
              selected: _selectedCategory == cat,
              onTap: () => setState(() => _selectedCategory = cat),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
    }

    final filtered = _selectedCategory == null
        ? _signs
        : _signs.where((s) => s.category == _selectedCategory).toList();

    if (filtered.isEmpty) {
      return _buildEmpty();
    }

    return Column(
      children: [
        // Backend source indicator
        if (_fetchedFromBackend)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Synced from server',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final sign = filtered[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SignCard(
                  sign: sign,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LessonPage(sign: sign),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.sign_language_rounded,
            color: AppColors.textMuted,
            size: 40,
          ),
          SizedBox(height: 12),
          Text(
            'No signs in this category',
            style: TextStyle(color: AppColors.textMuted, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ─── Upload bottom sheet ─────────────────────────────────────────────────────

class _UploadSheet extends StatefulWidget {
  const _UploadSheet({required this.fileName, required this.filePath});

  final String fileName;
  final String filePath;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  bool _submitting = false;
  bool _done = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    // Stub: simulate submission delay
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted)
      setState(() {
        _submitting = false;
        _done = true;
      });
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.shellBorder,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),

          const Text(
            'Submit Practice Video',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your video will be reviewed and matched against sign classes.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 20),

          // File info row
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.panelSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.shellBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.video_file_rounded,
                    color: AppColors.blue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Ready to submit',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_done)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: (_submitting || _done) ? null : _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _done
                      ? AppColors.success.withValues(alpha: 0.2)
                      : _submitting
                      ? AppColors.blue.withValues(alpha: 0.4)
                      : AppColors.blue,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _done ? Icons.check_rounded : Icons.upload_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _done ? 'Submitted!' : 'Submit for Review',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Category chip ────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.blue : AppColors.shellBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sign card ────────────────────────────────────────────────────────────────

class _SignCard extends StatelessWidget {
  const _SignCard({required this.sign, required this.onTap});

  final SignEntry sign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final diffColor = sign.difficultyLevel.toUpperCase() == 'ADVANCED'
        ? AppColors.emergency
        : sign.difficultyLevel.toUpperCase() == 'INTERMEDIATE'
        ? AppColors.warning
        : AppColors.success;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: sign.isCritical
                ? AppColors.emergencyBorder
                : AppColors.shellBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: sign.isCritical
                    ? AppColors.emergencyDeep
                    : AppColors.panelSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                sign.isCritical
                    ? Icons.warning_amber_rounded
                    : Icons.sign_language_rounded,
                size: 24,
                color: sign.isCritical
                    ? AppColors.emergency
                    : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        sign.label.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: diffColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sign.difficultyLevel,
                          style: TextStyle(
                            color: diffColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (sign.isCritical) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.emergencyDeep,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.emergencyBorder,
                            ),
                          ),
                          child: const Text(
                            'CRITICAL',
                            style: TextStyle(
                              color: AppColors.emergency,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (sign.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      sign.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (sign.category.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      sign.category,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
