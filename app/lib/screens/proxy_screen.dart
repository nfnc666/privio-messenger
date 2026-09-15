import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../network/proxy_config.dart';
import '../network/proxy_controller.dart';
import '../widgets/privio_back_button.dart';

class ProxyScreen extends StatefulWidget {
  const ProxyScreen({super.key});
  @override
  State<ProxyScreen> createState() => _ProxyScreenState();
}

class _ProxyScreenState extends State<ProxyScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '1080');
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _enabled = false;
  bool _busy = false;
  String? _status;
  @override
  void initState() {
    super.initState();
    final config = ProxyController.instance.config;
    if (config != null) {
      _host.text = config.host; _port.text = '${config.port}';
      _user.text = config.username; _password.text = config.password;
      _enabled = config.enabled;
    }
  }
  @override
  void dispose() {
    _host.dispose(); _port.dispose(); _user.dispose(); _password.dispose();
    super.dispose();
  }
  Future<void> _run({bool testing = false, bool remove = false}) async {
    final state = PrivioScope.of(context);
    final text = AppText.of(context);
    ProxyConfig? config;
    try {
      if (!remove) {
        config = ProxyConfig(host: _host.text.trim(), port: int.tryParse(_port.text) ?? 0,
          username: _user.text, password: _password.text, enabled: testing || _enabled);
        config.validate();
      }
    } on Object { setState(() => _status = text.proxyInvalid); return; }
    setState(() { _busy = true; _status = null; });
    try {
      if (testing) {
        await ProxyController.instance.test(config!, state.services.api.baseUrl);
      } else {
        await state.setProxy(config);
      }
      if (!mounted) return;
      setState(() {
        _status = testing ? text.proxyTestSuccess : text.proxySaved;
        if (remove) {
          _enabled = false; _host.clear(); _port.text = '1080';
          _user.clear(); _password.clear();
        }
      });
    } on Object {
      // Raw transport errors may contain credentials. Never display them.
      if (mounted) setState(() => _status = text.proxyFailed);
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Scaffold(
      appBar: AppBar(leading: const PrivioBackButton(), title: Text(text.proxyTitle)),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(text.proxyScope), const SizedBox(height: 16),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(text.proxyEnable),
          value: _enabled, onChanged: _busy ? null : (value) => setState(() {
            _enabled = value; _status = null;
          })),
        _field(_host, text.proxyHost), _field(_port, text.proxyPort, numeric: true),
        _field(_user, text.proxyUsername), _field(_password, text.proxyPassword, secret: true),
        const SizedBox(height: 16), Text(text.proxyPrivacy), const SizedBox(height: 16),
        OutlinedButton(onPressed: _busy ? null : () => _run(testing: true), child: Text(text.proxyTest)),
        FilledButton(onPressed: _busy ? null : () => _run(), child: Text(text.proxySave)),
        TextButton(onPressed: _busy ? null : () => _run(remove: true), child: Text(text.proxyRemove)),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_status != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_status!)),
      ]),
    );
  }
  Widget _field(TextEditingController controller, String label,
      {bool numeric = false, bool secret = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: controller, enabled: !_busy, obscureText: secret,
      autocorrect: false, enableSuggestions: false,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() => _status = null)),
  );
}
