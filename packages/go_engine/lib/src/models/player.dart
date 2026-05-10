/// Lightweight player record carried inside [GameState].
class Player {
  final String id;
  final String displayName;

  const Player({required this.id, required this.displayName});

  Map<String, dynamic> toJson() => {'id': id, 'displayName': displayName};

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Player && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Player($id, $displayName)';
}
