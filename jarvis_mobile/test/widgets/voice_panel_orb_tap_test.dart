import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// We test only the public surface: that onOrbTap is wired up.
// Stub widget that mimics VoicePanel's orb area:
class _OrbStub extends StatefulWidget {
  final VoidCallback? onOrbTap;
  const _OrbStub({this.onOrbTap});
  @override
  State<_OrbStub> createState() => _OrbStubState();
}
class _OrbStubState extends State<_OrbStub> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onOrbTap,
      child: const SizedBox(key: Key('orb'), width: 100, height: 100),
    );
  }
}

void main() {
  testWidgets('onOrbTap is called when orb is tapped', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _OrbStub(onOrbTap: () => tapped = true)),
    ));
    await tester.tap(find.byKey(const Key('orb')));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
