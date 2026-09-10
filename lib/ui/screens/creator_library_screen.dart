// ui/screens/creator_library_screen.dart
// COMPLETE - Premium Visual Library with Pinterest-style Grid
// Features: Smart filters, AI organization, visual browsing, search

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../models/media_file.dart';
import '../../providers/media_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/premium_provider.dart';
import '../../services/ai_service.dart';
import '../themes/app_theme.dart';
import '../widgets/media_viewer_screen.dart';
import 'cloud_vault_screen.dart';
import 'premium_screen.dart';

class CreatorLibraryScreen extends StatefulWidget {
  const CreatorLibraryScreen({Key? key}) : super(key: key);

  @override
  State<CreatorLibraryScreen> createState() => _CreatorLibraryScreenState();
}

class _CreatorLibraryScreenState extends State<CreatorLibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final AIService _ai = AIService();

  String _selectedFilter = 'All';
  String _selectedPlatform = 'All';
  String _selectedCategory = 'All';
  bool _isLoading = false;
  bool _showFilters = false;
  List<MediaFile> _filteredMedia = [];
  Map<String, dynamic> _libraryStats = {};
  List<Map<String, dynamic>> _collectionSuggestions = [];
  Set<String> _selectedItems = {};
  bool _selectionMode = false;

  final List<String> _filterOptions = [
    'All',
    'Today',
    'This Week',
    'This Month',
    'Favorites',
  ];

  final List<String> _categoryOptions = [
    'All',
    'Comedy',
    'Tutorial',
    'Music',
    'Fitness',
    'Gaming',
    'Cooking',
    'Education',
    'Travel',
    'Technology',
    'Fashion',
    'Business',
    'Sports',
  ];

  final Map<String, IconData> _categoryIcons = {
    'All': Icons.apps_rounded,
    'Comedy': Icons.emoji_emotions_rounded,
    'Tutorial': Icons.school_rounded,
    'Music': Icons.music_note_rounded,
    'Fitness': Icons.fitness_center_rounded,
    'Gaming': Icons.sports_esports_rounded,
    'Cooking': Icons.restaurant_rounded,
    'Education': Icons.menu_book_rounded,
    'Travel': Icons.flight_takeoff_rounded,
    'Technology': Icons.computer_rounded,
    'Fashion': Icons.checkroom_rounded,
    'Business': Icons.business_center_rounded,
    'Sports': Icons.sports_soccer_rounded,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
      await mediaProvider.refreshAllMedia();

      final localMedia = [
        ...mediaProvider.allMedia,
        ...mediaProvider.whatsappImages,
        ...mediaProvider.whatsappVideos,
      ];
      _libraryStats = _buildLocalStats(localMedia);
      _collectionSuggestions = _buildLocalCollections(localMedia);

      final premium = Provider.of<PremiumProvider>(context, listen: false);
      if (premium.isPremium) {
        try {
          final remoteStats = await _ai.getLibraryStats();
          final remoteSuggestions = await _ai.getCollectionSuggestions();
          if (remoteStats.isNotEmpty)
            _libraryStats = {..._libraryStats, ...remoteStats};
          if (remoteSuggestions.isNotEmpty) {
            _collectionSuggestions = remoteSuggestions;
          }
        } catch (e) {
          debugPrint('AI library enrichment unavailable: $e');
        }
      }

      _applyFilters();
    } catch (e) {
      debugPrint('Load library error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _buildLocalStats(List<MediaFile> media) {
    final categories = <String, int>{};
    final platforms = <String, int>{};
    final keywords = <String, int>{};
    for (final item in media) {
      final platform = item.sourceAppDisplayName;
      platforms[platform] = (platforms[platform] ?? 0) + 1;
      final category = item.isVideo ? 'Video' : 'Image';
      categories[category] = (categories[category] ?? 0) + 1;
      final words = item.fileName
          .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((word) => word.length > 2)
          .toSet();
      for (final word in words) keywords[word] = (keywords[word] ?? 0) + 1;
    }
    final sortedKeywords = Map<String, int>.fromEntries(
      keywords.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return {
      'total': media.length,
      'categories': categories,
      'moods': {'Mixed': media.length},
      'platforms': platforms,
      'topKeywords': Map.fromEntries(sortedKeywords.entries.take(12)),
    };
  }

  List<Map<String, dynamic>> _buildLocalCollections(List<MediaFile> media) {
    final counts = <String, int>{};
    for (final item in media) {
      final name = item.sourceAppDisplayName;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    const colors = ['#7357FF', '#9B7BFF', '#B9A9FF', '#4B2EA8', '#DCD4FF'];
    var index = 0;
    return counts.entries
        .map((entry) => {
              'name': entry.key,
              'count': entry.value,
              'suggestedColor': colors[(index++) % colors.length],
            })
        .toList();
  }

  void _applyFilters() {
    final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
    final allMedia = [
      ...mediaProvider.allMedia,
      ...mediaProvider.whatsappImages,
      ...mediaProvider.whatsappVideos,
    ];

    var filtered = List<MediaFile>.from(allMedia);

    // Search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered
          .where((m) =>
              m.fileName.toLowerCase().contains(query) ||
              m.sourceAppDisplayName.toLowerCase().contains(query))
          .toList();
    }

    // Platform filter
    if (_selectedPlatform != 'All') {
      filtered = filtered
          .where((m) =>
              m.sourceApp.toLowerCase() == _selectedPlatform.toLowerCase())
          .toList();
    }

    // Category filter from local media type, source labels, or AI metadata.
    if (_selectedCategory != 'All') {
      final category = _selectedCategory.toLowerCase();
      filtered = filtered.where((m) {
        final metadata = m.metadata?.toString().toLowerCase() ?? '';
        final haystack =
            '${m.fileName} ${m.sourceAppDisplayName} $metadata'.toLowerCase();
        return haystack.contains(category);
      }).toList();
    }

    // Time filter
    final now = DateTime.now();
    switch (_selectedFilter) {
      case 'Today':
        filtered = filtered
            .where((m) =>
                m.createdAt.year == now.year &&
                m.createdAt.month == now.month &&
                m.createdAt.day == now.day)
            .toList();
        break;
      case 'This Week':
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        filtered =
            filtered.where((m) => m.createdAt.isAfter(startOfWeek)).toList();
        break;
      case 'This Month':
        filtered = filtered
            .where((m) =>
                m.createdAt.year == now.year && m.createdAt.month == now.month)
            .toList();
        break;
    }

    setState(() => _filteredMedia = filtered);
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = Provider.of<PremiumProvider>(context).isPremium;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ──────────────────────────────────────────────────────
            _buildHeader(isPremium),

            // ─── Search Bar ──────────────────────────────────────────────────
            _buildSearchBar(),

            // ─── Filter Chips ────────────────────────────────────────────────
            _buildFilterChips(),

            // ─── Tab Bar ─────────────────────────────────────────────────────
            _buildTabBar(),

            // ─── Content ────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Grid
                  _buildGrid(),

                  // Tab 2: Collections
                  _buildCollectionsTab(),

                  // Tab 3: AI Insights (Premium)
                  _buildInsightsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isPremium) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.folder_rounded,
            color: AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Library',
                  style: AppTypography.headlineMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${_filteredMedia.length} files • ${_getStatsText()}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Selection mode toggle
          GestureDetector(
            onTap: () {
              setState(() {
                _selectionMode = !_selectionMode;
                if (!_selectionMode) _selectedItems.clear();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: _selectionMode
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: _selectionMode ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Icon(
                _selectionMode ? Icons.checklist_rounded : Icons.checklist,
                color: _selectionMode ? AppColors.primary : AppColors.textMuted,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Refresh button
          GestureDetector(
            onTap: _loadData,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Search Bar ──────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.soft,
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Icon(
                Icons.search_rounded,
                color: AppColors.textMuted,
                size: 18,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: AppTypography.bodyMedium,
                decoration: const InputDecoration(
                  hintText: 'Search files, tags, creators...',
                  hintStyle: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => _applyFilters(),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              IconButton(
                onPressed: () {
                  _searchController.clear();
                  _applyFilters();
                },
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textMuted,
                  size: 16,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            IconButton(
              onPressed: () {
                setState(() => _showFilters = !_showFilters);
              },
              icon: Icon(
                _showFilters
                    ? Icons.filter_alt_rounded
                    : Icons.filter_alt_outlined,
                color: _showFilters ? AppColors.primary : AppColors.textMuted,
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  // ─── Filter Chips ────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    if (!_showFilters) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          // Time filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filterOptions.map((filter) {
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = selected ? filter : 'All';
                        _applyFilters();
                      });
                    },
                    backgroundColor: AppColors.surface,
                    selectedColor: AppColors.primary.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: BorderSide(
                        color:
                            isSelected ? AppColors.primary : AppColors.border,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Platform filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPlatformChip('All', Icons.apps_rounded),
                _buildPlatformChip('Instagram', Icons.camera_alt_rounded),
                _buildPlatformChip('TikTok', Icons.music_note_rounded),
                _buildPlatformChip('Facebook', Icons.facebook),
                _buildPlatformChip('Twitter', Icons.alternate_email),
                _buildPlatformChip('WhatsApp', Icons.chat_bubble_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformChip(String label, IconData icon) {
    final isSelected = _selectedPlatform == label;
    final color = _getPlatformColor(label);

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedPlatform = selected ? label : 'All';
            _applyFilters();
          });
        },
        backgroundColor: AppColors.surface,
        selectedColor: color,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppColors.textSecondary,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: isSelected ? color : AppColors.border,
          ),
        ),
      ),
    );
  }

  // ─── Tab Bar ─────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w700,
        ),
        tabs: const [
          Tab(text: 'Grid'),
          Tab(text: 'Collections'),
          Tab(text: 'Insights'),
        ],
      ),
    );
  }

  // ─── Grid Tab ────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    if (_filteredMedia.isEmpty) {
      return _buildEmptyState();
    }

    if (_selectionMode) {
      return _buildSelectionGrid();
    }

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.8,
      ),
      itemCount: _filteredMedia.length,
      itemBuilder: (context, index) {
        final media = _filteredMedia[index];
        return _GridItem(
          mediaFile: media,
          onTap: () => _openMediaViewer(index),
          onLongPress: () {
            setState(() {
              _selectionMode = true;
              _selectedItems.add(media.id);
            });
          },
        );
      },
    );
  }

  Widget _buildSelectionGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.8,
      ),
      itemCount: _filteredMedia.length,
      itemBuilder: (context, index) {
        final media = _filteredMedia[index];
        final isSelected = _selectedItems.contains(media.id);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedItems.remove(media.id);
                if (_selectedItems.isEmpty) _selectionMode = false;
              } else {
                _selectedItems.add(media.id);
              }
            });
          },
          child: Stack(
            children: [
              _GridItem(
                mediaFile: media,
                onTap: () {},
                onLongPress: () {},
              ),
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSelected ? Icons.check_rounded : Icons.circle_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Collections Tab ─────────────────────────────────────────────────────

  Widget _buildCollectionsTab() {
    final suggestions = _collectionSuggestions;
    final total = (_libraryStats['total'] as int?) ?? 0;

    if (suggestions.isEmpty) {
      return _buildEmptyCollections();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.primary,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child:
                    const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your content universe',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total items arranged into ${suggestions.length} collections',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Collections', style: AppTypography.titleLarge),
            Text('Tap to explore',
                style:
                    AppTypography.caption.copyWith(color: AppColors.primary)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...suggestions.map((collection) {
          final name = collection['name']?.toString() ?? 'Collection';
          final count = (collection['count'] as num?)?.toInt() ?? 0;
          final colorText =
              collection['suggestedColor']?.toString() ?? '#7357FF';
          final color = _parseCollectionColor(colorText);
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _CollectionCard(
              name: name,
              count: count,
              icon: _getPlatformIcon(name.toLowerCase()),
              color: color,
              onTap: () {
                _selectedCategory = name;
                _applyFilters();
                _tabController.animateTo(0);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Showing $name content')),
                );
              },
            ),
          );
        }),
      ],
    );
  }

  Color _parseCollectionColor(String value) {
    final normalized = value.replaceFirst('#', '');
    final parsed = int.tryParse('FF$normalized', radix: 16);
    return parsed == null ? AppColors.primary : Color(parsed);
  }

  // ─── Insights Tab ─────────────────────────────────────────────────────────

  Widget _buildInsightsTab() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
      );
    }

    final stats = _libraryStats;
    final total = (stats['total'] as num?)?.toInt() ?? 0;
    final categories =
        Map<String, dynamic>.from(stats['categories'] as Map? ?? {});
    final platforms =
        Map<String, dynamic>.from(stats['platforms'] as Map? ?? {});
    final topKeywords =
        Map<String, dynamic>.from(stats['topKeywords'] as Map? ?? {});
    final videos = (categories['Video'] as num?)?.toInt() ?? 0;
    final images = (categories['Image'] as num?)?.toInt() ?? 0;

    Widget metric(String value, String label, IconData icon, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: color.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 10),
              Text(value,
                  style: AppTypography.headlineMedium
                      .copyWith(fontWeight: FontWeight.w900)),
              Text(label,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      );
    }

    Widget progressRow(String name, int count, Color color) {
      final ratio =
          total == 0 ? 0.0 : (count / total).clamp(0.0, 1.0).toDouble();
      return InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          _selectedPlatform = name;
          _applyFilters();
          _tabController.animateTo(0);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(name,
                          style: AppTypography.bodySmall
                              .copyWith(fontWeight: FontWeight.w600))),
                  Text('$count',
                      style: AppTypography.caption
                          .copyWith(color: color, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.textMuted),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 7,
                  backgroundColor: AppColors.cardAlt,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.primary,
          ),
          child: Row(
            children: [
              const Icon(Icons.insights_rounded, color: Colors.white, size: 32),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Library intelligence',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                        'A clear view of what you collect and where it comes from.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            metric('$total', 'Total files', Icons.inventory_2_rounded,
                AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            metric('${platforms.length}', 'Sources', Icons.hub_rounded,
                AppColors.info),
            const SizedBox(width: AppSpacing.sm),
            metric('${categories.length}', 'Media types',
                Icons.auto_awesome_mosaic_rounded, AppColors.success),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: AppShadows.soft),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                    child: Text('Media mix', style: AppTypography.titleLarge)),
                Text('$videos videos · $images images',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textMuted))
              ]),
              const SizedBox(height: AppSpacing.md),
              progressRow('Video', videos, AppColors.primary),
              progressRow('Image', images, AppColors.info),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: AppShadows.soft),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                    child: Text('Source performance',
                        style: AppTypography.titleLarge)),
                Text('Tap a row to filter',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.primary))
              ]),
              const SizedBox(height: AppSpacing.sm),
              if (platforms.isEmpty)
                const Text('Download content to see source insights.',
                    style: AppTypography.bodySmall),
              ...platforms.entries.map((entry) => progressRow(
                  entry.key.toString(),
                  (entry.value as num?)?.toInt() ?? 0,
                  _getPlatformColor(entry.key.toString()))),
            ],
          ),
        ),
        if (topKeywords.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: AppShadows.soft),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Content signals', style: AppTypography.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text('Common words in your file names',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textMuted)),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: topKeywords.entries
                      .take(10)
                      .map((entry) => Chip(
                          label: Text('${entry.key}  ${entry.value}'),
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.08),
                          side: BorderSide(
                              color:
                                  AppColors.primary.withValues(alpha: 0.15))))
                      .toList()),
            ]),
          ),
        ],
      ],
    );
  }

  // ─── Helper Widgets ──────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Your Library is Empty',
              style: AppTypography.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Download your first video from the Home tab',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('Go Download'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCollections() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.collections_bookmark_rounded,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Smart Collections',
              style: AppTypography.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Download more content to get AI-suggested collections',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh Library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumLocked() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              size: 64,
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'AI Insights',
              style: AppTypography.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Unlock AI-powered insights about your content library',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                );
              },
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Upgrade to Pro'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _StatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.headlineMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  void _openMediaViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          mediaFiles: _filteredMedia,
          initialIndex: index,
        ),
      ),
    );
  }

  String _getStatsText() {
    final stats = _libraryStats;
    if (stats.isEmpty) return '';
    final categories = stats['categories'] as Map<String, dynamic>? ?? {};
    return '${categories.keys.length} categories';
  }

  Color _getPlatformColor(String label) {
    switch (label) {
      case 'Instagram':
        return AppColors.instagram;
      case 'TikTok':
        return AppColors.tiktok;
      case 'Facebook':
        return AppColors.facebook;
      case 'Twitter':
        return AppColors.twitter;
      case 'WhatsApp':
        return AppColors.whatsapp;

      default:
        return AppColors.primary;
    }
  }

  IconData _getCategoryIcon(String category) {
    return _categoryIcons[category] ?? Icons.folder_rounded;
  }

  Color _getCategoryColor(String category) {
    final colors = {
      'Comedy': const Color(0xFFF59E0B),
      'Tutorial': const Color(0xFF3B82F6),
      'Music': const Color(0xFF8B5CF6),
      'Fitness': const Color(0xFF22C55E),
      'Gaming': const Color(0xFFEF4444),
      'Cooking': const Color(0xFFF97316),
      'Education': const Color(0xFF6366F1),
      'Travel': const Color(0xFF06B6D4),
      'Technology': const Color(0xFF0EA5E9),
      'Fashion': const Color(0xFFD946EF),
      'Business': const Color(0xFF1E293B),
      'Sports': const Color(0xFFF59E0B),
    };
    return colors[category] ?? AppColors.primary;
  }

  Color _getMoodColor(String mood) {
    switch (mood) {
      case 'Funny':
        return const Color(0xFFF59E0B);
      case 'Inspiring':
        return const Color(0xFF22C55E);
      case 'Educational':
        return const Color(0xFF3B82F6);
      case 'Relaxing':
        return const Color(0xFF06B6D4);
      case 'Energetic':
        return const Color(0xFFEF4444);
      case 'Motivational':
        return const Color(0xFF8B5CF6);
      case 'Calm':
        return const Color(0xFF22C55E);
      default:
        return AppColors.primary;
    }
  }

  /// Icon resolver for Collections. This method must be inside the state class
  /// because the Collections tab calls it directly.
  IconData _getPlatformIcon(String platform) {
    final key =
        platform.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (key.contains('instagram')) return Icons.camera_alt_rounded;
    if (key.contains('tiktok') || key.contains('musically')) {
      return Icons.music_note_rounded;
    }
    if (key.contains('facebook')) return Icons.facebook;
    if (key.contains('twitter') || key == 'x') return Icons.alternate_email;
    if (key.contains('whatsapp')) return Icons.chat_bubble_rounded;
    if (key.contains('cloud')) return Icons.cloud_rounded;
    if (key.contains('linkedin')) return Icons.business_center_rounded;
    return Icons.link_rounded;
  }
}

