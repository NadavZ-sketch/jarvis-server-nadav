import 'package:flutter/material.dart';
import 'app_settings.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final Function(AppSettings) onSave;

  const SettingsScreen({super.key, required this.settings, required this.onSave});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _s;
  late TextEditingController _assistantNameCtrl;
  late TextEditingController _userNameCtrl;

  @override
  void initState() {
    super.initState();
    _s = AppSettings(
      assistantName: widget.settings.assistantName,
      gender:        widget.settings.gender,
      personality:   widget.settings.personality,
      voiceEnabled:  widget.settings.voiceEnabled,
      userName:      widget.settings.userName,
    );
    _assistantNameCtrl = TextEditingController(text: _s.assistantName);
    _userNameCtrl      = TextEditingController(text: _s.userName);
  }

  @override
  void dispose() {
    _assistantNameCtrl.dispose();
    _userNameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    _s.assistantName = _assistantNameCtrl.text.trim().isEmpty ? 'Jarvis' : _assistantNameCtrl.text.trim();
    _s.userName      = _userNameCtrl.text.trim().isEmpty      ? 'נדב'   : _userNameCtrl.text.trim();
    widget.onSave(_s);
    Navigator.pop(context);
  }

  // ─── UI helpers ────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
    child: Text(
      title,
      style: const TextStyle(
        color: Color(0xFF6E6E6E),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
      ),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1C),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(children: children),
  );

  Widget _divider() => const Divider(color: Color(0xFF2A2A2A), height: 1, indent: 16);

  Widget _rowField(String label, TextEditingController ctrl, String hint) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
        const Spacer(),
        SizedBox(
          width: 140,
          child: TextField(
            controller: ctrl,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 15),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF444444)),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _rowDropdown<T>(String label, T value, List<DropdownMenuItem<T>> items, void Function(T?) onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
            const Spacer(),
            DropdownButton<T>(
              value: value,
              dropdownColor: const Color(0xFF2A2A2A),
              underline: const SizedBox(),
              style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 15),
              items: items,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'הגדרות',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('שמור', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── עוזר אישי ──────────────────────────────────────────────────
            _sectionHeader('עוזר אישי'),
            _card([
              _rowField('שם העוזר', _assistantNameCtrl, 'Jarvis'),
              _divider(),
              _rowDropdown<String>(
                'מגדר', _s.gender,
                const [
                  DropdownMenuItem(value: 'male',   child: Text('זכר')),
                  DropdownMenuItem(value: 'female', child: Text('נקבה')),
                ],
                (val) => setState(() => _s.gender = val!),
              ),
              _divider(),
              _rowDropdown<String>(
                'אופי', _s.personality,
                const [
                  DropdownMenuItem(value: 'friendly',  child: Text('ידידותי')),
                  DropdownMenuItem(value: 'formal',    child: Text('רשמי')),
                  DropdownMenuItem(value: 'concise',   child: Text('קצר ולעניין')),
                  DropdownMenuItem(value: 'humorous',  child: Text('הומוריסטי')),
                ],
                (val) => setState(() => _s.personality = val!),
              ),
            ]),

            // ── קול ────────────────────────────────────────────────────────
            _sectionHeader('קול'),
            _card([
              SwitchListTile(
                title: const Text('הפעלת קול', style: TextStyle(color: Colors.white, fontSize: 15)),
                subtitle: const Text('ג\'רביס יקרא את התשובות', style: TextStyle(color: Color(0xFF6E6E6E), fontSize: 12)),
                value: _s.voiceEnabled,
                activeColor: Colors.white,
                activeTrackColor: const Color(0xFF4A4A4A),
                inactiveThumbColor: const Color(0xFF5A5A5A),
                inactiveTrackColor: const Color(0xFF2A2A2A),
                onChanged: (val) => setState(() => _s.voiceEnabled = val),
              ),
            ]),

            // ── פרופיל ─────────────────────────────────────────────────────
            _sectionHeader('פרופיל'),
            _card([
              _rowField('השם שלך', _userNameCtrl, 'נדב'),
            ]),

            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}
