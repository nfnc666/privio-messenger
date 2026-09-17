import 'dart:async';
import 'package:flutter/material.dart';

import '../core/account_phone_controller.dart';
import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/phone_field.dart';
import '../widgets/privio_back_button.dart';

/// Account-only annotation. No access to the verified/discovery controller.
class AccountPhoneScreen extends StatefulWidget {
  const AccountPhoneScreen({super.key});
  @override
  State<AccountPhoneScreen> createState() => _AccountPhoneScreenState();
}

class _AccountPhoneScreenState extends State<AccountPhoneScreen> {
  AccountPhoneController? _controller;
  final _input = TextEditingController();
  GlobalKey<PhoneFieldState> _field = GlobalKey<PhoneFieldState>();
  bool _invalid = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = AccountPhoneController(PrivioScope.of(context).services.api)..addListener(_changed);
    unawaited(_controller!.load());
  }

  void _changed() { if (mounted) setState(() {}); }

  Future<void> _save({bool remove = false}) async {
    final controller = _controller!;
    if (!controller.active || controller.busy) return;
    final field = _field.currentState;
    if (!remove && field != null && !field.isEmpty && field.value == null) {
      setState(() => _invalid = true);
      return;
    }
    final success = remove ? await controller.remove() : await controller.save(field?.value?.e164);
    if (!mounted || !controller.active) return;
    if (success) {
      setState(() {
        _invalid = false;
        _input.clear();
        _field = GlobalKey<PhoneFieldState>();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppText.of(context).accountPhoneSaved)));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to account changes; an old route must not expose the old draft.
    PrivioScope.of(context);
    final text = AppText.of(context);
    final controller = _controller!;
    Widget body;
    if (!controller.active) {
      body = Center(child: Text(text.accountPhoneSessionEnded));
    } else if (!controller.loaded) {
      body = Center(child: controller.busy ? const CircularProgressIndicator() : Column(
        mainAxisSize: MainAxisSize.min,
        children: [Text(text.accountPhoneSaveError), TextButton(onPressed: controller.load, child: Text(text.commonRetry))],
      ),);
    } else {
      body = ListView(padding: const EdgeInsets.all(PrivioSpacing.gutter), children: [
        AbsorbPointer(absorbing: controller.busy, child: PhoneField(
          key: _field, controller: _input, initialNumber: controller.number,
          onChanged: (_) { if (_invalid) setState(() => _invalid = false); },
        ),),
        const SizedBox(height: PrivioSpacing.md),
        Text(text.accountPhoneNote),
        if (controller.number != null) ...[
          const SizedBox(height: PrivioSpacing.sm),
          Text(text.accountPhoneUnverified, style: Theme.of(context).textTheme.labelLarge),
        ],
        if (controller.hasVerifiedNumber) ...[
          const SizedBox(height: PrivioSpacing.md),
          Text(text.accountPhoneVerifiedSeparate),
        ],
        if (_invalid || controller.failed) ...[
          const SizedBox(height: PrivioSpacing.md),
          Text(_invalid ? text.failurePhoneInvalid : text.accountPhoneSaveError,
            style: const TextStyle(color: PrivioColors.danger),
          ),
        ],
        const SizedBox(height: PrivioSpacing.lg),
        FilledButton(onPressed: controller.busy ? null : () => _save(), child: Text(text.commonSave)),
        if (controller.number != null)
          TextButton(onPressed: controller.busy ? null : () => _save(remove: true), child: Text(text.phoneRemove)),
      ],);
    }
    return Scaffold(appBar: AppBar(leading: const PrivioBackButton(), title: Text(text.phoneFieldLabel)), body: body);
  }
}
