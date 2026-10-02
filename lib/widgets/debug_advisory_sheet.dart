import 'dart:async';

import 'package:flutter/material.dart';

import '../services/debug_advisories.dart';
import '../theme/app_colors.dart';

/// Taps on the trigger needed to open [DebugAdvisorySheet], each within
/// [_tapWindow] of the last.
const int _tapsToOpen = 7;
const Duration _tapWindow = Duration(milliseconds: 600);

/// Wraps [child] so that [_tapsToOpen] quick taps open the debug advisory
/// sheet. Gives no feedback until it opens — there is nothing to see for
/// anyone who doesn't already know it is there.
class DebugAdvisoryTrigger extends StatefulWidget {
  final Widget child;

  const DebugAdvisoryTrigger({super.key, required this.child});

  @override
  State<DebugAdvisoryTrigger> createState() => _DebugAdvisoryTriggerState();
}

class _DebugAdvisoryTriggerState extends State<DebugAdvisoryTrigger> {
  int _taps = 0;
  Timer? _reset;

  void _onTap() {
    _reset?.cancel();
    if (++_taps >= _tapsToOpen) {
      _taps = 0;
      DebugAdvisorySheet.show(context);
      return;
    }
    _reset = Timer(_tapWindow, () => _taps = 0);
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: widget.child,
    );
  }
}

/// Lists, adds and removes [DebugAdvisories] entries.
class DebugAdvisorySheet extends StatefulWidget {
  const DebugAdvisorySheet({super.key});

  /// Opens straight away; the list fills in when the stored names finish
  /// loading, since [DebugAdvisories] notifies its listeners then.
  static Future<void> show(BuildContext context) {
    // ignore: unawaited_futures
    DebugAdvisories.instance.ensureLoaded();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const DebugAdvisorySheet(),
    );
  }

  @override
  State<DebugAdvisorySheet> createState() => _DebugAdvisorySheetState();
}

class _DebugAdvisorySheetState extends State<DebugAdvisorySheet> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text;
    final added = await DebugAdvisories.instance.add(text);
    if (!mounted) return;
    setState(() {
      _error = added
          ? null
          : text.trim().isEmpty
              ? 'Type a product or brand name.'
              : 'Already on the list.';
    });
    if (added) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final debug = DebugAdvisories.instance;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: AnimatedBuilder(
        animation: debug,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_outlined, color: AppColors.warningText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Debug advisory entries',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
                if (debug.names.isNotEmpty)
                  TextButton(
                    onPressed: debug.clear,
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'A scan whose front panel contains every word of a name here '
              'comes back as a Warning. Stored on this phone only; these '
              'Warnings are marked as debug and never uploaded.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: 'e.g. Biogesic',
                      errorText: _error,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _add,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent),
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (debug.names.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No entries yet.',
                    style: TextStyle(color: AppColors.muted)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final name in debug.names)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(name,
                            style: TextStyle(color: AppColors.text)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: AppColors.muted),
                          tooltip: 'Remove',
                          onPressed: () => debug.remove(name),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
