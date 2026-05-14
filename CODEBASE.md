# GoHackMe — Codebase Guide

A bottom-up walkthrough of the architecture, data flow, and conventions
that keep everything consistent. Read it once; the code will make sense
forever after.

---

## 1. Repository Layout

```
GoHackMe_Flutter/
├── packages/go_engine/   ← Pure Dart. No Flutter. Shared by app and server.
├── server/               ← Dart Shelf HTTP + WebSocket server.
├── app/                  ← Flutter app.
└── melos.yaml            ← Monorepo orchestrator (links the three packages).
```

`go_engine` is the source of truth for game logic.
Both `app` and `server` depend on it — neither duplicates logic the other has.
`melos` makes `flutter pub get` work across all three in one command.

---

## 2. The Engine Package (`packages/go_engine`)

This is the most important part of the codebase. Everything else is just
plumbing around it.

### 2.1 The two rules

**Immutability** — every model is immutable. Mutations return a new instance.
**Pure functions** — every engine method is `static` and has no side effects.

These two rules together mean: given the same state and the same action, you
always get the same result. No hidden fields. No global variables. Trivially
testable.

### 2.2 The model stack (bottom to top)

```
Position          — an (x, y) grid coordinate. Value type with == / hashCode.
StoneColor        — enum p1 / p2 / p3 / p4. Index matches the player list index.
Board             — immutable Map<Position, StoneColor>. place() and remove()
                    return new Boards. operator== enables Ko detection.
Player            — id (UUID) + displayName. Identity only; no game data.
AttackType        — enum of all hacks (ddos, worm, patch, …).
AttackCard        — static catalogue mapping each AttackType to subnet cost + UI label.
AttackAction      — one attack submission: who attacked, who was targeted, where.
ActiveEffect      — a running effect with a remaining-turns counter.
GamePhase         — enum of turn phases (lobby → attack → placement → scoring → finished).
GameState         — the entire, serialisable game state (see §2.3).
```

### 2.3 GameState — the single source of truth

`GameState` is one flat, serialisable record with `copyWith`. It holds:

| Field | What it is |
|---|---|
| `board` | The current `Board` snapshot. |
| `boardHistory` | All previous `Board` snapshots. Used for superko (full board Ko rule). |
| `players` | Ordered list of `Player` objects. Order never changes after game start. |
| `currentPlayerIndex` | Index into `players`. Determines whose turn it is. |
| `subnets` | `Map<playerId, int>`. The hack-point currency. |
| `captureCount` | `Map<playerId, int>`. Lifetime captures per player. |
| `patchShields` | `Map<playerId, int>`. Stacked firewall shields. |
| `backdoorBy` | `Map<victimId, attackerId?>`. Tracks the BACKDOOR hijack state. |
| `phase` | Current `GamePhase`. Controls what actions are legal right now. |
| `activeEffects` | List of ticking `ActiveEffect` objects (DDOS, SPYWARE, etc.). |
| `consecutivePasses` | Two consecutive passes = game over. |

**Key helper methods on `GameState`:**
- `currentPlayerId` — shorthand for `players[currentPlayerIndex].id`.
- `subnetsOf(id)` — safe getter (defaults to 0).
- `hasEffect(id, type)` — checks `activeEffects` for a specific effect on a player.
- `currentPlayerColor(id)` — maps player ID to their `StoneColor` via list index.

### 2.4 The engine classes

```
GoRules         — pure Go: findGroup, libertiesOf, applyCapturesAfterPlacement, validatePlacement.
Scorer          — area scoring (Chinese rules): areaScore, subnetsForPlacement.
AttackSystem    — validateAttack, applyAttack, tickEffectsForPlayer.
GameEngine      — the public API: placeStone, pass, endAttackPhase, launchAttack, skipDdosVictim.
BotPlayer       — pickMove, pickAttack. Pure static functions; caller supplies Random.
```

