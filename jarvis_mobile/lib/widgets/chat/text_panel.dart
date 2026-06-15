import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../services/api_service.dart';
import '../../screens/chat/chat_screen.dart' show ChatMessage;

class TextPanel extends StatefulWidget {
  final List<ChatMessage> messages;
  final AppSettings settings;
  final String chatId;
  final void Function(ChatMessage msg) onNewMessage;

  const TextPanel({
    super.key,
    required this.messages,
    required this.settings,
    required this.chatId,
    required this.onNewMessage,
  });

  @override
  State<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends State<TextPanel>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  late final ApiService _api;

  // Mic animation
  late final AnimationController _micCtrl;
  late final Animation<double> _micScale;
  bool _micRecording = false;
  late final stt.SpeechToText _speech;

  bool _sending = false;
  int _prevCount = 0;

  String? _pendingFileName;
  List<int>? _pendingFileBytes;
  String? _pendingFileType; // 'image' | 'pdf' | 'docx' | 'audio:<ext>'

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.settings);
    _speech = stt.SpeechToText();
    _prevCount = widget.messages.length;

    _micCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _micScale = Tween<double>(begin: 1.0, end: 1.3)
        .animate(CurvedAnimation(parent: _micCtrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(TextPanel old) {
    super.didUpdateWidget(old);
    final newCount = widget.messages.length;
    if (newCount > _prevCount) {
      for (var i = _prevCount; i < newCount; i++) {
        _listKey.currentState?.insertItem(i,
            duration: const Duration(milliseconds: 200));
      }
      _prevCount = newCount;
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    if (_pendingFileBytes != null) { await _sendWithFile(); return; }
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _textCtrl.clear();
    setState(() => _sending = true);

    final userMsg = ChatMessage(
      id: 't-u-${DateTime.now().millisecondsSinceEpoch}',
      sender: 'user',
      text: text,
    );
    widget.onNewMessage(userMsg);

    try {
      // askJarvis signature: (String command, AppSettings settings, {String? intent})
      final result = await _api.askJarvis(text, widget.settings);
      final answer = (result['answer'] as String? ?? '').trim();
      if (answer.isNotEmpty) {
        widget.onNewMessage(ChatMessage(
          id: 't-${DateTime.now().millisecondsSinceEpoch}',
          sender: 'jarvis',
          text: answer,
        ));
      }
    } catch (_) {
      widget.onNewMessage(ChatMessage(
        id: 't-err-${DateTime.now().millisecondsSinceEpoch}',
        sender: 'jarvis',
        text: '⚠️ שגיאת חיבור',
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleMic() async {
    if (_micRecording) {
      await _speech.stop();
      _micCtrl.stop();
      _micCtrl.reset();
      if (mounted) setState(() => _micRecording = false);
      return;
    }
    final available = await _speech.initialize();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('מיקרופון לא זמין')));
      }
      return;
    }
    if (mounted) setState(() => _micRecording = true);
    _micCtrl.repeat(reverse: true);

    _speech.listen(
      onResult: (val) {
        if (!val.finalResult) return;
        final text = val.recognizedWords.trim();
        _micCtrl.stop();
        _micCtrl.reset();
        if (mounted) setState(() => _micRecording = false);
        if (text.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('לא זוהה דיבור')));
          }
          return;
        }
        _textCtrl.text = text;
        _sendText();
      },
      localeId: 'he_IL',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(milliseconds: 2000),
    );
  }

  void _clearPendingFile() {
    setState(() {
      _pendingFileName = null;
      _pendingFileBytes = null;
      _pendingFileType = null;
    });
  }

  Future<void> _showAttachmentSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32, height: 3,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: JC.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.image_rounded, color: JC.blue400),
              title: Text('📷 תמונה', style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: Icon(Icons.description_rounded, color: JC.indigo500),
              title: Text('📄 מסמך (PDF / Word)', style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
              onTap: () => Navigator.pop(context, 'doc'),
            ),
            ListTile(
              leading: Icon(Icons.audiotrack_rounded, color: const Color(0xFF22C55E)),
              title: Text('🎵 אודיו', style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
              onTap: () => Navigator.pop(context, 'audio'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'image') {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _pendingFileName = picked.name;
        _pendingFileBytes = List<int>.from(bytes);
        _pendingFileType = 'image';
      });
    } else if (choice == 'doc') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.first;
      setState(() {
        _pendingFileName = file.name;
        _pendingFileBytes = file.bytes != null ? List<int>.from(file.bytes!) : null;
        _pendingFileType = file.extension?.toLowerCase() == 'docx' ? 'docx' : 'pdf';
      });
    } else if (choice == 'audio') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.first;
      setState(() {
        _pendingFileName = file.name;
        _pendingFileBytes = file.bytes != null ? List<int>.from(file.bytes!) : null;
        _pendingFileType = 'audio:${file.extension ?? 'mp3'}';
      });
    }
  }

  Future<void> _sendWithFile() async {
    final bytes = _pendingFileBytes;
    final fileType = _pendingFileType;
    final fileName = _pendingFileName ?? 'קובץ';
    final caption = _textCtrl.text.trim();
    if (bytes == null || fileType == null) return;
    _textCtrl.clear();
    _clearPendingFile();
    setState(() => _sending = true);

    widget.onNewMessage(ChatMessage(
      id: 't-u-${DateTime.now().millisecondsSinceEpoch}',
      sender: 'user',
      text: caption.isNotEmpty ? caption : '📎 $fileName',
      fileName: fileName,
    ));

    try {
      final command = caption.isNotEmpty ? caption : 'נתח את הקובץ הזה';
      String? answer;

      if (fileType == 'image') {
        final base64 = base64Encode(bytes);
        final result = await _api.askJarvisWithImage(command, base64, widget.settings);
        answer = result['answer'] as String?;
      } else if (fileType.startsWith('audio:')) {
        final format = fileType.split(':').last;
        final transcript = await _api.transcribeAudio(bytes, format);
        if (transcript.isEmpty) throw Exception('לא זוהה תוכן');
        final result = await _api.askJarvis('תמלול: $transcript\n\n$command', widget.settings);
        answer = result['answer'] as String?;
      } else {
        final text = await _api.parseDocument(bytes, fileType);
        final result = await _api.askJarvis('תוכן הקובץ:\n$text\n\n$command', widget.settings);
        answer = result['answer'] as String?;
      }

      if ((answer ?? '').isNotEmpty) {
        widget.onNewMessage(ChatMessage(
          id: 't-${DateTime.now().millisecondsSinceEpoch}',
          sender: 'jarvis',
          text: answer!.trim(),
        ));
      }
    } catch (e) {
      widget.onNewMessage(ChatMessage(
        id: 't-err-${DateTime.now().millisecondsSinceEpoch}',
        sender: 'jarvis',
        text: '⚠️ ${e.toString().replaceFirst('Exception: ', '')}',
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _micCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('text'),
      children: [
        Expanded(
          child: AnimatedList(
            key: _listKey,
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            initialItemCount: widget.messages.length,
            itemBuilder: (context, index, animation) {
              final msg = widget.messages[index];
              return _BubbleEntry(msg: msg, animation: animation);
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: _pendingFileName == null
              ? const SizedBox.shrink()
              : _FilePreviewRow(
                  fileName: _pendingFileName!,
                  onDismiss: _clearPendingFile,
                ),
        ),
        _InputBar(
          controller: _textCtrl,
          micRecording: _micRecording,
          micScale: _micScale,
          sending: _sending,
          onSend: _sendText,
          onMic: _toggleMic,
          onAttach: _showAttachmentSheet,
        ),
      ],
    );
  }
}

// ─── Animated bubble entry ───────────────────────────────────────────────────

class _BubbleEntry extends StatelessWidget {
  final ChatMessage msg;
  final Animation<double> animation;
  const _BubbleEntry({required this.msg, required this.animation});

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: FadeTransition(
        opacity: animation,
        child: _Bubble(msg: msg),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.sender == 'user';
    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Container(
        margin: EdgeInsetsDirectional.only(
          bottom: 10,
          start: isUser ? 0 : 48,
          end: isUser ? 48 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? JC.userBubble : JC.jarvisBubble,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(18),
            topEnd: const Radius.circular(18),
            bottomStart: Radius.circular(isUser ? 6 : 18),
            bottomEnd: Radius.circular(isUser ? 18 : 6),
          ),
          border: Border.all(
            color: isUser
                ? JC.blue400.withValues(alpha: 0.4)
                : JC.border.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.fromVoice)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: Text(
                  '🎤',
                  style: TextStyle(fontSize: 10, color: JC.indigo500),
                ),
              ),
            Text(
              msg.text,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: JC.textPrimary,
                fontSize: 14.5,
                height: 1.55,
                fontFamily: 'Heebo',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Input bar ───────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool micRecording;
  final Animation<double> micScale;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onAttach;

  const _InputBar({
    required this.controller,
    required this.micRecording,
    required this.micScale,
    required this.sending,
    required this.onSend,
    required this.onMic,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
      decoration: BoxDecoration(
        color: JC.bg,
        border: Border(top: BorderSide(color: JC.border, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onAttach,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.attach_file_rounded, size: 22, color: JC.textSecondary),
            ),
          ),
          const SizedBox(width: 4),
          ScaleTransition(
            scale: micScale,
            child: GestureDetector(
              onTap: onMic,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: micRecording
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: micRecording
                        ? Colors.red.withValues(alpha: 0.6)
                        : JC.border,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 18,
                  color: micRecording ? Colors.red : JC.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textDirection: TextDirection.rtl,
              onSubmitted: (_) => onSend(),
              style: TextStyle(color: JC.textPrimary, fontSize: 14, fontFamily: 'Heebo'),
              decoration: InputDecoration(
                hintText: 'כתוב הודעה...',
                hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                filled: true,
                fillColor: JC.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sending ? JC.border : JC.indigo500,
              ),
              child: sending
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: JC.textPrimary),
                    )
                  : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── File preview row ────────────────────────────────────────────────────────

class _FilePreviewRow extends StatelessWidget {
  final String fileName;
  final VoidCallback onDismiss;
  const _FilePreviewRow({required this.fileName, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.indigo500.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.attach_file_rounded, size: 16, color: JC.indigo500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
              style: TextStyle(color: JC.textSecondary, fontSize: 12, fontFamily: 'Heebo'),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded, size: 16, color: JC.textMuted),
          ),
        ],
      ),
    );
  }
}
