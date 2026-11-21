// Catch-up has to find a turn that finished while no live edge was seen, even
// after a reconnect — and must not ring for the whole session history.

import 'package:dsh_app/notify/chat_alerts.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

SessionSummary _session(String id) => SessionSummary(
      sessionId: id,
      updatedAt: DateTime(2020),
      running: false,
      blank: false,
      agentAvailable: true,
    );

void main() {
  test('catch-up rings once for a turn finished while disconnected', () async {
    final source = FakeAlertSource();
    final alerts = <ChatAlert>[];
    final seenSeqs = <String, int>{};
    final trackers = <HostAlertTracker>[];
    HostAlertTracker newTracker() {
      final tracker = HostAlertTracker(
        host: HostRef.local,
        source: source,
        onAlert: alerts.add,
        onWithdraw: (_, _, _) {},
        onSessionGone: (_, _) {},
        turnSeqs: seenSeqs,
      );
      trackers.add(tracker);
      return tracker;
    }

    addTearDown(() => Future.wait(trackers.map((t) => t.dispose())));
    source.sessions = [_session('task')];
    source.outcomes['task'] = outcome(7, 'completed', title: 'Login fixed');

    var tracker = newTracker()..start();
    await settle();
    await tracker.sweep();
    await settle();
    expect(alerts, isEmpty, reason: 'the first sweep only records a baseline');

    // A reconnect replaces the tracker; the turn finished while we were away.
    await tracker.dispose();
    source.outcomes['task'] = outcome(8, 'completed', title: 'Login fixed');
    tracker = newTracker()..start();
    await settle();
    await tracker.sweep();
    await settle();

    expect(alerts.map((a) => a.sessionId), ['task']);
    expect(alerts.single.kind, AlertKind.done);

    await tracker.sweep();
    await settle();
    expect(alerts, hasLength(1), reason: 'the same turn must not ring twice');
  });
}