**`GameEngine` is the only entry point for mutations.** You never call
`GoRules` or `AttackSystem` directly from the UI or server — everything goes
through `GameEngine`, which chains the lower-level calls internally.

Every `GameEngine` method returns a `sealed class ActionResult`:

```dart
sealed class ActionResult {}
class ActionSuccess extends ActionResult {
  final GameState newState;
  final String? logMessage;   // e.g. "CAPTURED 3 stones"
}
class ActionFailure extends ActionResult {
  final String reason;        // e.g. "SUICIDE_MOVE"
}
```

The caller pattern is always the same:

```dart
final result = GameEngine.placeStone(state, playerId, pos);
switch (result) {
  case ActionSuccess(:final newState, :final logMessage): …
  case ActionFailure(:final reason): …
}
```

Because it is sealed, the compiler forces you to handle both branches.

### 2.5 The wire protocol

`GameMessage` is the only type sent over the network. It contains:

```dart
class GameMessage {
  final MessageType type;    // enum: joinRoom, placeStone, gameStateUpdate, error, …
  final String? playerId;
  final String? roomId;
  final Map<String, dynamic> payload;  // type-specific data
}
```

`GameMessage` lives in `go_engine` so both the app and server share the
exact same serialisation / deserialisation code. Neither side has its own
wire format.

**Direction contract:**

| Direction | Types |
|---|---|
| Client → Server | `joinRoom`, `placeStone`, `pass`, `performAttack`, `endAttackPhase`, `ping` |
| Server → Client | `gameStateUpdate`, `playerJoined`, `playerLeft`, `error`, `gameOver`, `pong` |

The server always sends the entire `GameState` snapshot after every change.
There are no diffs, no partial updates. This keeps client state trivially
correct — it just replaces whatever it had.

---

## 3. The Server (`server/`)

### 3.1 Layers

```
bin/server.dart         ← Entry point. Shelf HTTP + CORS. Mounts WS handler.
lib/src/ws_handler.dart ← Upgrades HTTP → WebSocket. Rate-limiting, size guard,
                          UUID validation. Routes messages to GameRoom.
lib/src/room_manager.dart← HashMap<roomId, GameRoom>. Creates, looks up, and
                           reaps rooms. Hard cap of 50 rooms.
lib/src/game_room.dart  ← One room. Holds the GameState. Fans out broadcasts.
                           Calls GameEngine on each client action.
lib/src/discovery_service.dart ← UDP beacon for LAN auto-discovery.
```

### 3.2 The server's job in one sentence

The server's only job is to be a **trusted relay**: it validates identity,
calls `GameEngine`, and broadcasts the result.

```
Client ──GameMessage──► ws_handler ──route──► GameRoom
                                                  │ GameEngine.placeStone(…)
                                                  │ → ActionSuccess(newState)
                                                  ▼
                     All connected clients ◄── gameStateUpdate(newState)
```

### 3.3 Security model

`ws_handler` applies four guards on every message before it touches game logic:

1. **Size guard** — messages > 4 096 bytes are rejected. Prevents memory exhaustion.
2. **Rate limit** — more than 20 messages/second per connection drops the connection.
3. **UUID format** — `playerId` must match UUID v4 regex. Prevents log injection.
4. **Server-verified identity** — the server ignores whatever `playerId` is in the
   message body for actions. It uses the `connectedPlayerId` stored at join time.
   A client cannot impersonate another player.

The `_validatePlayerAndRoom()` helper in `ws_handler.dart` consolidates rules 3 and 4.

### 3.4 Room lifecycle

```
Player sends joinRoom
    └─► RoomManager.getOrCreate(roomId)
           └─► GameRoom.addPlayer(player, channel)
                  ├─► broadcast playerJoined to all
                  └─► if isFull → _startGame()  (auto-starts when room fills)
                                                 (host can also call startGame() manually)

Game progresses (handleAction loop)

Last player disconnects
    └─► GameRoom.removePlayer → isEmpty → onEmpty()
           └─► RoomManager._reap(roomId)  (garbage collect)
```

