/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (C) 2020, 2021 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:wger/core/locator.dart';
import 'package:wger/database/exercises/exercise_database.dart';
import 'package:wger/exceptions/no_such_entry_exception.dart';
import 'package:wger/helpers/consts.dart';
import 'package:wger/helpers/shared_preferences.dart';
import 'package:wger/models/exercises/category.dart';
import 'package:wger/models/exercises/equipment.dart';
import 'package:wger/models/exercises/exercise.dart';
import 'package:wger/models/exercises/exercise_api.dart';
import 'package:wger/models/exercises/language.dart';
import 'package:wger/models/exercises/muscle.dart';
import 'package:wger/providers/base_provider.dart';

class ExercisesProvider with ChangeNotifier {
  final _logger = Logger('ExercisesProvider');

  final WgerBaseProvider baseProvider;
  late ExerciseDatabase database;

  ExercisesProvider(this.baseProvider, {ExerciseDatabase? database}) {
    this.database = database ?? locator<ExerciseDatabase>();
  }

  static const EXERCISE_CACHE_DAYS = 7;
  static const CACHE_VERSION = 4;

  static const exerciseInfoUrlPath = 'exerciseinfo';
  static const exerciseSearchPath = 'exercise/search';

  static const categoriesUrlPath = 'exercisecategory';
  static const musclesUrlPath = 'muscle';
  static const equipmentUrlPath = 'equipment';
  static const languageUrlPath = 'language';

  List<Exercise> exercises = [];

  List<ExerciseCategory> _categories = [];
  List<Muscle> _muscles = [];
  List<Equipment> _equipment = [];
  List<Language> _languages = [];

  Filters? _filters;

  Filters? get filters => _filters;

  Future<void> setFilters(Filters? newFilters) async {
    _filters = newFilters;
    await findByFilters();
  }

  List<Exercise> _filteredExercises = [];

  List<Exercise> get filteredExercises => _filteredExercises;

  set filteredExercises(List<Exercise> newFilteredExercises) {
    _filteredExercises = newFilteredExercises;
    notifyListeners();
  }

  Map<int, List<Exercise>> get exerciseByVariation {
    final Map<int, List<Exercise>> variations = {};

    for (final exercise in exercises.where((e) => e.variationId != null)) {
      if (!variations.containsKey(exercise.variationId)) {
        variations[exercise.variationId!] = [];
      }

      variations[exercise.variationId]!.add(exercise);
    }

    return variations;
  }

  List<ExerciseCategory> get categories => [..._categories];

  List<Muscle> get muscles => [..._muscles];

  List<Equipment> get equipment => [..._equipment];

  List<Language> get languages => [..._languages];

  set languages(List<Language> languages) {
    _languages = languages;
  }

