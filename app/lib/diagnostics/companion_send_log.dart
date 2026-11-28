// A release-readable trace of the companion send chain: Android's evidence
// file keeps only error types, and developer.log never reaches logcat.
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'redact.dart';

const _logName = 'companion-send.log';
const _maxLines = 240;
Future<void> _writes = Future.value();

/// The first app frame after [logCompanionSend], so a return has a file:line.
String _caller(StackTrace stack) {
  for (final frame in stack.toString().split('\n').skip(1)) {
    final match = RegExp(r'(package:dsh_app/[A-Za-z0-9_/.-]+\.dart):(\d+):(\d+)').firstMatch(frame);
    if (match != null) return '${match[1]}:${match[2]}';
  }
  return 'unknown';
}

/// One masked line, appended to the app's external files dir (adb-readable)
/// and kept in the in-memory bundle source. Never changes the send it observes.
void logCompanionSend(String detail) {
  final line = redactDiagnostics('${_caller(StackTrace.current)} $detail').replaceAll('\n', ' ');
  developer.log(line, name: 'CompanionSendDiag');
  _writes = _writes.whenComplete(() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      await dir.create(recursive: true);
      final file = File('${dir.path}/$_logName');
      final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
      final kept = [...lines, line];
      await file.writeAsString(
        '${kept.skip(kept.length > _maxLines ? kept.length - _maxLines : 0).join('\n')}\n',
        flush: true,
      );
    } catch (_) {
      // Diagnostics must not turn a failed observation into a failed send.
    }
  });
}

Future<List<String>> readCompanionSendLog() async {
  try {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return const <String>[];
    final file = File('${dir.path}/$_logName');
    return file.existsSync() ? file.readAsLinesSync() : const <String>[];
  } catch (_) {
    return const <String>[];
  }
}
