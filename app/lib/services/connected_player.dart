/// Lightweight player record used in LAN lobby and game screens.
///
/// Kept separate from the engine's [Player] model to avoid coupling
/// transport-layer identity concerns to the pure game engine.
class ConnectedPlayer {
  final String id;
  final String displayName;
  const ConnectedPlayer({required this.id, required this.displayName});
}
