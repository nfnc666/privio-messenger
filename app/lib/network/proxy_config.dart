import 'dart:convert';

/// Device network settings, never part of an account backup or sent to Privio.
class ProxyConfig {
  const ProxyConfig({required this.host, required this.port,
    this.username = '', this.password = '', this.enabled = false});

  final String host;
  final int port;
  final String username;
  final String password;
  final bool enabled;

  void validate() {
    if (host.isEmpty || host.length > 253 ||
        RegExp(r'[\s/@?#;\\]').hasMatch(host) || host.contains('://') ||
        port < 1 || port > 65535 ||
        utf8.encode(username).length > 255 || utf8.encode(password).length > 255 ||
        (username.isEmpty != password.isEmpty)) {
      throw const FormatException('Invalid SOCKS5 configuration');
    }
    // A colon is allowed only in an IPv6 literal, never a host:port pair.
    if (host.contains(':') && !RegExp(r'^[0-9a-fA-F:]+$').hasMatch(host)) {
      throw const FormatException('Invalid proxy host');
    }
  }

  Map<String, Object> toJson() => {'host': host, 'port': port,
    'username': username, 'password': password, 'enabled': enabled};

  factory ProxyConfig.fromJson(Map<String, dynamic> json) {
    final config = ProxyConfig(host: json['host'] as String,
      port: json['port'] as int, username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '', enabled: json['enabled'] as bool);
    config.validate();
    return config;
  }

  @override
  String toString() => 'ProxyConfig(enabled: $enabled)';
}
