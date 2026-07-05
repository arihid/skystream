import '../domain/entity/multimedia_item.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/tmdb_genre.dart';
import '../config/tmdb_config.dart';

class TmdbService {
  static final _yearRegex = RegExp(r'\b(19|20)\d{2}\b');
  static const _suggestionsCacheTtl = Duration(days: 1);
  final Dio _dio;
  final Map<String, _SuggestionCacheEntry> _suggestionsCache = {};

  TmdbService(Dio baseDio)
    : _dio = Dio(baseDio.options.copyWith(baseUrl: TmdbConfig.baseUrl)) {
    _dio.interceptors.addAll(baseDio.interceptors);
  }

  // 🚨 CENTRALIZED API KEY CHECK
  void _requireApiKey() {
    if (TmdbConfig.apiKey.isEmpty) {
      throw Exception('TMDB API Key is missing! Check your tmdb_config.dart or .env file.');
    }
  }

  Future<List<TmdbGenre>> getGenres({String language = 'en-US'}) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/genre/movie/list',
        queryParameters: {'api_key': TmdbConfig.apiKey, 'language': language},
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data!['genres'] as List)
            .map((dynamic i) => TmdbGenre.fromJson(i as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Failed to load genres: ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getGenres Error: $e');
      rethrow;
    }
  }

  Future<List<TmdbGenre>> getTvGenres({String language = 'en-US'}) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/genre/tv/list',
        queryParameters: {'api_key': TmdbConfig.apiKey, 'language': language},
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data!['genres'] as List)
            .map((dynamic i) => TmdbGenre.fromJson(i as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Failed to load TV genres: ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getTvGenres Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getDetailsForCarousel(
    int id,
    String mediaType, {
    String language = 'en-US',
  }) async {
    _requireApiKey();
    try {
      final langCode = language.split('-')[0];
      final response = await _dio.get<Map<String, dynamic>>(
        '/$mediaType/$id',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': 'en-US',
          'append_to_response': 'images',
          'include_image_language': '$langCode,null,en',
        },
      );
      if (response.statusCode == 200) return response.data;
      throw Exception('Failed to load details: ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getDetailsForCarousel Error: $e');
      rethrow;
    }
  }

  static int minVoteCount(String fullLanguageCode) {
    final iso = fullLanguageCode.split('-')[0].toLowerCase();
    const regional = {'kn', 'ml', 'bn', 'mr', 'pa', 'gu', 'or', 'as'};
    const major = {
      'hi', 'ta', 'te', 'es', 'fr', 'de', 'it', 'ja', 'ko', 'ru', 'pt', 'zh', 'tr', 'ar', 'pl', 'nl', 'sv',
    };
    if (iso == 'en') return 100;
    if (major.contains(iso)) return 25;
    if (regional.contains(iso)) return 10;
    return 25;
  }

  Future<List<MultimediaItem>> _fetchWithFilterFallback({
    required String discoverPath,
    required String directPath,
    required String sortBy,
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
    Map<String, dynamic>? additionalParams,
  }) async {
    final hasFilters =
        language != 'en-US' ||
        genreId != null ||
        year != null ||
        minRating != null;
    if (hasFilters) {
      return _getDiscoveryResults(
        discoverPath,
        language,
        sortBy,
        genreId: genreId,
        year: year,
        minRating: minRating,
        page: page,
        additionalParams: additionalParams,
      );
    }
    return _getResults(directPath, language: language, page: page);
  }

  Future<List<MultimediaItem>> getTrending({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/movie',
    directPath: '/trending/all/day',
    sortBy: 'popularity.desc',
    language: language,
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> getPopularMovies({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _getDiscoveryResults(
    '/discover/movie',
    language,
    'popularity.desc',
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> getTopRated({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _getDiscoveryResults(
    '/discover/movie',
    language,
    'vote_average.desc',
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> getNowPlayingMovies({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) {
    final today = DateTime.now().toString().split(' ')[0];
    final extra = <String, dynamic>{'release_date.lte': today};
    if (genreId != null ||
        year != null ||
        minRating != null ||
        language != 'en-US') {
      return _getDiscoveryResults(
        '/discover/movie',
        language,
        'release_date.desc',
        genreId: genreId,
        year: year,
        minRating: minRating,
        page: page,
        additionalParams: extra,
      );
    }
    return _getResults('/movie/now_playing', language: language, page: page);
  }

  Future<List<MultimediaItem>> getTrendingMovies({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/movie',
    directPath: '/trending/movie/week',
    sortBy: 'popularity.desc',
    language: language,
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> getTrendingAllDay({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/movie',
    directPath: '/trending/all/day',
    sortBy: 'popularity.desc',
    language: language,
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> getOnTheAirTV({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/tv',
    directPath: '/tv/on_the_air',
    sortBy: 'popularity.desc',
    language: language,
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> getPopularTV({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _getDiscoveryResults(
    '/discover/tv',
    language,
    'popularity.desc',
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> getTopRatedTV({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _getDiscoveryResults(
    '/discover/tv',
    language,
    'vote_average.desc',
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> getAiringTodayTV({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/tv',
    directPath: '/tv/airing_today',
    sortBy: 'first_air_date.desc',
    language: language,
    genreId: genreId,
    year: year,
    minRating: minRating,
    page: page,
  );

  Future<List<MultimediaItem>> multiSearch({
    required String query,
    String language = 'en-US',
    int page = 1,
  }) async {
    _requireApiKey();
    String cleanQuery = query;
    int? filterYear;
    String? filterLanguageCode;

    final yearMatch = _yearRegex.firstMatch(cleanQuery);
    if (yearMatch != null) {
      filterYear = int.tryParse(yearMatch.group(0)!);
      cleanQuery = cleanQuery
          .replaceAll(yearMatch.group(0)!, '')
          .replaceAll('()', '')
          .trim();
    }

    final languageMap = {
      'kannada': 'kn', 'tamil': 'ta', 'telugu': 'te', 'hindi': 'hi',
      'malayalam': 'ml', 'english': 'en', 'korean': 'ko', 'japanese': 'ja',
    };

    for (final key in languageMap.keys) {
      if (cleanQuery.toLowerCase().contains(key)) {
        filterLanguageCode = languageMap[key];
        cleanQuery = cleanQuery
            .replaceAll(RegExp(key, caseSensitive: false), '')
            .trim();
        break; 
      }
    }

    if (cleanQuery.isEmpty) cleanQuery = query;
    cleanQuery = cleanQuery.replaceAll(RegExp(r'\s+'), ' ');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/search/multi',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': language,
          'query': cleanQuery,
          'page': page,
          'include_adult': false,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final rawResults = List<Map<String, dynamic>>.from(
          response.data!['results'] as List,
        );

        final List<Map<String, dynamic>> processedResults = [];

        for (final item in rawResults) {
          final mediaType = item['media_type'];

          if (mediaType == 'person') {
            if (item['known_for'] != null) {
              final knownFor = List<Map<String, dynamic>>.from(
                item['known_for'] as List,
              );
              for (final known in knownFor) {
                known['media_type'] ??= 'movie';
                processedResults.add(known);
              }
            }
          } else if (mediaType == 'movie' || mediaType == 'tv') {
            processedResults.add(item);
          }
        }
        final today = DateTime.now();

        final finalResults = processedResults.where((item) {
          final mediaType = item['media_type'];
          if (mediaType != 'movie' && mediaType != 'tv') return false;

          String? dateStr;
          if (mediaType == 'movie') {
            dateStr = item['release_date'] as String?;
          } else if (mediaType == 'tv') {
            dateStr = item['first_air_date'] as String?;
          }
          if (dateStr == null || dateStr.isEmpty) return false;

          if (filterYear != null) {
            try {
              final date = DateTime.parse(dateStr);
              if (date.year != filterYear) return false;
            } catch (_) {
              return false;
            }
          }

          if (filterLanguageCode != null) {
            final originalLang = item['original_language'];
            if (originalLang != filterLanguageCode) return false;
          }

          try {
            final date = DateTime.parse(dateStr);
            return date.isBefore(today);
          } catch (e) {
            return false;
          }
        }).toList();

        final seenParams = <String>{}; 
        final uniqueResults = <Map<String, dynamic>>[];
        for (final item in finalResults) {
          final key = '${item['id']}_${item['media_type']}';
          if (!seenParams.contains(key)) {
            seenParams.add(key);
            uniqueResults.add(item);
          }
        }

        return uniqueResults
            .map((i) => MultimediaItem.fromTmdbJson(i))
            .toList();
      }
      throw Exception('Search failed with status: ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB multiSearch Error: $e');
      rethrow;
    }
  }

  Future<List<String>> getSuggestions({
    required String query,
    String language = 'en-US',
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    _requireApiKey();

    final cacheKey = '${language.toLowerCase()}|${trimmed.toLowerCase()}';
    final cached = _suggestionsCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _suggestionsCacheTtl) {
      return cached.suggestions;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/search/multi',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'query': trimmed,
          'language': language,
          'include_adult': false,
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        throw Exception('Suggestions failed: ${response.statusCode}');
      }

      final results = List<Map<String, dynamic>>.from(
        (response.data!['results'] as List?) ?? const <dynamic>[],
      );

      final seen = <String>{};
      final suggestions = <String>[];
      for (final item in results) {
        final mediaType = item['media_type']?.toString();
        if (mediaType != 'movie' && mediaType != 'tv') continue;

        final title = (item['title'] ?? item['name'])?.toString().trim();
        if (title == null || title.isEmpty) continue;

        if (seen.add(title)) {
          suggestions.add(title);
          if (suggestions.length == 10) break;
        }
      }

      _suggestionsCache[cacheKey] = _SuggestionCacheEntry(
        suggestions: suggestions,
        cachedAt: DateTime.now(),
      );

      return suggestions;
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getSuggestions Error: $e');
      rethrow;
    }
  }

  Future<List<MultimediaItem>> _getDiscoveryResults(
    String path,
    String fullLanguageCode,
    String sortBy, {
    Map<String, dynamic>? additionalParams,
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    _requireApiKey();
    final isoCode = fullLanguageCode.split('-')[0];
    final today = DateTime.now().toString().split(' ')[0];
    final isMovie = path.contains('movie');

    final query = <String, dynamic>{
      'api_key': TmdbConfig.apiKey,
      'language': 'en-US', 
      'sort_by': sortBy,
      'page': page,
      'include_null_first_air_dates': false,
      'vote_count.gte': minVoteCount(fullLanguageCode),
      if (fullLanguageCode != 'en-US') 'with_original_language': isoCode,
      if (isMovie) 'release_date.lte': today,
      if (!isMovie) 'first_air_date.lte': today,
      ...?additionalParams,
    };

    if (genreId != null) query['with_genres'] = genreId;
    if (year != null) {
      query[isMovie ? 'primary_release_year' : 'first_air_date_year'] = year;
    }
    if (minRating != null) query['vote_average.gte'] = minRating;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
      );

      if (response.statusCode == 200 && response.data != null) {
        return (response.data!['results'] as List)
            .map((i) => MultimediaItem.fromTmdbJson(i as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Discovery API returned ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB _getDiscoveryResults Error: $e');
      rethrow;
    }
  }

  Future<List<MultimediaItem>> _getResults(
    String path, {
    String language = 'en-US',
    int page = 1,
  }) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': language,
          'page': page,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        return (response.data!['results'] as List)
            .map((i) => MultimediaItem.fromTmdbJson(i as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Results API returned ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB _getResults Error: $e');
      rethrow;
    }
  }

  Future<String?> getBestLogo(
    int id, {
    String language = 'en',
    String mediaType = 'movie',
  }) async {
    if (TmdbConfig.apiKey.isEmpty) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/$mediaType/$id/images',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'include_image_language': '$language,null,en',
        },
      );

      final data = response.data;
      if (response.statusCode == 200 && data != null) {
        final logos = List<Map<String, dynamic>>.from(
          (data['logos'] as List?) ?? const <dynamic>[],
        );
        return pickBestLogo(logos, language);
      }
    } catch (_) {}
    return null;
  }

  static String? pickBestLogo(
    List<Map<String, dynamic>> logos,
    String language,
  ) {
    if (logos.isEmpty) return null;

    final langCode = language.split('-')[0];

    Map<String, dynamic> findLogo(bool Function(Map<String, dynamic>) test) {
      return logos.firstWhere(test, orElse: () => {});
    }

    var bestLogo = <String, dynamic>{};

    bestLogo = findLogo((l) => l['iso_639_1'] == langCode && l['file_path'].toString().endsWith('.png'));
    if (bestLogo.isEmpty) {
      bestLogo = findLogo((l) => l['iso_639_1'] == langCode && l['file_path'].toString().endsWith('.svg'));
    }

    if (bestLogo.isEmpty && langCode != 'en') {
      bestLogo = findLogo((l) => l['iso_639_1'] == 'en' && l['file_path'].toString().endsWith('.png'));
    }
    if (bestLogo.isEmpty && langCode != 'en') {
      bestLogo = findLogo((l) => l['iso_639_1'] == 'en' && l['file_path'].toString().endsWith('.svg'));
    }

    if (bestLogo.isEmpty) {
      bestLogo = findLogo((l) => l['iso_639_1'] == null && l['file_path'].toString().endsWith('.png'));
    }
    if (bestLogo.isEmpty) {
      bestLogo = findLogo((l) => l['iso_639_1'] == null && l['file_path'].toString().endsWith('.svg'));
    }

    if (bestLogo.isEmpty) {
      bestLogo = findLogo((l) => (((l['aspect_ratio'] as num?) ?? 0) > 1));
    }

    if (bestLogo.isEmpty) {
      bestLogo = logos.first;
    }

    if (bestLogo.isNotEmpty && bestLogo['file_path'] != null) {
      return '${TmdbConfig.imageBaseUrl}${bestLogo['file_path']}';
    }
    return null;
  }

  Future<Map<String, dynamic>?> getMovieDetails(
    int movieId, {
    String language = 'en-US',
  }) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/movie/$movieId',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': language,
          'append_to_response': 'credits,release_dates',
        },
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      throw Exception('Movie Details API returned ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getMovieDetails Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getMovieExtra(
    int movieId, {
    String language = 'en-US',
  }) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/movie/$movieId',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': language,
          'append_to_response': 'videos,images,translations,external_ids',
          'include_image_language': '$language,null,en',
        },
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      throw Exception('Movie Extra API returned ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getMovieExtra Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getCredits(
    int movieId, {
    String language = 'en-US',
  }) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/movie/$movieId/credits',
        queryParameters: {'api_key': TmdbConfig.apiKey, 'language': language},
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      throw Exception('Credits API returned ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getCredits Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getTvDetails(
    int tvId, {
    String language = 'en-US',
  }) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tv/$tvId',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': language,
          'append_to_response': 'credits,content_ratings',
        },
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      throw Exception('TV Details API returned ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getTvDetails Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getTvExtra(
    int tvId, {
    String language = 'en-US',
  }) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tv/$tvId',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': language,
          'append_to_response': 'videos,images,translations,external_ids',
          'include_image_language': '$language,null,en',
        },
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      throw Exception('TV Extra API returned ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getTvExtra Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getTvSeasonDetails(
    int tvId,
    int seasonNumber, {
    String language = 'en-US',
  }) async {
    _requireApiKey();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tv/$tvId/season/$seasonNumber',
        queryParameters: {'api_key': TmdbConfig.apiKey, 'language': language},
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      throw Exception('TV Season Details API returned ${response.statusCode}');
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB getTvSeasonDetails Error: $e');
      rethrow;
    }
  }
}

class _SuggestionCacheEntry {
  final List<String> suggestions;
  final DateTime cachedAt;

  const _SuggestionCacheEntry({
    required this.suggestions,
    required this.cachedAt,
  });
}