Rooms are also reaped after 2 hours of inactivity regardless of player count.

---

## 4. The Flutter App (`app/`)

### 4.1 Entry point chain

```
main.dart
  └─► ProviderScope (Riverpod root)
        └─► GoHackMeApp
              ├─► MaterialApp.router (appRouter = GoRouter)
              └─► builder wraps every screen in:
                    MediaQuery(textScaler: …)   ← scales ALL text globally
                    UiScale(scale: …)            ← scales layout dims via context.s()
```

You never touch `textScaleFactor` in individual widgets. All text scaling
happens in one place at the root.

### 4.2 Navigation

`app_router.dart` defines all named routes as constants on `Routes`:

```
/               → AuthScreen       (display name entry)
/lobby          → LobbyScreen
/solo           → LocalGameScreen  (vs bot)
/game/:roomId   → GameScreen       (WebSocket)
/lan/host       → LanHostScreen
/lan/join       → LanJoinScreen
/lan/game       → LanGameScreen
/wired/host     → WiredHostScreen
/wired/join     → WiredJoinScreen
/navi           → NaviTerminalScreen
```

Navigation always uses `context.push(Routes.xxx, extra: {…})` — never
`Navigator.push`. Route parameters come back through `state.pathParameters`
or `state.extra`.

### 4.3 State management (Riverpod)

Every stateful piece of the app is a `Notifier` or `AsyncNotifier`. There are
no `StatefulWidget` singletons holding game state.

| Provider | Type | What it holds |
|---|---|---|
| `authProvider` | `AsyncNotifier<AuthState>` | Local UUID + display name (SharedPreferences). |
| `gameStateProvider` | `AsyncNotifier<GameState?>` | WebSocket game (online mode). |
| `gameLogProvider` | `Notifier<List<String>>` | Last 50 log lines for the HUD terminal. |
| `lanGameProvider` | `Notifier<LanGameState>` | LAN session state (host or client role). |
| `localGameProvider` | `Notifier<GameState?>` | Solo game (vs bot). |
| `localGameLogProvider` | `Notifier<List<String>>` | Solo game log lines. |

**Pattern used everywhere:**

```dart
// In Notifier:
void placeStone(Position pos) {
  final result = GameEngine.placeStone(state!, playerId, pos);
  if (result case ActionSuccess(:final newState)) state = newState;
}

// In Widget:
ref.read(localGameProvider.notifier).placeStone(pos);
```

The widget reads state with `ref.watch(…)` and dispatches actions with
`ref.read(…notifier).method()`. Widgets are pure view; no game logic lives
in them.

### 4.4 The transport abstraction

All three multiplayer modes (WebSocket, LAN, WebRTC) have different transport
mechanisms but the same Riverpod notifier interface. The abstraction is
`IGameTransport`:

```dart
abstract interface class IGameTransport {
  Stream<GameState> get stateStream;
  Stream<String>    get logStream;
  Stream<String>    get errorStream;
  Stream<List<LanPlayer>> get playerListStream;
  void sendAction(GameMessage msg);
  Future<void> dispose();
}
```

`LanHostService`, `LanClientService`, and `WiredClientService` all implement
this. `LanGameNotifier` stores a single `IGameTransport? _transport` field
and never branches on host vs client for actions — it just calls
`_transport.sendAction(…)`.

The host and client are unified at the notifier level. Only the setup methods
(`startAsHost` vs `joinRoom`) differ.

### 4.5 The board renderer

`BoardPainter` is a `CustomPainter` that draws the board in a 3D
orthographic (axonometric) projection. Two top-level helpers in
`board_painter.dart` are the mathematical core:

```
compute3dScale(size, boardSize, elevation, zoom)
  → float: how many pixels one board-unit takes given viewport + camera.

board3dHitTest(tap, size, boardSize, azimuth, elevation, zoom)
  → Position?: inverse-projects a screen tap back to a board coordinate.
```

