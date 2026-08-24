import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FincoreGo/AssistantChat.dart';

void main() {
  testWidgets(
    'Contact Support Team card shows a Contact Number field',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const MaterialApp(home: AssistantChat()),
      );
      await tester.pumpAndSettle();

      // The "talk to a human agent" phrasing is caught by the deterministic
      // human-support trigger, which shows the support card directly with
      // no network call - ideal for testing the form itself in isolation.
      await tester.enterText(
        find.byType(TextField).first,
        'I want to talk to a human agent',
      );
      await tester.pump();

      // Tap the round send button (an ArrowUpward icon inside a
      // GestureDetector, per the input bar implementation).
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Contact Support Team'), findsOneWidget);
      expect(find.text('Contact Number'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);

      // Confirm the Contact Number field is an editable, empty phone-keyboard
      // TextField (not prefilled, unlike Name/Email).
      final phoneTextField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Your phone number (optional)',
      );
      expect(phoneTextField, findsOneWidget);
      final textFieldWidget = tester.widget<TextField>(phoneTextField);
      expect(textFieldWidget.controller?.text ?? '', isEmpty);
      expect(textFieldWidget.enabled, isTrue);
      expect(textFieldWidget.keyboardType, TextInputType.phone);
    },
  );
}
