// A finished turn raises the in-app call only while the global switch is on.

import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/incoming_call_bridge.dart';
import 'package:dsh_app/state/incoming_call_state.dart';
import 'package:dsh_app/state/notify_state.dart' show callChatProvider;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _call = IncomingCall(host: HostRef.local, sessionId: 's1', title: '修复登录按钮');

ProviderContainer _containerWithSwitch(bool? enabled) {
  SharedPreferences.setMockInitialValues(
    enabled == null ? const {} : {'speech_call_v1': '{"incomingCall": $enabled}'},
  );
  return ProviderContainer();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('completion rings by default; answering takes the prompt', () async {
    final container = _containerWithSwitch(null);
    addTearDown(container.dispose);

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(container.read(incomingCallProvider), _call);
    expect(container.read(incomingCallProvider.notifier).accept(), _call);
    expect(container.read(incomingCallProvider), isNull);
  });

  test('switch off: completion does not ring', () async {
    final container = _containerWithSwitch(false);
    addTearDown(container.dispose);

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(container.read(incomingCallProvider), isNull);
  });

  test('hanging up drops the prompt without taking a call', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);

    await container.read(incomingCallProvider.notifier).offer(_call);
    container.read(incomingCallProvider.notifier).dismiss();

    expect(container.read(incomingCallProvider), isNull);
    expect(container.read(incomingCallProvider.notifier).accept(), isNull);
  });

  test('native answer, hangup and timeout come back to the call controller', () async {
    const channel = MethodChannel('dsh/incoming_call');
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final bridge = container.read(incomingCallBridgeProvider);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call);
      // The mock replaces the bridge's handler: stand in for the native page,
      // but never echo Dart's own show/dismiss calls back as signals.
      if (call.method == 'answer' || call.method == 'hangup' || call.method == 'timeout') {
        bridge.onSignal?.call(call.method);
      }
      return null;
    });
    Future<void> native(String method) => messenger.handlePlatformMessage(
          channel.name,
          StandardMethodCodec().encodeMethodCall(MethodCall(method)),
          (_) {},
        );

    final notifier = container.read(incomingCallProvider.notifier);
    final answered = <IncomingCall>[];
    notifier.onNativeAnswer = answered.add;

    await notifier.offer(_call);
    expect(methods.map((c) => c.method), contains('show'));
    await native('answer');
    expect(answered, [_call]);
    expect(container.read(incomingCallProvider), isNull);
    expect(methods.map((c) => c.method), contains('dismiss'));

    await notifier.offer(_call);
    await native('timeout');
    expect(container.read(incomingCallProvider), isNull);

    await notifier.offer(_call);
    await native('hangup');
    expect(container.read(incomingCallProvider), isNull);
  });

  test('new turns queue while a call is up, then ring one at a time', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final notifier = container.read(incomingCallProvider.notifier);
    final live = container.read(callChatProvider.notifier);
    const second = IncomingCall(host: HostRef.local, sessionId: 's2', title: '第二个');
    const third = IncomingCall(host: HostRef.local, sessionId: 's3', title: '第三个');

    await notifier.offer(_call);
    notifier.accept();
    expect(container.read(callChatProvider)?.sessionId, 's1', reason: 'answering claims the call signal at once');
    await notifier.offer(second);
    await notifier.offer(third);
    expect(container.read(incomingCallProvider), isNull, reason: 'a second ring would interrupt the call');

    live.set(null);
    expect(container.read(incomingCallProvider), second);
    notifier.dismiss();
    expect(container.read(incomingCallProvider), third);
    notifier.dismiss();
    expect(container.read(incomingCallProvider), isNull);
  });

  test('the queue is bounded: the oldest waiting turns are dropped', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final notifier = container.read(incomingCallProvider.notifier);
    final live = container.read(callChatProvider.notifier);

    await notifier.offer(_call);
    notifier.accept();
    for (var i = 2; i <= 8; i++) {
      await notifier.offer(IncomingCall(host: HostRef.local, sessionId: 's$i', title: '任务 $i'));
    }
    live.set(null);
    expect(container.read(incomingCallProvider)!.sessionId, 's6');
    notifier.dismiss();
    expect(container.read(incomingCallProvider)!.sessionId, 's7');
    notifier.dismiss();
    expect(container.read(incomingCallProvider)!.sessionId, 's8');
    notifier.dismiss();
    expect(container.read(incomingCallProvider), isNull);
  });

  test('timeout and hangup leave a missed-call note; answering does not', () async {
    const channel = MethodChannel('dsh/notify');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final posts = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'show') posts.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final notifier = container.read(incomingCallProvider.notifier);
    notifier.onNativeAnswer = (_) {};

    await notifier.offer(_call);
    notifier.nativeSignal('timeout');
    expect(posts, hasLength(1));
    final args = posts.single.arguments! as Map<Object?, Object?>;
    expect(args['key'], 'missed-call');
    expect(args['sessionId'], 's1');
    expect(args['host'], HostRef.local.encode());

    await notifier.offer(_call);
    notifier.nativeSignal('hangup');
    expect(posts, hasLength(2));

    await notifier.offer(_call);
    notifier.nativeSignal('answer');
    expect(posts, hasLength(2), reason: 'an answered call is not missed');
  });

  test('an answer before the overlay mounts is handed to it, not dropped', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final notifier = container.read(incomingCallProvider.notifier);
    await notifier.offer(_call);

    notifier.nativeSignal('answer');

    expect(notifier.takePendingAnswer(), _call);
    expect(notifier.takePendingAnswer(), isNull);
  });
}
