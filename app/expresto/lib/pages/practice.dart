// ignore_for_file: avoid_print
import 'dart:async';

import 'package:expresto/core/api_client.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/pages/lesson.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

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

// ─── Sign model (from backend) ───────────────────────────────────────────────

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

// ─── Page ────────────────────────────────────────────────────────────────────

class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  bool _loading = true;
  String? _error;
  List<SignEntry> _signs = [];
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _fetchSigns();
  }

  Future<void> _fetchSigns() async {
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
        setState(() {
          _loading = false;
          _error = msg;
        });
        return;
      }

      final raw = result.data?['signDatabase'] as List<dynamic>? ?? [];
      setState(() {
        _loading = false;
        _signs = raw
            .map((e) => SignEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      print('[PracticePage] fetch error: $e');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── Category filter chips ─────────────────────────────────────────────────

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
            if (!_loading && _error == null && _signs.isNotEmpty)
              _buildCategoryFilter(),
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
              if (!_loading)
                IconButton(
                  onPressed: _fetchSigns,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textMuted,
                  ),
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
            onTap: () {
              setState(() => _selectedCategory = null);
              _fetchSigns();
            },
          ),
          ...cats.map(
            (cat) => _CategoryChip(
              label: cat,
              selected: _selectedCategory == cat,
              onTap: () {
                setState(() => _selectedCategory = cat);
                _fetchSigns();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.emergency),
      );
    }
    if (_error != null) {
      return _buildError();
    }
    if (_signs.isEmpty) {
      return _buildEmpty();
    }

    final filtered = _selectedCategory == null
        ? _signs
        : _signs.where((s) => s.category == _selectedCategory).toList();

    return ListView.builder(
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
                MaterialPageRoute(builder: (context) => LessonPage(sign: sign)),
              );
            },
          ),
        );
      },
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
            const Text(
              'Failed to load signs',
              style: TextStyle(
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
              onPressed: _fetchSigns,
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
            'No signs found',
            style: TextStyle(color: AppColors.textMuted, fontSize: 15),
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
