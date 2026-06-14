import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// UDP port used for LAN auto-discovery.
/// Must match [kDiscoveryPort] in the Flutter app.
const kDiscoveryPort = 8081;

/// Probe message the client broadcasts.
const _kProbe = 'GOHACKME_DISCOVER';

/// Reply prefix the server sends back.
const _kReplyPrefix = 'GOHACKME_SERVER:';

/// HMAC key shared with the Flutter client to authenticate discovery replies.
/// Baked into both binaries to prevent casual LAN spoofing — not a
/// cryptographic secret against a determined reverse-engineer.
const _kDiscoveryHmacKey = 'GOHACKME_DISCOVERY_v1';

/// Returns the first 8 bytes of HMAC-SHA256(payload) as a 16-char hex string.
String _discoveryHmacTag(String payload) {
  final mac = Hmac(sha256, utf8.encode(_kDiscoveryHmacKey));
  return mac
      .convert(utf8.encode(payload))
      .bytes
      .take(8)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Starts a UDP responder that lets Flutter clients auto-discover this server
/// on the local network without the user having to type an IP address.
///
/// Protocol (all UDP, port [kDiscoveryPort]):
///   Client → 255.255.255.255  : "GOHACKME_DISCOVER"
///   Server → client (unicast) : `GOHACKME_SERVER:<gamePort>`
///
/// The server responds directly (unicast) to the sender's address+port so
/// the client does not need to receive broadcasts itself — improving
/// compatibility with Android's multicast filtering.
Future<RawDatagramSocket?> startDiscoveryService(int gamePort) async {
  RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kDiscoveryPort,
    );
  } catch (e) {
    // Port already in use or permission denied — discovery is optional,
    // manual IP entry still works.
    print('[Discovery] Could not bind UDP :$kDiscoveryPort — $e');
    return null;
  }

  socket.broadcastEnabled = true;
  print('[Discovery] UDP auto-discovery on :$kDiscoveryPort');

  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;

    final msg = String.fromCharCodes(dg.data).trim();
    if (msg != _kProbe) return;

    // Respond directly to whoever sent the probe (unicast).
    // Reply format: GOHACKME_SERVER:<port>:<16-hex-hmac>
    // The HMAC covers the body (GOHACKME_SERVER:<port>) so clients can
    // reject spoofed replies from other LAN devices.
    final body = '$_kReplyPrefix$gamePort';
    final reply = '$body:${_discoveryHmacTag(body)}';
    socket.send(reply.codeUnits, dg.address, dg.port);
  });

  return socket;
}
