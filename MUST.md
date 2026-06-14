Production Readiness & Feature Review
Everything below is grounded in what I actually found reading the code, cross-referenced against practices from OGS/KGS/Sabaki (Go), Bitburner/IPvGO/Hacknet (hacking games), and Flutter production patterns.

1. Engine & Gameplay
A. ✅ DONE — Bot needs a third difficulty tier
Current BotPlayer has beginner (random) and intermediate (capture/save heuristics). pickAttack only ever launches DDOS. For a production game you want an advanced tier using a lightweight Monte Carlo simulation or a territory-count evaluation function — exactly what engines like Fuego do at a small scale. Concretely:

pickAttack at advanced should also consider TROJAN when the target has more subnets, PATCH when the bot is about to be attacked, and BACKDOOR when in a close-position game.
A territory-influence pass (count stones + enclosed empty intersections per candidate move) would beat the current centre-bias heuristic dramatically.
— Implemented: `BotDifficulty.advanced` added. `_pickAdvanced` samples up to 30 candidates, runs `Scorer.territoryRegions` before/after each simulated placement, and picks the move with the highest `(territory_gain + captures×2)` score. `_pickAdvancedAttack` priority: PATCH (if self is debuffed) → TROJAN (if target is richer) → BACKDOOR (close game, stone delta ≤ board÷3) → DDOS fallback.
B. ✅ DONE — Turn timer is not synchronized with the server
GameLayout starts a 15-second _turnCountdownTimer on the client independently of the server clock. Server timeout is also 15 s. If a reconnect happens mid-turn, the client resets to 15 s while the server may only have 3 s left. Sync: send the server's turnStartedAt timestamp inside gameStateUpdate payload, then the client calculates 15 - elapsed on receipt.
— Implemented: `GameRoom._turnStartedAt` tracks wall-clock turn start (UTC); included as `turnStartedAt` ms in every `gameStateUpdate` payload. `WiredServerService` extracts it and emits via a new `turnStartedAtStream` (added to `IGameTransport`; LAN services return `Stream.empty()`). `WiredGameState.serverTurnStartedAt` carries it. `GameLayout._resetTurnCountdown` seeds remaining seconds from the server timestamp when present, falling back to 15 s for local/LAN.

C. ✅ DONE — GamePhase.placement is dead code
It is declared in the enum but the game starts in GamePhase.attack and never transitions to placement. Either rename attack to something cleaner or remove the enum value — it creates reading confusion.
— Implemented: `placement` value and its doc comment removed from the enum; the `attack` doc comment updated to describe both placement and the optional attack phase.

D. ✅ DONE — Scoring phase has no territory visualization
The GamePhase.scoring transition just shows final scores. OGS, Sabaki, and Bitburner's IPvGO all colour the board with territory regions at game end. You have Scorer.areaScore() which does the flood-fill — you just need to expose the region sets alongside the scores so BoardPainter can shade them.
— Implemented: `Scorer.territoryRegions()` added to engine; `_drawScoringOverlay()` draws per-player diamond markers on claimed empty intersections; wired through `BoardWidget` and `GameLayout`.

E. No SGF export
Smart Game Format is the universal Go record format (used by every Go server). Even Bitburner/IPvGO supports exporting a replay string. One Dart serialization function of ~50 lines would give you replay sharing, game analysis in external tools, and a trophy system at zero server cost.

2. Server
A. ✅ DONE — HTTP rate-limiter has an unbounded memory leak
In _httpRateLimit() the counters map grows forever — one entry per unique IP, entries are never deleted after their window expires. A server running for weeks accumulates thousands of stale entries. Fix: after evicting old timestamps, also delete the map entry if the slice becomes empty:
— Implemented: `if (timestamps.isEmpty) counters.remove(ip);` added immediately after `removeWhere`; the `if` check now reads from the map so the removed entry is handled correctly.


B. No spectator connections
Every major Go server (OGS, KGS, IGS) supports watchers. Currently a non-player WebSocket that joins a started room is either rejected (Wired) or treated as a new player (LAN). A spectator join type would open the /rooms lobby experience to live game watching — high impact for community.

C. No persistence
Games, move history, and room metadata evaporate on restart. Even a SQLite file via package:sqlite3 would enable replays, player history, and ELO. Hacknet and Bitburner both store full session state. For a stateless cloud deployment you can store games as append-only JSON lines streamed to an S3-compatible bucket.

D. /stats exposes internal room count without auth
Anyone can poll GET /stats and correlate with /rooms to infer exactly how many games are active and when the server is idle. For a competitive game this is fine; for a production service you'd gate it behind a bearer token or remove it.

E. No server-side move log or replay feed
The server discards every ActionSuccess.logMessage after broadcasting. Store these in a List<String> per room and include them in a GET /rooms/:id/log endpoint — the basis for a replay system and better post-game analysis.

F. Server tests are stale and give false confidence
server_test.dart tests / and /echo/hello — sample routes that no longer exist. They fail with 404. Replace with tests that actually cover /health, /rooms, WebSocket join/join-collision, rate limiting, and UUID validation.

3. Flutter App
A. ✅ DONE — No haptic feedback on stone placement
Every production mobile game uses haptics. HapticFeedback.mediumImpact() on stone placement and HapticFeedback.heavyImpact() on capture would dramatically improve feel — one-line change per event.
— Implemented: medium on placement, light on attack dispatch, heavy on capture detection in `didUpdateWidget`.

