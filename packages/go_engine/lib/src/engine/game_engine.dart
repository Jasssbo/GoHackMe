import '../models/attack.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/position.dart';
import '../models/stone_color.dart';
import 'attack_system.dart';
import 'go_rules.dart';
import 'scorer.dart';

// ── Action result sealed type ─────────────────────────────────────────────

sealed class ActionResult {
  const ActionResult();
}

class ActionSuccess extends ActionResult {
  final GameState newState;

  /// Optional server-log message (e.g. "CAPTURED 3 stones").
  final String? logMessage;

  const ActionSuccess(this.newState, {this.logMessage});
}

class ActionFailure extends ActionResult {
  final String reason;
  const ActionFailure(this.reason);
}

// ── GameEngine ────────────────────────────────────────────────────────────

/// The main authoritative game loop.
///
/// All methods are static and pure.  The [GameState] is never mutated
/// in-place; every operation returns a new one wrapped in [ActionResult].
///
/// Intended to be called by the server on each client action, and also
/// by the Flutter app for optimistic local prediction.
class GameEngine {
  GameEngine._();

  // ── Place stone ───────────────────────────────────────────────────────────

  /// Processes a stone-placement request from [playerId] at [pos].
  static ActionResult placeStone(
    GameState state,
    String playerId,
    Position pos,
  ) {
    // ── Hijacked turn – hijacker places the victim's stone ─────────────────
    if (state.phase == GamePhase.hijackedVictimPlacement) {
      return _placeHijacked(state, playerId, pos);
    }

    // ── Normal placement ──────────────────────────────────────────────────
    if (state.phase != GamePhase.attack) {
      return const ActionFailure('NOT_YOUR_TURN');
    }
    if (state.currentPlayerId != playerId) {
      return const ActionFailure('NOT_YOUR_TURN');
    }

    // Check DDOS effect
    if (state.hasEffect(playerId, AttackType.ddos)) {
      return const ActionFailure('DDOS_ACTIVE: your placement is blocked');
    }

    final playerIndex = state.players.indexWhere((p) => p.id == playerId);
    final color = StoneColor.fromIndex(playerIndex);

    // Validate Go rules
    final error = GoRules.validatePlacement(
      state.board,
      pos,
      color,
      state.boardHashes,
    );
    if (error != null) return ActionFailure(error);

    return _applyPlacement(state, playerId, playerIndex, pos, color);
  }

