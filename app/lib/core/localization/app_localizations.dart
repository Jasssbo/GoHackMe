import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLanguage {
  en('en', 'ENGLISH', 'English'),
  es('es', 'SPANISH', 'Español'),
  ja('ja', 'JAPANESE', '日本語'),
  zh('zh', 'CHINESE', '中文');

  final String code;
  final String label;
  final String nativeName;
  const AppLanguage(this.code, this.label, this.nativeName);

  static AppLanguage fromCode(String code) {
    final normalized = code.trim().toLowerCase();
    return AppLanguage.values.firstWhere(
      (l) => l.code == normalized || l.label.toLowerCase() == normalized,
      orElse: () => AppLanguage.en,
    );
  }
}

class LocaleNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() => AppLanguage.en;

  void setLanguage(AppLanguage language) {
    state = language;
  }

  bool switchByCode(String code) {
    final lang = AppLanguage.fromCode(code);
    state = lang;
    return true;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, AppLanguage>(
  LocaleNotifier.new,
);

/// Lightweight localized string lookup helper.
class AppStrings {
  static final Map<AppLanguage, Map<String, String>> _translations = {
    AppLanguage.en: {
      'your_turn': 'YOUR_TURN.exe',
      'awaiting_signal': 'AWAITING_ENTITY_UPLINK',
      'entities': '// ENTITIES',
      'logs': '// LOGS',
      'attack_vector': '// ATTACK_VECTOR',
      'select_target': '> SELECT_TARGET',
      'say': 'SAY...',
      'pass': 'PASS',
      'save': 'SAVE',
      'undo': 'UNDO',
      'exit': 'EXIT',
      'lang_switched': 'LANGUAGE_SET :: ',
    },
    AppLanguage.es: {
      'your_turn': 'TU_TURNO.exe',
      'awaiting_signal': 'ESPERANDO_SEÑAL_RED',
      'entities': '// ENTIDADES',
      'logs': '// REGISTROS',
      'attack_vector': '// VECTOR_DE_ATAQUE',
      'select_target': '> SELECCIONAR_OBJETIVO',
      'say': 'HABLAR...',
      'pass': 'PASAR',
      'save': 'GUARDAR',
      'undo': 'DESHACER',
      'exit': 'SALIR',
      'lang_switched': 'IDIOMA_ESTABLECIDO :: ',
    },
    AppLanguage.ja: {
      'your_turn': 'アナタノターン.exe',
      'awaiting_signal': 'シグナルタイキチュウ',
      'entities': '// エンティティ',
      'logs': '// ログ',
      'attack_vector': '// アタックベクトル',
      'select_target': '> ターゲットセンタク',
      'say': 'チャット...',
      'pass': 'パス',
      'save': 'セーブ',
      'undo': 'アンドゥ',
      'exit': 'シュウリョウ',
      'lang_switched': 'ゲンゴセッテイ :: ',
    },
    AppLanguage.zh: {
      'your_turn': '你的回合.exe',
      'awaiting_signal': '等待信号连接',
      'entities': '// 实体节点',
      'logs': '// 终端日志',
      'attack_vector': '// 攻击载荷',
      'select_target': '> 选择目标节点',
      'say': '发送...',
      'pass': '跳过',
      'save': '保存',
      'undo': '撤销',
      'exit': '退出',
      'lang_switched': '语言设置 :: ',
    },
  };

  static String tr(AppLanguage lang, String key) {
    return _translations[lang]?[key] ?? _translations[AppLanguage.en]?[key] ?? key;
  }
}