B. No audio
Stone placement, captures, and attack launches have no sound. Hacknet's sound design is 70% of its atmosphere. Even simple 8-bit tones generated with package:audioplayers would transform the cyberpunk experience. Bitburner/IPvGO uses distinct click sounds per action type.

C. No deep links / share sheet for room codes
If a host wants to invite someone to a Wired room, they have to communicate the 6-char code out-of-band. go_router already supports GoRouter.of(context).go() from a URI; adding app_links or Flutter's uni_links would let you generate shareable links like gohackme://join/XYZABC that open the app directly into the join flow.

D. ✅ DONE — Board coordinate overlay is missing
Every Go app (Sabaki, OGS, even IPvGO) shows A–T column labels and 1–19 row labels. Experienced players reference moves by coordinate (Q16 opening, tengen, etc.). A toggle in the game settings for coordinate overlay would cost about 20 lines in BoardPainter.
— Implemented: `_drawCoordLabels` was already present; fixed column letters to skip 'I' per standard Go convention (A–H then J–T).

E. ✅ DONE — No undo in solo mode
Every mobile Go app has undo in single-player. LocalGameNotifier could maintain a List<GameState> history and pop it on undo — the immutable GameState design you already have makes this trivial.
— Implemented: `_undoHistory` stack (cap 10) in `LocalGameNotifier`; `canUndo` getter + `undo()` method; [UNDO] button in `GameStatusStrip` (magenta, only visible when `canUndo` is true).

F. App lifecycle: game continues while backgrounded
When the app goes to background mid-Wired game, the server's 15 s turn timer fires and auto-passes. The client has no warning. Add WidgetsBindingObserver.didChangeAppLifecycleState in WiredGameScreen to emit a BACKGROUNDED log line and optionally display a banner on resume showing missed turns.

G. Responsive layout
On tablets and landscape desktop the board takes up a fixed fraction of screen. LayoutBuilder + a two-column game layout (board left, HUD right) for screens wider than 600 pt would make the desktop build feel intentional rather than a stretched phone UI.

H. Accessibility
No Semantics wrappers on board intersections, no excludeSemantics on decorative glitch effects. A screen reader cannot play the game. At minimum, each intersection should have a Semantics(label: '${color} stone at ${col}${row}') for accessibility compliance.

I. Dependency drift
flutter_riverpod ^2.6.1 is pinned behind v3 (a major Riverpod release with breaking changes but also large performance gains). go_router ^14.8.1 is behind v17. These won't break anything today but will block adopting new Flutter versions. Both packages have migration guides.

J. build_runner and build_resolvers are discontinued
flutter pub outdated showed these are discontinued. They're only dev dependencies (used by riverpod_generator and json_serializable) but when they eventually stop working you'll need to migrate to Dart Macros or an alternative. Worth tracking as a known tech-debt item.

4. Security / Production Ops (remaining from audit)
A. Android cleartext is globally permitted
network_security_config.xml:22 sets cleartextTrafficPermitted="true" globally. The comment explains the LAN constraint correctly, but this also silently allows any future http:// or ws:// URL for any host including internet ones. The safer shape: set cleartextTrafficPermitted="false" at base level and rely on NSAllowsLocalNetworking-equivalent (<base-config cleartextTrafficPermitted="false">) plus an explicit <domain-config> for localhost only. LAN IP routing still works via NSAllowsLocalNetworking on iOS; Android LAN traffic goes through the socket directly without HTTP, so game data (TCP/WS raw sockets) is unaffected by the NSC flag.

B. No CI pipeline at all
No workflows. For production you need at minimum: dart test + flutter test on push, flutter analyze as a gate, and dart pub outdated as a weekly scheduled job. GitHub Actions has free minutes for public repos.

C. ✅ DONE — /rooms leaks geolocation metadata publicly
The city/country/lat/lon of the host's IP is returned to anyone who calls GET /rooms. This is a privacy risk. Either omit coordinates from the public rooms list (keep them only for internal globe rendering) or only return coarse data (country code only, no coordinates or city).
— Implemented: `city` removed from the public rooms map; lat/lon kept (already rounded to 1 decimal ≈ 11 km precision) so the globe widget continues to function; country kept for coarse display.

5. New Features — Best Impact / Effort
Feature	Inspiration	Effort	Impact
Sound effects (stone, capture, attack)	Hacknet, Bitburner	Low	Very high
Haptic feedback	Every mobile game	Trivial	High	✅ DONE
Territory colour overlay at game end	OGS, IPvGO, Sabaki	Low	High	✅ DONE
Board coordinates (A1–T19)	Every Go app	Low	Medium	✅ DONE
Undo in solo mode	Every mobile Go app	Low	Medium	✅ DONE
Room share link via deep link	OGS, mobile games	Medium	High
Move counter / game clock display	KGS, OGS	Low	Medium	✅ DONE
SGF export	Sabaki, OGS, KGS	Medium	High
ELO rating system	OGS, GoQuest	High	Very high
Spectator mode	OGS, KGS	High	High
Bot advanced difficulty (MCTS or minimax)	Fuego, GnuGo, IPvGO	High	Medium
Byoyomi time control (Japanese: N periods of K seconds)	KGS, OGS	Medium	Medium
Tsumego / puzzle mode	OGS, Joseki apps	High	High
Post-game replay scrubber	Sabaki, OGS	High	High
Server persistence (SQLite or S3 log)	All production Go servers	High	High