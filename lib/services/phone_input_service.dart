import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../api/debrid_api.dart';
import '../api/mdblist_service.dart';
import '../api/settings_service.dart';

/// Lightweight HTTP server that lets the user enter API keys from their phone.
/// Start the server, show the URL on the TV screen, and the phone connects
/// over the local Wi-Fi network.
class PhoneInputService {
  static final PhoneInputService _instance = PhoneInputService._internal();
  factory PhoneInputService() => _instance;
  PhoneInputService._internal();

  HttpServer? _server;
  bool get isRunning => _server != null;

  /// Stream that emits the service name + key when saved from the phone.
  final StreamController<Map<String, String>> _onKeySaved =
      StreamController.broadcast();
  Stream<Map<String, String>> get onKeySaved => _onKeySaved.stream;

  /// Start the server on the given port (default 8080).
  Future<String?> start({int port = 8080}) async {
    if (_server != null) return await _getUrl();

    try {
      // Bind to any IPv4 so phones on the same network can connect.
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      debugPrint('[PhoneInput] Server started on port $port');
      _server!.listen(_handleRequest);
      return await _getUrl();
    } catch (e) {
      debugPrint('[PhoneInput] Failed to start: $e');
      return null;
    }
  }

  void stop() {
    _server?.close();
    _server = null;
  }

  Future<String?> _getUrl() async {
    if (_server == null) return null;
    final ip = await _getLocalIp();
    if (ip == null) return null;
    return 'http://$ip:${_server!.port}';
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // CORS headers
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/') {
      await _serveForm(request);
    } else if (request.method == 'POST' && request.uri.path == '/save') {
      await _handleSave(request);
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  }

  Future<void> _serveForm(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_htmlForm);
    await request.response.close();
  }

  Future<void> _handleSave(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = json.decode(body) as Map<String, dynamic>;
      final service = data['service'] as String? ?? '';
      final apiKey = data['api_key'] as String? ?? '';

      if (service.isEmpty || apiKey.isEmpty) {
        request.response.statusCode = 400;
        request.response.write(json.encode({'error': 'Missing service or api_key'}));
        await request.response.close();
        return;
      }

      // Save the key to the appropriate service
      final debrid = DebridApi();
      switch (service) {
        case 'Real-Debrid':
          await debrid.saveRDApiKey(apiKey);
          break;
        case 'TorBox':
          await debrid.saveTorBoxKey(apiKey);
          break;
        case 'AllDebrid':
          await debrid.saveAllDebridKey(apiKey);
          break;
        case 'Premiumize':
          await debrid.savePremiumizeKey(apiKey);
          break;
        case 'Debrid-Link':
          await debrid.saveDebridLinkKey(apiKey);
          break;
        case 'Jackett':
          await SettingsService().setJackettApiKey(apiKey);
          break;
        case 'Prowlarr':
          await SettingsService().setProwlarrApiKey(apiKey);
          break;
        case 'MDBlist':
          await MdblistService().setApiKey(apiKey);
          break;
        default:
          request.response.statusCode = 400;
          request.response.write(json.encode({'error': 'Unknown service: $service'}));
          await request.response.close();
          return;
      }

      _onKeySaved.add({'service': service, 'key': apiKey});

      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'status': 'ok', 'service': service}));
      await request.response.close();

      debugPrint('[PhoneInput] Saved key for $service');
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write(json.encode({'error': e.toString()}));
      await request.response.close();
    }
  }

  static const _htmlForm = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PlayTorrio – Enter API Key</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0B0B12;
      color: #fff;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: #15151E;
      border: 1px solid rgba(124,77,255,0.3);
      border-radius: 16px;
      padding: 32px;
      max-width: 420px;
      width: 100%;
    }
    h1 {
      font-size: 22px;
      margin-bottom: 8px;
      color: #7C4DFF;
    }
    p { color: rgba(255,255,255,0.5); font-size: 14px; margin-bottom: 24px; }
    label {
      display: block;
      font-size: 13px;
      color: rgba(255,255,255,0.6);
      margin-bottom: 6px;
      font-weight: 600;
    }
    select, input {
      width: 100%;
      padding: 12px 16px;
      border-radius: 10px;
      border: 1px solid rgba(255,255,255,0.1);
      background: rgba(255,255,255,0.05);
      color: #fff;
      font-size: 16px;
      margin-bottom: 16px;
      outline: none;
    }
    select:focus, input:focus {
      border-color: #7C4DFF;
    }
    select option { background: #15151E; color: #fff; }
    button {
      width: 100%;
      padding: 14px;
      border-radius: 12px;
      border: none;
      background: #7C4DFF;
      color: #fff;
      font-size: 16px;
      font-weight: 700;
      cursor: pointer;
      margin-top: 8px;
    }
    button:active { opacity: 0.8; }
    .success {
      display: none;
      text-align: center;
      padding: 20px;
    }
    .success h2 { color: #00E676; margin-bottom: 8px; }
    .error { color: #FF5252; font-size: 13px; margin-top: 12px; display: none; }
  </style>
</head>
<body>
  <div class="card">
    <div id="form">
      <h1>🔑 PlayTorrio</h1>
      <p>Enter your API key on your phone and it will be saved on your TV.</p>
      <label>Service</label>
      <select id="service">
        <option value="Premiumize">Premiumize</option>
        <option value="Real-Debrid">Real-Debrid</option>
        <option value="TorBox">TorBox</option>
        <option value="AllDebrid">AllDebrid</option>
        <option value="Debrid-Link">Debrid-Link</option>
        <option value="Jackett">Jackett</option>
        <option value="Prowlarr">Prowlarr</option>
        <option value="MDBlist">MDBlist</option>
      </select>
      <label>API Key</label>
      <input type="text" id="apikey" placeholder="Paste your API key here" autocomplete="off" />
      <button onclick="save()">Save to TV</button>
      <div class="error" id="error"></div>
    </div>
    <div class="success" id="success">
      <h2>✅ Saved!</h2>
      <p>API key saved on your TV. You can close this page.</p>
    </div>
  </div>
  <script>
    async function save() {
      const service = document.getElementById('service').value;
      const api_key = document.getElementById('apikey').value.trim();
      if (!api_key) {
        document.getElementById('error').style.display = 'block';
        document.getElementById('error').textContent = 'Please enter an API key';
        return;
      }
      try {
        const res = await fetch('/save', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({service, api_key})
        });
        const data = await res.json();
        if (data.status === 'ok') {
          document.getElementById('form').style.display = 'none';
          document.getElementById('success').style.display = 'block';
        } else {
          document.getElementById('error').style.display = 'block';
          document.getElementById('error').textContent = data.error || 'Save failed';
        }
      } catch (e) {
        document.getElementById('error').style.display = 'block';
        document.getElementById('error').textContent = 'Network error: ' + e.message;
      }
    }
  </script>
</body>
</html>''';
}


