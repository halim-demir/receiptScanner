import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:receiptscanner/main.dart';

void main() {
  testWidgets('App launches and shows the camera tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ReceiptScannerApp());
    await tester.pumpAndSettle();

    // The camera screen header shows "KAMERA".
    expect(find.text('KAMERA'), findsOneWidget);

    // Bottom nav shows both tabs.
    expect(find.text('Kamera'), findsWidgets);
    expect(find.text('Galeri'), findsWidgets);
  });
}
