import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/models.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/search_field.dart';

/// Screen 7: call history.
///
/// The list is real; placing a call is V2, when WebRTC and the SRTP key exchange
/// land. Until then the buttons are inert rather than pretending.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final calls = _filter == 0
        ? DemoData.calls
        : DemoData.calls.where((c) => c.direction == CallDirection.missed).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.add_call),
            tooltip: 'New call',
          ),
          const SizedBox(width: PrivioSpacing.xs),
        ],
      ),
      body: Column(
        children: [
          FilterChips(
            labels: const ['All', 'Missed'],
            selectedIndex: _filter,
            onSelected: (index) => setState(() => _filter = index),
          ),
          const SizedBox(height: PrivioSpacing.sm),
          Expanded(
            child: ListView.builder(
              itemCount: calls.length,
              itemBuilder: (context, index) => _CallRow(call: calls[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call});

  final CallEntry call;

  (IconData, Color, String) get _direction => switch (call.direction) {
        CallDirection.incoming => (
            Icons.call_received_rounded,
            PrivioColors.textSecondary,
            'Incoming',
          ),
        CallDirection.outgoing => (
            Icons.call_made_rounded,
            PrivioColors.textSecondary,
            'Outgoing',
          ),
        CallDirection.missed => (
            Icons.call_missed_rounded,
            PrivioColors.danger,
            'Missed',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, colour, label) = _direction;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.gutter,
        vertical: PrivioSpacing.xs,
      ),
      leading: PrivioAvatar(label: call.contactName, seed: call.avatarSeed),
      title: Text(call.contactName, style: theme.textTheme.titleMedium),
      subtitle: Row(
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: colour)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(call.timestamp, style: theme.textTheme.labelSmall),
          const SizedBox(width: PrivioSpacing.md),
          Icon(
            call.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
            size: 20,
            color: PrivioColors.accent,
          ),
        ],
      ),
    );
  }
}
