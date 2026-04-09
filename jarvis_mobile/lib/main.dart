import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';

void main() => runApp(const JarvisApp());

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jarvis Mobile',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2D2D2D),
          elevation: 0,
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

enum JarvisState { idle, listening, thinking, speaking }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  late stt.SpeechToText _speech;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();
  
  JarvisState _currentState = JarvisState.idle;
  String _listeningText = "";
  
  File? _selectedImage;
  String? _base64Image;

  String _getCurrentTime() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  late List<Map<String, String>> messages = [
    {"sender": "jarvis", "text": "מערכת הראייה מחוברת. אני מוכן לסרוק תמונות, נדב.", "time": _getCurrentTime()}
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _currentState = JarvisState.idle;
        });
      }
    });
  }

  List<Color> _getOrbColors() {
    switch (_currentState) {
      case JarvisState.listening:
        return [Colors.redAccent, Colors.red[900]!];
      case JarvisState.thinking:
        return [Colors.purpleAccent, Colors.deepPurple[900]!];
      case JarvisState.speaking:
        return [Colors.greenAccent, Colors.teal[900]!];
      case JarvisState.idle:
      default:
        return [Colors.blueAccent, Colors.blue[900]!];
    }
  }

  Future<void> _playAudio(String base64String) async {
    try {
      setState(() => _currentState = JarvisState.speaking);
      await _audioPlayer.play(BytesSource(base64Decode(base64String)));
    } catch (e) {
      print("❌ שגיאה בניגון אודיו: $e");
      setState(() => _currentState = JarvisState.idle);
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image != null) {
      final bytes = await File(image.path).readAsBytes();
      setState(() {
        _selectedImage = File(image.path);
        _base64Image = base64Encode(bytes);
      });
    }
  }

  void _listen() async {
    if (_currentState != JarvisState.listening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'notListening' || val == 'done') {
            setState(() => _currentState = JarvisState.idle);
          }
        },
      );
      if (available) {
        setState(() {
          _currentState = JarvisState.listening;
          _listeningText = "מקשיב לך...";
        });
        _speech.listen(
          onResult: (val) {
            if (_currentState == JarvisState.listening) {
              setState(() {
                _controller.text = val.recognizedWords;
                _listeningText = val.recognizedWords;
              });
            }
          },
          localeId: 'he_IL',
        );
      }
    } else {
      setState(() {
        _currentState = JarvisState.idle;
        _listeningText = "";
      });
      _speech.stop();
    }
  }

  Future<void> sendCommand(String text) async {
    if (text.trim().isEmpty && _base64Image == null) return;

    _speech.stop();

    setState(() {
      String displayMsg = text;
      if (_selectedImage != null) displayMsg += " [תמונה מצורפת]";
      messages.add({"sender": "user", "text": displayMsg, "time": _getCurrentTime()});
      _currentState = JarvisState.thinking;
      _listeningText = "";
    });
    
    _scrollToBottom();
    _controller.clear();
    
    String? imageToSend = _base64Image;
    setState(() {
      _selectedImage = null;
      _base64Image = null;
    });

    // 🛑 החלף את הכתובת כאן לכתובת ה-Render שלך! 🛑
    final url = Uri.parse('https://jarvis-server-nadav.onrender.com/ask-jarvis'); 
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'command': text,
          'image': imageToSend
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String answer = data['answer'];
        String? audioBase64 = data['audio'];

        setState(() {
          messages.add({"sender": "jarvis", "text": answer, "time": _getCurrentTime()});
        });
        
        if (audioBase64 != null && audioBase64.isNotEmpty) {
          _playAudio(audioBase64);
        } else {
          setState(() => _currentState = JarvisState.idle);
        }
      } else {
        // התיקון: אם השרת מחזיר שגיאה (כמו 413 Payload Too Large), עוצרים את העיבוד!
        setState(() {
          messages.add({"sender": "jarvis", "text": "שגיאה מהשרת: קוד ${response.statusCode}", "time": _getCurrentTime()});
          _currentState = JarvisState.idle;
        });
      }
    } catch (e) {
      setState(() {
        messages.add({"sender": "jarvis", "text": "תקלה בתקשורת עם השרת: $e", "time": _getCurrentTime()});
        _currentState = JarvisState.idle;
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

  @override
  Widget build(BuildContext context) {
    bool isListeningMode = _currentState == JarvisState.listening;
    int itemCount = messages.length + (_currentState == JarvisState.thinking ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text('J.A.R.V.I.S', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: _currentState == JarvisState.thinking ? 90 : 80,
              height: _currentState == JarvisState.thinking ? 90 : 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: _getOrbColors()),
                boxShadow: [
                  BoxShadow(
                    color: _getOrbColors()[0].withOpacity(0.6),
                    blurRadius: _currentState == JarvisState.listening ? 30 : 15,
                    spreadRadius: _currentState == JarvisState.speaking ? 10 : 2,
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(15),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index == messages.length && _currentState == JarvisState.thinking) {
                   return Align(
                     alignment: Alignment.centerRight,
                     child: Container(
                       margin: const EdgeInsets.only(bottom: 10),
                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                       decoration: const BoxDecoration(
                         color: Color(0xFF2D2D2D),
                         borderRadius: BorderRadius.only(
                           topLeft: Radius.circular(15),
                           topRight: Radius.circular(15),
                           bottomLeft: Radius.circular(15),
                           bottomRight: Radius.circular(0),
                         ),
                       ),
                       child: const Row(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           SizedBox(
                             width: 15,
                             height: 15,
                             child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent),
                           ),
                           SizedBox(width: 10),
                           Text("מנתח מידע...", style: TextStyle(color: Colors.grey, fontSize: 14)),
                         ],
                       ),
                     ),
                   );
                }

                final msg = messages[index];
                final isUser = msg['sender'] == 'user';
                
                return Align(
                  alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blueGrey[800] : const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(15),
                        topRight: const Radius.circular(15),
                        bottomLeft: Radius.circular(isUser ? 0 : 15),
                        bottomRight: Radius.circular(isUser ? 15 : 0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['text']!,
                          style: const TextStyle(fontSize: 16, color: Colors.white),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          msg['time'] ?? '',
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
            
          if (isListeningMode)
             Padding(
               padding: const EdgeInsets.all(8.0),
               child: Text(_listeningText, style: const TextStyle(color: Colors.redAccent, fontStyle: FontStyle.italic)),
             ),

          if (_selectedImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(
                            image: FileImage(_selectedImage!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedImage = null;
                            _base64Image = null;
                          });
                        },
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      )
                    ],
                  ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image),
                  color: Colors.grey,
                  onPressed: _pickImage,
                ),
                IconButton(
                  icon: Icon(isListeningMode ? Icons.mic : Icons.mic_none),
                  color: isListeningMode ? Colors.redAccent : Colors.grey,
                  onPressed: _listen,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'מה תרצה שאעשה?',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 15),
                    ),
                    onSubmitted: (value) => sendCommand(value),
                  ),
                ),
                CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () => sendCommand(_controller.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}