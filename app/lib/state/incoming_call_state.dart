// One pending in-app call for a finished turn. Answering reuses the chat call;
// hanging up only drops the prompt.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../notify/notify_channel.dart';
import '../speech/speech_settings.dart';
import 'hosts_state.dart';
import 'incoming_call_bridge.dart';
import 'notify_state.dart' show appForegroundProvider, callChatProvider, notifyChannelProvider;

class IncomingCall {
  const IncomingCall({required this.host, required this.sessionId, required this.title});

  final HostRef host;
  final String sessionId;
  final String title;
}

class IncomingCallController extends Notifier<IncomingCall?> {
  /// Set by the home overlay: only it has the context to open the chat call.
  void Function(IncomingCall)? onNativeAnswer;
  IncomingCall? _pendingAnswer;
  static const _maxQueued = 3;
  final List<IncomingCall> _queue = [];

  @override
  IncomingCall? build() {
    final bridge = ref.read(incomingCallBridgeProvider);
    bridge.onSignal = nativeSignal;
    bridge.onDebugOffer = (title, sessionId) => unawaited(
          offer(IncomingCall(host: HostRef.local, sessionId: sessionId, title: title)),
        );
    // Changing the switch retires a prompt still on screen and its native page.
    ref.listen(callSettingsProvider.select((s) => s.autoAnswer), (was, on) {
      if (on && was != true) unawaited(bridge.prepare());
      if (!on && was == true) {
        unawaited(bridge.dismiss());
        _pendingAnswer = null;
        _queue.clear();
      }
    });
    // ChatCallConversation clears this when the call page closes: that ends
    // the answered telecom call, then lets the next queued turn ring.
    ref.listen(callChatProvider, (_, live) {
      if (live == null) {
        unawaited(bridge.dismiss());
        unawaited(_presentNext());
      }
    });
    if (ref.read(callSettingsProvider.select((s) => s.autoAnswer))) unawaited(bridge.prepare());
    return null;
  }

  Future<void> offer(IncomingCall call) async {
    final settings = await ref.read(callSettingsProvider.notifier).ready();
    if (!ref.mounted || !callOffered(settings, DateTime.now()) || ref.read(appForegroundProvider)) return;
    if (state != null || ref.read(callChatProvider) != null) {
      if (_queue.length >= _maxQueued) _queue.removeAt(0);
      _queue.add(call);
      return;
    }
    await _ring(call);
  }

  Future<void> _ring(IncomingCall call) async {
    state = call;
    _pendingAnswer = null;
    await ref.read(incomingCallBridgeProvider).show(call.title, call.sessionId);
  }

  /// One at a time: neither a prompt on screen nor a live call is interrupted.
  Future<void> _presentNext() async {
    if (_queue.isEmpty || state != null || !ref.mounted || ref.read(callChatProvider) != null) return;
    // A turn queued in the background was already notified; don't ring it once the app is on screen.
    if (ref.read(appForegroundProvider)) {
      _queue.clear();
      return;
    }
    await _ring(_queue.removeAt(0));
  }

  /// The native page's answer/hangup/timeout, back on the same state as the
  /// in-app overlay. One answer that arrives before the overlay mounts waits
  /// for it; it is not a queue of calls.
  void nativeSignal(String signal) {
    if (signal == 'answer') {
      final call = accept();
      if (call == null) return;
      final handler = onNativeAnswer;
      if (handler != null) {
        handler(call);
      } else {
        _pendingAnswer = call;
      }
      return;
    }
    dismiss();
  }

  IncomingCall? takePendingAnswer() {
    final call = _pendingAnswer;
    _pendingAnswer = null;
    return call;
  }

  IncomingCall? accept() {
    final call = state;
    state = null;
    if (call != null) {
      // Claim the in-call signal now: the page only sets it once its first
      // send runs, after permission and audio setup. A turn arriving in that
      // gap must still queue. openChatCall clears it when the call closes.
      ref.read(callChatProvider.notifier).set((host: call.host, sessionId: call.sessionId));
    }
    unawaited(ref.read(incomingCallBridgeProvider).answered());
    return call;
  }

  /// Native hangup/timeout and the in-app hangup key land here. Only a call
  /// that was still ringing is missed; answering cleared it already.
  void dismiss() {
    final missed = state;
    state = null;
    unawaited(ref.read(incomingCallBridgeProvider).dismiss());
    if (missed != null) {
      final label = appL10n.stateMissedCall(missed.title);
      unawaited(
        ref.read(notifyChannelProvider).show(
          NotifyPost(
            group: notifyGroup(missed.host, missed.sessionId),
            key: 'missed-call',
            attention: false,
            title: label,
            text: label,
            publicText: appL10n.stateMissedCallPublic,
            sessionId: missed.sessionId,
            host: missed.host,
            kind: 'missedCall',
          ),
        ),
      );
    }
    unawaited(_presentNext());
  }
}

final incomingCallProvider = NotifierProvider<IncomingCallController, IncomingCall?>(IncomingCallController.new);
