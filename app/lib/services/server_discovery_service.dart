import 'dart:async';
import 'dart:io';

/// UDP port that matches the server's [kDiscoveryPort].
const _kDiscoveryPort = 8081;
const _kProbe = 'GOHACKME_DISCOVER';
const _kReplyPrefix = 'GOHACKME_SERVER:';

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
    if (msg.startsWith(_kReplyPrefix) && !completer.isCompleted) {
      final port = msg.substring(_kReplyPrefix.length).trim();
      completer.complete('ws://${dg.address.address}:$port/ws');
    }
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
