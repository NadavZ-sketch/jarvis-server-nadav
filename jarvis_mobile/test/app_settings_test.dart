import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jarvis_mobile/app_settings.dart';

void main() {
  group('AppSettings defaults', () {
    test('has expected default values', () {
      final s = AppSettings();
      expect(s.assistantName, 'Jarvis');
      expect(s.gender, 'male');
      expect(s.personality, 'friendly');
      expect(s.voiceEnabled, true);
      expect(s.userName, 'נדב');
      expect(s.useLocalModel, false);
      expect(s.useLocalServer, false);
      expect(s.obsidianAutoSync, true);
    });

    test('serverUrl returns cloud URL when useLocalServer=false', () {
      final s = AppSettings(useLocalServer: false);
      expect(s.serverUrl, AppSettings.cloudServerUrl);
    });

    test('serverUrl returns localServerUrl when useLocalServer=true', () {
      final s = AppSettings(
        useLocalServer: true,
        localServerUrl: 'http://10.0.0.1:3000',
      );
      expect(s.serverUrl, 'http://10.0.0.1:3000');
    });
  });

  group('AppSettings.toJson', () {
    test('maps voiceEnabled to ttsEnabled for server', () {
      final s = AppSettings(voiceEnabled: false);
      expect(s.toJson()['ttsEnabled'], false);
    });

    test('includes all expected keys', () {
      final json = AppSettings().toJson();
      expect(json.containsKey('assistantName'), true);
      expect(json.containsKey('gender'), true);
      expect(json.containsKey('personality'), true);
      expect(json.containsKey('userName'), true);
      expect(json.containsKey('useLocalModel'), true);
      expect(json.containsKey('useLocalServer'), true);
      expect(json.containsKey('ttsEnabled'), true);
    });

    test('reflects custom values', () {
      final s = AppSettings(
        assistantName: 'Nova',
        gender: 'female',
        personality: 'concise',
        userName: 'מיכאל',
      );
      final json = s.toJson();
      expect(json['assistantName'], 'Nova');
      expect(json['gender'], 'female');
      expect(json['personality'], 'concise');
      expect(json['userName'], 'מיכאל');
    });
  });

  group('AppSettings.load', () {
    test('returns defaults when prefs are empty', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await AppSettings.load();
      expect(s.assistantName, 'Jarvis');
      expect(s.voiceEnabled, true);
      expect(s.useLocalServer, false);
    });

    test('reads all persisted values', () async {
      SharedPreferences.setMockInitialValues({
        'assistantName': 'Alexa',
        'gender': 'female',
        'personality': 'formal',
        'voiceEnabled': false,
        'userName': 'שרה',
        'useLocalModel': true,
        'useLocalServer': true,
        'localServerUrl': 'http://192.168.0.5:3000',
        'obsidianAutoSync': false,
      });
      final s = await AppSettings.load();
      expect(s.assistantName, 'Alexa');
      expect(s.gender, 'female');
      expect(s.personality, 'formal');
      expect(s.voiceEnabled, false);
      expect(s.userName, 'שרה');
      expect(s.useLocalModel, true);
      expect(s.useLocalServer, true);
      expect(s.localServerUrl, 'http://192.168.0.5:3000');
      expect(s.serverUrl, 'http://192.168.0.5:3000');
      expect(s.obsidianAutoSync, false);
    });
  });

  group('AppSettings.save', () {
    test('round-trips all values through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final original = AppSettings(
        assistantName: 'Echo',
        gender: 'female',
        personality: 'humorous',
        voiceEnabled: false,
        userName: 'דן',
        useLocalModel: true,
        useLocalServer: true,
        localServerUrl: 'http://localhost:3000',
        obsidianAutoSync: false,
      );
      await original.save();
      final loaded = await AppSettings.load();
      expect(loaded.assistantName, 'Echo');
      expect(loaded.gender, 'female');
      expect(loaded.personality, 'humorous');
      expect(loaded.voiceEnabled, false);
      expect(loaded.userName, 'דן');
      expect(loaded.useLocalModel, true);
      expect(loaded.useLocalServer, true);
      expect(loaded.localServerUrl, 'http://localhost:3000');
      expect(loaded.obsidianAutoSync, false);
    });
  });
}
