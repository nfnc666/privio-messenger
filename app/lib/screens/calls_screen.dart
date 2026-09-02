import 'package:flutter/material.dart';

import '../calls/call.dart';
import '../calls/call_signal.dart';
import '../core/app_state.dart';
import '../theme/privio_colors.dart';

/// Screen 7: calls.
///
/// The list is this device's own record of calls that happened, written when
/// each one ended. It used to render five entries out of `DemoData` — Alice at
/// 11:32, Charlie at 10:21, a missed one from Alice yesterday — under a doc
/// comment claiming "the list is real". It was not, and a fabricated call log
/// is worse than an empty one: it is the app telling someone they spoke to a
/// person they did not speak to.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PrivioScope.of(context).services.calls.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final calls = PrivioScope.of(context).services.calls;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        actions: [
          ListenableBuilder(
            listenable: calls,
            builder: (context, _) => calls.history.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: () => _confirmClear(context, calls.clearHistory),
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Clear call history',
                  ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: calls,
        builder: (context, _) =>
            calls.history.isEmpty ? const _Empty() : _History(records: calls.history),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, Future<void> Function() clear) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Clear call history?'),
        content: const Text(
          'This list is only on this device — clearing it removes it from here '
          'and from nowhere else, because it was never anywhere else.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear', style: TextStyle(color: PrivioColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await clear();
  }
}

class _History extends StatelessWidget {
  const _History({required this.records});

  final List<CallRecord> records;

  @override
  Widget build(BuildContext context) {
    final calls = PrivioScope.of(context).services.calls;

    return ListView.separated(
      itemCount: records.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        if (index == records.length) {
          return Padding(
            padding: const EdgeInsets.all(PrivioSpacing.xxl),
            child: Text(
              'This list never leaves the device. The server routes a call\'s '
              'setup the way it routes a message — sealed, and unreadable to it '
              '— so it holds no record of who called whom.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          );
        }
        final record = records[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: PrivioColors.surface,
            child: Text(record.username.characters.first.toUpperCase()),
          ),
          title: Text(
            record.username,
            style: TextStyle(color: record.wasMissed ? PrivioColors.danger : null),
          ),
          subtitle: Row(
            children: [
              Icon(_icon(record), size: 14, color: _colour(record)),
              const SizedBox(width: PrivioSpacing.xs),
              Text(_describe(record)),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.call_outlined, color: PrivioColors.accent),
            tooltip: 'Call ${record.username}',
            onPressed: () => calls.place(
              CallParty(accountId: record.accountId, username: record.username),
            ),
          ),
        );
      },
    );
  }

  IconData _icon(CallRecord record) => record.wasMissed
      ? Icons.call_missed_rounded
      : record.direction == CallDirection.incoming
          ? Icons.call_received_rounded
          : Icons.call_made_rounded;

  Color _colour(CallRecord record) =>
      record.wasMissed ? PrivioColors.danger : PrivioColors.textTertiary;

  /// What happened, plainly. A call that never connected says so rather than
  /// showing "0:00", which reads as a call that was answered and said nothing.
  String _describe(CallRecord record) {
    final when = _when(record.at);
    if (!record.wasAnswered) {
      return switch (record.ending) {
        CallEnding.declined =>
          record.direction == CallDirection.incoming ? 'Declined · $when' : 'Not taken · $when',
        CallEnding.busy => 'Busy · $when',
        CallEnding.failed => 'Could not connect · $when',
        _ => record.direction == CallDirection.incoming ? 'Missed · $when' : 'No answer · $when',
      };
    }
    final minutes = record.duration.inMinutes;
    final seconds = record.duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} · $when';
  }

  String _when(DateTime at) {
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    if (sameDay) return time;
    return '${at.day}.${at.month}. $time';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_outlined, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.lg),
            Text('No calls yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              'Start one from a chat. The call is set up over the Signal session '
              'that chat already uses, so the addresses your two devices swap to '
              'find each other are sealed to each other and not to the server.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
