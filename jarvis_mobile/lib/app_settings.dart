import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  String assistantName;
  String gender;       // 'male' | 'female'
  String personality;  // 'friendly' | 'formal' | 'concise' | 'humorous'
  bool voiceEnabled;
  String userName;

  AppSettings({
    this.assistantName = 'Jarvis',
    this.gender = 'male',
    this.personality = 'friendly',
    this.voiceEnabled = true,
    this.userName = 'נדב',
  });

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      assistantName: prefs.getString('assistantName') ?? 'Jarvis',
      gender:        prefs.getString('gender')        ?? 'male',
      personality:   prefs.getString('personality')   ?? 'friendly',
      voiceEnabled:  prefs.getBool('voiceEnabled')    ?? true,
      userName:      prefs.getString('userName')       ?? 'נדב',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assistantName', assistantName);
    await prefs.setString('gender',        gender);
    await prefs.setString('personality',   personality);
    await prefs.setBool('voiceEnabled',    voiceEnabled);
    await prefs.setString('userName',      userName);
  }

  Map<String, dynamic> toJson() => {
    'assistantName': assistantName,
    'gender':        gender,
    'personality':   personality,
    'userName':      userName,
  };
}
