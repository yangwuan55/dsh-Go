// The wire format of the Android full-screen call page. No call state lives here.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IncomingCallBridge {
  IncomingCallBridge(this.channel);

  final MethodChannel channel;

  /// `answer`, `hangup` or `timeout`, sent by the native call page.
  void Function(String signal)? onSignal;

  void install() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'answer' || call.method == 'hangup' || call.method == 'timeout') {
        onSignal?.call(call.method);
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

  Future<void> dismiss() => _send('dismiss');
}

final incomingCallBridgeProvider = Provider<IncomingCallBridge>((ref) {
  final bridge = IncomingCallBridge(const MethodChannel('dsh/incoming_call'));
  bridge.install();
  ref.onDispose(() => bridge.channel.setMethodCallHandler(null));
  return bridge;
});
