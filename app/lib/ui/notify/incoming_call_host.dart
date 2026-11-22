// A finished turn rings like a call: answer goes through the chat's call entry,
// hang up only drops the prompt. No phone permissions or dialling involved.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../performance/performance_state.dart';
import '../../state/android_features.dart' show operatingSystemProvider;
import '../../state/hosts_state.dart';
import '../../state/incoming_call_state.dart';
import '../../state/notify_state.dart' show callCatchUpProvider;
import '../speech/voice_call_page.dart';
import '../speech/call/call_parts.dart';
import '../speech/call/call_visuals.dart';
import '../theme/app_icons.dart';

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

  // The ring waits: its orb holds still, only the status dots breathe.
  final CallScene _scene = CallScene()..appear = 1;

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
    _scene.dispose();
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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final palette = CallPalette.of(theme.colorScheme, light: !dark);
    final ink = CallInk(dark: dark, child: const SizedBox());
    final performance = ref.watch(performanceDefaultsProvider);
    final keyBlur = performance.blur && !performance.lightweight && ref.watch(operatingSystemProvider) != 'ohos';
    final width = MediaQuery.sizeOf(context).width;
    final orb = width > 380 ? 300.0 : width * 0.78;
    return Positioned.fill(
      child: Material(
        color: palette.field,
        child: CallInk(
          dark: dark,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CallField(scene: _scene, palette: palette, center: 0.42),
              CallEdgeGlow(scene: _scene, palette: palette),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    CallFrosted(
                      shape: const StadiumBorder(),
                      blur: keyBlur,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.call, size: 18, color: ink.fg),
                            const SizedBox(width: 10),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: width - 120),
                              child: Text(
                                call.title,
                                key: const ValueKey('call-title'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: ink.fg,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Center(
                          child: Transform.scale(
                            scale: (box.maxHeight / (orb * 1.04)).clamp(0.56, 1.0),
                            child: CallLight(scene: _scene, palette: palette, size: orb),
                          ),
                        ),
                      ),
                    ),
                    CallStatus(text: l10n.stateAlertTurnDone, dots: true),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Text(
                          l10n.speechCallFooter,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: ink.fg.withValues(alpha: 0.94),
                            height: 1.6,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        HangUpKey(
                          key: const ValueKey('call-hang-up'),
                          icon: AppIcons.hangUp,
                          label: l10n.speechCallHangUp,
                          onTap: () => ref.read(incomingCallProvider.notifier).dismiss(),
                        ),
                        CallKey(
                          key: const ValueKey('call-answer'),
                          icon: AppIcons.call,
                          label: l10n.commonConfirm,
                          on: true,
                          blur: keyBlur,
                          size: 74,
                          onTap: () => _answer(context, ref, call),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ],
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
