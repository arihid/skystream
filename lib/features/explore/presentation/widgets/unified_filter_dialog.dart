import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/input/gamepad_actions.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../data/explore_filter_provider.dart';
import '../../data/explore_language_provider.dart';
import '../../data/explore_tmdb_provider.dart';
import '../../data/explore_mode_provider.dart';
import '../../../../shared/widgets/loading_indicator.dart';

import '../../../../core/input/gamepad_intents.dart';
import '../../../../core/widgets/focusable_wrapper.dart';

class UnifiedFilterDialog extends ConsumerStatefulWidget {
  const UnifiedFilterDialog({super.key});

  @override
  ConsumerState<UnifiedFilterDialog> createState() =>
      _UnifiedFilterDialogState();
}

class _UnifiedFilterDialogState extends ConsumerState<UnifiedFilterDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<FocusNode> _tabFocusNodes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    _tabFocusNodes = List.generate(4, (_) => FocusNode(skipTraversal: true));

    // Listen to tab changes and forcefully yank focus to the selected item!
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _tabFocusNodes[_tabController.index].requestFocus();
      }
    });

    // Yank focus to the first tab on initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabFocusNodes[_tabController.index].requestFocus();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var node in _tabFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _cycleTab(int direction) {
    int newIndex = _tabController.index + direction;
    if (newIndex < 0) newIndex = _tabController.length - 1;
    if (newIndex >= _tabController.length) newIndex = 0;
    _tabController.animateTo(newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final isAnime = ref.watch(exploreModeProvider);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Actions(
        actions: <Type, Action<Intent>>{
          AppLeftBumperIntent: CallbackAction<AppLeftBumperIntent>(
            onInvoke: (_) {
              _cycleTab(-1);
              return null;
            }
          ),
          AppRightBumperIntent: CallbackAction<AppRightBumperIntent>(
            onInvoke: (_) {
              _cycleTab(1);
              return null;
            }
          ),
          AppBackIntent: CallbackAction<AppBackIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            }
          ),
        },
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 650, maxWidth: 500),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(
                alpha: 0.9,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2), 
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                      ),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune,
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                              const SizedBox(width: LayoutConstants.spacingSm),
                              Text(
                                "Filters",
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ExcludeFocus(
                          child: TabBar(
                            controller: _tabController,
                            indicatorColor: Theme.of(context).colorScheme.primary,
                            labelColor: Theme.of(context).colorScheme.primary,
                            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            tabs: [
                              if (isAnime)
                                const Tab(text: "Title Lang", icon: Icon(Icons.title, size: 20))
                              else
                                const Tab(text: "Lang", icon: Icon(Icons.translate, size: 20)),
                              Consumer(
                                builder: (c, ref, _) {
                                  final hasFilter = ref.watch(exploreFilterProvider).selectedGenre != null;
                                  return Tab(
                                    text: "Genre",
                                    icon: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        const Icon(Icons.category_outlined, size: 20),
                                        if (hasFilter)
                                          Positioned(
                                            right: -2, top: -2,
                                            child: Container(
                                              width: 8, height: 8,
                                              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              Consumer(
                                builder: (c, ref, _) {
                                  final hasFilter = ref.watch(exploreFilterProvider).selectedYear != null;
                                  return Tab(
                                    text: "Year",
                                    icon: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        const Icon(Icons.calendar_today, size: 20),
                                        if (hasFilter)
                                          Positioned(
                                            right: -2, top: -2,
                                            child: Container(
                                              width: 8, height: 8,
                                              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              Consumer(
                                builder: (c, ref, _) {
                                  final hasFilter = ref.watch(exploreFilterProvider).minRating != null;
                                  return Tab(
                                    text: "Rating",
                                    icon: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        const Icon(Icons.star_outline, size: 20),
                                        if (hasFilter)
                                          Positioned(
                                            right: -2, top: -2,
                                            child: Container(
                                              width: 8, height: 8,
                                              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        if (isAnime) 
                          _TitleLanguageTab(activeNode: _tabFocusNodes[0]) 
                        else 
                          _LanguageTab(activeNode: _tabFocusNodes[0]),
                        _GenreTab(activeNode: _tabFocusNodes[1]),
                        _YearTab(activeNode: _tabFocusNodes[2]),
                        _RatingTab(activeNode: _tabFocusNodes[3]),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "Filters are applied immediately",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMiniHint(context, 'A', 'Select', Colors.greenAccent.shade400),
                            const SizedBox(width: 16),
                            _buildMiniHint(context, 'B', 'Close', Colors.redAccent.shade400),
                            const SizedBox(width: 16),
                            _buildMiniHint(context, 'LB / RB', 'Switch Tab', Colors.white),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniHint(BuildContext context, String btn, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            btn,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 11, fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TABS
// -----------------------------------------------------------------------------

class _RatingTab extends ConsumerStatefulWidget {
  final FocusNode activeNode;
  const _RatingTab({required this.activeNode});

  @override
  ConsumerState<_RatingTab> createState() => _RatingTabState();
}

class _RatingTabState extends ConsumerState<_RatingTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final selectedRating = ref.watch(exploreFilterProvider).minRating;
    final ratings = [null, 5.0, 6.0, 7.0, 8.0, 9.0];

    return ListView.builder(
      scrollCacheExtent: const ScrollCacheExtent.pixels(99999),
      padding: const EdgeInsets.all(LayoutConstants.spacingMd),
      itemCount: ratings.length,
      itemBuilder: (context, index) {
        final rating = ratings[index];
        final isSelected = rating == selectedRating;

        final label = rating == null ? "Any Rating" : "$rating+ Stars";
        final subtitle = rating == null ? "Show all movies" : "Movies with $rating or higher (TMDB/User)";

        return FocusableWrapper(
          focusNode: isSelected ? widget.activeNode : null,
          useScaleEffect: false,
          onTap: () {
            ref.read(exploreFilterProvider.notifier).setRating(rating);
          },
          child: ListTile(
            onTap: () {
              ref.read(exploreFilterProvider.notifier).setRating(rating);
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : null,
            leading: Icon(
              Icons.star,
              color: isSelected ? Theme.of(context).colorScheme.primary : (rating == null ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3) : Colors.amber),
            ),
            title: Text(
              label,
              style: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
          ),
        );
      },
    );
  }
}

class _LanguageTab extends ConsumerStatefulWidget {
  final FocusNode activeNode;
  const _LanguageTab({required this.activeNode});

  @override
  ConsumerState<_LanguageTab> createState() => _LanguageTabState();
}

class _LanguageTabState extends ConsumerState<_LanguageTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final languages = ref.watch(languageListProvider);
    final currentLang = ref.watch(languageProvider);

    return GridView.builder(
      scrollCacheExtent: const ScrollCacheExtent.pixels(99999),
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 2.5, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: languages.length,
      itemBuilder: (context, index) {
        final lang = languages[index];
        final isSelected = lang.code == currentLang;

        return FocusableWrapper(
          focusNode: isSelected ? widget.activeNode : null,
          useScaleEffect: false,
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            ref.read(languageProvider.notifier).setLanguage(lang.code);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd),
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                  child: Text(
                    lang.code.split('-')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: LayoutConstants.spacingSm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lang.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold, fontSize: 15,
                        ),
                      ),
                      Text(
                        lang.nativeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7) : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected) Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GenreTab extends ConsumerStatefulWidget {
  final FocusNode activeNode;
  const _GenreTab({required this.activeNode});

  @override
  ConsumerState<_GenreTab> createState() => _GenreTabState();
}

class _GenreTabState extends ConsumerState<_GenreTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final genresAsync = ref.watch(genresProvider);
    final selectedGenre = ref.watch(exploreFilterProvider).selectedGenre;

    return genresAsync.when(
      data: (genres) => ListView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(99999),
        padding: const EdgeInsets.all(LayoutConstants.spacingMd),
        itemCount: genres.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = selectedGenre == null;
            return FocusableWrapper(
              focusNode: isSelected ? widget.activeNode : null,
              useScaleEffect: false,
              onTap: () {
                ref.read(exploreFilterProvider.notifier).setGenre(null);
              },
              child: ListTile(
                onTap: () {
                  ref.read(exploreFilterProvider.notifier).setGenre(null);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : null,
                leading: Icon(
                  Icons.category,
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white24,
                ),
                title: Text(
                  "All Genres",
                  style: TextStyle(
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }

          final genre = genres[index - 1];
          final isSelected = selectedGenre != null && selectedGenre.id == genre.id;
          return FocusableWrapper(
            focusNode: isSelected ? widget.activeNode : null,
            useScaleEffect: false,
            onTap: () {
              ref.read(exploreFilterProvider.notifier).setGenre(genre);
            },
            child: ListTile(
              onTap: () {
                ref.read(exploreFilterProvider.notifier).setGenre(genre);
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : null,
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              title: Text(
                genre.name,
                style: TextStyle(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
      loading: () => const Center(child: AppLoadingIndicator()),
      error: (_, _) => const Center(child: Text("Failed to load genres", style: TextStyle(color: Colors.white))),
    );
  }
}

class _YearTab extends ConsumerStatefulWidget {
  final FocusNode activeNode;
  const _YearTab({required this.activeNode});

  @override
  ConsumerState<_YearTab> createState() => _YearTabState();
}

class _YearTabState extends ConsumerState<_YearTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final selectedYear = ref.watch(exploreFilterProvider).selectedYear;
    final currentYear = DateTime.now().year;
    final years = List.generate(50, (index) => currentYear - index);

    return GridView.builder(
      scrollCacheExtent: const ScrollCacheExtent.pixels(99999),
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 2.0, crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: years.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          final isSelected = selectedYear == null;
          return FocusableWrapper(
            focusNode: isSelected ? widget.activeNode : null,
            useScaleEffect: false,
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              ref.read(exploreFilterProvider.notifier).setYear(null);
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "All",
                    style: TextStyle(
                      color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 16,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary),
                  ],
                ],
              ),
            ),
          );
        }

        final year = years[index - 1];
        final isSelected = year == selectedYear;

        return FocusableWrapper(
          focusNode: isSelected ? widget.activeNode : null,
          useScaleEffect: false,
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            ref.read(exploreFilterProvider.notifier).setYear(year);
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  year.toString(),
                  style: TextStyle(
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TitleLanguageTab extends ConsumerStatefulWidget {
  final FocusNode activeNode;
  const _TitleLanguageTab({required this.activeNode});

  @override
  ConsumerState<_TitleLanguageTab> createState() => _TitleLanguageTabState();
}

class _TitleLanguageTabState extends ConsumerState<_TitleLanguageTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentLang = ref.watch(animeTitleLanguageProvider);
    final titleLangs = [
      {'code': 'english', 'name': 'English Title', 'native': 'English'},
      {'code': 'japanese', 'name': 'Japanese Title', 'native': '日本語 (Native)'},
      {'code': 'romaji', 'name': 'Romaji Title', 'native': 'Rōmaji'},
    ];

    return GridView.builder(
      scrollCacheExtent: const ScrollCacheExtent.pixels(99999),
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 2.5, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: titleLangs.length,
      itemBuilder: (context, index) {
        final lang = titleLangs[index];
        final isSelected = lang['code'] == currentLang;

        return FocusableWrapper(
          focusNode: isSelected ? widget.activeNode : null,
          useScaleEffect: false,
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            ref.read(animeTitleLanguageProvider.notifier).setLanguage(lang['code']!);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd),
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                  child: Text(
                    lang['code']!.substring(0, 2).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: LayoutConstants.spacingSm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lang['name']!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold, fontSize: 15,
                        ),
                      ),
                      Text(
                        lang['native']!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7) : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected) Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}