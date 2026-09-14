import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../crypto/safety_number.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';

/// The screen that makes end-to-end encryption checkable.
///
/// Everything else in Privio takes the server's word for who a key belongs to.
/// This is where that stops: two people compare a number computed from both
/// their keys, over a channel the server has no part in, and a server that
/// substituted a key of its own cannot make the numbers agree.
///
/// There is no QR here. Scanning needs a camera package Privio does not carry,
/// and a QR nobody can scan is decoration on a security screen. Reading the
/// digits aloud is the method; the compare box below is for the case where the
/// other person sends theirs in writing, because comparing sixty digits by eye
/// is where a person makes the one mistake this screen exists to prevent.
class SafetyNumberScreen extends StatefulWidget {
  const SafetyNumberScreen({
    required this.accountId,
    required this.title,
    super.key,
  });

  /// The peer's account, not a group. Group members are verified one by one,
  /// in the 1:1 chat with each of them.
  final String accountId;
  final String title;

  @override
  State<SafetyNumberScreen> createState() => _SafetyNumberScreenState();
}

class _SafetyNumberScreenState extends State<SafetyNumberScreen> {
  SafetyNumbers? _numbers;
  bool _loading = true;
  final TextEditingController _compare = TextEditingController();
  String? _comparison;
  bool _comparisonMatched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _compare.dispose();
    super.dispose();
  }

  /// True when the user arrived here because a key changed under an incoming
  /// message. Captured before the notice is answered, since showing the number
  /// is what answers it.
  bool _arrivedAfterChange = false;

  Future<void> _load() async {
    final state = PrivioScope.of(context);
    final me = state.accountId;
    if (me == null) return;
    final flagged = state.conversations.hasKeyChangeAlert(widget.accountId);
    final numbers = await state.services.crypto.safetyNumbers(
      localAccountId: me,
      remoteAccountId: widget.accountId,
    );
    if (!mounted) return;
    setState(() {
      _numbers = numbers;
      _loading = false;
      _arrivedAfterChange = _arrivedAfterChange || flagged;
    });
    // The notice existed to get the number in front of somebody. It is in
    // front of them.
    await state.conversations.acknowledgeKeyChange(widget.accountId);
  }

  Future<void> _setVerified(bool verified) async {
    final state = PrivioScope.of(context);
    final numbers = _numbers;
    if (numbers == null) return;
    if (verified) {
      await state.services.crypto.markVerified(widget.accountId, numbers);
    } else {
      await state.services.crypto.clearVerified(widget.accountId);
    }
    await _load();
  }

  Future<void> _acceptChange() async {
    final state = PrivioScope.of(context);
    await state.conversations.acceptIdentityChange(widget.accountId);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppText.of(context).safetyTrustedToast)),
    );
  }

  void _runComparison() {
    final text = AppText.of(context);
    final numbers = _numbers;
    final typed = _compare.text;
    if (numbers == null || typed.trim().isEmpty) {
      setState(() => _comparison = null);
      return;
    }
    final matched = numbers.numbers.any((n) => n.matches(typed));
    setState(() {
      _comparisonMatched = matched;
      _comparison = matched ? text.safetyMatches : text.safetyNoMatch;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);
    final numbers = _numbers;
    final text = AppText.of(context);
    final pending = state.conversations.identityChangesFor(widget.accountId);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.chatSafetyNumber),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.accents.accent))
          : ListView(
              padding: const EdgeInsets.all(PrivioSpacing.gutter),
              children: [
                if (pending.isNotEmpty) _ChangedBanner(onAccept: _acceptChange),
                if (pending.isEmpty && _arrivedAfterChange) const _ReceivedChangeNotice(),
                if (numbers != null && numbers.isEmpty)
                  _Explainer(text.safetyNothingYet(widget.title))
                else ...[
                  _StateChip(state: numbers?.state ?? VerificationState.unverified),
                  const SizedBox(height: PrivioSpacing.lg),
                  _Explainer(text.safetyReadThese(widget.title)),
                  const SizedBox(height: PrivioSpacing.xl),
                  for (final number in numbers!.numbers)
                    _NumberCard(number: number, showDevice: numbers.numbers.length > 1),
                  const SizedBox(height: PrivioSpacing.lg),
                  _CompareBox(
                    controller: _compare,
                    onCompare: _runComparison,
                    result: _comparison,
                    matched: _comparisonMatched,
                  ),
                  const SizedBox(height: PrivioSpacing.xl),
                  FilledButton(
                    key: const Key('safety-verify'),
                    style: FilledButton.styleFrom(
                      backgroundColor: numbers.state == VerificationState.verified
                          ? PrivioColors.surfaceHigh
                          : context.accents.accent,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () =>
                        unawaited(_setVerified(numbers.state != VerificationState.verified)),
                    child: Text(
                      numbers.state == VerificationState.verified
                          ? text.safetyMarkNotVerified
                          : text.safetyMarkVerified,
                      style: TextStyle(
                        color: numbers.state == VerificationState.verified
                            ? PrivioColors.textPrimary
                            : PrivioColors.background,
                      ),
                    ),
                  ),
                  const SizedBox(height: PrivioSpacing.md),
                  Text(
                    text.safetyMarkNote(widget.title),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: PrivioColors.textTertiary),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final VerificationState state;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final (label, colour, icon) = switch (state) {
      VerificationState.verified =>
        (text.safetyVerified, context.accents.accent, Icons.verified_user_outlined),
      VerificationState.changed =>
        (text.safetyChangedSince, PrivioColors.warning, Icons.error_outline),
      VerificationState.unverified =>
        (text.safetyNotVerified, PrivioColors.textSecondary, Icons.help_outline),
    };
    return Row(
      key: const Key('safety-state'),
      children: [
        Icon(icon, size: 18, color: colour),
        const SizedBox(width: PrivioSpacing.sm),
        Text(label, style: TextStyle(color: colour, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _NumberCard extends StatelessWidget {
  const _NumberCard({required this.number, required this.showDevice});

  final SafetyNumber number;
  final bool showDevice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: PrivioSpacing.md),
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      decoration: BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        border: Border.all(color: PrivioColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDevice) ...[
            Text(
              AppText.of(context).safetyTheirDevice(number.deviceIndex),
              style: theme.textTheme.labelSmall?.copyWith(color: PrivioColors.textTertiary),
            ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
          // Selectable text carries no label of its own, which leaves a
          // screen reader with nothing to say on the one screen where the
          // content *is* the security. The label spells the groups out.
          Semantics(
            label: number.formatted,
            readOnly: true,
            child: ExcludeSemantics(
              child: SelectableText(
                number.formatted,
                style: theme.textTheme.titleMedium?.copyWith(
                  // Tabular figures so two screens held side by side line up.
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 1.4,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareBox extends StatelessWidget {
  const _CompareBox({
    required this.controller,
    required this.onCompare,
    required this.result,
    required this.matched,
  });

  final TextEditingController controller;
  final VoidCallback onCompare;
  final String? result;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('safety-compare-field'),
          controller: controller,
          maxLines: 2,
          minLines: 1,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          keyboardType: TextInputType.number,
          inputFormatters: [LengthLimitingTextInputFormatter(120)],
          decoration: InputDecoration(
            labelText: AppText.of(context).safetyCompareTitle,
            hintText: '12345 67890 …',
          ),
          onSubmitted: (_) => onCompare(),
        ),
        const SizedBox(height: PrivioSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('safety-compare'),
            onPressed: onCompare,
            child: Text(AppText.of(context).safetyCompare),
          ),
        ),
        if (result != null)
          Text(
            result!,
            key: const Key('safety-compare-result'),
            style: TextStyle(
              color: matched ? context.accents.accent : PrivioColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _ChangedBanner extends StatelessWidget {
  const _ChangedBanner({required this.onAccept});

  final Future<void> Function() onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: PrivioSpacing.lg),
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      decoration: BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        border: Border.all(color: PrivioColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: PrivioColors.warning, size: 18),
              const SizedBox(width: PrivioSpacing.sm),
              Text(
                AppText.of(context).safetyKeyNotYours,
                style: theme.textTheme.titleSmall?.copyWith(color: PrivioColors.warning),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.sm),
          Text(
            AppText.of(context).safetyRefusedUntilDecide,
            style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textSecondary),
          ),
          const SizedBox(height: PrivioSpacing.md),
          FilledButton(
            key: const Key('safety-accept'),
            style: FilledButton.styleFrom(
              backgroundColor: PrivioColors.warning,
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: () => unawaited(onAccept()),
            child: Text(
              AppText.of(context).safetyTrustNewKey,
              style: const TextStyle(color: PrivioColors.background),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the change arrived rather than being refused.
///
/// Nothing to accept here: it is already pinned, because a message that
/// carries a new key cannot be refused without giving anyone the power to
/// stop a conversation by sending one. What is left is telling the truth
/// about it.
class _ReceivedChangeNotice extends StatelessWidget {
  const _ReceivedChangeNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('safety-received-change'),
      margin: const EdgeInsets.only(bottom: PrivioSpacing.lg),
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      decoration: BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        border: Border.all(color: PrivioColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: PrivioColors.warning, size: 18),
              const SizedBox(width: PrivioSpacing.sm),
              Expanded(
                child: Text(
                  AppText.of(context).safetyKeyChangedArrived,
                  style: theme.textTheme.titleSmall?.copyWith(color: PrivioColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.sm),
          Text(
            AppText.of(context).safetyKeyChangedBody,
            style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: PrivioColors.textSecondary),
      );
}