  // Initialize filters for exercises search in exercises list
  void initFilters() {
    if (_muscles.isEmpty || _equipment.isEmpty || _filters != null) {
      return;
    }

    setFilters(
      Filters(
        exerciseCategories: FilterCategory(
          title: 'Category',
          items: Map.fromEntries(
            _categories.map(
              (category) => MapEntry<ExerciseCategory, bool>(category, false),
            ),
          ),
        ),
        equipment: FilterCategory(
          title: 'Equipment',
          items: Map.fromEntries(
            _equipment.map(
              (singleEquipment) => MapEntry<Equipment, bool>(singleEquipment, false),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> findByFilters() async {
    // Filters not initialized
    if (filters == null) {
      filteredExercises = [];
      return;
    }

    // Filters are initialized and nothing is marked
    if (filters!.isNothingMarked && filters!.searchTerm.length <= 1) {
      filteredExercises = exercises;
      return;
    }

    filteredExercises = [];

    List<Exercise> filteredItems = exercises;
    if (filters!.searchTerm.length > 1) {
      filteredItems = await searchExercise(filters!.searchTerm);
    }
    filteredExercises = filteredItems.where((exercise) {
      final bool isInAnyCategory = filters!.exerciseCategories.selected.contains(exercise.category);

      final bool doesContainAnyEquipment = filters!.equipment.selected.any(
        (selectedEquipment) => exercise.equipment.contains(selectedEquipment),
      );

      return (isInAnyCategory || filters!.exerciseCategories.selected.isEmpty) &&
          (doesContainAnyEquipment || filters!.equipment.selected.isEmpty);
    }).toList();
  }

  /// Clears all lists
  void clear() {
    _equipment = [];
    _muscles = [];
    _categories = [];
    _languages = [];
    exercises = [];
  }

  /// Find exercise base by ID
  ///
  /// Note: prefer using the async `fetchAndSetExercise` method
  Exercise findExerciseById(int id) {
    return exercises.firstWhere(
      (exercise) => exercise.id == id,
      orElse: () => throw const NoSuchEntryException(),
    );
  }

  /// Find exercises by variation IDs
  ///
  /// exerciseIdToExclude: the ID of the exercise to exclude from the list of
  /// returned exercises. Since this is typically called by one exercise, we are
  /// not interested in seeing that same exercise returned in the list of variations.
  /// If this parameter is not passed, all exercises are returned.
  List<Exercise> findExercisesByVariationId(
    int? variationId, {
    int? exerciseIdToExclude,
  }) {
    if (variationId == null) {
      return [];
    }

    var out = exercises.where((base) => base.variationId == variationId).toList();

    if (exerciseIdToExclude != null) {
      out = out.where((e) => e.id != exerciseIdToExclude).toList();
    }
    return out;
  }

  /// Find category by ID
  ExerciseCategory findCategoryById(int id) {
    return _categories.firstWhere(
      (cat) => cat.id == id,
      orElse: () => throw const NoSuchEntryException(),
    );
  }

  /// Find equipment by ID
  Equipment findEquipmentById(int id) {
    return _equipment.firstWhere(
      (equipment) => equipment.id == id,
      orElse: () => throw const NoSuchEntryException(),
    );
  }

  /// Find muscle by ID
  Muscle findMuscleById(int id) {
    return _muscles.firstWhere(
      (muscle) => muscle.id == id,
      orElse: () => throw const NoSuchEntryException(),
    );
  }

  /// Find language by ID
  Language findLanguageById(int id) {
    return _languages.firstWhere(
      (language) => language.id == id,
      orElse: () => throw const NoSuchEntryException(),
    );
  }

  Future<void> fetchAndSetCategoriesFromApi() async {
    _logger.info('Loading exercise categories from API');
    final categories = await baseProvider.fetchPaginated(baseProvider.makeUrl(categoriesUrlPath));
    for (final category in categories) {
      _categories.add(ExerciseCategory.fromJson(category));
    }
  }

  Future<void> fetchAndSetMusclesFromApi() async {
    _logger.info('Loading muscles from API');
    final muscles = await baseProvider.fetchPaginated(baseProvider.makeUrl(musclesUrlPath));

    for (final muscle in muscles) {
      _muscles.add(Muscle.fromJson(muscle));
    }
  }

  Future<void> fetchAndSetEquipmentsFromApi() async {
    _logger.info('Loading equipment from API');
    final equipments = await baseProvider.fetchPaginated(baseProvider.makeUrl(equipmentUrlPath));

    for (final equipment in equipments) {
      _equipment.add(Equipment.fromJson(equipment));
    }
  }

  Future<void> fetchAndSetLanguagesFromApi() async {
    _logger.info('Loading languages from API');

    final languageData = await baseProvider.fetchPaginated(baseProvider.makeUrl(languageUrlPath));

    for (final language in languageData) {
      _languages.add(Language.fromJson(language));
    }
  }

  /// Returns the exercise with the given ID
  ///
  /// If the exercise is not known locally, it is fetched from the server.
  Future<Exercise?> fetchAndSetExercise(int exerciseId) async {
    // _logger.finer('Fetching exercise $exerciseId');
    try {
      final exercise = findExerciseById(exerciseId);

      // _logger.finer('Found $exerciseId in provider list');

      // Note: no await since we don't care for the updated data right now. It
      // will be written to the db whenever the request finishes and we will get
      // the updated exercise the next time
      handleUpdateExerciseFromApi(database, exerciseId);

      return exercise;
    } on NoSuchEntryException {
      return handleUpdateExerciseFromApi(database, exerciseId);
    }
  }

  /// Handles updates to exercises from the server to the local database
  ///
  /// The current logic is:
  /// Is the exercise known locally:
  /// -> no: fetch and add to the DB
  /// -> yes: Do we need to re-fetch?
  ///    -> no: just return what we have in the DB
  ///    -> yes: fetch data and update if necessary
  Future<Exercise> handleUpdateExerciseFromApi(
    ExerciseDatabase database,
    int exerciseId,
  ) async {
    Exercise exercise;

    // NOTE: this should not be necessary anymore. We had a bug that would
    //       create duplicate entries in the database and should be fixed now.
    //       However, we keep it here for now to be on the safe side.
    //       In the future this can be replaced by a .getSingleOrNull()
    final exerciseResult =
        await (database.select(database.exercises)..where((e) => e.id.equals(exerciseId))).get();

    ExerciseTable? exerciseDb;
    if (exerciseResult.isNotEmpty) {
      exerciseDb = exerciseResult.first;
    }

    // Note that this shouldn't happen anymore...
    if (exerciseResult.length > 1) {
      _logger.warning('Found ${exerciseResult.length} entries for exercise $exerciseId in the db');
    }

    // Exercise is already known locally
    if (exerciseDb != null) {
      final nextFetch = exerciseDb.lastFetched.add(const Duration(days: EXERCISE_CACHE_DAYS));
      exercise = Exercise.fromApiDataString(exerciseDb.data, _languages);

      // Fetch and update
      if (nextFetch.isBefore(DateTime.now())) {
        _logger.fine(
          'Re-fetching exercise $exerciseId from API since last fetch was ${exerciseDb.lastFetched}',
        );

        final apiData = await baseProvider.fetch(
          baseProvider.makeUrl(exerciseInfoUrlPath, id: exerciseId),
        );
        final exerciseApiData = ExerciseApiData.fromJson(apiData);

        // There have been changes on the server, update
        if (exerciseApiData.lastUpdateGlobal.isAfter(exerciseDb.lastUpdate)) {
          exercise = Exercise.fromApiData(exerciseApiData, _languages);

          await (database.update(database.exercises)..where((e) => e.id.equals(exerciseId))).write(
            ExercisesCompanion(
              data: Value(jsonEncode(apiData)),
              lastUpdate: Value(exercise.lastUpdateGlobal!),
              lastFetched: Value(DateTime.now()),
            ),
          );
          // Update last fetched date, otherwise we'll keep hitting the API
        } else {
          await (database.update(database.exercises)..where((e) => e.id.equals(exerciseId))).write(
            ExercisesCompanion(lastFetched: Value(DateTime.now())),
          );
        }
      }
      // New exercise, fetch and insert to DB
    } else {
      _logger.fine('New exercise $exerciseId, fetching from API');
      final exerciseData = await baseProvider.fetch(
        baseProvider.makeUrl(exerciseInfoUrlPath, id: exerciseId),
      );
      exercise = Exercise.fromApiDataJson(exerciseData, _languages);

      if (exerciseDb == null) {
        await database.into(database.exercises).insert(
              ExercisesCompanion.insert(
                id: exercise.id!,
                data: jsonEncode(exerciseData),
                lastUpdate: exercise.lastUpdateGlobal!,
                lastFetched: DateTime.now(),
              ),
            );
        _logger.finer('Saved exercise ${exercise.id!} to db cache');
      }
    }

    // Either update or add the exercise to local list
    final index = exercises.indexWhere((exercise) => exercise.id == exerciseId);
    if (index != -1) {
      exercises[index] = exercise;
    } else {
      exercises.add(exercise);
    }

    return exercise;
  }

  Future<void> initCacheTimesLocalPrefs({forceInit = false}) async {
    final prefs = PreferenceHelper.asyncPref;

    final initDate = DateTime(2023, 1, 1).toIso8601String();

    if (forceInit || !(await prefs.containsKey(PREFS_LAST_UPDATED_MUSCLES))) {
      await prefs.setString(PREFS_LAST_UPDATED_MUSCLES, initDate);
    }
    if (forceInit || !(await prefs.containsKey(PREFS_LAST_UPDATED_EQUIPMENT))) {
      await prefs.setString(PREFS_LAST_UPDATED_EQUIPMENT, initDate);
    }
    if (forceInit || !(await prefs.containsKey(PREFS_LAST_UPDATED_LANGUAGES))) {
      await prefs.setString(PREFS_LAST_UPDATED_LANGUAGES, initDate);
    }
    if (forceInit || !(await prefs.containsKey(PREFS_LAST_UPDATED_CATEGORIES))) {
      await prefs.setString(PREFS_LAST_UPDATED_CATEGORIES, initDate);
    }
  }

  Future<void> clearAllCachesAndPrefs() async {
    await database.deleteEverything();
    await initCacheTimesLocalPrefs(forceInit: true);
  }

  /// Loads all needed data for the exercises from the local cache, or if not available,
  /// from the API:
  /// - Muscles
  /// - Categories
  /// - Languages
  /// - Equipment
  /// - Exercises (only local cache)
  Future<void> fetchAndSetInitialData() async {
    // clear();
    _logger.info('Fetching initial exercise data');

    await initCacheTimesLocalPrefs();

    // Load categories, muscles, equipment and languages
    await Future.wait([
      fetchAndSetMuscles(database),
      fetchAndSetCategories(database),
      fetchAndSetLanguages(database),
      fetchAndSetEquipments(database),
    ]);
    await setExercisesFromDatabase(database);

    initFilters();
    notifyListeners();
  }

  /// Set the available exercises as available in the db
  Future<void> setExercisesFromDatabase(
    ExerciseDatabase database, {
    bool forceDeleteCache = false,
  }) async {
    if (forceDeleteCache) {
      await database.delete(database.exercises).go();
    }

    final exercisesDb = await database.select(database.exercises).get();
    _logger.info('Loaded ${exercisesDb.length} exercises from DB cache');

    exercises = exercisesDb.map((e) => Exercise.fromApiDataString(e.data, _languages)).toList();
  }

  /// Updates the exercise database with *all* the exercises from the server
  Future<void> updateExerciseCache(ExerciseDatabase database) async {
    final data = await baseProvider.fetchPaginated(
      baseProvider.makeUrl(exerciseInfoUrlPath, query: {'limit': '999'}),
    );
    exercises = data.map((e) => Exercise.fromApiDataJson(e, _languages)).toList();

    // Insert new entries and update ones that have been edited
    Future.forEach(data, (exerciseData) async {
      final exercise = await (database.select(database.exercises)
            ..where((e) => e.id.equals(exerciseData['id'])))
          .getSingleOrNull();

      // New exercise, insert
      if (exercise == null) {
        database.into(database.exercises).insert(
              ExercisesCompanion.insert(
                id: exerciseData['id'],
                data: jsonEncode(exerciseData),
                lastUpdate: DateTime.parse(exerciseData['last_update_global']),
                lastFetched: DateTime.now(),
              ),
            );
      }

      // If there were updates on the server, update
      final lastUpdateApi = DateTime.parse(exerciseData['last_update_global']);
      if (exercise != null && lastUpdateApi.isAfter(exercise.lastUpdate)) {
        // TODO: timezones 🥳
        _logger.fine(
          'Exercise ${exercise.id}: update API $lastUpdateApi | Update DB: ${exercise.lastUpdate}',
        );
        (database.update(database.exercises)..where((e) => e.id.equals(exerciseData['id']))).write(
          ExercisesCompanion(
            id: Value(exerciseData['id']),
            data: Value(jsonEncode(exerciseData)),
            lastUpdate: Value(DateTime.parse(exerciseData['last_update_global'])),
            lastFetched: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  /// Fetches and sets the available muscles
  ///
  /// We first try to read from the local DB, and from the API if the data is too old
  Future<void> fetchAndSetMuscles(ExerciseDatabase database) async {
    final prefs = PreferenceHelper.asyncPref;
    var validTill = DateTime.parse((await prefs.getString(PREFS_LAST_UPDATED_MUSCLES))!);

    // Cache still valid, return it
    if (validTill.isAfter(DateTime.now())) {
      final muscles = await database.select(database.muscles).get();

      if (muscles.isNotEmpty) {
        _muscles = muscles.map((e) => e.data).toList();
        _logger.info('Loaded ${_muscles.length} muscles from cache');
        return;
      }
    }

    // Fetch from API and save to DB
    await fetchAndSetMusclesFromApi();
    await database.delete(database.muscles).go();
    await Future.forEach(_muscles, (e) async {
      await database.into(database.muscles).insert(
            MusclesCompanion.insert(id: e.id, data: e),
          );
    });
    validTill = DateTime.now().add(const Duration(days: EXERCISE_CACHE_DAYS));
    await prefs.setString(
      PREFS_LAST_UPDATED_MUSCLES,
      validTill.toIso8601String(),
    );
    _logger.fine('Saved ${_muscles.length} muscles to cache (valid till $validTill)');
  }

  /// Fetches and sets the available categories
  ///
  /// We first try to read from the local DB, and from the API if the data is too old
  Future<void> fetchAndSetCategories(ExerciseDatabase database) async {
    final prefs = PreferenceHelper.asyncPref;
    var validTill = DateTime.parse((await prefs.getString(PREFS_LAST_UPDATED_CATEGORIES))!);

    // Cache still valid, return it
    if (validTill.isAfter(DateTime.now())) {
      final categories = await database.select(database.categories).get();

      if (categories.isNotEmpty) {
        _categories = categories.map((e) => e.data).toList();
        _logger.info('Loaded ${categories.length} categories from cache');
        return;
      }
    }

    // Fetch from API and save to DB
    await fetchAndSetCategoriesFromApi();
    await database.delete(database.categories).go();
    await Future.forEach(_categories, (e) async {
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(id: e.id, data: e),
          );
    });
    validTill = DateTime.now().add(const Duration(days: EXERCISE_CACHE_DAYS));
    await prefs.setString(
      PREFS_LAST_UPDATED_CATEGORIES,
      validTill.toIso8601String(),
    );
    _logger.fine('Saved ${_categories.length} categories to cache (valid till $validTill)');
  }

  /// Fetches and sets the available languages
  ///
  /// We first try to read from the local DB, and from the API if the data is too old
  Future<void> fetchAndSetLanguages(ExerciseDatabase database) async {
    final prefs = PreferenceHelper.asyncPref;
    var validTill = DateTime.parse((await prefs.getString(PREFS_LAST_UPDATED_LANGUAGES))!);

    // Cache still valid, return it
    if (validTill.isAfter(DateTime.now())) {
      final languages = await database.select(database.languages).get();

      if (languages.isNotEmpty) {
        _languages = languages.map((e) => e.data).toList();
        _logger.info('Loaded ${languages.length} languages from cache');
        return;
      }
    }

    // Fetch from API and save to DB
    await fetchAndSetLanguagesFromApi();
    await database.delete(database.languages).go();
    await Future.forEach(_languages, (e) async {
      await database.into(database.languages).insert(
            LanguagesCompanion.insert(id: e.id, data: e),
          );
    });

    validTill = DateTime.now().add(const Duration(days: EXERCISE_CACHE_DAYS));
    await prefs.setString(
      PREFS_LAST_UPDATED_LANGUAGES,
      validTill.toIso8601String(),
    );
    _logger.info('Saved ${languages.length} languages to cache (valid till $validTill)');
  }

  /// Fetches and sets the available equipment
  ///
  /// We first try to read from the local DB, and from the API if the data is too old
  Future<void> fetchAndSetEquipments(ExerciseDatabase database) async {
    final prefs = PreferenceHelper.asyncPref;
    var validTill = DateTime.parse((await prefs.getString(PREFS_LAST_UPDATED_EQUIPMENT))!);

    // Cache still valid, return it
    if (validTill.isAfter(DateTime.now())) {
      final equipments = await database.select(database.equipments).get();

      if (equipments.isNotEmpty) {
        _equipment = equipments.map((e) => e.data).toList();
        _logger.info('Loaded ${equipment.length} equipment from cache');
        return;
      }
    }

    // Fetch from API and save to DB
    await fetchAndSetEquipmentsFromApi();
    await database.delete(database.equipments).go();
    await Future.forEach(_equipment, (e) async {
      await database.into(database.equipments).insert(
            EquipmentsCompanion.insert(id: e.id, data: e),
          );
    });
    validTill = DateTime.now().add(const Duration(days: EXERCISE_CACHE_DAYS));
    await prefs.setString(
      PREFS_LAST_UPDATED_EQUIPMENT,
      validTill.toIso8601String(),
    );
    _logger.fine('Saved ${_equipment.length} equipment entries to cache (valid till $validTill)');
  }

  /// Searches for an exercise
  ///
  /// We could do this locally, but the server has better text searching capabilities
  /// with postgresql.
  Future<List<Exercise>> searchExercise(
    String name, {
    String languageCode = LANGUAGE_SHORT_ENGLISH,
    bool searchEnglish = false,
  }) async {
    if (name.length <= 1) {
      return [];
    }

    final languages = [languageCode];
    if (searchEnglish && languageCode != LANGUAGE_SHORT_ENGLISH) {
      languages.add(LANGUAGE_SHORT_ENGLISH);
    }

    // Send the request
    final result = await baseProvider.fetch(
      baseProvider.makeUrl(
        exerciseSearchPath,
        query: {'term': name, 'language': languages.join(',')},
      ),
    );

    // Load the exercises
    final results = ExerciseApiSearch.fromJson(result);

    final List<Exercise> out = [];
    for (final result in results.suggestions) {
      final exercise = await fetchAndSetExercise(result.data.exerciseId);
      if (exercise != null) {
        out.add(exercise);
      }
    }
    // return Future.wait(
    //   results.suggestions.map((e) => fetchAndSetExercise(e.data.exerciseId)),
    // );

    return out;
  }
}

class FilterCategory<T> {
  bool isExpanded;
  final Map<T, bool> items;
  final String title;

  List<T> get selected => [...items.keys].where((key) => items[key]!).toList();

  FilterCategory({
    required this.title,
    required this.items,
    this.isExpanded = false,
  });

  FilterCategory<T> copyWith({
    bool? isExpanded,
    Map<T, bool>? items,
    String? title,
  }) {
    return FilterCategory(
      isExpanded: isExpanded ?? this.isExpanded,
      items: items ?? this.items,
      title: title ?? this.title,
    );
  }
}

class Filters {
  final FilterCategory<ExerciseCategory> exerciseCategories;
  final FilterCategory<Equipment> equipment;
  String searchTerm;

  Filters({
    required this.exerciseCategories,
    required this.equipment,
    this.searchTerm = '',
    bool doesNeedUpdate = false,
  }) : _doesNeedUpdate = doesNeedUpdate;

  List<FilterCategory> get filterCategories => [exerciseCategories, equipment];

  bool get isNothingMarked {
    final isExerciseCategoryMarked = exerciseCategories.items.values.any((isMarked) => isMarked);
    final isEquipmentMarked = equipment.items.values.any((isMarked) => isMarked);
    return !isExerciseCategoryMarked && !isEquipmentMarked;
  }

  bool _doesNeedUpdate = false;

  bool get doesNeedUpdate => _doesNeedUpdate;

  void markNeedsUpdate() {
    _doesNeedUpdate = true;
  }

  void markUpdated() {
    _doesNeedUpdate = false;
  }

  Filters copyWith({
    FilterCategory<ExerciseCategory>? exerciseCategories,
    FilterCategory<Equipment>? equipment,
    String? searchTerm,
    bool? doesNeedUpdate,
  }) {
    return Filters(
      exerciseCategories: exerciseCategories ?? this.exerciseCategories,
      equipment: equipment ?? this.equipment,
      searchTerm: searchTerm ?? this.searchTerm,
      doesNeedUpdate: doesNeedUpdate ?? _doesNeedUpdate,
    );
  }
}
