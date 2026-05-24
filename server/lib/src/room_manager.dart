import 'dart:async';
import 'dart:collection';

import 'game_room.dart';

/// Manages all active game rooms.
///
/// Rooms are created on demand when a player issues [joinRoom] with an
/// unknown [roomId].  Rooms are reaped after [_kRoomTimeout] of inactivity.
class RoomManager {
  RoomManager();

  static const _kRoomTimeout = Duration(hours: 2);

  /// Hard cap on concurrent rooms to prevent memory-exhaustion DoS.
  static const _kMaxRooms = 50;

  final _rooms = HashMap<String, GameRoom>();
  final _reapTimers = HashMap<String, Timer>();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns the room for [roomId], creating it if it doesn't exist.
  ///
  /// Returns null if the server has hit [_kMaxRooms] and the room is new.
  GameRoom? getOrCreate(String roomId, {required int boardSize}) {
    if (_rooms.containsKey(roomId)) return _rooms[roomId];
    if (_rooms.length >= _kMaxRooms) return null; // server at capacity
    final room = GameRoom(
      id: roomId,
      boardSize: boardSize,
      onEmpty: () => _reap(roomId),
    );
    _rooms[roomId] = room;
    _scheduleReap(roomId);
    return room;
  }

  GameRoom? getRoom(String roomId) => _rooms[roomId];

  int get activeRoomCount => _rooms.length;

  /// All rooms visible in the Wired lobby browser:
  /// - Not-yet-started rooms open for new players.
  /// - Started rooms where a player disconnected and has an active reconnect
  ///   grace window (so they can find and rejoin the game).
  List<Map<String, dynamic>> get openRooms => _rooms.values
      .where((r) => (!r.isStarted && !r.isEmpty) || r.hasReconnectSlots)
      .map((r) => {
            'code': r.id,
            'boardSize': r.boardSize,
            'playerCount': r.playerCount,
            'maxPlayers': r.maxPlayers,
            'reconnecting': r.hasReconnectSlots,
            if (r.hostLat != null) 'lat': r.hostLat,
            if (r.hostLon != null) 'lon': r.hostLon,
            if (r.hostCity != null && r.hostCity!.isNotEmpty) 'city': r.hostCity,
            if (r.hostCountry != null && r.hostCountry!.isNotEmpty)
              'country': r.hostCountry,
          })
      .toList();

  /// Stores the geolocation result for the host of [roomId].
  void setRoomGeo(String roomId,
      {required double lat,
      required double lon,
      required String city,
      required String country}) {
    final room = _rooms[roomId];
    if (room == null) return;
    room.hostLat = lat;
    room.hostLon = lon;
    room.hostCity = city;
    room.hostCountry = country;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void _reap(String roomId) {
    _reapTimers.remove(roomId)?.cancel();
    final room = _rooms.remove(roomId);
    room?.dispose(); // cancel pending reconnect + turn timers
    print('[RoomManager] reaped room $roomId (${_rooms.length} remaining)');
  }

  void _scheduleReap(String roomId) {
    _reapTimers[roomId]?.cancel();
    _reapTimers[roomId] = Timer(_kRoomTimeout, () {
      _reapTimers.remove(roomId);
      final room = _rooms[roomId];
      if (room != null && room.isEmpty) _reap(roomId);
    });
  }
}
