import '../models/attack.dart';
import '../models/position.dart';
import '../models/stone_color.dart';

// ── GameEvent sealed class ────────────────────────────────────────────────

/// A typed, read-only description of something that just happened in the game.
///
/// Events are emitted alongside [ActionResult] and are consumed by UI layers
/// (terminal renderer, tutorial narration) that need more than just the
/// before/after [GameState] diff.  They carry no mutable state and impose
/// no obligations on the engine — the engine never reads events back.
///
/// The sealed hierarchy lets consumers use exhaustive switch:
/// ```dart
/// switch (event) {
///   case StonePlacedEvent e  => ...
///   case StonesCaptoredEvent e => ...
///   ...
/// }
/// ```
sealed class GameEvent {
  const GameEvent();
}

// ── Placement ─────────────────────────────────────────────────────────────

/// A stone was placed at [pos] by [playerId].
///
/// Emitted for both human and bot placements, including hijacked turns.
/// [isHijacked] is true when the placing player is controlling someone else's
/// stone via the BACKDOOR/MITM effect.
class StonePlacedEvent extends GameEvent {
  final String playerId;
  final Position pos;
  final StoneColor color;
  final bool isHijacked;

  const StonePlacedEvent({
    required this.playerId,
    required this.pos,
    required this.color,
    this.isHijacked = false,
  });
}

// ── Capture ───────────────────────────────────────────────────────────────

/// One or more stones were captured as a result of a placement.
///
/// [captured] is the set of board positions that were removed.
class StonesCapturedEvent extends GameEvent {
  final String capturedByPlayerId;
  final Set<Position> captured;

  const StonesCapturedEvent({
    required this.capturedByPlayerId,
    required this.captured,
  });
}

// ── Pass ──────────────────────────────────────────────────────────────────

/// [playerId] passed their turn.
class PlayerPassedEvent extends GameEvent {
  final String playerId;
  const PlayerPassedEvent({required this.playerId});
}

// ── Turn advance ──────────────────────────────────────────────────────────

/// The active player changed.
///
/// [turnNumber] is the new turn number (matches [GameState.turnNumber]).
class TurnAdvancedEvent extends GameEvent {
  final String newCurrentPlayerId;
  final int turnNumber;

  const TurnAdvancedEvent({
    required this.newCurrentPlayerId,
    required this.turnNumber,
  });
}

// ── Attack ────────────────────────────────────────────────────────────────

/// An attack was validated and applied (or blocked by PATCH).
///
/// [wasBlocked] is true when the target had an active PATCH shield that
/// intercepted the attack.  The attacker still paid the subnet cost.
class AttackLaunchedEvent extends GameEvent {
  final AttackType type;
  final String attackerPlayerId;
  final String targetPlayerId;
  final bool wasBlocked;

  const AttackLaunchedEvent({
    required this.type,
    required this.attackerPlayerId,
    required this.targetPlayerId,
    this.wasBlocked = false,
  });
}

// ── Auto-effects ──────────────────────────────────────────────────────────

/// A player was auto-skipped because of an active DDOS effect.
class DdosSkipEvent extends GameEvent {
  final String skippedPlayerId;
  const DdosSkipEvent({required this.skippedPlayerId});
}

/// A BACKDOOR hijack became active: [hijackerPlayerId] now controls
/// [victimPlayerId]'s next stone placement.
class HijackActivatedEvent extends GameEvent {
  final String hijackerPlayerId;
  final String victimPlayerId;

  const HijackActivatedEvent({
    required this.hijackerPlayerId,
    required this.victimPlayerId,
  });
}

// ── Game over ─────────────────────────────────────────────────────────────

/// The game ended and final area scores were computed.
///
/// [scores] maps each [StoneColor] to its final area score (stones + territory).
class GameOverEvent extends GameEvent {
  final Map<StoneColor, int> scores;
  const GameOverEvent({required this.scores});
}
