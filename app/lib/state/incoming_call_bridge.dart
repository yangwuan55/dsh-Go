// The wire format of the Android full-screen call page. No call state lives here.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IncomingCallBridge {
  IncomingCallBridge(this.channel);

  final MethodChannel channel;

  /// `answer`, `hangup` or `timeout`, sent by the native call page.
  void Function(String signal)? onSignal;

  /// Debug APK's TEST_INCOMING_CALL broadcast takes the same path as a finished turn.
  void Function(String title, String sessionId)? onDebugOffer;

  void install() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'answer' || call.method == 'hangup' || call.method == 'timeout') {
        onSignal?.call(call.method);
      } else if (kDebugMode && call.method == 'debugOffer') {
        final args = call.arguments as Map<dynamic, dynamic>;
        onDebugOffer?.call(args['title'] as String? ?? '', args['sessionId'] as String? ?? '');
      }
    });
  }

  Future<void> _send(String method, [Object? arguments]) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // HarmonyOS has no native call page; the in-app overlay still works.
    }
  }

  /// Starts the keep-alive service and asks for notification access.
  Future<void> prepare() => _send('prepare');

  Future<void> disable() => _send('disable');

  Future<void> show(String title, String sessionId) => _send('show', {'title': title, 'sessionId': sessionId});

  /// A voice call borrows Telecom's call state until its own audio is up.
  Future<void> placeCall(String title) => _send('placeCall', {'title': title});

  /// The borrowed call is released without touching an incoming ring.
  Future<void> endOutgoing() => _send('endOutgoing');

  /// Answered: the native side leaves Telecom, the voice call owns the audio.
  Future<void> answered() => _send('answered');

  Future<void> dismiss() => _send('dismiss');
}

final incomingCallBridgeProvider = Provider<IncomingCallBridge>((ref) {
  final bridge = IncomingCallBridge(const MethodChannel('dsh/incoming_call'));
  bridge.install();
  ref.onDispose(() => bridge.channel.setMethodCallHandler(null));
  return bridge;
});
