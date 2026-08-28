import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/license_controller.dart';
import '../theme/privio_colors.dart';

/// Activation for the builds that are not sold through a store.
///
/// Nothing here decides anything: the key is sent to the server, and what comes
/// back is what the screen shows. A client that decided for itself would be
/// worth nothing anyway — this build is open source and anyone can remove the
/// screen entirely.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _controller = TextEditingController();
  LicenseController? _license;

  @override
  void initState() {
    super.initState();
    // The status may be stale by the time someone opens this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _license?.refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _license = PrivioScope.of(context).license;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final license = _license!;
    FocusScope.of(context).unfocus();
    final activated = await license.redeem(_controller.text);
    if (!mounted || !activated) return;

    _controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('License activated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final license = PrivioScope.of(context).license;
    final status = license.status;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('License')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.gutter,
          vertical: PrivioSpacing.lg,
        ),
        children: [
          if (status?.licensed ?? false)
            _ActiveLicense(status: status!)
          else ...[
            Text('Activate Privio', style: text.titleLarge),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              'Privio Libre and the direct APK are activated with a license '
              'key bought on privio.com. One key, one account, no renewals.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.2),
              decoration: const InputDecoration(
                labelText: 'License key',
                hintText: 'PRIVIO-XXXX-XXXX-XXXX-XXXX',
              ),
              inputFormatters: [_LicenseKeyFormatter()],
              onChanged: (_) => license.clearError(),
              onSubmitted: (_) => license.busy ? null : _submit(),
            ),
            if (license.error != null) ...[
              const SizedBox(height: PrivioSpacing.md),
              Text(
                license.error!,
                style: text.bodySmall?.copyWith(color: PrivioColors.danger),
              ),
            ],
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton(
              onPressed: license.busy ? null : _submit,
              child: license.busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Activate'),
            ),
            const SizedBox(height: PrivioSpacing.xl),
            Text(
              'Activation binds the key to this account permanently. It cannot '
              'be moved to another one afterwards, so activate it on the '
              'account you mean to keep.',
              style: text.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              'Never share your key. Anyone who redeems it first keeps it — '
              'support will never ask you for the whole thing.',
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveLicense extends StatelessWidget {
  const _ActiveLicense({required this.status});

  final LicenseStatus status;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final source = switch (status.source) {
      'apple' => 'App Store purchase',
      'google' => 'Google Play purchase',
      _ => 'License key',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.verified_rounded, color: PrivioColors.accent),
            const SizedBox(width: PrivioSpacing.md),
            Text('License active', style: text.titleLarge),
          ],
        ),
        const SizedBox(height: PrivioSpacing.md),
        Text(
          'This account is activated for life. There is nothing to renew and '
          'nothing to pay again.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: PrivioSpacing.xl),
        _DetailRow(label: 'Source', value: source),
        if (status.redeemedAt != null)
          _DetailRow(
            label: 'Activated',
            value: status.redeemedAt!.toLocal().toString().split('.').first,
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Prints the key the way it appears on the receipt while it is typed. What is
/// sent is unchanged — the server folds case and separators itself.
class _LicenseKeyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    if (value.text.isEmpty) return value;

    final formatted = formatLicenseKey(value.text);
    // Deleting through a separator would otherwise re-add it and trap the
    // cursor, so let a shrinking edit stand as typed.
    if (formatted.length < value.text.length) return value;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
