import 'attack.dart';
import 'board.dart';
import 'player.dart';
import 'position.dart';
import 'stone_color.dart';

// ── Phase enum ────────────────────────────────────────────────────────────

enum GamePhase {
  /// Room created, waiting for minimum players to join.
  lobby,

  /// Active player must place a stone or pass.
  placement,

  /// Active player may optionally spend subnets on attacks.
  /// After resolving (or skipping), the turn advances.
  attack,

  /// Both/all players have passed consecutively; dead-stone agreement needed.
  scoring,

  /// Game over, final scores computed.
  finished,

  /// BACKDOOR hijack: the hijacker places a stone on behalf of the victim
  /// (using the victim's colour).  [currentPlayerIndex] points to the hijacker.
  /// The hijacker already placed their own stone during their normal turn.
  hijackedVictimPlacement,
}

// ── GameState ─────────────────────────────────────────────────────────────

/// The complete, serialisable state of one GoHackMe game.
///
/// All fields are immutable; mutations produce a new [GameState] via
/// [copyWith].
class GameState {
  // Board
  final Board board;

  /// Board hash history (oldest first) used for superko detection.
  ///
  /// Stores [Board.zobristHash] (a 62-bit Zobrist hash) after every completed
  /// placement.  Collision probability is ≈ 1/2^62 per comparison — negligible
  /// for any real game.  Hashes are never transmitted over the network; they
  /// stay on the authority device only.
  final List<int> boardHashes;

  // Players
  final List<Player> players;

  /// Index into [players] for the current active player.
  final int currentPlayerIndex;

  // Resources – keyed by [Player.id]
  final Map<String, int> subnets;
  final Map<String, int> captureCount;

  /// Number of PATCH shields stacked by each player.
  /// Each PATCH use increments by 1; each blocked attack decrements by 1.
  final Map<String, int> patchShields;

  /// Backdoor state: maps a victim player ID to the attacker who backdoored
  /// them.  Null means no active backdoor on that player.  At most one
  /// backdoor per victim at a time (no stacking).
  final Map<String, String?> backdoorBy;

  // Turn tracking
  final int turnNumber;
  final int consecutivePasses;
  final GamePhase phase;

  /// Active effects applied by the attack system.
  final List<ActiveEffect> activeEffects;

  const GameState({
    required this.board,
    required this.boardHashes,
    required this.players,
    required this.currentPlayerIndex,
    required this.subnets,
    required this.captureCount,
    required this.patchShields,
    required this.backdoorBy,
    required this.turnNumber,
    required this.consecutivePasses,
    required this.phase,
    required this.activeEffects,
  });

  // ── Convenience getters ───────────────────────────────────────────────────

  Player get currentPlayer => players[currentPlayerIndex];

  String get currentPlayerId => currentPlayer.id;

  StoneColor currentPlayerColor(String playerId) {
    final idx = players.indexWhere((p) => p.id == playerId);
    if (idx < 0) return StoneColor.p1; // fallback: player not in this game
    return StoneColor.fromIndex(idx);
  }

  int subnetsOf(String playerId) => subnets[playerId] ?? 0;
  int capturesOf(String playerId) => captureCount[playerId] ?? 0;

  bool hasEffect(String playerId, AttackType type) => activeEffects.any(
        (e) => e.targetPlayerId == playerId && e.type == type,
      );

  // ── Factory: new game ─────────────────────────────────────────────────────

  factory GameState.newGame({
    required List<Player> players,
    required int boardSize,
    int initialSubnets = 0,
  }) {
    if (players.length < 2 || players.length > 4) {
      throw ArgumentError(
          'GoHackMe requires 2–4 players, got ${players.length}');
    }
    return GameState(
      board: Board(size: boardSize),
      boardHashes: const [],
      players: players,
      currentPlayerIndex: 0,
      subnets: {for (final p in players) p.id: initialSubnets},
      captureCount: {for (final p in players) p.id: 0},
      patchShields: {for (final p in players) p.id: 0},
      backdoorBy: {for (final p in players) p.id: null},
      turnNumber: 1,
      consecutivePasses: 0,
      phase: GamePhase.attack,
      activeEffects: const [],
    );
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  GameState copyWith({
    Board? board,
    List<int>? boardHashes,
    List<Player>? players,
    int? currentPlayerIndex,
    Map<String, int>? subnets,
    Map<String, int>? captureCount,
    Map<String, int>? patchShields,
    Map<String, String?>? backdoorBy,
    int? turnNumber,
    int? consecutivePasses,
    GamePhase? phase,
    List<ActiveEffect>? activeEffects,
  }) =>
      GameState(
        board: board ?? this.board,
        boardHashes: boardHashes ?? this.boardHashes,
        players: players ?? this.players,
        currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
        subnets: subnets ?? this.subnets,
        captureCount: captureCount ?? this.captureCount,
        patchShields: patchShields ?? this.patchShields,
        backdoorBy: backdoorBy ?? this.backdoorBy,
        turnNumber: turnNumber ?? this.turnNumber,
        consecutivePasses: consecutivePasses ?? this.consecutivePasses,
        phase: phase ?? this.phase,
        activeEffects: activeEffects ?? this.activeEffects,
      );

  // ── JSON ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'board': {
          'size': board.size,
          'stones': board.stones.map(
            (pos, color) => MapEntry('${pos.x},${pos.y}', color.name),
          ),
        },
        'players': players.map((p) => p.toJson()).toList(),
        'currentPlayerIndex': currentPlayerIndex,
        'subnets': subnets,
        'captureCount': captureCount,
        'patchShields': patchShields,
        'backdoorBy': backdoorBy,
        'phase': phase.name,
        'turnNumber': turnNumber,
        'consecutivePasses': consecutivePasses,
        'activeEffects': activeEffects.map((e) => e.toJson()).toList(),
      };

  factory GameState.fromJson(Map<String, dynamic> json) {
    final boardJson = json['board'] as Map<String, dynamic>;
    final boardSize = boardJson['size'] as int;
    final stonesRaw = boardJson['stones'] as Map<String, dynamic>;
    final stones = <Position, StoneColor>{};
    for (final entry in stonesRaw.entries) {
      final parts = entry.key.split(',');
      final pos = Position(int.parse(parts[0]), int.parse(parts[1]));
      stones[pos] = StoneColor.values.byName(entry.value as String);
    }

    final boardHashes = (json['boardHashes'] as List<dynamic>?)
        ?.map((h) => h as int)
        .toList() ??
        const <int>[];

    return GameState(
      board: Board(size: boardSize, stones: stones),
      boardHashes: boardHashes,
      players:
          (json['players'] as List).map((p) => Player.fromJson(p as Map<String, dynamic>)).toList(),
      currentPlayerIndex: json['currentPlayerIndex'] as int,
      subnets: Map<String, int>.from(json['subnets'] as Map),
      captureCount: Map<String, int>.from(json['captureCount'] as Map),
      patchShields: Map<String, int>.from((json['patchShields'] as Map?) ?? {}),
      backdoorBy: (json['backdoorBy'] as Map?)?.map(
            (k, v) => MapEntry(k as String, v as String?),
          ) ??
          {},
      turnNumber: json['turnNumber'] as int? ?? 1,
      consecutivePasses: json['consecutivePasses'] as int? ?? 0,
      phase: GamePhase.values.byName(json['phase'] as String),
      activeEffects: (json['activeEffects'] as List)
          .map((e) => ActiveEffect.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
