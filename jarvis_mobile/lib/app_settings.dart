import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  String assistantName;
  String gender;       // 'male' | 'female'
  String personality;  // 'friendly' | 'formal' | 'concise' | 'humorous'
  bool voiceEnabled;
  String userName;
  bool useLocalModel;   // true = Ollama, false = Groq/DeepSeek/Gemini
  bool useLocalServer;  // true = local server, false = Render cloud
  String localServerUrl;

  static const String cloudServerUrl = 'https://jarvis-server-nadav.onrender.com';

  String get serverUrl => useLocalServer ? localServerUrl : cloudServerUrl;

  AppSettings({
    this.assistantName = 'Jarvis',
    this.gender = 'male',
    this.personality = 'friendly',
    this.voiceEnabled = true,
    this.userName = 'נדב',
    this.useLocalModel = false,
    this.useLocalServer = false,
    this.localServerUrl = 'http://192.168.1.100:3000',
  });

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      assistantName:  prefs.getString('assistantName')  ?? 'Jarvis',
      gender:         prefs.getString('gender')         ?? 'male',
      personality:    prefs.getString('personality')    ?? 'friendly',
      voiceEnabled:   prefs.getBool('voiceEnabled')     ?? true,
      userName:       prefs.getString('userName')       ?? 'נדב',
      useLocalModel:  prefs.getBool('useLocalModel')    ?? false,
      useLocalServer: prefs.getBool('useLocalServer')   ?? false,
      localServerUrl: prefs.getString('localServerUrl') ?? 'http://192.168.1.100:3000',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assistantName',  assistantName);
    await prefs.setString('gender',         gender);
    await prefs.setString('personality',    personality);
    await prefs.setBool('voiceEnabled',     voiceEnabled);
    await prefs.setString('userName',       userName);
    await prefs.setBool('useLocalModel',    useLocalModel);
    await prefs.setBool('useLocalServer',   useLocalServer);
    await prefs.setString('localServerUrl', localServerUrl);
  }

  Map<String, dynamic> toJson() => {
    'assistantName':  assistantName,
    'gender':         gender,
    'personality':    personality,
    'userName':       userName,
    'useLocalModel':  useLocalModel,
    'useLocalServer': useLocalServer,
    'ttsEnabled':     voiceEnabled,   // server checks settings.ttsEnabled
  };
}
