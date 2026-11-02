import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// One line of the connection test. [ok] is null while the check is running.
class _TestResult {
  final String name;
  final bool? ok;
  final String detail;
  const _TestResult(this.name, this.ok, this.detail);
}

Future<String> _reach(String url) async {
  final r = await http.get(Uri.parse(url));
  return 'reachable (HTTP ${r.statusCode})';
}

final List<MapEntry<String, Future<String> Function()>> _checks = [
  MapEntry('Phone date & time', () async => '${DateTime.now()}  (should match the real time)'),
  MapEntry('Internet', () => _reach('https://www.google.com/generate_204')),
  MapEntry('Firebase Auth server', () => _reach('https://identitytoolkit.googleapis.com/')),
  MapEntry('Firestore (live read)', () async {
    final snap = await FirebaseFirestore.instance
        .collection('pricing')
        .limit(1)
        .get(const GetOptions(source: Source.server));
    return 'read OK, ${snap.docs.length} doc(s) from the server';
  }),
  MapEntry('EmailJS server', () => _reach('https://api.emailjs.com/')),
];

Future<_TestResult> _timed(String name, Future<String> Function() body, int seconds) async {
  final sw = Stopwatch()..start();
  try {
    final detail = await body().timeout(Duration(seconds: seconds));
    return _TestResult(name, true, '$detail - ${sw.elapsedMilliseconds} ms');
  } on TimeoutException {
    return _TestResult(name, false, 'timed out after $seconds s');
  } catch (e) {
    return _TestResult(name, false, e.toString());
  }
}

/// Opens a dialog that checks, one by one, whether this phone can reach each
/// server the app depends on. Screenshot the result when something is slow
/// or missing - it shows exactly which connection is the problem.
Future<void> showConnectionTestDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ConnectionTestDialog(),
  );
}

class _ConnectionTestDialog extends StatefulWidget {
  const _ConnectionTestDialog();

  @override
  State<_ConnectionTestDialog> createState() => _ConnectionTestDialogState();
}

class _ConnectionTestDialogState extends State<_ConnectionTestDialog> {
  late List<_TestResult> _results;
  bool _running = true;

  List<_TestResult> _fresh() => [for (final c in _checks) _TestResult(c.key, null, 'running...')];

  @override
  void initState() {
    super.initState();
    _results = _fresh();
    _runChecks();
  }

  Future<void> _runChecks() async {
    for (var i = 0; i < _checks.length; i++) {
      final entry = _checks[i];
      final seconds = entry.key.startsWith('Firestore') ? 15 : 10;
      final result = await _timed(entry.key, entry.value, seconds);
      if (!mounted) return;
      setState(() => _results[i] = result);
    }
    if (!mounted) return;
    setState(() => _running = false);
  }

  void _rerun() {
    setState(() {
      _results = _fresh();
      _running = true;
    });
    _runChecks();
  }

  Widget _row(_TestResult r) {
    final Widget icon = r.ok == null
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(
            r.ok! ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: r.ok! ? Colors.green : Colors.red,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(r.detail, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connection test'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in _results) _row(r),
              const SizedBox(height: 8),
              const Text(
                'Take a screenshot of this and send it if something shows a red X.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _running ? null : _rerun, child: const Text('Run again')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