  /// Hijacked turn: [playerId] (the hijacker) places a stone using the
  /// victim's colour.  The hijacker already placed their own stone during
  /// their normal attack phase; this is the second stone they control.
  static ActionResult _placeHijacked(
    GameState state,
    String playerId, // the hijacker
    Position pos,
  ) {
    if (state.currentPlayerId != playerId) {
      return const ActionFailure('NOT_YOUR_TURN');
    }

    // Find which victim this hijacker is controlling via backdoorBy.
    // victimId = the player whose turn was hijacked.
    String? victimId;
    for (final entry in state.backdoorBy.entries) {
      if (entry.value == playerId) {
        victimId = entry.key;
        break;
      }
    }
    if (victimId == null) return const ActionFailure('NO_HIJACK_EFFECT_FOUND');

    final victimIdx = state.players.indexWhere((p) => p.id == victimId);
    final color = StoneColor.fromIndex(victimIdx);

    // Validate Go rules using the victim’s colour.
    final error = GoRules.validatePlacement(
      state.board,
      pos,
      color,
      state.boardHashes,
    );
    if (error != null) return ActionFailure(error);

    // Apply the stone placement and captures.
    final (boardAfterMove, capturedPositions) =
        GoRules.applyPlacement(state.board, pos, color);

    // Handle honeypot captures.
    final (finalBoard, honeypotLog, honeypotBonusCaptures) =
        _resolveHoneypots(state, boardAfterMove, capturedPositions);

    final captureCount = capturedPositions.length;
    final earned = Scorer.subnetsForPlacement(finalBoard, pos, captureCount);

    // Subnets and captures are credited to the hijacker (they control the stone).
    final newCaptures = Map<String, int>.from(state.captureCount);
    newCaptures[playerId] = (newCaptures[playerId] ?? 0) + captureCount;

    final newSubnets = Map<String, int>.from(state.subnets);
    newSubnets[playerId] = (newSubnets[playerId] ?? 0) + earned;
    // Credit honeypot-owner bonus captures.
    for (final entry in honeypotBonusCaptures.entries) {
      newSubnets[entry.key] = (newSubnets[entry.key] ?? 0) + entry.value;
      newCaptures[entry.key] = (newCaptures[entry.key] ?? 0) + entry.value;
    }

    final newHistory = [
      ...state.boardHashes,
      state.board.zobristHash,
    ];

    final log = captureCount > 0
        ? '>> BACKDOOR :: HIJACK_NODE ($captureCount captured) [+$earned SN]${honeypotLog.isNotEmpty ? ' | $honeypotLog' : ''}'
        : '>> BACKDOOR :: HIJACK_NODE [+$earned SN]${honeypotLog.isNotEmpty ? ' | $honeypotLog' : ''}';

    // Clear the backdoor entry for the victim.
    final newBackdoorBy = Map<String, String?>.from(state.backdoorBy)
      ..[victimId] = null;

    // Remove backdoor + any fired honeypot effects.
    final withoutBackdoor = state.activeEffects.toList();
    final finalEffects =
        _removeFiredHoneypots(withoutBackdoor, state, capturedPositions);

    // Advance turn from the victim's position (not the hijacker's).
    final nextIndex = (victimIdx + 1) % state.players.length;
    final nextPlayerId = state.players[nextIndex].id;
    var nextState = state.copyWith(
      board: finalBoard,
      boardHashes: newHistory,
      subnets: newSubnets,
      captureCount: newCaptures,
      consecutivePasses: 0,
      phase: GamePhase.attack,
      activeEffects: finalEffects,
      backdoorBy: newBackdoorBy,
      currentPlayerIndex: nextIndex,
      turnNumber: state.turnNumber + 1,
    );
    nextState = AttackSystem.tickEffectsForPlayer(nextState, nextPlayerId);
    return _autoResolveEffects(nextState, log);
  }

  // ── Pass ──────────────────────────────────────────────────────────────────

  /// Processes a pass from [playerId].
  static ActionResult pass(GameState state, String playerId) {
    if (state.phase != GamePhase.attack) {
      return const ActionFailure('NOT_YOUR_TURN');
    }
    if (state.currentPlayerId != playerId) {
      return const ActionFailure('NOT_YOUR_TURN');
    }

    final newPasses = state.consecutivePasses + 1;
    final gameEnds = newPasses >= state.players.length;

    if (gameEnds) {
      return ActionSuccess(
        state.copyWith(
          consecutivePasses: newPasses,
          phase: GamePhase.scoring,
        ),
        logMessage: '>> LAYER_RESOLVED :: ALL ENTITIES PASSED',
      );
    }

    // Pass → immediately advance to next player; tick their effects.
    final nextIndex = (state.currentPlayerIndex + 1) % state.players.length;
    final nextPlayerId = state.players[nextIndex].id;
    var nextState = state.copyWith(
      consecutivePasses: newPasses,
      currentPlayerIndex: nextIndex,
      turnNumber: state.turnNumber + 1,
      phase: GamePhase.attack,
    );
    nextState = AttackSystem.tickEffectsForPlayer(nextState, nextPlayerId);
    return _autoResolveEffects(nextState, '>> IDLE_PROTOCOL :: PASS');
  }

  // ── End attack phase / advance turn ──────────────────────────────────────

  /// Called when [playerId] finishes their attack phase (or skips it).
  static ActionResult endAttackPhase(GameState state, String playerId) {
    if (state.phase != GamePhase.attack) {
      return const ActionFailure('NOT_IN_ATTACK_PHASE');
    }
    if (state.currentPlayerId != playerId) {
      return const ActionFailure('NOT_YOUR_TURN');
    }

    // Advance to the next player; tick incoming player's effects at turn start.
    // Use attack phase (not placement) so the next player can place a stone.
    final nextIndex = (state.currentPlayerIndex + 1) % state.players.length;
    final nextPlayerId = state.players[nextIndex].id;
    var nextState = state.copyWith(
      currentPlayerIndex: nextIndex,
      turnNumber: state.turnNumber + 1,
      phase: GamePhase.attack,
    );
    nextState = AttackSystem.tickEffectsForPlayer(nextState, nextPlayerId);
    return _autoResolveEffects(nextState, '>> LAYER::T${state.turnNumber} ADVANCE');
  }

