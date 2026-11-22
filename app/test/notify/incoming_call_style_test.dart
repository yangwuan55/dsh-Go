// The in-app ring speaks the voice call page's visual language: the same field,
// orb, status line, frosted title and keys, not a separate dialog.

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/incoming_call_state.dart';
import 'package:dsh_app/state/notify_state.dart' show appForegroundProvider;
import 'package:dsh_app/ui/notify/incoming_call_host.dart';
import 'package:dsh_app/ui/speech/call/call_parts.dart';
import 'package:dsh_app/ui/speech/call/call_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the in-app ring is dressed like a voice call', (tester) async {
    const channel = MethodChannel('dsh/incoming_call');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const notifyChannel = MethodChannel('dsh/notify');
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    messenger.setMockMethodCallHandler(notifyChannel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(() => messenger.setMockMethodCallHandler(notifyChannel, null));
    SharedPreferences.setMockInitialValues(const {'speech_call_v1': '{"incomingCall": true}'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appForegroundProvider.notifier).set(false);
    await container.read(incomingCallProvider.notifier).offer(
      const IncomingCall(host: HostRef.local, sessionId: 's1', title: '修复登录按钮'),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IncomingCallHost()),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CallField), findsOneWidget, reason: 'the ring sits on the voice call field');
    expect(find.byType(CallLight), findsOneWidget, reason: 'the ring shows the voice call orb');
    expect(find.byType(CallEdgeGlow), findsOneWidget);
    expect(find.byType(CallStatus), findsOneWidget);
    expect(find.byType(CallFrosted), findsWidgets, reason: 'the title wears the call page frosted glass');
    expect(find.byType(CallKey), findsOneWidget);
    expect(find.byType(HangUpKey), findsOneWidget);
    expect(find.text('修复登录按钮'), findsOneWidget);
    expect(find.bySemanticsLabel(appL10n.speechCallHangUp), findsOneWidget);
    expect(find.bySemanticsLabel(appL10n.commonConfirm), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('call-hang-up')));
    await tester.pump();
    expect(container.read(incomingCallProvider), isNull, reason: 'the restyled hang-up key still drops the prompt');
  });
}
