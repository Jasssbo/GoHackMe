import 'dart:math';

import '../models/attack.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/position.dart';
import '../models/stone_color.dart';
import 'go_rules.dart';
import 'scorer.dart';

// ── Difficulty ────────────────────────────────────────────────────────────

/// How smart the local bot plays.
enum BotDifficulty {
  /// Picks any random legal move (or passes).
  beginner,

  /// Heuristic priority: capture atari → save own atari → avoid self-atari → random.
  intermediate,

  /// Territory-influence evaluation: scores each candidate move by the change
  /// in controlled empty intersections; also uses a smarter attack selection
  /// that considers PATCH, TROJAN, and BACKDOOR in addition to DDOS.
  advanced,
}

// ── BotPlayer ─────────────────────────────────────────────────────────────

/// Pure-function bot that selects moves for a local single-player game.
///
/// All methods are static and side-effect free.  The [Random] instance must
/// be supplied by the caller so that tests can seed it deterministically.
class BotPlayer {
  BotPlayer._();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the [Position] the bot wants to play, or null to pass.
  ///
  /// Runs synchronously and is fast enough for boards up to 19×19 without
  /// needing an isolate.
  static Position? pickMove(
    GameState state,
    String botPlayerId,
    BotDifficulty difficulty, {
    Random? rng,
  }) {
    final rand = rng ?? Random();
    final legal = _legalMoves(state, botPlayerId);

    if (legal.isEmpty) return null; // forced pass

    switch (difficulty) {
      case BotDifficulty.beginner:
        return _pickRandom(legal, rand);

      case BotDifficulty.intermediate:
        return _pickHeuristic(state, botPlayerId, legal, rand);

      case BotDifficulty.advanced:
        return _pickAdvanced(state, botPlayerId, legal, rand);
    }
  }

