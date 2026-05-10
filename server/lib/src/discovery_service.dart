import 'dart:async';
import 'dart:io';

/// UDP port used for LAN auto-discovery.
/// Must match [kDiscoveryPort] in the Flutter app.
const kDiscoveryPort = 8081;

/// Probe message the client broadcasts.
const _kProbe = 'GOHACKME_DISCOVER';

/// Reply prefix the server sends back.
const _kReplyPrefix = 'GOHACKME_SERVER:';

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
    socket.send(
      '$_kReplyPrefix$gamePort'.codeUnits,
      dg.address,
      dg.port,
    );
  });

  return socket;
}
