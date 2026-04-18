import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JC;
import '../main_shell.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breathCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _breath;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat(reverse: true);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _breath = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool('onboarded') ?? false;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            onboarded ? const MainShell() : const OnboardingScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Orb
              AnimatedBuilder(
                animation: _breath,
                builder: (_, __) => Transform.scale(
                  scale: _breath.value,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 148,
                        height: 148,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: JC.blue500.withOpacity(0.06),
                        ),
                      ),
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: JC.blue500.withOpacity(0.12),
                        ),
                      ),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [JC.blue400, Color(0xFF1E3A8A)],
                            center: Alignment(-0.25, -0.3),
                            radius: 0.85,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: JC.blue500.withOpacity(0.55),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: JC.blue500.withOpacity(0.2),
                              blurRadius: 60,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                'Jarvis',
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo',
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'העוזר האישי שלך',
                style: TextStyle(
                  color: JC.textMuted,
                  fontSize: 14,
                  fontFamily: 'Heebo',
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
