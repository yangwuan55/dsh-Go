// A finished turn raises the in-app call only while the call reminder switch is on.

import 'dart:convert';

import 'package:dsh_app/speech/speech_settings.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/incoming_call_bridge.dart';
import 'package:dsh_app/state/incoming_call_state.dart';
import 'package:dsh_app/state/notify_state.dart' show appForegroundProvider, callChatProvider;
import 'package:dsh_app/ui/notify/chat_alert_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _call = IncomingCall(host: HostRef.local, sessionId: 's1', title: '修复登录按钮');

ProviderContainer _containerWithSwitch(bool? enabled) =>
    _containerWithSettings(enabled == null ? const {} : {'autoAnswer': enabled});

ProviderContainer _containerWithSettings(Map<String, Object> saved) {
  SharedPreferences.setMockInitialValues({'speech_call_v1': jsonEncode(saved)});
  final container = ProviderContainer();
  // These tests describe turns that arrive while the app is in the background.
  container.read(appForegroundProvider.notifier).set(false);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), null));

  test('completion rings by default; answering takes the prompt', () async {
    final container = _containerWithSwitch(null);
    addTearDown(container.dispose);

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(container.read(incomingCallProvider), _call);
    expect(container.read(incomingCallProvider.notifier).accept(), _call);
    expect(container.read(incomingCallProvider), isNull);
  });

  test('a foreground turn is left to the notification, with no native call', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      return null;
    });
    container.read(appForegroundProvider.notifier).set(true);

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(container.read(incomingCallProvider), isNull);
    expect(methods.where((m) => m != 'prepare'), isEmpty,
        reason: 'the foreground turn must not raise a telecom call');
  });

  test('queued turns still ring one at a time after returning to the foreground', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      return null;
    });
    final notifier = container.read(incomingCallProvider.notifier);
    await notifier.offer(_call);
    await notifier.offer(const IncomingCall(host: HostRef.local, sessionId: 's2', title: '下一个任务'));
    await notifier.offer(const IncomingCall(host: HostRef.local, sessionId: 's3', title: '再下一个任务'));
    notifier.accept();
    methods.clear();
    container.read(appForegroundProvider.notifier).set(true);

    container.read(callChatProvider.notifier).set(null);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(incomingCallProvider)?.sessionId, 's2');
    expect(methods, contains('show'), reason: 'a queued turn is still put to the person after the call ends');
    notifier.dismiss();
    expect(container.read(incomingCallProvider)?.sessionId, 's3');
    notifier.dismiss();
    expect(container.read(incomingCallProvider), isNull);
  });

  test('the telecom call ends when the voice call page closes', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      return null;
    });
    final notifier = container.read(incomingCallProvider.notifier);
    await notifier.offer(_call);
    notifier.accept();
    methods.clear();

    container.read(callChatProvider.notifier).set(null);

    expect(methods, contains('dismiss'), reason: 'an answered call must not stay up after the chat page closes');
  });

  test('switch off: completion does not ring, but the telecom account is still prepared', () async {
    final container = _containerWithSwitch(false);
    addTearDown(container.dispose);
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      return null;
    });

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(container.read(incomingCallProvider), isNull);
    expect(methods, contains('prepare'), reason: 'outgoing calls need the account with reminders off');
    expect(methods, isNot(contains('show')));
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
    expect(methods.map((c) => c.method), contains('answered'));
    expect(methods.map((c) => c.method), isNot(contains('dismiss')),
        reason: 'answering does not count as a missed call; Telecom is left in native');

    await notifier.offer(_call);
    await native('timeout');
    expect(container.read(incomingCallProvider), isNull);

    await notifier.offer(_call);
    await native('hangup');
    expect(container.read(incomingCallProvider), isNull);
  });

  test('a debug broadcast raises the same call as a finished turn', () async {
    const channel = MethodChannel('dsh/incoming_call');
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final bridge = container.read(incomingCallBridgeProvider);
    container.read(incomingCallProvider.notifier);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'debugOffer') {
        final args = call.arguments as Map<dynamic, dynamic>;
        bridge.onDebugOffer?.call(args['title'] as String? ?? '', args['sessionId'] as String? ?? '');
      }
      return null;
    });

    await messenger.handlePlatformMessage(
      channel.name,
      StandardMethodCodec().encodeMethodCall(
        const MethodCall('debugOffer', {'title': '测试来电', 'sessionId': 'test-session'}),
      ),
      (_) {},
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(incomingCallProvider)?.title, '测试来电');
    expect(methods, contains('show'), reason: 'the debug trigger goes through the same native ring');
  });

  test('a finished turn in the conversation being called is not queued', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final notifier = container.read(incomingCallProvider.notifier);
    final live = container.read(callChatProvider.notifier);
    live.set((host: HostRef.local, sessionId: 's1'));

    await notifier.offer(_call);
    await notifier.offer(const IncomingCall(host: HostRef.local, sessionId: 's2', title: '别的任务'));
    live.set(null);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(incomingCallProvider)?.sessionId, 's2',
        reason: 'replies of the conversation in the call must not be queued');
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

  testWidgets('a paused app is no longer foreground, so a finished turn rings', (tester) async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      return null;
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const ChatAlertHost(child: SizedBox.shrink()),
    ));
    container.read(appForegroundProvider.notifier).set(true);
    await container.read(incomingCallProvider.notifier).offer(_call);
    expect(methods, isNot(contains('show')), reason: 'a foreground turn only notifies');

    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(container.read(appForegroundProvider), isFalse, reason: 'swiping the app away leaves the foreground');
    await container.read(incomingCallProvider.notifier).offer(
      const IncomingCall(host: HostRef.local, sessionId: 's2', title: '后台任务'),
    );
    expect(methods, contains('show'), reason: 'a background turn must still ring');
  });

  test('the reminder switch never answers the call: a person must tap answer', () async {
    final container = _containerWithSwitch(true);
    addTearDown(container.dispose);
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      return null;
    });

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(methods, contains('show'));
    expect(methods, isNot(contains('answered')), reason: 'no setting may pick up a telecom call');
    expect(container.read(incomingCallProvider), _call, reason: 'the ring page stays until a person answers');
    expect(container.read(incomingCallProvider.notifier).takePendingAnswer(), isNull);
  });

  test('call hours are on by default, all day when always on, and wrap at midnight', () {
    const always = CallSettings(autoAnswer: true);
    final night = CallSettings(
      autoAnswer: true,
      autoAnswerWindow: true,
      autoAnswerStart: 22 * 60,
      autoAnswerEnd: 8 * 60,
    );
    expect(callOffered(const CallSettings(), DateTime(2026, 11, 21, 23)), isTrue);
    expect(callOffered(const CallSettings(autoAnswer: false), DateTime(2026, 11, 21, 12)), isFalse);
    expect(callOffered(night, DateTime(2026, 11, 21, 21, 59)), isFalse);
    expect(callOffered(night, DateTime(2026, 11, 21, 22)), isTrue);
    expect(callOffered(night, DateTime(2026, 11, 22, 3)), isTrue);
    expect(callOffered(night, DateTime(2026, 11, 22, 8)), isFalse, reason: 'the end time is exclusive');
    expect(callOffered(night, DateTime(2026, 11, 22, 12)), isFalse);
    expect(callOffered(always, DateTime(2026, 11, 22, 12)), isTrue);
  });

  test('outside the set hours no call is offered', () async {
    final now = DateTime.now();
    final minute = now.hour * 60 + now.minute;
    final container = _containerWithSettings({
      'autoAnswer': true,
      'autoAnswerWindow': true,
      'autoAnswerStart': (minute + 120) % 1440,
      'autoAnswerEnd': (minute + 180) % 1440,
    });
    addTearDown(container.dispose);
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      return null;
    });

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(container.read(incomingCallProvider), isNull);
    expect(methods, isNot(contains('show')), reason: 'only calls inside the hours are offered');
  });

  test('inside the set hours a call is offered, but not answered', () async {
    final now = DateTime.now();
    final minute = now.hour * 60 + now.minute;
    final container = _containerWithSettings({
      'autoAnswer': true,
      'autoAnswerWindow': true,
      'autoAnswerStart': (minute + 1440 - 60) % 1440,
      'autoAnswerEnd': (minute + 60) % 1440,
    });
    addTearDown(container.dispose);
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      return null;
    });

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(methods, contains('show'));
    expect(methods, isNot(contains('answered')));
    expect(container.read(incomingCallProvider), _call);
    expect(container.read(incomingCallProvider.notifier).takePendingAnswer(), isNull);
  });

  test('a call raised just before going foreground still waits for a person to answer', () async {
    late final ProviderContainer container;
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/incoming_call'), (call) async {
      methods.add(call.method);
      if (call.method == 'show') container.read(appForegroundProvider.notifier).set(true);
      return null;
    });
    container = _containerWithSwitch(true);
    addTearDown(container.dispose);

    await container.read(incomingCallProvider.notifier).offer(_call);

    expect(methods, contains('show'));
    expect(methods, isNot(contains('answered')),
        reason: 'a foreground turn is left to its notification, even if it arrived in the background');
  });
}