  // ── Launch attack ─────────────────────────────────────────────────────────

  /// Processes an attack action during the placement or attack phase.
  ///
  /// If the target has an active [AttackType.patch] effect, the attack cost is
  /// still paid but the attack is blocked (one patch is consumed).
  static ActionResult launchAttack(GameState state, AttackAction action) {
    final error = AttackSystem.validateAttack(state, action);
    if (error != null) return ActionFailure(error);

    final card = AttackCard.forType(action.type);

    // Deduct the attacker's cost first.
    final costDeducted = state.copyWith(
      subnets: {
        ...state.subnets,
        action.attackerPlayerId:
            state.subnetsOf(action.attackerPlayerId) - card.subnetCost,
      },
    );

    // PATCH intercept: block one incoming attack if the target is shielded.
    // patch does not intercept itself (it's self-applied, no real target).
    if (action.type != AttackType.patch &&
        AttackSystem.isPatched(costDeducted, action.targetPlayerId)) {
      final blocked =
          AttackSystem.consumePatch(costDeducted, action.targetPlayerId);
      final targetName = state.players
          .firstWhere((p) => p.id == action.targetPlayerId,
              orElse: () =>
                  Player(id: action.targetPlayerId, displayName: '???'))
          .displayName;
      return ActionSuccess(
        blocked,
        logMessage:
            '>> PATCH_BLOCKED :: ${card.terminalName} DEFLECTED BY $targetName',
      );
    }

    // Apply the attack effect on the cost-already-deducted state.
    // applyAttack no longer deducts cost itself (SRP: cost is owned here).
    final newState = AttackSystem.applyAttack(costDeducted, action);

    final targetName = state.players
        .firstWhere((p) => p.id == action.targetPlayerId,
            orElse: () =>
                Player(id: action.targetPlayerId, displayName: '???'))
        .displayName;

    // Worm: the replacement stone may enclose adjacent enemy groups that now
    // have 0 liberties – resolve those captures and credit subnets.
    if (action.type == AttackType.worm) {
      final wormPos = action.targetPosition!;
      final attackerColor = state.currentPlayerColor(action.attackerPlayerId);
      final (boardAfterWorm, wormCaptures) =
          GoRules.applyCapturesAfterPlacement(newState.board, wormPos, attackerColor);

      final resolvedState = wormCaptures.isEmpty
          ? newState
          : newState.copyWith(
              board: boardAfterWorm,
              subnets: {
                ...newState.subnets,
                action.attackerPlayerId:
                    newState.subnetsOf(action.attackerPlayerId) +
                        wormCaptures.length,
              },
              captureCount: {
                ...newState.captureCount,
                action.attackerPlayerId:
                    (newState.captureCount[action.attackerPlayerId] ?? 0) +
                        wormCaptures.length,
              },
            );
      final wormLog = wormCaptures.isNotEmpty
          ? '>> ATTACK_VECTOR :: ${card.terminalName} >> $targetName | NODE_CAPTURE: ${wormCaptures.length} [+${wormCaptures.length} SN]'
          : '>> ATTACK_VECTOR :: ${card.terminalName} >> $targetName';
      return ActionSuccess(resolvedState, logMessage: wormLog);
    }

    return ActionSuccess(
      newState,
      logMessage: '>> ATTACK_VECTOR :: ${card.terminalName} >> $targetName',
    );
  }

  // ── DDOS auto-skip ────────────────────────────────────────────────────────

