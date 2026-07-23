# Demo / Tutorial System — Implementation Plan

A two-phase interactive tutorial: first it teaches Go rules as a guided
walkthrough, then it gives an interactive sandbox for every special move.
The whole thing lives entirely on-device — no network, no server.

---

## What it is

The demo is split into two sequential chapters:

**Chapter 1 — GO_BASICS.protocol**
A scripted, step-by-step walkthrough of a real 7×7 board. NAVI narrates
each step and highlights the relevant intersections. The player cannot make
wrong moves — they tap the exact stone NAVI tells them to, or tap `[SKIP]`.
Concepts introduced in order:

1. What a liberty is (place a single stone, show its 4 neighbours highlighted)
2. Capture (place stones around an enemy group, watch it disappear)
3. Ko rule teaser (show a position and explain why you can't recapture)
4. Territory and scoring (show an end position, count area, sum up)
5. The `PASS` action

**Chapter 2 — ATTACK_CODEX.interactive**
Eight mini-sandboxes, one per attack, each with a pre-set board position
and infinite undo. The player can freely experiment; NAVI explains what just
happened after each use. Order follows subnet cost (cheapest first):

| # | Attack | What the sandbox shows |
|---|--------|------------------------|
| 1 | BACKDOOR.sh | Pre-placed enemy group. Player activates BACKDOOR, places 2 stones, sees the difference vs. a normal turn. |
| 2 | PATCH.sh | Enemy threatens to DDOS. Player uses PATCH, enemy DDOS fires, nothing happens. |
| 3 | WORM.sh | Board with several enemy stones. Player selects one to overwrite. |
| 4 | TROJAN.sh | Enemy has 10 SN. Player fires TROJAN, watches subnet split. |
| 5 | KNIGHTS_EYE.sh | Player plants the trap on a stone in danger. Bot captures it. Reclaim fires. |
| 6 | DDOS.sh | Player fires DDOS at bot. Bot's turn comes, it is skipped, log shows "DDOS'd". |
| 7 | MITM.sh | Player fires MITM. On bot's turn, player sees "place bot's stone" prompt. |
| 8 | PSYCHE.sh | Player fires PSYCHE. Next 3 bot turns show the 5-second countdown UI. |

---

## Entry Points

### First launch prompt (first time only)
After the user sets their display name and lands on the lobby for the first
time, a modal dialog appears:

```
┌─────────────────────────────────────────────────┐
│  NEW ENTITY DETECTED                            │
│                                                 │
│  NAVI has prepared a training protocol.         │
│  Learn Go rules and all special moves           │
│  before your first session.                     │
│                                                 │
│  [RUN_DEMO.sh]          [SKIP — jack in blind]  │
└─────────────────────────────────────────────────┘
```

The "seen demo prompt" flag is persisted in `SharedPreferences` with key
`demo_prompt_seen`. After the user responds (either way), the flag is set
so the dialog never appears again.

### From NAVI terminal
A new command `[demo]` is added to the NAVI terminal, visible in the `[help]`
listing. Typing `demo` navigates to the demo screen and starts from Chapter 1.

A second command `[demo attacks]` jumps directly to Chapter 2 (attack sandbox)
for players who already know Go but want to explore the hacks.

---

## Architecture

### New files

#### [NEW] `app/lib/features/demo/`
A self-contained feature folder — no dependency on any game provider.

```
demo/
  screens/
    demo_screen.dart           ← Root screen. Owns chapter index + step index.
  widgets/
    demo_board_widget.dart     ← Simplified read-only board. Highlights cells.
                                 Accepts a callback for "tap allowed" positions.
    demo_navi_panel.dart       ← NAVI narration box (typewriter effect, same
                                 style as NaviTerminalScreen).
    demo_step_controls.dart    ← [NEXT ▶] / [SKIP] / [PREV ◀] row.
    attack_sandbox_widget.dart ← Full interactive mini-game for Chapter 2.
  data/
    demo_steps.dart            ← All Chapter 1 steps as a plain data list.
    attack_sandboxes.dart      ← Pre-set GameState + narration for each attack.
```

#### [NEW] `app/lib/services/demo_service.dart`
One tiny service: `bool hasSeenDemoPrompt()` and `markDemoPromptSeen()`,
backed by `SharedPreferences`. No Riverpod provider needed; just static methods.

### Modified files

#### [MODIFY] `app/lib/core/router/app_router.dart`
Add route `/demo` → `DemoScreen`. Optionally accept `?chapter=2` to jump
straight to the attack sandbox.

```dart
static const demo = '/demo';
```

#### [MODIFY] `app/lib/features/lobby/screens/navi_terminal_screen.dart`
Add `demo` and `demo attacks` to `_naviResponses`:

```
'demo': [
  '> LOADING: DEMO_PROTOCOL_v1.0...',
  '',
  '  Initialising training environment.',
  '',
],
```
The `_submit()` handler detects `demo` / `demo attacks` and calls
`context.push(Routes.demo, extra: {'chapter': 1})`.

#### [MODIFY] `app/lib/features/lobby/screens/lobby_screen.dart`
In `initState`, after the greeting audio:

```dart
final seen = await DemoService.hasSeenDemoPrompt();
if (!seen && mounted) _showDemoPromptDialog();
```

The dialog uses the same `_DialogShell` / `showGeneralDialog` pattern as every
other lobby dialog. Two buttons: `[RUN_DEMO.sh]` → mark seen + push `/demo`,
`[SKIP]` → mark seen only.

---

## Chapter 1 — Step Data Model

```dart
class DemoStep {
  final String naviText;          // Typewriter narration
  final List<Position> highlight; // Glowing intersections
  final List<Position> tapTarget; // If non-empty, user must tap one of these
  final GameState? boardState;    // Null = carry forward from previous step
}
```

Each step has a pre-baked `GameState` (the immutable engine model already used
everywhere). Steps are stored in `demo_steps.dart` as a `const List<DemoStep>`.
The board is fixed at 7×7 to keep the tutorial compact without adding new
engine logic.

---

## Chapter 2 — Sandbox Data Model

```dart
class AttackSandbox {
  final AttackType attack;
  final GameState initialState; // Pre-set position with enough SN to fire
  final String naviIntro;       // Shown before the player acts
  final String naviAfter;       // Shown after the attack fires
}
```

`attack_sandbox_widget.dart` wraps a real `LocalGameNotifier`-style state
(but self-contained, not using `localGameProvider`) so `GameEngine.launchAttack`
and `GameEngine.placeStone` work exactly as in a real game. There is a
`[RESET]` button to restore `initialState` and a `[NEXT ATTACK ▶]` button
to proceed to the next sandbox.

---

## User Flow Diagram

```
First launch
  └─► AuthScreen (name entry)
        └─► LobbyScreen.initState
              └─► DemoService.hasSeenDemoPrompt() == false
                    └─► _NewEntityDialog shown
                          ├─► [RUN_DEMO.sh]  → mark seen → push /demo (ch 1)
                          └─► [SKIP]         → mark seen → stay on lobby

Returning user
  └─► LobbyScreen (dialog never shown again)

From NAVI terminal
  ├─► type "demo"         → push /demo (ch 1)
  └─► type "demo attacks" → push /demo?chapter=2 (ch 2 only)

/demo screen
  ├─► Chapter 1: GO_BASICS
  │     Step 0..N → user taps or hits [NEXT]
  │     Final step → "Protocol complete. Proceed to ATTACK_CODEX? [YES] [EXIT]"
  │
  └─► Chapter 2: ATTACK_CODEX
        Sandbox 0..7 (one per attack)
        Final sandbox → "Training complete. [JACK IN]" → pop to lobby
```

---

## Key Design Decisions

> [!IMPORTANT]
> **No new engine logic.** The demo uses `GameEngine` and `GameState` exactly
> as the real game does. Chapter 2 sandboxes are just pre-baked `GameState`
> values; no special-casing inside the engine.

> [!NOTE]
> **7×7 board for Chapter 1.** The engine already supports any board size.
> 7×7 is not a standard Go size but is ideal for tutorial visibility.
> No engine change needed.

> [!NOTE]
> **Chapter 2 is standalone state.** Each sandbox creates a fresh ephemeral
> notifier (plain `StateNotifier`-like class, not a Riverpod provider) so
> sandboxes don't pollute `localGameProvider` or any other provider. Pressing
> `[RESET]` just re-assigns to `initialState`.

> [!IMPORTANT]
> **`demo_prompt_seen` is the only persisted state.** The demo itself saves
> nothing. Progress is not resumed if the user closes mid-demo — they restart
> from Chapter 1. (This keeps the data model dead simple and matches the
> "tutorial is short" assumption.)

---

## Open Questions

1. **Should Chapter 1 allow free placement** (anywhere legal) or **force the
   exact tap target** NAVI describes? Forcing is more guided; free placement
   lets the player explore at the cost of more complex step validation.

2. **Should the first-launch prompt also appear on the SECOND launch** if the
   player chose `[SKIP]` before? Or is once-and-never-again the right UX?
   Current plan: mark seen regardless of choice (never show again).

3. **"demo attacks" as a NAVI command** — should it skip the whole chapter
   and go directly to a specific attack? E.g., `demo worm` jumps straight
   to the WORM sandbox? This would be useful for quick reference mid-session.

---

## Verification Plan

### Automated Tests
- Unit-test `DemoService` (mock `SharedPreferences`): `hasSeenDemoPrompt` returns
  false on first call, true after `markDemoPromptSeen()`.
- Widget-test `DemoScreen` Chapter 1 step progression (tap → advance).

### Manual Verification
- Fresh app install → name entry → lobby → demo dialog appears.
- Tap `[SKIP]` → dialog never shows again.
- Navigate to NAVI → type `demo` → `/demo` screen opens.
- Type `demo attacks` → opens Chapter 2 directly.
- Walk through all 8 attack sandboxes and confirm each effect fires as described.
- Tap `[RESET]` in a sandbox, confirm state reverts to `initialState`.
