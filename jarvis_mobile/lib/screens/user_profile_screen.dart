import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../main.dart' show JC;
import '../services/api_service.dart';

class UserProfileScreen extends StatefulWidget {
  final AppSettings settings;
  const UserProfileScreen({super.key, required this.settings});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _toneCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _interestsCtrl = TextEditingController();
  final _tasksCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  ApiService get _api => ApiService(widget.settings);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _api.getUserProfile();
      if (!mounted) return;
      _toneCtrl.text = (profile?['speaking_tone'] ?? 'friendly').toString();
      _hoursCtrl.text =
          ((profile?['preferred_hours'] as List?) ?? []).join(', ');
      _interestsCtrl.text = ((profile?['interests'] as List?) ?? []).join(', ');
      _tasksCtrl.text =
          ((profile?['recurring_tasks'] as List?) ?? []).join(', ');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _split(String v) => v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('מה למדנו עליך')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(children: [
          TextField(controller: _toneCtrl, decoration: const InputDecoration(labelText: 'טון דיבור')),
          TextField(controller: _hoursCtrl, decoration: const InputDecoration(labelText: 'שעות מועדפות (מופרד בפסיקים)')),
          TextField(controller: _interestsCtrl, decoration: const InputDecoration(labelText: 'תחומי עניין (מופרד בפסיקים)')),
          TextField(controller: _tasksCtrl, decoration: const InputDecoration(labelText: 'משימות חוזרות (מופרד בפסיקים)')),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              setState(() => _saving = true);
              try {
                await _api.saveUserProfile(
                  speakingTone: _toneCtrl.text.trim().isEmpty
                      ? 'friendly'
                      : _toneCtrl.text.trim(),
                  preferredHours: _split(_hoursCtrl.text),
                  interests: _split(_interestsCtrl.text),
                  recurringTasks: _split(_tasksCtrl.text),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('נשמר בהצלחה')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ApiService.friendlyError(e))),
                );
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
            child: Text(_saving ? 'שומר...' : 'שמור'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              try {
                await _api.deleteUserProfile();
                if (!mounted) return;
                _toneCtrl.text = 'friendly';
                _hoursCtrl.clear();
                _interestsCtrl.clear();
                _tasksCtrl.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('הפרופיל נמחק')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ApiService.friendlyError(e))),
                );
              }
            },
            style: OutlinedButton.styleFrom(foregroundColor: JC.cancelRed),
            child: const Text('מחק פרופיל'),
          ),
        ]),
      ),
    );
  }
}
