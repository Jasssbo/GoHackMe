import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UDP port used for room beacon broadcasts.
const int kLanDiscoveryPort = 7778;

const String _kBeaconMagic = 'GOHACKME_LAN:';

// ── LanRoom ────────────────────────────────────────────────────────────────

/// A LAN room that was discovered via UDP beacon.
class LanRoom {
  final String roomCode;
  final InternetAddress hostAddress;
  final int tcpPort;
  final String hostName;
  final int boardSize;
  final int maxPlayers;
  final int currentPlayers;
  final DateTime lastSeen;

  const LanRoom({
    required this.roomCode,
    required this.hostAddress,
    required this.tcpPort,
    required this.hostName,
    required this.boardSize,
    required this.maxPlayers,
    required this.currentPlayers,
    required this.lastSeen,
  });

  LanRoom copyWith({int? currentPlayers, DateTime? lastSeen}) => LanRoom(
        roomCode: roomCode,
        hostAddress: hostAddress,
        tcpPort: tcpPort,
        hostName: hostName,
        boardSize: boardSize,
        maxPlayers: maxPlayers,
        currentPlayers: currentPlayers ?? this.currentPlayers,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  // Beacon payload format (pipe-separated, no spaces):
  // roomCode|tcpPort|hostName|boardSize|maxPlayers|currentPlayers
  String get _beaconPayload =>
      '$roomCode|$tcpPort|$hostName|$boardSize|$maxPlayers|$currentPlayers';

  static LanRoom? tryParse(String payload, InternetAddress sender) {
    try {
      final parts = payload.split('|');
      if (parts.length < 6) return null;
      return LanRoom(
        roomCode: parts[0],
        hostAddress: sender,
        tcpPort: int.parse(parts[1]),
        hostName: parts[2],
        boardSize: int.parse(parts[3]),
        maxPlayers: int.parse(parts[4]),
        currentPlayers: int.parse(parts[5]),
        lastSeen: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

// ── LanBeaconBroadcaster ───────────────────────────────────────────────────

/// Broadcasts a UDP beacon every 2 seconds so nearby devices can
/// discover this room.  Call [start] once, [updateRoom] whenever the
/// player count changes, and [stop] when the game starts or the host leaves.
class LanBeaconBroadcaster {
  RawDatagramSocket? _socket;
  Timer? _timer;
  LanRoom? _room;

  bool get isActive => _socket != null;

  Future<void> start(LanRoom room) async {
    _room = room;
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
    } catch (_) {
      return;
    }
    _send();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _send());
  }

  void updateRoom(LanRoom room) {
    _room = room;
  }

  void _send() {
    final s = _socket;
    final r = _room;
    if (s == null || r == null) return;
    final data = utf8.encode('$_kBeaconMagic${r._beaconPayload}');
    try {
      s.send(data, InternetAddress('255.255.255.255'), kLanDiscoveryPort);
    } catch (_) {}
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

// ── scanForLanRooms ────────────────────────────────────────────────────────

/// Listens for UDP beacons for [timeout] and returns all unique rooms found.
///
/// Returns an empty list if the socket cannot be bound (port in use, etc.).
Future<List<LanRoom>> scanForLanRooms({
  Duration timeout = const Duration(seconds: 3),
}) async {
  RawDatagramSocket socket;
  try {
    socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, kLanDiscoveryPort);
    socket.broadcastEnabled = true;
  } catch (_) {
    return const [];
  }

  final rooms = <String, LanRoom>{}; // roomCode → latest room
  final done = Completer<void>();

  Timer(timeout, () {
    if (!done.isCompleted) done.complete();
  });

  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    final msg = utf8.decode(dg.data, allowMalformed: true).trim();
    if (!msg.startsWith(_kBeaconMagic)) return;
    final payload = msg.substring(_kBeaconMagic.length);
    final room = LanRoom.tryParse(payload, dg.address);
    if (room != null) rooms[room.roomCode] = room;
  });

  await done.future;
  await sub.cancel();
  socket.close();

  return rooms.values.toList();
}
