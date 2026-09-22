import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_into_app_desktop/main.dart';

void main() {
  testWidgets('App boots to generator screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const WebIntoAppDesktop());
    await tester.pump();
    expect(find.text('Web Into App'), findsOneWidget);
    expect(find.text('Generate APK'), findsOneWidget);
  });
}
