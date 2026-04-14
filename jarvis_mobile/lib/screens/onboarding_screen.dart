import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JC, MainShell;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardPage(
      emoji: '👋',
      title: 'ברוך הבא לג׳רביס',
      subtitle: 'העוזר האישי שלך — חכם, מהיר, ומדבר עברית.',
    ),
    _OnboardPage(
      emoji: '🎙️',
      title: 'דבר איתי',
      subtitle: 'שאל בקול או בכתב.\nאני מבין שאלות בעברית טבעית.',
    ),
    _OnboardPage(
      emoji: '✅',
      title: 'משימות ותזכורות',
      subtitle: 'נהל משימות, תזכורות, אנשי קשר\nורשימות קניות — הכל במקום אחד.',
    ),
    _OnboardPage(
      emoji: '🌤️',
      title: 'מחובר לעולם',
      subtitle: 'מזג אוויר עדכני, חדשות, ספורט —\nהכל עם חיפוש חי.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainShell(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: JC.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: _finish,
                child: const Text(
                  'דלג',
                  style: TextStyle(
                      color: JC.textMuted, fontFamily: 'Heebo', fontSize: 14),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _pages[i],
              ),
            ),

            // Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _page == i ? JC.blue400 : JC.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Action button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: JC.blue500,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: isLast
                      ? _finish
                      : () => _pageCtrl.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOut,
                          ),
                  child: Text(
                    isLast ? 'בוא נתחיל!' : 'הבא',
                    style: const TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;

  const _OnboardPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji orb
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: JC.blue500.withOpacity(0.15),
              border: Border.all(color: JC.blue500.withOpacity(0.3), width: 1.5),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 44)),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: JC.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFamily: 'Heebo',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: JC.textSecondary,
              fontSize: 15,
              height: 1.65,
              fontFamily: 'Heebo',
            ),
          ),
        ],
      ),
    );
  }
}
