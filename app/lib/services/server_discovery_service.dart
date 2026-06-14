import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// UDP port that matches the server's [kDiscoveryPort].
const _kDiscoveryPort = 8081;
const _kProbe = 'GOHACKME_DISCOVER';
const _kReplyPrefix = 'GOHACKME_SERVER:';

/// Shared HMAC key — must match [_kDiscoveryHmacKey] in the server package.
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

/// Scans the local network for a running GoHackMe server.
///
/// Sends a UDP broadcast probe and waits up to [timeout] for a response.
///
/// Returns a `ws://` URL string on success, or `null` if nothing was found.
///
/// How it works:
///   1. Bind a UDP socket on a random port (port 0 = OS picks one).
///   2. Broadcast `GOHACKME_DISCOVER` to 255.255.255.255:<_kDiscoveryPort>.
///   3. Server receives it and replies directly (unicast) to our socket.
///   4. Parse the reply and return the WS URL.
///
/// Using unicast replies means the client does NOT need to receive
/// broadcasts — only the server does. This improves Android compatibility
/// where broadcast reception is often filtered.
Future<String?> discoverServer({
  Duration timeout = const Duration(seconds: 3),
}) async {
  RawDatagramSocket socket;
  try {
    // Port 0 → OS assigns an ephemeral port; broadcastEnabled for sending.
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  } catch (_) {
    return null;
  }
  socket.broadcastEnabled = true;

  final completer = Completer<String?>();
  StreamSubscription<RawSocketEvent>? sub;

  sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;

    final msg = String.fromCharCodes(dg.data).trim();
    if (!msg.startsWith(_kReplyPrefix) || completer.isCompleted) return;

    // Expected format: GOHACKME_SERVER:<port>:<16-hex-hmac>
    // Reject replies that lack a valid HMAC to prevent casual LAN spoofing.
    final rest = msg.substring(_kReplyPrefix.length).trim();
    final lastColon = rest.lastIndexOf(':');
    if (lastColon < 1) return; // malformed or unauthenticated reply
    final portStr = rest.substring(0, lastColon).trim();
    final receivedTag = rest.substring(lastColon + 1).trim();
    if (receivedTag != _discoveryHmacTag('$_kReplyPrefix$portStr')) return;
    completer.complete('ws://${dg.address.address}:$portStr/ws');
  });

  // Send the broadcast probe.
  try {
    socket.send(
      _kProbe.codeUnits,
      InternetAddress('255.255.255.255'),
      _kDiscoveryPort,
    );
  } catch (_) {
    // Broadcast may be restricted on some environments; still wait in case
    // the server is sending periodic proactive beacons (future enhancement).
  }

  // Timeout: resolve with null if no server replied in time.
  Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(null);
  });

  final result = await completer.future;
  await sub.cancel();
  socket.close();
  return result;
}
