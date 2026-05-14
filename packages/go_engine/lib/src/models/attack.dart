import 'position.dart';

// ── Attack type catalogue ─────────────────────────────────────────────────

/// Every available hack / attack a player can purchase with subnets.
enum AttackType {
  /// DDOS.sh – skip the target's next stone placement.
  ddos,

  /// SPYWARE.sh – steal 3 subnets from target (attacker gains, target loses).
  trojan,

  /// BACKDOOR.sh – hijack target's next turn: attacker places their own stone
  /// then the target's stone; turn then returns to the attacker.
  backdoor,

  /// PATCH.sh – self-shield: block the next attack received. Stacks per use.
  patch,

  /// WORM.sh – overwrite one enemy-occupied intersection with your stone.
  worm,

  /// KNIGHTS_EYE.sh – plant a trap stone; if it is captured it reclaims itself
  /// and all adjacent empty intersections for the owner.
  knightseye,

  /// PSYCHE.sh – for the next 3 of each opponent's turns they must act
  /// within 5 seconds or their turn is auto-skipped.
  psyche,
}

/// Static metadata for each [AttackType].
class AttackCard {
  final AttackType type;
  final int subnetCost;
  final String terminalName; // e.g. "DDOS.sh"
  final String description;

  const AttackCard({
    required this.type,
    required this.subnetCost,
    required this.terminalName,
    required this.description,
  });

  static const all = [
    // Sorted ascending by subnetCost.
    AttackCard(
      type: AttackType.ddos,
      subnetCost: 6,
      terminalName: 'DDOS.sh',
      description: 'Flood target node. Target skips next placement.',
    ),
    AttackCard(
      type: AttackType.patch,
      subnetCost: 6,
      terminalName: 'PATCH.sh',
      description: 'Apply security patch. Block next incoming attack. Stacks.',
    ),
    AttackCard(
      type: AttackType.worm,
      subnetCost: 8,
      terminalName: 'WORM.sh',
      description: 'Inject worm. Overwrite one enemy stone with yours.',
    ),
    AttackCard(
      type: AttackType.trojan,
      subnetCost: 10,
      terminalName: 'TROJAN.sh',
      description: 'Deploy trojan. Steal half their subnets – you gain, they lose.',
    ),
    AttackCard(
      type: AttackType.knightseye,
      subnetCost: 10,
      terminalName: 'KNIGHTS_EYE.sh',
      description: 'Deploy trap. If captured, reclaims node and overwrites all 4 adjacent nodes.',
    ),
    AttackCard(
      type: AttackType.backdoor,
      subnetCost: 12,
      terminalName: 'BACKDOOR.sh',
      description: 'Hijack next turn. You place the enemy stone; they skip attacks.',
    ),
    AttackCard(
      type: AttackType.psyche,
      subnetCost: 20,
      terminalName: 'PSYCHE.sh',
      description: 'Initiate countdown. All enemies must act within 5s for 3 turns or be auto-skipped.',
    ),
  ];

  static AttackCard forType(AttackType type) =>
      all.firstWhere((c) => c.type == type);
}

// ── Attack action (submitted by a player) ────────────────────────────────

/// An attack action submitted by [attackerPlayerId] during the attack phase.
class AttackAction {
  final AttackType type;
  final String attackerPlayerId;
  final String targetPlayerId;

  /// Target intersection (required by [worm] and [honeypot]).
  /// Null for [ddos], [spyware], [backdoor], and [patch].
  final Position? targetPosition;

  const AttackAction({
    required this.type,
    required this.attackerPlayerId,
    required this.targetPlayerId,
    this.targetPosition,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'attackerPlayerId': attackerPlayerId,
        'targetPlayerId': targetPlayerId,
        if (targetPosition != null)
          'targetPosition': {
            'x': targetPosition!.x,
            'y': targetPosition!.y,
          },
      };

  factory AttackAction.fromJson(Map<String, dynamic> json) {
    // Validate enum name before byName to get a clear error in outer catch.
    final typeName = json['type'] as String;
    final type = AttackType.values.byName(typeName);

    // Safe targetPosition parsing — malformed values produce null instead of
    // throwing a TypeError that would propagate up to the room stream handler.
    Position? targetPosition;
    final rawPos = json['targetPosition'];
    if (rawPos is Map) {
      final x = rawPos['x'];
      final y = rawPos['y'];
      if (x is int && y is int) targetPosition = Position(x, y);
    }

    return AttackAction(
      type: type,
      attackerPlayerId: json['attackerPlayerId'] as String,
      targetPlayerId: json['targetPlayerId'] as String,
      targetPosition: targetPosition,
    );
  }
}

// ── Active effect (persisted in GameState) ────────────────────────────────

/// An in-flight effect that was applied by an attack and will resolve
/// over the coming turns.
class ActiveEffect {
  final AttackType type;
  final String targetPlayerId;

  /// How many more turns this effect is active (decremented each time
  /// [targetPlayerId]'s turn begins).
  final int turnsRemaining;

  /// Anchor position used by [worm] and [honeypot] to record the
  /// target / trap intersection.
  final Position? anchorPosition;

  /// For [backdoor] effects: the player who launched the hijack.
  final String? hijackedByPlayerId;

  const ActiveEffect({
    required this.type,
    required this.targetPlayerId,
    required this.turnsRemaining,
    this.anchorPosition,
    this.hijackedByPlayerId,
  });

  ActiveEffect withTurnsRemaining(int turns) => ActiveEffect(
        type: type,
        targetPlayerId: targetPlayerId,
        turnsRemaining: turns,
        anchorPosition: anchorPosition,
        hijackedByPlayerId: hijackedByPlayerId,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'targetPlayerId': targetPlayerId,
        'turnsRemaining': turnsRemaining,
        if (anchorPosition != null)
          'anchorPosition': {
            'x': anchorPosition!.x,
            'y': anchorPosition!.y,
          },
        if (hijackedByPlayerId != null)
          'hijackedByPlayerId': hijackedByPlayerId,
      };

  factory ActiveEffect.fromJson(Map<String, dynamic> json) {
    Position? anchorPosition;
    final rawAnchor = json['anchorPosition'];
    if (rawAnchor is Map) {
      final x = rawAnchor['x'];
      final y = rawAnchor['y'];
      if (x is int && y is int) anchorPosition = Position(x, y);
    }
    return ActiveEffect(
      type: AttackType.values.byName(json['type'] as String),
      targetPlayerId: json['targetPlayerId'] as String,
      turnsRemaining: json['turnsRemaining'] as int,
      anchorPosition: anchorPosition,
      hijackedByPlayerId: json['hijackedByPlayerId'] as String?,
    );
  }
}
