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

  /// All rooms that are waiting for players (not yet started, not empty).
  /// Used by the Wired lobby browser.
  List<Map<String, dynamic>> get openRooms => _rooms.values
      .where((r) => !r.isStarted && !r.isEmpty)
      .map((r) => {
            'code': r.id,
            'boardSize': r.boardSize,
            'playerCount': r.playerCount,
            'maxPlayers': r.maxPlayers,
          })
      .toList();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void _reap(String roomId) {
    _rooms.remove(roomId);
    print('[RoomManager] reaped room $roomId (${_rooms.length} remaining)');
  }

  void _scheduleReap(String roomId) {
    Timer(_kRoomTimeout, () {
      final room = _rooms[roomId];
      if (room != null && room.isEmpty) _reap(roomId);
    });
  }
}
