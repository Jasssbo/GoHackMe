import '../models/attack.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/position.dart';
import 'go_rules.dart';

/// Resolves attack actions and manages active effects.
///
/// All methods are static and pure – they return new [GameState] instances.
class AttackSystem {
  AttackSystem._();

  // ── Attack validation ─────────────────────────────────────────────────────

  /// Returns null if [action] is valid in the current [state], or an error
  /// string if it is not.
  static String? validateAttack(GameState state, AttackAction action) {
    // Attacks are allowed during the attack phase only.
    if (state.phase != GamePhase.attack) {
      return 'NOT_IN_ATTACK_PHASE';
    }
    if (state.currentPlayerId != action.attackerPlayerId) {
      return 'NOT_YOUR_TURN';
    }

    // PATCH and HONEYPOT are self-applied; all other attacks must target a
    // different player. Honeypot places a trap stone owned by the attacker –
    // any opponent who captures it triggers the effect, so no explicit target
    // player is needed.
    if (action.type != AttackType.patch && action.type != AttackType.honeypot) {
      if (action.attackerPlayerId == action.targetPlayerId) {
        return 'CANNOT_ATTACK_SELF';
      }
      if (!state.players.any((p) => p.id == action.targetPlayerId)) {
        return 'TARGET_PLAYER_NOT_FOUND';
      }
    }

    // Sufficient subnets
    final card = AttackCard.forType(action.type);
    final available = state.subnetsOf(action.attackerPlayerId);
    if (available < card.subnetCost) {
      return 'INSUFFICIENT_SUBNETS (need ${card.subnetCost}, have $available)';
    }

    // Type-specific validation
    switch (action.type) {
      case AttackType.worm:
        if (action.targetPosition == null) return 'POSITION_REQUIRED';
        if (!state.board.isInBounds(action.targetPosition!)) {
          return 'POSITION_OUT_OF_BOUNDS';
        }
        final stoneAt = state.board.at(action.targetPosition!);
        final targetColor =
            state.currentPlayerColor(action.targetPlayerId);
        if (stoneAt != targetColor) return 'NO_ENEMY_STONE_AT_POSITION';

      case AttackType.honeypot:
        if (action.targetPosition == null) return 'POSITION_REQUIRED';
        if (!state.board.isInBounds(action.targetPosition!)) {
          return 'POSITION_OUT_OF_BOUNDS';
        }
        if (state.board.at(action.targetPosition!) != null) {
          return 'POSITION_OCCUPIED';
        }
        // Suicide check: the honeypot stone must have at least one liberty
        // after placement (skip KO – honeypot bypasses normal turn history).
        final honeypotColor =
            state.currentPlayerColor(action.attackerPlayerId);
        final suicideError = GoRules.validatePlacement(
          state.board,
          action.targetPosition!,
          honeypotColor,
          const [], // no KO check for honeypot
        );
        if (suicideError != null) return 'HONEYPOT_INVALID: $suicideError';

      case AttackType.backdoor:
        // No stacking: reject if target already has an active backdoor.
        if (state.backdoorBy[action.targetPlayerId] != null) {
          return 'BACKDOOR_ALREADY_ACTIVE';
        }

      default:
        break;
    }

    return null;
  }

  // ── Attack application ────────────────────────────────────────────────────