The camera has three degrees of freedom: **azimuth** (horizontal rotation),
**elevation** (tilt), and **zoom**. `BoardWidget` owns these values and
updates them via `onScaleStart/Update/End` gestures (orbit + pinch).

Tap detection is not `onTap` but a manual check in `onScaleEnd`:
no drag + scale delta near 1.0 + elapsed < 350 ms = it was a tap.
This is needed because the same gesture system handles both orbit and tap.

Each player's stones are rendered with a distinct `_SignalIdentity`
(colour, glow radius, node shape index). The shape index selects one of four
vector symbols drawn on the stone surface, making players distinguishable
without relying on colour alone.

---

## 5. LAN Mode in Detail

LAN mode is the most complex flow in the app because one device is both a
server and a player.

```
Host device                         Client device
───────────────────────────────     ─────────────────────────────────
LanHostService
  .startServer()
    │ binds TCP socket
    │ starts UDP beacon (port 8081)
    └─► LanDiscoveryService
          broadcasts "GOHACKME_DISCOVER"
                                    LanDiscoveryService (scan)
                                      receives "GOHACKME_SERVER:<port>"
                                    ↓
                                    LanClientService.connect()
                                      TCP connect to host
                                      send joinRoom message

Host receives joinRoom
  └─► applies as local engine action (no socket round-trip for the host)
      broadcasts gameStateUpdate to all clients

All connected devices receive GameState via stateStream
```

On the host device, `LanHostService.sendAction()` bypasses TCP entirely —
it runs `GameEngine` locally and broadcasts the result. On client devices,
`LanClientService.sendAction()` writes a JSON line over the TCP socket.
`LanGameNotifier` does not know or care which one it has.

---

## 6. Consistency Conventions

These are the rules the codebase follows to stay coherent. If you add code,
follow them.

### Immutable state

Never mutate a `GameState`, `Board`, or any model in place.
Always call `.copyWith(…)` or a method that returns a new instance.
Riverpod enforces this at the provider level — assigning `state =` triggers
a rebuild; mutating a field inside the current `state` does not.

### GameEngine is the only mutation gate

All state changes, whether in the server's `GameRoom`, in
`LocalGameNotifier`, or in `LanGameNotifier`, go through one of:

```dart
GameEngine.placeStone(…)
GameEngine.pass(…)
GameEngine.launchAttack(…)
GameEngine.endAttackPhase(…)
GameEngine.skipDdosVictim(…)
```

Never write game rules inline in a provider or widget. Always call the engine.

### ActionResult handling

Always use a `switch` on `ActionResult`. The sealed class prevents missing
a branch at compile time:

```dart
switch (result) {
  case ActionSuccess(:final newState): state = newState;
  case ActionFailure(:final reason): log.append('ERR: $reason');
}
```

### Server is authoritative

The server never trusts the `playerId` field in action messages — it uses the
identity established at `joinRoom` time. The client cannot lie about who it is.

### GameState is the full snapshot

The server sends the complete `GameState` after every mutation. There are no
delta updates, no client-side predictions to reconcile. Whatever `stateStream`
emits is the ground truth; the client replaces its state wholesale.

### Shared protocol

`GameMessage` and the entire `go_engine` package are shared. If you change
the serialisation of any model (e.g. add a field to `GameState`), update
`toJson` / `fromJson` in one place and both the app and server pick it up
automatically. Never define a second JSON format.

### Streams, not callbacks

Inter-service communication uses `Stream`. Services expose `stateStream`,
`logStream`, `errorStream`. Providers subscribe in their `build()` method
and cancel subscriptions in `ref.onDispose`. No callbacks, no global
event buses.

### UiScale for layout, textScaler for text

- Text sizes: set them once in `CyberpunkTheme` or inline `style: TextStyle(fontSize: 12)`.
  The `textScaler` at the root handles screen-density scaling automatically.
- Layout dimensions (padding, container height, icon size): use `context.s(value)`.
  This multiplies by `UiScale.of(context)` which scales from 1.0 on phones
  up to 1.8 on 4K desktops.