  /// Returns the [AttackAction] the bot wants to perform, or null to skip.
  ///
  /// At beginner level the bot always skips.
  /// At intermediate level it launches a DDOS if it can afford it and the
  /// player has more subnets than the bot.
  static AttackAction? pickAttack(
    GameState state,
    String botPlayerId,
    String targetPlayerId,
    BotDifficulty difficulty, {
    Random? rng,
  }) {
    if (difficulty == BotDifficulty.beginner) return null;

    if (difficulty == BotDifficulty.advanced) {
      return _pickAdvancedAttack(state, botPlayerId, targetPlayerId,
          rng ?? Random());
    }

    // intermediate: DDOS if target is richer
    final botSubnets = state.subnetsOf(botPlayerId);
    final ddosCost = AttackCard.forType(AttackType.ddos).subnetCost;

    if (botSubnets >= ddosCost) {
      return AttackAction(
        type: AttackType.ddos,
        attackerPlayerId: botPlayerId,
        targetPlayerId: targetPlayerId,
      );
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Legal move generation
  // ─────────────────────────────────────────────────────────────────────────

  /// Enumerates all intersections and returns those where a placement is valid.
  static List<Position> _legalMoves(GameState state, String playerId) {
    final size = state.board.size;
    final playerIndex = state.players.indexWhere((p) => p.id == playerId);
    final color = StoneColor.fromIndex(playerIndex);

    final legal = <Position>[];
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final pos = Position(x, y);
        if (state.board.at(pos) != null) continue; // occupied
        final err = GoRules.validatePlacement(
          state.board,
          pos,
          color,
          state.boardHashes,
        );
        if (err == null) legal.add(pos);
      }
    }
    return legal;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Difficulty: beginner
  // ─────────────────────────────────────────────────────────────────────────

  static Position _pickRandom(List<Position> legal, Random rand) =>
      legal[rand.nextInt(legal.length)];

  // ─────────────────────────────────────────────────────────────────────────
  // Difficulty: intermediate  (priority-based heuristics)
  //
  // Priorities based on classical computer Go heuristics (Sensei's Library):
  //   1. Capture – play the last liberty of any opponent group in atari
  //   2. Save    – play the last liberty of an own group in atari
  //   3. Influence – avoid moves immediately adjacent to the edge (first pass)
  //   4. Avoid self-atari – filter moves that leave our group with 0 liberties
  //   5. Center-biased random fallback
  // ─────────────────────────────────────────────────────────────────────────

  static Position _pickHeuristic(
    GameState state,
    String botPlayerId,
    List<Position> legal,
    Random rand,
  ) {
    final playerIndex = state.players.indexWhere((p) => p.id == botPlayerId);
    final botColor = StoneColor.fromIndex(playerIndex);

    // ── 1. Capture: find moves that complete a capture ──────────────────
    final captureMoves = _captureMoves(state.board, botColor, legal);
    if (captureMoves.isNotEmpty) {
      return _pickRandom(captureMoves, rand);
    }

    // ── 2. Save own groups in atari ──────────────────────────────────
    final saveMoves = _saveMoves(state.board, botColor, legal);
    if (saveMoves.isNotEmpty) {
      return _pickRandom(saveMoves, rand);
    }

    // ── 3. Filter self-atari moves (unless no other option) ─────────────
    final nonSelfAtari = legal
        .where((pos) => !_isSelfAtari(state.board, pos, botColor))
        .toList();
    final candidates = nonSelfAtari.isNotEmpty ? nonSelfAtari : legal;

    // ── 4. Center-biased random ─────────────────────────────────────────
    return _centerBiasedRandom(candidates, state.board.size, rand);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Heuristic helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns all moves in [legal] that would capture at least one opponent group.
  static List<Position> _captureMoves(
    Board board,
    StoneColor botColor,
    List<Position> legal,
  ) {
    final result = <Position>[];
    for (final pos in legal) {
      final boardAfter = board.place(pos, botColor);
      final (_, captured) =
          GoRules.applyCapturesAfterPlacement(boardAfter, pos, botColor);
      if (captured.isNotEmpty) result.add(pos);
    }
    return result;
  }

  /// Returns all moves in [legal] that rescue an own group currently in atari
  /// (1 liberty) by giving it at least 2 liberties after the placement.
  static List<Position> _saveMoves(
    Board board,
    StoneColor botColor,
    List<Position> legal,
  ) =>
      legal.where((pos) => _isSavingMove(board, pos, botColor)).toList();

  static bool _isSavingMove(Board board, Position pos, StoneColor botColor) {
    // Check if any adjacent own group is in atari (1 liberty)
    for (final neighbor in board.neighborsOf(pos)) {
      if (board.at(neighbor) != botColor) continue;
      final group = GoRules.findGroup(board, neighbor);
      if (GoRules.libertiesOf(board, group).length == 1) {
        // Playing at pos would add a liberty (pos is currently empty)
        // Simulate and check the group has >= 2 liberties after
        final boardAfter = board.place(pos, botColor);
        final mergedGroup = GoRules.findGroup(boardAfter, pos);
        if (GoRules.libertiesOf(boardAfter, mergedGroup).length >= 2) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns true if placing at [pos] immediately leaves the resulting group
  /// with zero liberties (self-atari / suicide that isn't a capture).
  static bool _isSelfAtari(Board board, Position pos, StoneColor botColor) {
    final boardAfter = board.place(pos, botColor);
    // Apply any captures that would result from the placement
    final (boardFinal, _) =
        GoRules.applyCapturesAfterPlacement(boardAfter, pos, botColor);
    final group = GoRules.findGroup(boardFinal, pos);
    return GoRules.libertiesOf(boardFinal, group).isEmpty;
  }

  /// Picks a random move but gives higher weight to intersections closer to
  /// the centre of the board (encourages influence plays over edge clinging).
  static Position _centerBiasedRandom(
    List<Position> candidates,
    int boardSize,
    Random rand,
  ) {
    if (candidates.isEmpty) throw StateError('no candidates');

    // Weight = max(1, boardSize/2 - distance_to_center)
    final cx = (boardSize - 1) / 2.0;
    final cy = (boardSize - 1) / 2.0;

    final weights = candidates.map((pos) {
      final dist = sqrt(pow(pos.x - cx, 2) + pow(pos.y - cy, 2));
      return (boardSize / 2.0 - dist).clamp(1.0, boardSize / 2.0);
    }).toList();

    final totalWeight = weights.fold(0.0, (a, b) => a + b);
    var pick = rand.nextDouble() * totalWeight;

    for (int i = 0; i < candidates.length; i++) {
      pick -= weights[i];
      if (pick <= 0) return candidates[i];
    }
    return candidates.last;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Difficulty: advanced  (territory-influence evaluation)
  //
  // For each candidate move (up to 30 sampled randomly to keep it fast):
  //   score = bot_territory_after - bot_territory_before + captured * 2
  // Falls back to the intermediate heuristics for captures / saves so the
  // bot never misses obvious tactical responses.
  // ─────────────────────────────────────────────────────────────────────────

  static Position _pickAdvanced(
    GameState state,
    String botPlayerId,
    List<Position> legal,
    Random rand,
  ) {
    final playerIndex = state.players.indexWhere((p) => p.id == botPlayerId);
    final botColor = StoneColor.fromIndex(playerIndex);

    // Keep capture / save as top priority so advanced never blunders tactically.
    final captureMoves = _captureMoves(state.board, botColor, legal);
    if (captureMoves.isNotEmpty) return _pickRandom(captureMoves, rand);

    final saveMoves = _saveMoves(state.board, botColor, legal);
    if (saveMoves.isNotEmpty) return _pickRandom(saveMoves, rand);

    final candidates = legal
        .where((pos) => !_isSelfAtari(state.board, pos, botColor))
        .toList();
    if (candidates.isEmpty) return _pickRandom(legal, rand);

    return _pickByTerritoryScore(state.board, botColor, candidates, rand);
  }

  /// Scores each sampled candidate by territory gain, picks the best.
  static Position _pickByTerritoryScore(
    Board board,
    StoneColor botColor,
    List<Position> candidates,
    Random rand,
  ) {
    // Sample at most 30 to keep evaluation O(sample × board) not O(n²).
    final sample = candidates.length > 30
        ? (List<Position>.from(candidates)..shuffle(rand)).take(30).toList()
        : candidates;

    // Baseline territory owned by the bot.
    final baseline = Scorer.territoryRegions(board);
    final baseScore =
        baseline.values.where((c) => c == botColor).length;

    var bestScore = -1;
    final bestMoves = <Position>[];

    for (final pos in sample) {
      final boardAfter = board.place(pos, botColor);
      final (boardFinal, captured) =
          GoRules.applyCapturesAfterPlacement(boardAfter, pos, botColor);
      final regions = Scorer.territoryRegions(boardFinal);
      final score = regions.values.where((c) => c == botColor).length
          - baseScore
          + captured.length * 2; // captures count double (removes enemy + gains territory)

      if (score > bestScore) {
        bestScore = score;
        bestMoves
          ..clear()
          ..add(pos);
      } else if (score == bestScore) {
        bestMoves.add(pos);
      }
    }

    return _pickRandom(bestMoves, rand);
  }

  /// Advanced attack selection:
  ///   1. PATCH  – self-heal if under any debuff and can afford it.
  ///   2. TROJAN – steal subnets if target is richer than us.
  ///   3. BACKDOOR – free second placement when game is close (≤ board/3 stones apart).
  ///   4. DDOS   – fallback crowd-control.
  ///   5. null   – skip (insufficient subnets).
  static AttackAction? _pickAdvancedAttack(
    GameState state,
    String botPlayerId,
    String targetPlayerId,
    Random rand,
  ) {
    final botSubnets    = state.subnetsOf(botPlayerId);
    final targetSubnets = state.subnetsOf(targetPlayerId);

    // 1. PATCH: remove any active debuff on ourselves.
    const patchCost = 3; // AttackCard for patch
    final isDebuffed = state.hasEffect(botPlayerId, AttackType.ddos) ||
        state.hasEffect(botPlayerId, AttackType.psyche) ||
        state.hasEffect(botPlayerId, AttackType.mitm);
    if (isDebuffed && botSubnets >= patchCost) {
      return AttackAction(
        type: AttackType.patch,
        attackerPlayerId: botPlayerId,
        targetPlayerId: botPlayerId,
      );
    }

    // 2. TROJAN: target has more subnets — steal half.
    const trojanCost = 5;
    if (botSubnets >= trojanCost && targetSubnets > botSubnets) {
      return AttackAction(
        type: AttackType.trojan,
        attackerPlayerId: botPlayerId,
        targetPlayerId: targetPlayerId,
      );
    }

    // 3. BACKDOOR: close game → place two stones for tempo advantage.
    const backdoorCost = 3;
    final botColor    = state.currentPlayerColor(botPlayerId);
    final targetColor = state.currentPlayerColor(targetPlayerId);
    final botStones = state.board.stones.values
        .where((c) => c == botColor)
        .length;
    final targetStones = state.board.stones.values
        .where((c) => c == targetColor)
        .length;
    if (botSubnets >= backdoorCost &&
        (targetStones - botStones).abs() <= state.board.size ~/ 3) {
      return AttackAction(
        type: AttackType.backdoor,
        attackerPlayerId: botPlayerId,
        targetPlayerId: botPlayerId,
      );
    }

    // 4. DDOS fallback.
    const ddosCost = 7;
    if (botSubnets >= ddosCost) {
      return AttackAction(
        type: AttackType.ddos,
        attackerPlayerId: botPlayerId,
        targetPlayerId: targetPlayerId,
      );
    }

    return null;
  }
}
