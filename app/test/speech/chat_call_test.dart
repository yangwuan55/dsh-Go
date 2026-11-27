// A call follows the whole conversation, not just one send: an assistant item
// that lands after the turn was done (a subagent result) must still reach the
// call as a fresh reply, and already read items must never be handed out again.

import 'package:dsh_app/speech/call/chat_call.dart';
import 'package:dsh_app/speech/call/voice_call.dart';
import 'package:dsh_app/state/chat_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart';

AssistantChatItem _item(String id, String text) => AssistantChatItem(id: id, text: text, reasoning: '');

ChatState _state(List<ChatItem> items, {bool running = false, String? title}) =>
    ChatState(items: items, running: running, loading: false, title: title);

void main() {
  test('a reply landing after the turn ended is fresh; old items are not replayed', () async {
    final chat = FakeChatController('s', _state(const []));
    final container = ProviderContainer(overrides: [chatProvider.overrideWith2((id) => chat)]);
    addTearDown(container.dispose);
    final conversation = ChatCallConversation(container, () async => 's');
    addTearDown(conversation.dispose);
    final replies = <CallReply>[];
    final sub = conversation.replies.listen(replies.add);
    addTearDown(sub.cancel);

    expect(await conversation.send('问题'), isTrue);

    final first = _item('a1', '第一句。');
    chat.emit(_state([first], running: true));
    chat.emit(_state([first]));
    await pumpEventQueue();
    expect(replies, hasLength(2));
    expect(replies.map((r) => r.fresh), [false, false]);
    expect(replies.last.text, '第一句。');
    expect(replies.last.done, isTrue);

    // The subagent result arrives with the turn already over.
    chat.emit(_state([first, _item('a2', '子代理结果。')]));
    await pumpEventQueue();
    expect(replies, hasLength(4));
    expect(replies[2].text, '子代理结果。');
    expect(replies[2].fresh, isTrue);
    expect(replies[3].text, '子代理结果。');
    expect(replies[3].done, isTrue);
    expect(replies[3].fresh, isTrue);

    // Unrelated updates to the same transcript do not re-read what was read.
    chat.emit(_state([first, _item('a2', '子代理结果。')], title: 't'));
    await pumpEventQueue();
    expect(replies, hasLength(4));
  });
}
