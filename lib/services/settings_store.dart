import 'package:shared_preferences/shared_preferences.dart';

/// Persists the set of selected display ids between launches (SPEC §9.7, D-1).
abstract class SettingsStore {
  Set<String> loadEnabledIds();
  Future<void> saveEnabledIds(Set<String> ids);
}

class SharedPrefsSettingsStore implements SettingsStore {
  SharedPrefsSettingsStore(this._prefs);

  static const _kIds = 'enabledDisplayIds';
  static const _kSchema = 'schemaVersion';

  final SharedPreferences _prefs;

  @override
  Set<String> loadEnabledIds() => (_prefs.getStringList(_kIds) ?? const []).toSet();

  @override
  Future<void> saveEnabledIds(Set<String> ids) async {
    await _prefs.setInt(_kSchema, 1);
    await _prefs.setStringList(_kIds, ids.toList()..sort());
  }
}

class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([Set<String> initial = const {}]) : ids = {...initial};

  Set<String> ids;

  @override
  Set<String> loadEnabledIds() => {...ids};

  @override
  Future<void> saveEnabledIds(Set<String> next) async => ids = {...next};
}
