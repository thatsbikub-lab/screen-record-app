import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recording.dart';

class RecordingStore {
  RecordingStore._(this._preferences, this._recordings);

  static const _storageKey = 'capturenest.recordings.v1';
  final SharedPreferences _preferences;
  final List<Recording> _recordings;

  List<Recording> get recordings => List<Recording>.unmodifiable(_recordings);

  static Future<RecordingStore> open() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null) return RecordingStore._(preferences, <Recording>[]);

    try {
      final decoded = (jsonDecode(raw) as List<dynamic>)
          .map((entry) => Recording.fromJson(entry as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return RecordingStore._(preferences, decoded);
    } catch (_) {
      return RecordingStore._(preferences, <Recording>[]);
    }
  }

  Future<void> put(Recording recording) async {
    _recordings.removeWhere((item) => item.id == recording.id);
    _recordings.add(recording);
    _recordings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _save();
  }

  Future<void> remove(String id) async {
    _recordings.removeWhere((item) => item.id == id);
    await _save();
  }

  Future<void> _save() => _preferences.setString(
        _storageKey,
        jsonEncode(_recordings.map((recording) => recording.toJson()).toList()),
      );
}


