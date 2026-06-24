import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Mini-Orb FAB calls onSwitchToVoice when tapped', (tester) async {
    bool switched = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              bottom: 70, left: 14,
              child: GestureDetector(
                key: const Key('mini_orb_fab'),
                onTap: () => switched = true,
                child: const SizedBox(width: 42, height: 42),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('mini_orb_fab')));
    await tester.pump();
    expect(switched, isTrue);
  });
}