// ─── Grid Item Widget ──────────────────────────────────────────────────────

class _GridItem extends StatelessWidget {
  final MediaFile mediaFile;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GridItem({
    required this.mediaFile,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail
            _buildThumbnail(),

            // Gradient overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Info
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Row(
                children: [
                  if (mediaFile.isVideo)
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  Expanded(
                    child: Text(
                      mediaFile.fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Platform badge
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getPlatformIcon(mediaFile.sourceApp),
                      color: Colors.white70,
                      size: 8,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      mediaFile.sourceAppDisplayName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 7,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    if (!mediaFile.exists) {
      return _buildPlaceholder();
    }

    if (mediaFile.isVideo) {
      return _LibraryVideoThumb(
        filePath: mediaFile.path,
        placeholder: _buildPlaceholder(),
      );
    }

    return Image.file(
      File(mediaFile.path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.cardAlt,
      child: Center(
        child: Icon(
          mediaFile.isVideo ? Icons.videocam_rounded : Icons.image_rounded,
          color: AppColors.textMuted,
          size: 28,
        ),
      ),
    );
  }

  /// Returns the icon used for a platform label in Collections and Grid cards.
  /// The helper intentionally lives inside _CreatorLibraryScreenState because
  /// both call sites are state-owned widgets in this screen.
  IconData _getPlatformIcon(String platform) {
    final key =
        platform.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (key.contains('instagram')) return Icons.camera_alt_rounded;
    if (key.contains('tiktok') || key.contains('musically')) {
      return Icons.music_note_rounded;
    }
    if (key.contains('facebook')) return Icons.facebook;
    if (key.contains('twitter') || key == 'x') {
      return Icons.alternate_email;
    }
    if (key.contains('whatsapp')) return Icons.chat_bubble_rounded;
    if (key.contains('cloud')) return Icons.cloud_rounded;
    if (key.contains('linkedin')) return Icons.business_center_rounded;
    return Icons.link_rounded;
  }
}

// ─── Video thumbnail widget ──────────────────────────────────────────────────
// Generates and caches an actual preview frame for video items, the same
// approach saved_screen.dart uses, instead of a static play-icon block.

class _LibraryVideoThumb extends StatefulWidget {
  final String filePath;
  final Widget placeholder;

  const _LibraryVideoThumb({
    required this.filePath,
    required this.placeholder,
  });

  @override
  State<_LibraryVideoThumb> createState() => _LibraryVideoThumbState();
}

class _LibraryVideoThumbState extends State<_LibraryVideoThumb> {
  dynamic _thumbData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void didUpdateWidget(_LibraryVideoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _thumbData = null;
      _loading = true;
      _generate();
    }
  }

  Future<void> _generate() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists() || await file.length() < 1024) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final data = await VideoThumbnail.thumbnailData(
        video: widget.filePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 70,
        timeMs: 500,
      );
      if (mounted) {
        setState(() {
          _thumbData = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white38,
            ),
          ),
        ),
      );
    }

    if (_thumbData == null) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Icon(
            Icons.play_circle_rounded,
            color: Colors.white54,
            size: 32,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          _thumbData,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => widget.placeholder,
        ),
        const Center(
          child: Icon(
            Icons.play_circle_rounded,
            color: Colors.white70,
            size: 28,
          ),
        ),
      ],
    );
  }
}

// ─── Collection Card Widget ───────────────────────────────────────────────

class _CollectionCard extends StatelessWidget {
  final String name;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CollectionCard({
    required this.name,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              name,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '$count items',
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mood Item Widget ──────────────────────────────────────────────────────

class _MoodItem extends StatelessWidget {
  final String label;
  final int percentage;
  final Color color;

  const _MoodItem({
    required this.label,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$percentage%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
