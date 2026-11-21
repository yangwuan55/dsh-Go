// A finished turn rings like a call: answer goes through the chat's call entry,
// hang up only drops the prompt. No phone permissions or dialling involved.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/hosts_state.dart';
import '../../state/incoming_call_state.dart';
import '../../state/notify_state.dart' show callCatchUpProvider;
import '../speech/voice_call_page.dart';
import '../speech/call/call_parts.dart';
import '../speech/call/call_visuals.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// Inserted once inside the home route; draws nothing until a turn rings.
class IncomingCallHost extends ConsumerStatefulWidget {
  const IncomingCallHost({super.key});

  @override
  ConsumerState<IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends ConsumerState<IncomingCallHost> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entry != null) return;
      _entry = OverlayEntry(builder: (_) => const _IncomingCallLayer());
      Overlay.of(context, rootOverlay: true).insert(_entry!);
    });
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the catch-up alive: it attaches trackers for every configured host.
    ref.watch(callCatchUpProvider);
    return const SizedBox.shrink();
  }
}

class _IncomingCallLayer extends ConsumerStatefulWidget {
  const _IncomingCallLayer();

  @override
  ConsumerState<_IncomingCallLayer> createState() => _IncomingCallLayerState();
}

class _IncomingCallLayerState extends ConsumerState<_IncomingCallLayer> {
  late final IncomingCallController _calls;

  @override
  void initState() {
    super.initState();
    // Keep the notifier: ref.read is unsafe once the widget is being unmounted.
    _calls = ref.read(incomingCallProvider.notifier);
    _calls.onNativeAnswer = _answerFromNative;
    final pending = _calls.takePendingAnswer();
    if (pending != null) _answerFromNative(pending);
  }

  @override
  void dispose() {
    _calls.onNativeAnswer = null;
    super.dispose();
  }

  /// The native full-screen page was answered: use the same chat entry as the
  /// in-app button, once the overlay's context is usable again.
  void _answerFromNative(IncomingCall call) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) _answer(context, ref, call);
    });
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(incomingCallProvider);
    if (call == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final ink = CallInk.of(context);
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.76),
        child: CallInk(
          dark: true,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassSurface(
                  tier: GlassTier.chrome,
                  borderRadius: AppShape.radiusLg,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.call, size: 36, color: ink.fg),
                        const SizedBox(height: AppSpace.md),
                        Text(
                          l10n.stateAlertTurnDone,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          call.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: ink.fg),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          l10n.speechCallFooter,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ink.dim),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpace.xxl),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            HangUpKey(
                              icon: AppIcons.hangUp,
                              label: l10n.speechCallHangUp,
                              onTap: () => ref.read(incomingCallProvider.notifier).dismiss(),
                            ),
                            CallKey(
                              icon: AppIcons.call,
                              label: l10n.commonConfirm,
                              on: true,
                              onTap: () => _answer(context, ref, call),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _answer(BuildContext context, WidgetRef ref, IncomingCall call) {
    ref.read(incomingCallProvider.notifier).accept();
    // The same conversation id on another host is a different conversation.
    ref.read(activeHostProvider.notifier).select(call.host);
    unawaited(
      openChatCall(
        context,
        title: call.title,
        session: () async => ref.read(activeHostProvider) == call.host ? call.sessionId : null,
        openingPrompt: appL10n.stateIncomingCallReportPrompt,
      ),
    );
  }
}
