import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'main.dart' show JC;

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
  late TextEditingController _localServerUrlCtrl;

  @override
  void initState() {
    super.initState();
    _s = AppSettings(
      assistantName:  widget.settings.assistantName,
      gender:         widget.settings.gender,
      personality:    widget.settings.personality,
      voiceEnabled:   widget.settings.voiceEnabled,
      userName:       widget.settings.userName,
      useLocalModel:  widget.settings.useLocalModel,
      useLocalServer: widget.settings.useLocalServer,
      localServerUrl: widget.settings.localServerUrl,
    );
    _assistantNameCtrl  = TextEditingController(text: _s.assistantName);
    _userNameCtrl       = TextEditingController(text: _s.userName);
    _localServerUrlCtrl = TextEditingController(text: _s.localServerUrl);
  }

  @override
  void dispose() {
    _assistantNameCtrl.dispose();
    _userNameCtrl.dispose();
    _localServerUrlCtrl.dispose();
    super.dispose();
  }

  void _save() {
    _s.assistantName  = _assistantNameCtrl.text.trim().isEmpty ? 'Jarvis'                    : _assistantNameCtrl.text.trim();
    _s.userName       = _userNameCtrl.text.trim().isEmpty      ? 'נדב'                       : _userNameCtrl.text.trim();
    _s.localServerUrl = _localServerUrlCtrl.text.trim().isEmpty? 'http://192.168.1.100:3000' : _localServerUrlCtrl.text.trim();
    widget.onSave(_s);
    Navigator.pop(context);
  }

  // ─── UI helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
    child: Row(
      children: [
        Icon(icon, size: 13, color: JC.blue400),
        const SizedBox(width: 7),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: JC.blue400,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontFamily: 'Heebo',
          ),
        ),
      ],
    ),
  );

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    decoration: BoxDecoration(
      color: JC.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: JC.border.withOpacity(0.7), width: 0.8),
    ),
    child: Column(children: children),
  );

  Widget _divider() => Divider(
    color: JC.border.withOpacity(0.5),
    height: 1,
    indent: 16,
    endIndent: 16,
  );

  Widget _rowField({
    required String label,
    required IconData icon,
    required TextEditingController ctrl,
    required String hint,
    TextDirection textDir = TextDirection.ltr,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: JC.textMuted),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    color: JC.textPrimary,
                    fontSize: 15,
                    fontFamily: 'Heebo')),
            const Spacer(),
            SizedBox(
              width: 150,
              child: TextField(
                controller: ctrl,
                textAlign: TextAlign.end,
                textDirection: textDir,
                style: const TextStyle(
                    color: JC.textSecondary,
                    fontSize: 14,
                    fontFamily: 'Heebo'),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: TextStyle(color: JC.textMuted.withOpacity(0.6)),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _rowDropdown<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: JC.textMuted),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    color: JC.textPrimary,
                    fontSize: 15,
                    fontFamily: 'Heebo')),
            const Spacer(),
            DropdownButton<T>(
              value: value,
              dropdownColor: JC.surface,
              underline: const SizedBox(),
              icon: Icon(Icons.expand_more_rounded,
                  color: JC.textMuted, size: 18),
              style: const TextStyle(
                  color: JC.textSecondary,
                  fontSize: 14,
                  fontFamily: 'Heebo'),
              items: items,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  Widget _rowSwitch({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool value,
    required void Function(bool) onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: JC.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: JC.textPrimary,
                          fontSize: 15,
                          fontFamily: 'Heebo')),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: JC.textMuted,
                          fontSize: 12,
                          fontFamily: 'Heebo')),
                ],
              ),
            ),
            Switch(
              value: value,
              activeColor: Colors.white,
              activeTrackColor: JC.blue500,
              inactiveThumbColor: JC.textMuted,
              inactiveTrackColor: JC.border,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final initials = _s.userName.isNotEmpty
        ? _s.userName[0].toUpperCase()
        : 'J';

    return Scaffold(
      backgroundColor: JC.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: JC.textSecondary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'הגדרות',
          style: TextStyle(
            color: JC.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 17,
            fontFamily: 'Heebo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'שמור',
              style: TextStyle(
                color: JC.blue400,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                fontFamily: 'Heebo',
              ),
            ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 100),

            // ── Profile card ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      JC.blue500.withOpacity(0.15),
                      JC.surfaceAlt,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: JC.blue500.withOpacity(0.3), width: 0.8),
                ),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [JC.blue400, JC.blue500],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: JC.blue500.withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Heebo',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _s.userName,
                            style: const TextStyle(
                              color: JC.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Heebo',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF22C55E),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF22C55E)
                                          .withOpacity(0.5),
                                      blurRadius: 4,
                                    )
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_s.assistantName} פעיל',
                                style: const TextStyle(
                                  color: JC.textSecondary,
                                  fontSize: 13,
                                  fontFamily: 'Heebo',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── עוזר אישי ────────────────────────────────────────────────────
            _sectionHeader('עוזר אישי', Icons.smart_toy_outlined),
            _card([
              _rowField(
                label: 'שם העוזר',
                icon: Icons.badge_outlined,
                ctrl: _assistantNameCtrl,
                hint: 'Jarvis',
              ),
              _divider(),
              _rowDropdown<String>(
                label: 'מגדר',
                icon: Icons.person_outline_rounded,
                value: _s.gender,
                items: const [
                  DropdownMenuItem(value: 'male',   child: Text('זכר')),
                  DropdownMenuItem(value: 'female', child: Text('נקבה')),
                ],
                onChanged: (val) => setState(() => _s.gender = val!),
              ),
              _divider(),
              _rowDropdown<String>(
                label: 'אופי',
                icon: Icons.psychology_outlined,
                value: _s.personality,
                items: const [
                  DropdownMenuItem(value: 'friendly',  child: Text('ידידותי')),
                  DropdownMenuItem(value: 'formal',    child: Text('רשמי')),
                  DropdownMenuItem(value: 'concise',   child: Text('קצר ולעניין')),
                  DropdownMenuItem(value: 'humorous',  child: Text('הומוריסטי')),
                ],
                onChanged: (val) => setState(() => _s.personality = val!),
              ),
            ]),

            // ── פרופיל ───────────────────────────────────────────────────────
            _sectionHeader('פרופיל', Icons.person_outline_rounded),
            _card([
              _rowField(
                label: 'השם שלך',
                icon: Icons.account_circle_outlined,
                ctrl: _userNameCtrl,
                hint: 'נדב',
                textDir: TextDirection.rtl,
              ),
            ]),

            // ── קול ──────────────────────────────────────────────────────────
            _sectionHeader('קול', Icons.volume_up_outlined),
            _card([
              _rowSwitch(
                label: 'הפעלת קול',
                subtitle: '${_s.assistantName} יקרא את התשובות בקול',
                icon: Icons.record_voice_over_outlined,
                value: _s.voiceEnabled,
                onChanged: (val) => setState(() => _s.voiceEnabled = val),
              ),
            ]),

            // ── שרת ──────────────────────────────────────────────────────────
            _sectionHeader('שרת', Icons.dns_outlined),
            _card([
              _rowSwitch(
                label: 'שרת מקומי',
                subtitle: _s.useLocalServer
                    ? _s.localServerUrl
                    : 'Render Cloud (${AppSettings.cloudServerUrl.replaceFirst('https://', '')})',
                icon: Icons.router_outlined,
                value: _s.useLocalServer,
                onChanged: (val) => setState(() => _s.useLocalServer = val),
              ),
              if (_s.useLocalServer) ...[
                _divider(),
                _rowField(
                  label: 'כתובת IP',
                  icon: Icons.lan_outlined,
                  ctrl: _localServerUrlCtrl,
                  hint: 'http://192.168.1.x:3000',
                ),
              ],
            ]),

            // ── מודל AI ──────────────────────────────────────────────────────
            _sectionHeader('מודל AI', Icons.memory_outlined),
            _card([
              _rowSwitch(
                label: 'מודל מקומי (Ollama)',
                subtitle: _s.useLocalModel
                    ? 'Ollama על השרת המקומי'
                    : 'Groq → DeepSeek → Gemini',
                icon: Icons.precision_manufacturing_outlined,
                value: _s.useLocalModel,
                onChanged: (val) => setState(() => _s.useLocalModel = val),
              ),
            ]),

            const SizedBox(height: 32),

            // ── Save button ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [JC.blue400, JC.blue500],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: JC.blue500.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'שמור שינויים',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}
