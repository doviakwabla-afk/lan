import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const LanBridgeApp());

class LanBridgeApp extends StatelessWidget {
  const LanBridgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LanBridge',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF356AE6)), useMaterial3: true),
        home: const HomePage(),
      );
}

class Peer {
  const Peer({required this.name, required this.address, required this.port});
  final String name;
  final InternetAddress address;
  final int port;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const discoveryPort = 38941;
  static const httpPort = 38942;
  final List<Peer> _peers = [];
  final List<String> _events = [];
  RawDatagramSocket? _discoverySocket;
  HttpServer? _server;
  Timer? _announceTimer;
  bool _receiving = false;
  bool _scanning = false;
  String _status = 'Ready to connect on your local network';
  String _pairCode = '';
  String _deviceName = Platform.localHostname;

  @override
  void dispose() {
    _announceTimer?.cancel();
    _discoverySocket?.close();
    _server?.close(force: true);
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, '${TimeOfDay.now().format(context)}  $message');
      if (_events.length > 30) _events.removeLast();
    });
  }

  Future<void> _discover() async {
    if (_scanning) return;
    setState(() { _scanning = true; _status = 'Searching this local network…'; _peers.clear(); });
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        try {
          final obj = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
          if (obj['kind'] != 'lanbridge-peer' || obj['name'] == null || obj['port'] == null) return;
          final peer = Peer(name: obj['name'].toString(), address: datagram.address, port: (obj['port'] as num).toInt());
          if (peer.address.address == _localIPv4()) return;
          if (mounted && !_peers.any((p) => p.address.address == peer.address.address && p.port == peer.port)) {
            setState(() { _peers.add(peer); _status = '${_peers.length} device(s) found'; });
          }
        } catch (_) { /* Ignore malformed LAN discovery packets. */ }
      });
      socket.send(utf8.encode(jsonEncode({'kind': 'lanbridge-discover'})), InternetAddress('255.255.255.255'), discoveryPort);
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted && _peers.isEmpty) setState(() => _status = 'No devices found. Ensure both devices use the same Wi-Fi/LAN.');
    } on SocketException catch (e) {
      if (mounted) setState(() => _status = 'Network discovery failed: ${e.message}');
    } finally {
      socket?.close();
      if (mounted) setState(() => _scanning = false);
    }
  }

  String? _localIPv4() {
    // A best-effort check only; multi-interface devices may have more than one address.
    return null;
  }

  Future<void> _toggleReceive(bool enabled) async {
    if (!enabled) {
      _announceTimer?.cancel();
      await _server?.close(force: true);
      _server = null;
      _discoverySocket?.close();
      _discoverySocket = null;
      if (mounted) setState(() { _receiving = false; _status = 'Receive mode stopped'; });
      _log('Receive mode stopped');
      return;
    }
    try {
      final code = (100000 + Random.secure().nextInt(900000)).toString();
      final server = await HttpServer.bind(InternetAddress.anyIPv4, httpPort, shared: true);
      _server = server;
      _pairCode = code;
      _deviceName = await _askDeviceName() ?? Platform.localHostname;
      server.listen(_handleHttpRequest, onError: (Object e) => _log('Server error: $e'));

      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
      udp.broadcastEnabled = true;
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = udp.receive();
        if (d == null) return;
        try {
          final message = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
          if (message['kind'] == 'lanbridge-discover') {
            udp.send(utf8.encode(jsonEncode({'kind': 'lanbridge-peer', 'name': _deviceName, 'port': httpPort})), d.address, d.port);
          }
        } catch (_) {}
      });
      _discoverySocket = udp;
      if (mounted) setState(() { _receiving = true; _status = 'Receive mode is active on port $httpPort'; });
      _log('Receive mode enabled. Share the pairing code only with the intended sender.');
    } on SocketException catch (e) {
      if (mounted) setState(() => _status = 'Could not start receive mode: ${e.message}');
    }
  }

  Future<String?> _askDeviceName() async {
    final controller = TextEditingController(text: Platform.localHostname);
    return showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Name this device'),
      content: TextField(controller: controller, maxLength: 40, decoration: const InputDecoration(labelText: 'Device name')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim().isEmpty ? Platform.localHostname : controller.text.trim()), child: const Text('Continue'))],
    ));
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    // This starter requires the receiver session code for each transfer.
    // HTTP is not encrypted; use only on a trusted test LAN until TLS/pairing is implemented.
    if (request.method == 'GET' && request.uri.path == '/health') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'app': 'LanBridge', 'name': _deviceName}));
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/upload') {
      final supplied = request.headers.value('x-pair-code') ?? '';
      if (_pairCode.isEmpty || supplied != _pairCode) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write('Pairing code required or incorrect');
        await request.response.close();
        return;
      }
      final encodedName = request.headers.value('x-file-name') ?? 'received-file';
      String rawName;
      try { rawName = Uri.decodeComponent(encodedName); } catch (_) { rawName = 'received-file'; }
      final name = rawName.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'[^A-Za-z0-9._ ()-]'), '_');
      if (name.isEmpty || name == '.' || name == '..') {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Invalid filename');
        await request.response.close();
        return;
      }
      const maxBytes = 100 * 1024 * 1024;
      final contentLength = request.contentLength;
      if (contentLength < 0 || contentLength > maxBytes) {
        request.response.statusCode = HttpStatus.requestEntityTooLarge;
        request.response.write('Maximum supported file size is 100 MB');
        await request.response.close();
        return;
      }
      final directory = await getApplicationDocumentsDirectory();
      final receiveDir = Directory('${directory.path}${Platform.pathSeparator}LanBridge Received');
      await receiveDir.create(recursive: true);
      var destination = File('${receiveDir.path}${Platform.pathSeparator}$name');
      if (await destination.exists()) {
        final dot = name.lastIndexOf('.');
        final stem = dot > 0 ? name.substring(0, dot) : name;
        final ext = dot > 0 ? name.substring(dot) : '';
        destination = File('${receiveDir.path}${Platform.pathSeparator}$stem-${DateTime.now().millisecondsSinceEpoch}$ext');
      }
      final sink = destination.openWrite();
      var received = 0;
      try {
        await for (final chunk in request) {
          received += chunk.length;
          if (received > maxBytes) throw const HttpException('Upload exceeds size limit');
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        if (await destination.exists()) await destination.delete();
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Upload failed');
        await request.response.close();
        return;
      }
      _log('Received $name (${received} bytes)');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true, 'name': destination.uri.pathSegments.last, 'bytes': received}));
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<void> _sendFile(Peer peer) async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final file = File(path);
    final name = result.files.single.name;
    final codeController = TextEditingController();
    final code = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text('Send to ${peer.name}?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [Text('Selected: $name'), const SizedBox(height: 12), const Text('Enter the pairing code shown on the receiving device.'), TextField(controller: codeController, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: '6-digit pairing code'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, codeController.text.trim()), child: const Text('Send'))],
    ));
    if (code == null || code.length != 6) return;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri(scheme: 'http', host: peer.address.address, port: peer.port, path: '/upload'));
      request.headers.set('x-pair-code', code);
      request.headers.set('x-file-name', Uri.encodeComponent(name));
      request.headers.contentType = ContentType.binary;
      request.contentLength = await file.length();
      await request.addStream(file.openRead());
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log('Sent $name to ${peer.name}');
        if (mounted) setState(() => _status = 'Transfer completed: $name');
      } else {
        throw HttpException('Receiver rejected transfer (${response.statusCode}): $body');
      }
    } catch (e) {
      _log('Transfer failed: $e');
      if (mounted) setState(() => _status = 'Transfer failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 760;
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.swap_horiz_rounded), SizedBox(width: 10), Text('LanBridge')]), actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text(Platform.isWindows ? 'WINDOWS' : Platform.isAndroid ? 'ANDROID' : 'DESKTOP', style: Theme.of(context).textTheme.labelSmall)))]),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [Color(0xFF173A83), Color(0xFF356AE6)])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Share across your devices', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('Private, local-network file transfer — no cloud account required.', style: TextStyle(color: Colors.white70)), const SizedBox(height: 20), Wrap(spacing: 10, runSpacing: 10, children: [FilledButton.icon(onPressed: _scanning ? null : _discover, icon: const Icon(Icons.radar), label: Text(_scanning ? 'Searching…' : 'Find devices')), OutlinedButton.icon(onPressed: () => _toggleReceive(!_receiving), icon: Icon(_receiving ? Icons.stop_circle_outlined : Icons.download_rounded), label: Text(_receiving ? 'Stop receiving' : 'Enable receiving'))])]),
        const SizedBox(height: 16), Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Icon(_receiving ? Icons.wifi_tethering : Icons.info_outline, color: _receiving ? Colors.green : null), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)), if (_receiving) Text('Pairing code: $_pairCode  •  Share only with your intended sender', style: Theme.of(context).textTheme.bodySmall)]))]))),
        const SizedBox(height: 20),
        if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _peerPanel()), const SizedBox(width: 16), Expanded(child: _activityPanel())]) else Column(children: [_peerPanel(), const SizedBox(height: 16), _activityPanel()]),
        const SizedBox(height: 16), const Text('Security note: this starter uses unencrypted HTTP on the LAN. Use only on a trusted test network; do not send confidential files until TLS and explicit receiver approval are added.', style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
      ]))),
    );
  }

  Widget _peerPanel() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Nearby devices', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12), if (_peers.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Column(children: [Icon(Icons.devices_other, size: 42), SizedBox(height: 8), Text('No devices yet'), Text('Tap “Find devices” to scan your LAN.', textAlign: TextAlign.center)]))) else ..._peers.map((peer) => ListTile(leading: const CircleAvatar(child: Icon(Icons.devices)), title: Text(peer.name), subtitle: Text('${peer.address.address}:${peer.port}'), trailing: IconButton(tooltip: 'Send file', onPressed: () => _sendFile(peer), icon: const Icon(Icons.send_rounded))))])));

  Widget _activityPanel() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Recent activity', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12), if (_events.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Transfers and status messages will appear here.'))) else ..._events.map((event) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check_circle_outline, size: 18), const SizedBox(width: 8), Expanded(child: Text(event))])))])));
}