  /// Applies [action]'s board and effect changes to [state] and returns the
  /// new state.
  ///
  /// Assumes [validateAttack] returned null **and** that the attacker's subnet
  /// cost has already been deducted by the caller (i.e. [state] already
  /// reflects the reduced subnet count).  This keeps cost-deduction
  /// responsibility in [GameEngine.launchAttack] (SRP).
  static GameState applyAttack(GameState state, AttackAction action) {
    // Subnet adjustments for effect-side transfers (e.g. spyware steal).
    final newSubnets = Map<String, int>.from(state.subnets);
    final newPatchShields = Map<String, int>.from(state.patchShields);
    final newBackdoorBy = Map<String, String?>.from(state.backdoorBy);

    Board newBoard = state.board;
    List<ActiveEffect> newEffects = List.from(state.activeEffects);

    switch (action.type) {
      // ── Instant effects ───────────────────────────────────────────────────

      case AttackType.trojan:
        // Steal half the target's subnets (floor division).
        final targetHas = (newSubnets[action.targetPlayerId] ?? 0);
        final actualSteal = targetHas ~/ 2;
        newSubnets[action.targetPlayerId] = targetHas - actualSteal;
        newSubnets[action.attackerPlayerId] =
            (newSubnets[action.attackerPlayerId] ?? 0) + actualSteal;

      case AttackType.worm:
        // Remove the enemy stone, replace with attacker's stone.
        final attackerColor =
            state.currentPlayerColor(action.attackerPlayerId);
        newBoard = newBoard
            .remove({action.targetPosition!})
            .place(action.targetPosition!, attackerColor);

      // ── Persisted effects ─────────────────────────────────────────────────

      case AttackType.ddos:
        // turnsRemaining: 2 so that after the incoming-turn tick (2→1) the
        // effect is still active and detectable before placement.
        newEffects.add(ActiveEffect(
          type: AttackType.ddos,
          targetPlayerId: action.targetPlayerId,
          turnsRemaining: 2,
        ));

      case AttackType.backdoor:
        // Mark the victim as backdoored by the attacker.
        newBackdoorBy[action.targetPlayerId] = action.attackerPlayerId;

      case AttackType.patch:
        // Increment the attacker's shield stack by 1.
        newPatchShields[action.attackerPlayerId] =
            (newPatchShields[action.attackerPlayerId] ?? 0) + 1;

      case AttackType.honeypot:
        // Place attacker's stone; track it as a honeypot via an active effect.
        final attackerColor =
            state.currentPlayerColor(action.attackerPlayerId);
        newBoard = newBoard.place(action.targetPosition!, attackerColor);
        newEffects.add(ActiveEffect(
          type: AttackType.honeypot,
          targetPlayerId: action.attackerPlayerId, // owner of the trap
          turnsRemaining: 999, // persists until the trap fires or stone is gone
          anchorPosition: action.targetPosition,
        ));
    }

    return state.copyWith(
      board: newBoard,
      subnets: newSubnets,
      patchShields: newPatchShields,
      backdoorBy: newBackdoorBy,
      activeEffects: newEffects,
    );
  }

  // ── Effect resolution on turn start ──────────────────────────────────────

  /// Called at the start of [playerId]'s turn to tick down and resolve
  /// any expiring effects.
  ///
  /// [patch] effects (turnsRemaining: 999) and [honeypot] effects are NOT
  /// ticked – they are consumed explicitly.
  static GameState tickEffectsForPlayer(GameState state, String playerId) {
    final stillActive = <ActiveEffect>[];

    for (final effect in state.activeEffects) {
      if (effect.targetPlayerId != playerId) {
        stillActive.add(effect);
        continue;
      }
      // backdoor and honeypot are event-driven, not turn-ticked.
      if (effect.type == AttackType.honeypot) {
        stillActive.add(effect);
        continue;
      }
      final remaining = effect.turnsRemaining - 1;
      if (remaining > 0) {
        stillActive.add(effect.withTurnsRemaining(remaining));
      }
      // remaining == 0 → effect expires, not re-added.
    }

    return state.copyWith(activeEffects: stillActive);
  }

  // ── Patch helpers ─────────────────────────────────────────────────────────

  /// Returns true if [playerId] has at least one stacked PATCH shield.
  static bool isPatched(GameState state, String playerId) =>
      (state.patchShields[playerId] ?? 0) > 0;

  /// Decrements [playerId]'s PATCH shield count by 1 and returns the new
  /// state.  Call only after confirming [isPatched] is true.
  static GameState consumePatch(GameState state, String playerId) {
    final shields = Map<String, int>.from(state.patchShields);
    final current = shields[playerId] ?? 0;
    if (current > 0) shields[playerId] = current - 1;
    return state.copyWith(patchShields: shields);
  }

  // ── Honeypot helpers ──────────────────────────────────────────────────────

  /// Returns true if [pos] is tracked as a honeypot owned by [ownerId].
  static bool isHoneypot(GameState state, Position pos, String ownerId) =>
      state.activeEffects.any(
        (e) =>
            e.type == AttackType.honeypot &&
            e.targetPlayerId == ownerId &&
            e.anchorPosition == pos,
      );

  /// Removes the honeypot effect anchored at [pos] (owned by [ownerId]) and
  /// returns the new state.  Call only after confirming [isHoneypot] is true.
  static GameState consumeHoneypot(
      GameState state, Position pos, String ownerId) {
    final remaining = state.activeEffects
        .where(
          (e) => !(e.type == AttackType.honeypot &&
              e.targetPlayerId == ownerId &&
              e.anchorPosition == pos),
        )
        .toList();
    return state.copyWith(activeEffects: remaining);
  }
}

