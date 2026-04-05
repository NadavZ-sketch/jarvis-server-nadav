import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyAssistantApp());
}

class MyAssistantApp extends StatelessWidget {
  const MyAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyAssistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C6AF7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _taskController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = false;
  int _currentTab = 0;
  String _language = 'he';

  final Map<String, Map<String, String>> _texts = {
    'he': {
      'appTitle': '🤖 MyAssistant',
      'chat': '💬 צ\'אט',
      'tasks': '✅ משימות',
      'settings': '⚙️ הגדרות',
      'inputHint': 'כתוב הודעה...',
      'newTask': 'משימה חדשה...',
      'addTask': '+ הוסף',
      'saveSettings': '💾 שמור הגדרות',
      'model': '🤖 מודל שפה',
      'personality': '🎭 אישיות',
      'language': '🌐 שפה',
      'modelValue': 'Groq (חינמי מהיר)',
      'personalityValue': 'ידידותי ומקצועי',
      'languageValue': 'עברית',
      'error': '❌ שגיאה בחיבור לשרת',
    },
    'en': {
      'appTitle': '🤖 MyAssistant',
      'chat': '💬 Chat',
      'tasks': '✅ Tasks',
      'settings': '⚙️ Settings',
      'inputHint': 'Type a message...',
      'newTask': 'New task...',
      'addTask': '+ Add',
      'saveSettings': '💾 Save Settings',
      'model': '🤖 Language Model',
      'personality': '🎭 Personality',
      'language': '🌐 Language',
      'modelValue': 'Groq (Fast & Free)',
      'personalityValue': 'Friendly & Professional',
      'languageValue': 'English',
      'error': '❌ Connection error',
    },
  };

  String t(String key) => _texts[_language]?[key] ?? key;

  static const String apiUrl = 'https://myassistant-backend-production.up.railway.app';

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'content': message});
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': message, 'language': _language}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _messages.add({'role': 'assistant', 'content': data['reply']});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({'role': 'assistant', 'content': t('error')});
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadTasks() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/tasks'));
      final data = jsonDecode(response.body);
      setState(() {
        _tasks = List<Map<String, dynamic>>.from(data['tasks']);
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _addTask() async {
    final title = _taskController.text.trim();
    if (title.isEmpty) return;
    _taskController.clear();
    try {
      await http.post(
        Uri.parse('$apiUrl/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title}),
      );
      _loadTasks();
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _completeTask(String id) async {
    try {
      await http.put(Uri.parse('$apiUrl/tasks/$id/complete'));
      _loadTasks();
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _deleteTask(String id) async {
    try {
      await http.delete(Uri.parse('$apiUrl/tasks/$id'));
      _loadTasks();
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = _language == 'he';
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text(
            t('appTitle'),
            style: const TextStyle(color: Color(0xFF7C6AF7), fontWeight: FontWeight.bold),
          ),
          actions: [
            GestureDetector(
              onTap: () => setState(() {
                _language = _language == 'he' ? 'en' : 'he';
              }),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A4A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _language == 'he' ? 'EN' : 'עב',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 16),
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: const Color(0xFF1A1A2E),
              child: Row(
                children: [
                  _buildTab(t('chat'), 0),
                  _buildTab(t('tasks'), 1),
                  _buildTab(t('settings'), 2),
                ],
              ),
            ),
            Expanded(
              child: _currentTab == 0
                  ? _buildChat()
                  : _currentTab == 1
                      ? _buildTasks()
                      : _buildSettings(),
            ),
            if (_currentTab == 0) _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _currentTab == index;
    return GestureDetector(
      onTap: () {
        setState(() => _currentTab = index);
        if (index == 1) _loadTasks();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF7C6AF7) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildChat() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return _buildTypingIndicator();
        final message = _messages[index];
        final isUser = message['role'] == 'user';
        return _buildMessage(message['content']!, isUser);
      },
    );
  }

  Widget _buildMessage(String content, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(colors: [Color(0xFF7C6AF7), Color(0xFF9B8BFF)])
              : const LinearGradient(colors: [Color(0xFF1E1E3A), Color(0xFF252545)]),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 4 : 16),
            bottomRight: Radius.circular(isUser ? 16 : 4),
          ),
          boxShadow: [
            BoxShadow(
              color: isUser
                  ? const Color(0xFF7C6AF7).withOpacity(0.3)
                  : Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          content,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E3A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [_dot(), const SizedBox(width: 4), _dot(), const SizedBox(width: 4), _dot()],
        ),
      ),
    );
  }

  Widget _dot() {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: Color(0xFF7C6AF7), shape: BoxShape.circle),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1A1A2E),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: t('inputHint'),
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF0F0F1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF7C6AF7), Color(0xFF9B8BFF)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasks() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taskController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: t('newTask'),
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1E1E3A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _addTask(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addTask,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C6AF7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _tasks.length,
            itemBuilder: (context, index) {
              final task = _tasks[index];
              final completed = task['completed'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E3A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2A4A)),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _completeTask(task['id'].toString()),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: completed ? const Color(0xFF7C6AF7) : Colors.transparent,
                          border: Border.all(color: const Color(0xFF7C6AF7), width: 2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: completed
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        task['title'].toString(),
                        style: TextStyle(
                          color: completed ? Colors.grey : Colors.white,
                          fontSize: 15,
                          decoration: completed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _deleteTask(task['id'].toString()),
                      child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _settingsCard(t('model'), t('modelValue'), Icons.psychology),
          const SizedBox(height: 12),
          _settingsCard(t('personality'), t('personalityValue'), Icons.face),
          const SizedBox(height: 12),
          _settingsCard(t('language'), t('languageValue'), Icons.language),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C6AF7),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                t('saveSettings'),
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E3A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF7C6AF7), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Color(0xFF7C6AF7), fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}