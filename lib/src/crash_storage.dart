import 'dart:convert' as json;
import 'package:shared_preferences/shared_preferences.dart';
import 'models/crash_data.dart';

class CrashStorage {
  static const String _crashStorageKey = 'crash_reporter';
  static const int _maxStoredCrashes = 50;
  final Function(String) _debugPrint;

  CrashStorage({required Function(String) debugPrint})
      : _debugPrint = debugPrint;

  Future<List<CrashData>> getLocalCrashLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crashesJson = prefs.getString(_crashStorageKey);

      if (crashesJson != null && crashesJson.isNotEmpty) {
        final List<dynamic> crashesList = json.jsonDecode(crashesJson);
        return crashesList
            .map((crashJson) => CrashData.fromJson(crashJson))
            .toList();
      }
      return [];
    } catch (e) {
      _debugPrint('Error reading crash logs: $e');
      return [];
    }
  }

  Future<void> saveCrashLocally(CrashData crashData) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing crashes
      List<CrashData> crashes = await getLocalCrashLogs();

      // Add new crash
      crashes.add(crashData);

      // Keep only last N crashes
      if (crashes.length > _maxStoredCrashes) {
        crashes = crashes.sublist(crashes.length - _maxStoredCrashes);
      }

      // Save back to SharedPreferences
      final crashesJson =
          json.jsonEncode(crashes.map((crash) => crash.toJson()).toList());
      await prefs.setString(_crashStorageKey, crashesJson);
    } catch (e) {
      _debugPrint('Failed to save crash locally: $e');
    }
  }

  Future<void> clearLocalCrashLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_crashStorageKey);
    } catch (e) {
      _debugPrint('Error clearing crash logs: $e');
    }
  }
}