---

## 7. File Map

```
app/lib/
  main.dart                          Entry point. ProviderScope + UiScale setup.
  core/
    router/app_router.dart           All GoRouter routes and the Routes constants.
    theme/
      cyberpunk_colors.dart          All colour constants (CyberpunkColors.cyan etc.).
      cyberpunk_theme.dart           Full ThemeData. Used once in main.dart.
      ui_scale.dart                  UiScale InheritedWidget + context.s() extension.
    widgets/
      glitch_overlay.dart            CRT scanline + glitch burst animation wrapper.
  features/
    auth/
      providers/auth_provider.dart   UUID + display name. Loaded from SharedPreferences.
      screens/auth_screen.dart       Name entry screen shown on first launch.
    lobby/
      screens/lobby_screen.dart      Mode selector (solo / LAN / Wired).
      screens/navi_terminal_screen.dart  Lore/help terminal (NAVI).
    board/
      providers/
        game_provider.dart           Online (WebSocket) game state + log.
        lan_game_provider.dart       LAN game state (unified host+client).
        local_game_provider.dart     Solo vs bot game state + log.
      screens/
        game_screen.dart             Online game screen.
        lan_game_screen.dart         LAN game screen.
        local_game_screen.dart       Solo game screen.
        lan_join_screen.dart         LAN discovery scan + room list.
      widgets/
        board_widget.dart            GestureDetector wrapper; owns camera state.
        board_painter.dart           CustomPainter; 3D projection math.
        game_layout.dart             Full game UI (board + HUD + attack picker).
  services/
    i_game_transport.dart            Transport interface (IGameTransport).
    lan_client_service.dart          TCP client implementation of IGameTransport.
    lan_host_service.dart            TCP server implementation of IGameTransport.
    lan_discovery_service.dart       UDP beacon broadcaster + scanner.
    game_sync_service.dart           WebSocket client for online mode.
    wired_client_service.dart        WebRTC client implementation of IGameTransport.

packages/go_engine/lib/
  go_engine.dart                     Barrel export. Import this everywhere.
  src/models/
    position.dart                    (x, y) value type.
    stone_color.dart                 p1–p4 enum.
    board.dart                       Immutable grid.
    player.dart                      id + displayName.
    attack.dart                      AttackType, AttackCard, AttackAction, ActiveEffect.
    game_state.dart                  Full game snapshot + GamePhase.
  src/engine/
    go_rules.dart                    Pure Go rules (group, liberty, capture, Ko).
    scorer.dart                      Area scoring + subnet bonus.
    attack_system.dart               Attack validation + effect application.
    game_engine.dart                 Public API. ActionResult sealed type.
    bot_player.dart                  Local AI (beginner + intermediate).
  src/messages/
    game_message.dart                Wire protocol. Shared by app and server.

server/lib/src/
  ws_handler.dart                    WebSocket upgrade. Security guards. Routes to room.
  game_room.dart                     One room. GameState. Fan-out broadcasts.
  room_manager.dart                  Room lifecycle (create, reap, cap).
  discovery_service.dart             UDP auto-discovery responder.
```

---

## 8. Adding a New Feature — Checklist

1. **New game mechanic?** — Add logic to `go_engine`. Pure static function.
   Update `GameState.copyWith` if new state is needed. Add tests.

2. **New attack type?** — Add to `AttackType` enum, add an `AttackCard` entry,
   handle the new case in `AttackSystem.applyAttack` and `tickEffectsForPlayer`.

3. **New screen?** — Add a `Routes.xxx` constant, add a `GoRoute` in
   `app_router.dart`, create the screen file under `features/`.

4. **New provider?** — Use `Notifier` for sync state, `AsyncNotifier` for
   async state. Expose actions as plain methods, not as streams or callbacks.

5. **New network message?** — Add the type to `MessageType`, handle it in
   `ws_handler.dart` (server) and in the relevant service's `_handleLine` /
   `_handleJson` (client).