  /// Auto-skips the current player whose placement is blocked by DDOS.
  ///
  /// Call this when [state.hasEffect(state.currentPlayerId, AttackType.ddos)]
  /// is true at the start of a placement phase.
  static ActionResult skipDdosVictim(GameState state) {
    final playerId = state.currentPlayerId;
    // Tick the victim's effects again (they were already ticked at turn start;
    // this second tick consumes the remaining DDOS, 1 → 0).
    var tickedState = AttackSystem.tickEffectsForPlayer(state, playerId);
    // Advance to next player and tick their effects at their turn start.
    final nextIndex = (state.currentPlayerIndex + 1) % state.players.length;
    final nextPlayerId = state.players[nextIndex].id;
    var nextState = tickedState.copyWith(
      currentPlayerIndex: nextIndex,
      turnNumber: state.turnNumber + 1,
      phase: GamePhase.attack,
    );
    nextState = AttackSystem.tickEffectsForPlayer(nextState, nextPlayerId);
    return ActionSuccess(
      nextState,
      logMessage: '>> DDoS_ACTIVE :: ${state.currentPlayer.displayName} SIGNAL BLOCKED',
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Resolves any chained DDOS skips and BACKDOOR hijacks after a turn
  /// advance.  Called at the end of [_applyPlacement], [pass], [endAttackPhase],
  /// and [_placeHijacked] so that callers never need to handle these effects
  /// externally.
  static ActionResult _autoResolveEffects(GameState state, String? baseLog) {
    final logs = <String>[
      if (baseLog != null && baseLog.isNotEmpty) baseLog,
    ];

    // Guard against infinite loops (e.g. everyone DDOS'd simultaneously).
    int guard = 0;
    while (guard <= state.players.length) {
      guard++;
      final currentId = state.currentPlayerId;

      // BACKDOOR: hijacker places the victim's stone this turn.
      final hijackerId = state.backdoorBy[currentId];
      if (hijackerId != null) {
        final hijackerIndex =
            state.players.indexWhere((p) => p.id == hijackerId);
        final hijackerName = state.players
            .firstWhere((p) => p.id == hijackerId,
                orElse: () => Player(id: hijackerId, displayName: '???'))
            .displayName;
        final victimName = state.players
            .firstWhere((p) => p.id == currentId,
                orElse: () => Player(id: currentId, displayName: '???'))
            .displayName;
        logs.add('>> BACKDOOR :: $hijackerName HIJACKED $victimName UPLINK');
        return ActionSuccess(
          state.copyWith(
            currentPlayerIndex: hijackerIndex,
            phase: GamePhase.hijackedVictimPlacement,
          ),
          logMessage: logs.join(' | '),
        );
      }

      // DDOS: skip this player's placement.
      if (state.hasEffect(currentId, AttackType.ddos)) {
        final name = state.players
            .firstWhere((p) => p.id == currentId,
                orElse: () => Player(id: currentId, displayName: '???'))
            .displayName;
        // Second tick on the victim consumes the DDOS (turnsRemaining 1 → 0).
        var ticked = AttackSystem.tickEffectsForPlayer(state, currentId);
        final nextIndex =
            (state.currentPlayerIndex + 1) % state.players.length;
        final nextId = state.players[nextIndex].id;
        state = ticked.copyWith(
          currentPlayerIndex: nextIndex,
          turnNumber: state.turnNumber + 1,
          phase: GamePhase.attack,
        );
        state = AttackSystem.tickEffectsForPlayer(state, nextId);
        logs.add('>> DDoS_ACTIVE :: $name SIGNAL BLOCKED');
        continue;
      }

      break; // Normal turn — no special effects.
    }

    return ActionSuccess(
      state,
      logMessage: logs.isNotEmpty ? logs.join(' | ') : null,
    );
  }

  /// Core placement logic shared by [placeStone] (normal turn).
  static ActionResult _applyPlacement(
    GameState state,
    String playerId,
    int playerIndex,
    Position pos,
    StoneColor color,
  ) {
    final (boardAfterMove, capturedPositions) =
        GoRules.applyPlacement(state.board, pos, color);

    // Resolve any honeypot captures.
    final (finalBoard, honeypotLog, honeypotBonusCaptures) =
        _resolveHoneypots(state, boardAfterMove, capturedPositions);

    final captureCount = capturedPositions.length;
    final earned = Scorer.subnetsForPlacement(finalBoard, pos, captureCount);

    final newCaptureCount = Map<String, int>.from(state.captureCount);
    newCaptureCount[playerId] =
        (newCaptureCount[playerId] ?? 0) + captureCount;

    final newSubnets = Map<String, int>.from(state.subnets);
    newSubnets[playerId] = (newSubnets[playerId] ?? 0) + earned;
    // Credit honeypot-owner bonus captures (1 subnet each, no base or star bonus).
    for (final entry in honeypotBonusCaptures.entries) {
      newSubnets[entry.key] = (newSubnets[entry.key] ?? 0) + entry.value;
      newCaptureCount[entry.key] =
          (newCaptureCount[entry.key] ?? 0) + entry.value;
    }

    final newHistory = [
      ...state.boardHashes,
      state.board.zobristHash,
    ];

    final log = captureCount > 0
        ? '>> NODE_CAPTURE :: $captureCount TAKEN [+$earned SN]${honeypotLog.isNotEmpty ? ' | $honeypotLog' : ''}'
        : '>> +$earned SN ACQUIRED${honeypotLog.isNotEmpty ? ' | $honeypotLog' : ''}';

    // Remove fired honeypot effects from active effects.
    final finalEffects =
        _removeFiredHoneypots(state.activeEffects, state, capturedPositions);

    // Placement done → immediately advance to next player.
    // Tick incoming player's effects at their turn start.
    final nextIndex =
        (state.currentPlayerIndex + 1) % state.players.length;
    final nextPlayerId = state.players[nextIndex].id;
    var nextState = state.copyWith(
      board: finalBoard,
      boardHashes: newHistory,
      subnets: newSubnets,
      captureCount: newCaptureCount,
      consecutivePasses: 0,
      phase: GamePhase.attack,
      activeEffects: finalEffects,
      currentPlayerIndex: nextIndex,
      turnNumber: state.turnNumber + 1,
    );
    nextState = AttackSystem.tickEffectsForPlayer(nextState, nextPlayerId);
    return _autoResolveEffects(nextState, log);
  }

  /// After [boardAfterCaptures], explodes any honeypot stones that were
  /// captured.  Returns the updated board, a log snippet, and a map of
  /// extra captures credited to each honeypot owner (1 subnet per capture).
  ///
  /// The explosion places the owner's stone back at the captured position
  /// plus all in-bounds neighbours (overwriting enemy stones).  After
  /// placing all explosion stones, capture resolution is run for each
  /// newly placed stone so the board remains valid.
  static (Board, String, Map<String, int>) _resolveHoneypots(
    GameState state,
    Board boardAfterCaptures,
    Set<Position> capturedPositions,
  ) {
    var board = boardAfterCaptures;
    final log = StringBuffer();
    final bonusCaptures = <String, int>{};

    for (final pos in capturedPositions) {
      // The captured stone's colour is taken from the PRE-capture board.
      final capturedColor = state.board.at(pos);
      if (capturedColor == null) continue;
      final ownerId = state.players[capturedColor.index].id;

      if (!AttackSystem.isHoneypot(state, pos, ownerId)) continue;

      // Collect explosion positions BEFORE placing any stones.
      final explosionPositions = <Position>[pos, ...board.neighborsOf(pos)];

      // Place all explosion stones, counting overwritten enemy stones.
      for (final ePos in explosionPositions) {
        final existing = board.at(ePos);
        if (existing != null && existing != capturedColor) {
          bonusCaptures[ownerId] = (bonusCaptures[ownerId] ?? 0) + 1;
        }
        board = board.place(ePos, capturedColor);
      }

      // Resolve captures for each explosion stone so the board stays valid.
      for (final ePos in explosionPositions) {
        final (newBoard, triggered) =
            GoRules.applyCapturesAfterPlacement(board, ePos, capturedColor);
        board = newBoard;
        if (triggered.isNotEmpty) {
          bonusCaptures[ownerId] =
              (bonusCaptures[ownerId] ?? 0) + triggered.length;
        }
      }

      if (log.isNotEmpty) log.write(', ');
      log.write('HONEYPOT@(${pos.x},${pos.y}) exploded');
    }

    return (board, log.toString(), bonusCaptures);
  }

  /// Removes honeypot effects whose trap positions were just captured.
  static List<ActiveEffect> _removeFiredHoneypots(
    List<ActiveEffect> effects,
    GameState preState,
    Set<Position> capturedPositions,
  ) {
    return effects.where((e) {
      if (e.type != AttackType.knightseye) return true;
      if (e.anchorPosition == null) return true;
      // Keep the effect only if the trap was NOT just captured.
      return !capturedPositions.contains(e.anchorPosition);
    }).toList();
  }

  // ── Game-over check ───────────────────────────────────────────────────────

  static bool isGameOver(GameState state) =>
      state.phase == GamePhase.scoring || state.phase == GamePhase.finished;
}
