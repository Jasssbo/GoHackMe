import 'package:go_router/go_router.dart';
import 'package:go_engine/go_engine.dart';

import '../../features/auth/screens/auth_screen.dart';
import '../../features/board/screens/game_screen.dart';
import '../../features/board/screens/lan_game_screen.dart';
import '../../features/board/screens/lan_join_screen.dart';
import '../../features/board/screens/local_game_screen.dart';
import '../../features/board/screens/wired_game_screen.dart';
import '../../features/lobby/screens/lobby_screen.dart';
import '../../features/lobby/screens/navi_terminal_screen.dart';
import '../../features/lobby/screens/resume_game_screen.dart';
import '../../services/lan_discovery_service.dart';
import '../../services/saved_game_service.dart';

/// Named route constants.
abstract class Routes {
  static const auth = '/';
  static const lobby = '/lobby';
  static const game = '/game/:roomId';
  static const solo = '/solo';
  static const lanHost = '/lan/host';
  static const lanJoin = '/lan/join';
  static const lanGame = '/lan/game';
  static const wiredHost = '/wired/host';
  static const wiredJoin = '/wired/join';
  static const navi = '/navi';
  static const resumeGame = '/resume';

  static String gamePath(String roomId) => '/game/$roomId';
}

final appRouter = GoRouter(
  initialLocation: Routes.auth,
  routes: [
    GoRoute(
      path: Routes.auth,
      name: 'auth',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: Routes.lobby,
      name: 'lobby',
      builder: (context, state) => const LobbyScreen(),
    ),
    GoRoute(
      path: Routes.game,
      name: 'game',
      builder: (context, state) {
        final roomId = state.pathParameters['roomId']!;
        final extras = state.extra as Map<String, dynamic>?;
        return GameScreen(
          roomId: roomId,
          boardSize: (extras?['boardSize'] as int?) ?? 19,
          maxPlayers: (extras?['maxPlayers'] as int?) ?? 2,
          serverUrl: (extras?['serverUrl'] as String?) ?? 'ws://localhost:8080/ws',
        );
      },
    ),
    GoRoute(
      path: Routes.solo,
      name: 'solo',
      builder: (context, state) {
        final extras = state.extra as Map<String, dynamic>?;
        final diffStr = extras?['difficulty'] as String? ?? 'intermediate';
        final difficulty = diffStr == 'beginner'
            ? BotDifficulty.beginner
            : BotDifficulty.intermediate;
        return LocalGameScreen(
          boardSize: (extras?['boardSize'] as int?) ?? 9,
          difficulty: difficulty,
          botCount: (extras?['botCount'] as int?) ?? 1,
        );
      },
    ),
    GoRoute(
      path: Routes.lanJoin,
      name: 'lanJoin',
      builder: (context, state) => const LanJoinScreen(),
    ),
    GoRoute(
      path: Routes.lanHost,
      name: 'lanHost',
      builder: (context, state) {
        final extras = state.extra as Map<String, dynamic>?;
        return LanGameScreen(
          boardSize: (extras?['boardSize'] as int?) ?? 19,
          maxPlayers: (extras?['maxPlayers'] as int?) ?? 2,
        );
      },
    ),
    GoRoute(
      path: Routes.lanGame,
      name: 'lanGame',
      builder: (context, state) {
        final extras = state.extra as Map<String, dynamic>?;
        final room = extras?['room'] as LanRoom?;
        return LanGameScreen(room: room);
      },
    ),
    GoRoute(
      path: Routes.wiredHost,
      name: 'wiredHost',
      builder: (context, state) {
        final extras = state.extra as Map<String, dynamic>?;
        return WiredGameScreen(
          isHost: true,
          boardSize: (extras?['boardSize'] as int?) ?? 19,
          maxPlayers: (extras?['maxPlayers'] as int?) ?? 2,
        );
      },
    ),
    GoRoute(
      path: Routes.wiredJoin,
      name: 'wiredJoin',
      builder: (context, state) {
        final extras = state.extra as Map<String, dynamic>?;
        final roomCode = extras?['roomCode'] as String?;
        return WiredGameScreen(isHost: false, initialRoomCode: roomCode);
      },
    ),
    GoRoute(
      path: Routes.navi,
      name: 'navi',
      builder: (context, state) => const NaviTerminalScreen(),
    ),
    GoRoute(
      path: Routes.resumeGame,
      name: 'resumeGame',
      builder: (context, state) {
        final extras = state.extra as Map<String, dynamic>;
        return ResumeGameScreen(
          save: extras['save'] as SavedGame,
          mode: extras['mode'] as ResumeGameMode,
        );
      },
    ),
  ],
);
