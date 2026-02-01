import 'dart:async';
import 'package:intl/intl.dart';

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/player.dart';
import 'providers/game_state.dart';
import 'models/item.dart';
import 'models/pet.dart';
import 'models/hunting_zone.dart';
import 'models/monster.dart';
import 'services/update_service.dart';
import 'services/auth_service.dart';
import 'config/supabase_config.dart';
import 'widgets/inventory_panel.dart';
import 'widgets/skill_panel.dart';
import 'widgets/pet_panel.dart';
import 'widgets/achievement_panel.dart';
import 'widgets/character_panel.dart';
import 'widgets/common_widgets.dart';
import 'widgets/quest_overlay.dart';
import 'widgets/quick_menu_panel.dart'; // 🆕 신규 통합 메뉴 도입
import 'widgets/arena_panel.dart'; // 🆕 무투회 결투장 패널 도입
import 'engine/game_loop.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Supabase 초기화
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
  
  runApp(const IdleWarriorApp());
}

class IdleWarriorApp extends StatelessWidget {
  const IdleWarriorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GameState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Idle Warrior Adventure',
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.deepPurple,
          scaffoldBackgroundColor: const Color(0xFF0F111A),
          textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
          useMaterial3: true,
        ),
        home: const GameMainPage(),
      ),
    );
  }
}

class GameMainPage extends StatefulWidget {
  const GameMainPage({super.key});

  @override
  State<GameMainPage> createState() => _GameMainPageState();
}

// ═══════════════════════════════════════════════════════════════════════════
// 🎮 GAME STATE CLASS - 게임 상태 관리 클래스
// ═══════════════════════════════════════════════════════════════════════════

class _GameMainPageState extends State<GameMainPage> with TickerProviderStateMixin {
  late GameLoop _gameLoop;
  int _selectedIndex = 0; // 0~9
  int _currentLogTab = 0;

  // 가방 필터 및 정렬용
  Timer? _scrollStopTimer;

  late AnimationController _playerAttackController;
  late AnimationController _playerHitController;
  late AnimationController _monsterAttackController;
  late AnimationController _monsterHitController;
  late AnimationController _uiTickerController; // 60FPS UI 갱신용
  late AnimationController _shimmerController; // 프리미엄 아이템 광택용
  late AnimationController _monsterSpawnController; // 몬스터 등장 연출
  late AnimationController _monsterDeathController; // 몬스터 사망 연출
  late AnimationController _heroPulseController; 
  late AnimationController _heroRotateController;
  final DamageManager damageManager = DamageManager(); 
  int _sessionMaxDamage = 0; 

  // 효율 측정용 (UI 표시용 세션 데이터만 유지)
  final List<GainRecord> _recentGains = [];
  int _sessionGold = 0;
  int _sessionExp = 0;
  

  // 전리품 파티클 시스템
  final List<LootParticle> _lootParticles = [];
  final GlobalKey _battleSceneKey = GlobalKey(); // 🆕 배틀 장면 좌표 기준키
  final GlobalKey _monsterKey = GlobalKey();
  
  // 관리자 모드
  bool _isAdminAuthenticated = false;
  double _monsterDefenseMultiplier = 0.0; // 몬스터 방어력 배율 (0.0 ~ 1.0)

  // 화면 모드 관리
  DisplayMode _displayMode = DisplayMode.normal;
  // 세션 통합 통계 (절전 모드용)
  static const int _sessionItems = 0; // Const as they are 0 and never changed in this class
  static const int _sessionStones = 0;
  static const int _sessionPowder = 0;
  static const int _sessionReroll = 0;
  static const int _sessionCube = 0;
  static const int _sessionProtection = 0;

  // 스테이지 가속(점프) 시스템 관련
  DateTime _lastUiTick = DateTime.now(); // 🆕 30FPS 쓰로틀링용
  
  // 알림 중착 방지용
  OverlayEntry? _activeNotification;
  bool _showJumpEffect = false; // [v0.0.79] 경량화된 점프 애니메이션 상태
  Timer? _jumpEffectTimer;

  // 🆕 화면 흔들림(Screen Shake) 관련 상태
  double _shakeOffsetX = 0;
  double _shakeOffsetY = 0;
  Timer? _shakeTimer;

  // --- [신규 v0.0.60] 제작 시스템 상태 ---
  int _selectedCraftTier = 2; // 기본 선택 티어 (T2)
  int _expandedCraftCategory = 0; // 0: 장외 제작, 그 외: 준비 중
  bool _isGeneralExpanded = true; 
  bool _isSpecialExpanded = true;
  Timer? _efficiencyTimer; // 🆕 메모리 관리를 위해 타이머를 변수화

  // --- [신규 v0.0.53] 무한의 탑 상태 ---
  int _towerCountdown = 0;
  bool _isEnteringTower = false;
  bool _isTowerResultShowing = false;
  HuntingZone? _previousZone;
  int? _previousStage;
  Timer? _towerTimer;

  // --- [신규 v0.5.6] 지능형 전리품 알림 시스템 상태 ---
  final List<LootNotification> _lootNotifications = [];
  final GlobalKey<AnimatedListState> _lootListKey = GlobalKey<AnimatedListState>();

  // --- [신규 v0.5.47] 적정 사냥터 버프 힌트 상태 ---
  bool _showOptimalZoneHint = false;
  Timer? _optimalZoneHintTimer;

  // --- [신규 v0.8.32] 버프 상세 정보 힌트 상태 ---
  String? _activeBuffHint;
  Timer? _buffHintTimer;

  // --- [신규 v0.0.61] 자동 분해 시스템 ---

  // --- [신규 v0.1.x] 라운드 로빈 전투 시스템 ---
  // --- [신규 v0.1.x] 전역 게터 ---
  Player get player => context.read<GameState>().player;
  GameState get gameState => context.read<GameState>();
  AuthService get _authService => context.read<GameState>().authService;
  bool get _isCloudSynced => context.read<GameState>().isCloudSynced;
  set _isCloudSynced(bool val) => context.read<GameState>().isCloudSynced = val;
  HuntingZone get _currentZone => context.read<GameState>().currentZone;
  set _currentZone(HuntingZone val) => context.read<GameState>().currentZone = val;
  int get _currentStage => context.read<GameState>().currentStage;
  set _currentStage(int val) => context.read<GameState>().currentStage = val;
  Map<ZoneId, int> get _zoneStages => context.read<GameState>().zoneStages;
  
  Monster? get currentMonster => context.read<GameState>().currentMonster;
  set currentMonster(Monster? m) => context.read<GameState>().currentMonster = m;
  
  int get playerCurrentHp => gameState.playerCurrentHp;
  set playerCurrentHp(int val) => gameState.playerCurrentHp = val;
  int get monsterCurrentHp => gameState.monsterCurrentHp;
  set monsterCurrentHp(int val) => gameState.monsterCurrentHp = val;

  List<CombatLogEntry> get combatLogs => gameState.logs;
  List<CombatLogEntry> get damageLogs => gameState.logs.where((l) => l.type == LogType.damage).toList();
  List<CombatLogEntry> get itemLogs => gameState.logs.where((l) => l.type == LogType.item).toList();
  List<CombatLogEntry> get eventLogs => gameState.logs.where((l) => l.type == LogType.event).toList();

  // 다음에 탐색할 스킬 인덱스

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔄 LIFECYCLE & DATA MANAGEMENT - 생명주기 및 데이터 관리
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    final gameState = context.read<GameState>();
    _gameLoop = GameLoop(gameState);
    
    _playerAttackController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _playerHitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _monsterAttackController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _monsterHitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _uiTickerController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _shimmerController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    
    _monsterSpawnController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    // 🆕 [v2.2.1] 등장 애니메이션 종료 시점에 전투 시작 허용
    _monsterSpawnController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 무한의 탑이나 무투회는 이미 spawnMonster에서 잠금을 해제했을 수 있으나, 
        // 일반 사냥터의 리듬을 위해 애니메이션 종료 후 확실히 해제함
        if (gameState.currentZone.id != ZoneId.tower && !gameState.isArenaMode) {
          gameState.completeMonsterSpawn();
        }
      }
    });
    _monsterDeathController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _heroPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    _heroRotateController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    
    _uiTickerController.addListener(() {
      final now = DateTime.now();
      // 🆕 30FPS 쓰로틀링: 33ms가 경과하지 않았으면 업데이트 스킵
      if (now.difference(_lastUiTick).inMilliseconds < 33) return;
      _lastUiTick = now;

      _updateParticles(); 
      damageManager.update(); 
    });
    
    _gameLoop.start();
    
    // 🆕 전투 이벤트와 UI 연출 연결
    gameState.onDamageDealt = (text, damage, isCrit, isSkill, {ox, oy, shouldAnimate = true, skillIcon, combo}) {
      if (!mounted) return;

      // 🆕 데미지 효율 기록 추가
      _recentGains.add(GainRecord(DateTime.now(), damage: damage));

      // 🆕 최대 데미지 기록 갱신 (단일 타격 기준)
      if (damage > _sessionMaxDamage) {
        setState(() {
          _sessionMaxDamage = damage;
        });
      }

      if (shouldAnimate) {
        // 몬스터 피격 (뒤로 밀림)
        _monsterHitController.forward(from: 0);
        // 플레이어 공격 (앞으로 튀어남)
        _playerAttackController.forward(from: 0);
      }
      // 데미지 텍스트 (isSkill 여부 전달, 오프셋 반영, 스킬 아이콘 전달)
      _addFloatingText(text, true, isCrit: isCrit, isSkill: isSkill, offsetX: ox, offsetY: oy, skillIcon: skillIcon, combo: combo);
    };

    gameState.onHeal = (healAmount) {
      if (!mounted) return;
      _addFloatingText('+$healAmount', false, isHeal: true);
    };

    gameState.onPlayerDamageTaken = (damage, {isShield = false}) {
      if (!mounted) return;
      // 플레이어 피격 (뒤로 밀림)
      _playerHitController.forward(from: 0);
      // 몬스터 공격 (앞으로 튀어나감)
      _monsterAttackController.forward(from: 0);
      
      // 🆕 [v0.8.29] 보호막 피격 여부에 따른 텍스트 연출
      _addFloatingText('-$damage', false, isShield: isShield);
    };

    gameState.onMonsterSpawned = () {
      if (!mounted) return;
      // 몬스터 등장 애니메이션 초기화 및 실행
      _monsterDeathController.reset();
      _monsterSpawnController.forward(from: 0);
    };

    // 🆕 럭키 스트릭, 천장 성공 등 특수 연출 연결
    gameState.onSpecialEvent = (title, message) {
      if (!mounted) return;
      _showSuccess(title, message);
    };

    // 🆕 [v0.5.6] 전리품 획득 알림 연결
    gameState.onLootAcquired = (icon, name, grade, {amount = 1}) {
      if (!mounted) return;
      _addLootNotification(icon, name, grade, amount: amount);
    };

    gameState.onVictory = (gold, exp) {
      if (!mounted) return;
      
      // 1. 세션 데이터 업데이트 (UI 표시용)
      _recentGains.add(GainRecord(DateTime.now(), gold: gold, exp: exp, kills: 1));
      _sessionGold += gold;
      _sessionExp += exp;

      // 2. 몬스터 사망 애니메이션 실행
      _monsterDeathController.forward(from: 0);

      // 3. 드롭 파티클 연출 제거 (v0.5.54)
      /* 
      final monsterBox = _monsterKey.currentContext?.findRenderObject() as RenderBox?;
      final battleBox = _battleSceneKey.currentContext?.findRenderObject() as RenderBox?;
      
      if (monsterBox != null && battleBox != null) {
        final globalCenter = monsterBox.localToGlobal(monsterBox.size.center(Offset.zero));
        final localPos = battleBox.globalToLocal(globalCenter);
        _spawnLootParticles(gold, exp, localPos);
      }
      */

      // 4. 무한의 탑일 경우 결과창 표시
      if (gameState.currentZone.id == ZoneId.tower) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTowerResultDialog(true);
        });
      }
    };

    gameState.onStageJump = () {
      if (!mounted) return;
      _triggerJumpEffect();
    };

    gameState.onPlayerDeath = () {
      if (!mounted) return;
      if (gameState.currentZone.id == ZoneId.tower) {
        _showTowerResultDialog(false);
      } else {
        _showToast('사망하여 스테이지가 하락했습니다.', isError: true);
      }
    };

    gameState.onPromotionSuccess = (level, name, bonus) {
      if (!mounted) return;
      _showPromotionDialog(level, name, bonus);
    };

    gameState.onItemPromotionSuccess = (item, oldTier, oldStat1, oldStat2) {
      if (!mounted) return;
      _showItemPromotionDialog(item, oldTier, oldStat1, oldStat2);
    };

    gameState.onSpecialDungeonEnd = () {
      if (!mounted) return;
      _exitSpecialDungeon();
    };


    // 초기 실행 시 몬스터가 이미 있다면 등장 애니메이션 실행
    if (gameState.currentMonster != null) {
      _monsterSpawnController.forward(from: 0);
    }
    
    // 🆕 분당 효율 계산 타이머 (2초마다 갱신으로 상향)
    _efficiencyTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updateEfficiencyStats();
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOfflineRewards();
      UpdateService.checkUpdate(context);
      _precacheCurrentZoneImages(); // 🆕 시작 시 이미지 사전 캐싱
    });
  }

  // 🆕 [v0.5.55] 현재 지역 및 인접 사냥터 이미지 사전 캐싱 (디코딩 지연 방지)
  void _precacheCurrentZoneImages() {
    if (!mounted) return;
    
    // 현재 지역 몬스터 이미지들
    final zoneIds = [gameState.currentZone.id];
    
    for (var zid in zoneIds) {
      final zone = HuntingZoneData.list.firstWhere((z) => z.id == zid);
      for (var species in zone.monsterNames) {
        final fileName = Monster.monsterImgMap[species];
        if (fileName != null) {
          final path = (species == '슬라임') 
            ? 'assets/images/slime.png' 
            : 'assets/images/monsters/$fileName';
          
          precacheImage(AssetImage(path), context);
        }
      }
    }
  }

  // 🆕 분당 효율 통계 계산
  void _updateEfficiencyStats() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 60));
    
    // 60초 이전 데이터 제거
    _recentGains.removeWhere((g) => g.time.isBefore(cutoff));
    
    if (_recentGains.isEmpty) {
      gameState.resetEfficiency(); // Call resetEfficiency
      return;
    }
    
    // 최근 60초간의 총합 계산
    int totalGold = 0;
    int totalExp = 0;
    int totalKills = 0;
    int totalDmg = 0;
    
    for (var record in _recentGains) {
      totalGold += record.gold;
      totalExp += record.exp;
      totalKills += record.kills;
      totalDmg += record.damage;
    }
    
    // 실제 경과 시간 계산 (초 단위)
    final oldestTime = _recentGains.first.time;
    final elapsedSeconds = now.difference(oldestTime).inSeconds;
    
    if (elapsedSeconds > 0) {
      // 분당 환산 (초당 * 60)
      gameState.updateEfficiency(
        totalGold / elapsedSeconds * 60,
        totalExp / elapsedSeconds * 60,
        totalKills / elapsedSeconds * 60,
        totalDmg / elapsedSeconds * 60,
      );
    }
  }


  @override
  void dispose() {
    // 1. 타이머 및 컨트롤러 정지
    _scrollStopTimer?.cancel();
    _jumpEffectTimer?.cancel();
    _efficiencyTimer?.cancel();
    _towerTimer?.cancel();
    _optimalZoneHintTimer?.cancel();

    
    // 2. 오버레이 클린업 (알림이 남아있는 경우 제거)
    _activeNotification?.remove();
    _activeNotification = null;

    // 3. 글로벌 위젯 콜백 해제 (GameState 참조 해제하여 GC 유도)
    final gs = context.read<GameState>();
    gs.onDamageDealt = null;
    gs.onHeal = null;
    gs.onPlayerDamageTaken = null;
    gs.onMonsterSpawned = null;
    gs.onSpecialEvent = null;
    gs.onVictory = null;
    gs.onStageJump = null;

    // 4. 애니메이션 컨트롤러 해제
    _playerAttackController.dispose();
    _playerHitController.dispose();
    _monsterAttackController.dispose();
    _monsterHitController.dispose();
    _uiTickerController.dispose();
    _shimmerController.dispose();
    _monsterSpawnController.dispose();
    _monsterDeathController.dispose();
    _heroPulseController.dispose();
    _heroRotateController.dispose();
    
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⚔️ COMBAT SYSTEM - 전투 시스템
  // ═══════════════════════════════════════════════════════════════════════════


  // --- 화면 모드 순환 (일반 -> 화면유지 -> 절전 -> 일반) ---
  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 UI FEEDBACK & DISPLAY - UI 피드백 및 화면 모드
  // ═══════════════════════════════════════════════════════════════════════════

  void _cycleDisplayMode() {
    setState(() {
      switch (_displayMode) {
        case DisplayMode.normal:
          _displayMode = DisplayMode.stayAwake;
          WakelockPlus.enable();
          _showToast('화면 유지 모드 활성화', isError: false);
          break;
        case DisplayMode.stayAwake:
          _displayMode = DisplayMode.powerSave;
          // 절전 모드에서도 화면은 계속 켜져 있어야 하므로 유지
          _showToast('절전 모드 진입', isError: false);
          break;
        case DisplayMode.powerSave:
          _displayMode = DisplayMode.normal;
          WakelockPlus.disable();
          _showToast('일반 모드로 복귀', isError: false);
          break;
      }
    });
  }

  void _spawnLootParticles(int gold, int exp, Offset startPos) {
    if (!mounted) return;
    final rand = Random();

    // 골드 파티클 생성
    for (int i = 0; i < 5; i++) {
      _lootParticles.add(LootParticle(
        startPos,
        LootType.gold,
        DateTime.now().add(Duration(milliseconds: i * 50)),
        rand,
      ));
    }
    // 경험치 파티클 생성
    for (int i = 0; i < 3; i++) {
      _lootParticles.add(LootParticle(
        startPos,
        LootType.exp,
        DateTime.now().add(Duration(milliseconds: i * 70)),
        rand,
      ));
    }
    
    // 파티클은 CustomPainter가 직접 그리므로 setState를 부르지 않거나 최소화
  }

  void _updateParticles() {
    final now = DateTime.now();
    if (!mounted || _lootParticles.isEmpty) return;
    
    // 1초 이상 된 파티클 제거
    _lootParticles.removeWhere((p) => now.difference(p.startTime).inMilliseconds > 1200);
  }


  // 🆕 데미지 텍스트 추가 API (통합 관리)
  // 🆕 통합 관제 센터 메뉴 열기
  void _showQuickMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'QuickMenu',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const QuickMenuPanel(),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutBack)),
            child: child,
          ),
        );
      },
    );
  }

  void _addFloatingText(String text, bool isMonsterTarget, {
    bool isCrit = false, 
    bool isSkill = false,
    bool isHeal = false, 
    bool isGold = false, 
    bool isExp = false, 
    bool isShield = false, // 🆕 보호막 전용 필드
    double? offsetX, 
    double? offsetY,
    String? skillIcon, // 🆕 스킬 아이콘 추가
    int? combo, // 🆕 콤보 정보 추가
  }) {
    final rand = Random();
    
    // 타입 결정 (우선순위: 회복 > 스킬 > 크리티컬 > 기타)
    DamageType type = DamageType.normal;
    if (isHeal) { type = DamageType.heal; }
    else if (isSkill) { type = DamageType.skill; }
    else if (isCrit) { type = DamageType.critical; }
    else if (isShield) { type = DamageType.shield; } // 🆕 보호막 우선순위 반영
    else if (isGold) { type = DamageType.gold; }
    else if (isExp) { type = DamageType.exp; }

    // 1. 기준 좌표 계산 (글로벌 -> 로컬 변환)
    Offset basePos = const Offset(200, 300); // 폴백값
    
    // 배틀 장면의 렌더박스 확보
    final battleBox = _battleSceneKey.currentContext?.findRenderObject() as RenderBox?;
    if (battleBox != null) {
      if (isMonsterTarget) {
        final monsterBox = _monsterKey.currentContext?.findRenderObject() as RenderBox?;
        if (monsterBox != null) {
          // 몬스터 중심의 글로벌 좌표를 배틀 장면의 로컬 좌표로 변환
          final globalCenter = monsterBox.localToGlobal(Offset(monsterBox.size.width / 2, monsterBox.size.height / 2));
          basePos = battleBox.globalToLocal(globalCenter);
        }
      } else {
        // 플레이어 캐릭터는 좌측에 고정된 편 (배틀 박스 기준 상대 좌표 사용 제안)
        // 화면 크기에 대응하기 위해 하드코딩 대신 비율 또는 몬스터 대비 좌측 위치 사용
        basePos = Offset(battleBox.size.width * 0.25, battleBox.size.height * 0.6);
      }
    }

    // 2. 추가 오프셋 적용 (더 넓게 흩어지도록 범위 확장)
    double ox = offsetX ?? (rand.nextDouble() * 80) - 40; // ±40px 범위
    double oy = offsetY ?? (rand.nextDouble() * 50) - 25; // ±25px 범위
    
    damageManager.add(DamageEntry(
      text: text,
      createdAt: DateTime.now(),
      type: type,
      basePosition: basePos + Offset(ox, oy),
      skillIcon: skillIcon, // 🆕 아이콘 전달
      combo: combo, // 🆕 콤보 전달
    ));
  }

  // 🆕 화면 흔들림 효과 유도함수
  void _triggerScreenShake({double intensity = 5.0, int duration = 200}) {
    if (_displayMode == DisplayMode.powerSave) return; // 절전 모드 시 스킵
    
    _shakeTimer?.cancel();
    final endTime = DateTime.now().add(Duration(milliseconds: duration));
    final rand = Random();
    
    _shakeTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || DateTime.now().isAfter(endTime)) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _shakeOffsetX = 0;
            _shakeOffsetY = 0;
          });
        }
        return;
      }
      
      setState(() {
        _shakeOffsetX = (rand.nextDouble() * 2 - 1) * intensity;
        _shakeOffsetY = (rand.nextDouble() * 2 - 1) * intensity;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 0번 탭(전투)일 때만 전역 사냥터 배경 활성화 (RepaintBoundary 최적화 순서 교정)
          if (_selectedIndex == 0)
            Positioned.fill(
              child: RepaintBoundary(
                child: Selector<GameState, ZoneId>(
                  selector: (_, gs) => gs.currentZone.id,
                  builder: (context, zoneId, child) {
                    String bgName;
                    if (zoneId == ZoneId.goldenRoom) {
                      bgName = 'chamber';
                    } else if (zoneId == ZoneId.trialRoom) {
                      bgName = 'material';
                    } else {
                      bgName = zoneId.name;
                    }
                    return Image(
                      image: AssetImage('assets/images/backgrounds/bg_$bgName.png'),
                      fit: BoxFit.cover,
                      color: Colors.black.withValues(alpha: 0.2),
                      colorBlendMode: BlendMode.darken,
                      errorBuilder: (context, error, stackTrace) => Container(color: Colors.black), 
                    );
                  },
                ),
              ),
            ),
          
          Container(
            color: _selectedIndex == 0 ? Colors.black26 : const Color(0xFF0F111A),
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopDashboard(),
                  _buildStageBarLarge(),
                  Expanded(
                    child: Stack(
                      children: [
                        // 핵심: 바디 콘텐츠를 RepaintBoundary로 감싸서 다른 UI와 렌더링 레이어 분리
                        Positioned.fill(child: RepaintBoundary(child: _buildBodyContent())),
                        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomDock()),
                        if (_selectedIndex == 0)
                          const Positioned(
                            right: 16,
                            bottom: 160,
                            child: QuestOverlay(),
                          ),
                        // 🆕 파티클 레이어 제거 (v0.5.54)

                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // --- 절전 모드 오버레이 (최상단) ---
          if (_displayMode == DisplayMode.powerSave)
            _buildPowerSaveOverlay(),
            
          // --- 스테이지 점프 효과 (전투 탭에서만 표시) ---
        if (_showJumpEffect && _selectedIndex == 0)
          _buildJumpStageEffect(),
        ],
      ),
    );
  }

  // --- 알림 시스템 핵심 로직 (Overlay 방식) ---
  void _showToast(String message, {bool isError = true}) {
    _activeNotification?.remove();
    _activeNotification = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastOverlayWidget(
        message: message,
        isError: isError,
        onDismiss: () {
          if (_activeNotification == entry) {
            entry.remove();
            _activeNotification = null;
          }
        },
      ),
    );
    _activeNotification = entry;
    Overlay.of(context).insert(entry);
  }

  void _showSuccess(String title, String subtitle) {
    _activeNotification?.remove();
    _activeNotification = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _SuccessOverlayWidget(
        title: title,
        subtitle: subtitle,
        onDismiss: () {
          if (_activeNotification == entry) {
            entry.remove();
            _activeNotification = null;
          }
        },
        shadowTextBuilder: (String text, {double fontSize = 14, Color color = Colors.white, FontWeight fontWeight = FontWeight.normal, TextOverflow? overflow}) => 
            ShadowText(text, fontSize: fontSize, color: color, fontWeight: fontWeight, overflow: overflow),
      ),
    );
    _activeNotification = entry;
    Overlay.of(context).insert(entry);
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 MAIN UI COMPONENTS - 메인 UI 컴포넌트
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBodyContent() {
    switch (_selectedIndex) {
      case 0: return _buildCombatTab();
      case 1: return const CharacterPanel();
      case 2: return _buildHuntingZoneTab(); // 사냥터 이동 메뉴 연결
      case 3: return InventoryPanel(onShowToast: _showToast); // 가방 메뉴 연결
      case 4: return _buildCraftTab();
      case 5: return SkillPanel(onShowToast: _showToast);
      case 6: return const PetPanel();
      case 7: return _buildMenuPlaceholder('유물 (환생)');
      case 8: return AchievementPanel(onShowToast: _showToast, onShowSuccess: _showSuccess);
      case 9: return _buildSystemTab(); // 실제 시스템/관리자 모드 연결
      case 10: return const ArenaPanel(); // 🆕 결투장 패널 연결
      default: return _buildCombatTab();
    }
  }

  Widget _buildMenuPlaceholder(String name) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: Column(
            children: [
              const Icon(Icons.construction, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 16),
              Text('$name 메뉴 준비 중', style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              PopBtn('전투로 돌아가기', Colors.blueAccent, () => setState(() => _selectedIndex = 0), isFull: false, icon: Icons.sports_martial_arts),
            ],
          ),
        ),
      ],
    ));
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // 🗺️ HUNTING ZONE - 사냥터 시스템
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHuntingZoneTab() {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 16),
                child: ShadowText('사냥터 이동', fontSize: 28, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // --- 일반 사냥터 섹션 ---
                    _buildCategoryHeader(
                      '일반 사냥터', 
                      Icons.explore, 
                      _isGeneralExpanded, 
                      () => setState(() => _isGeneralExpanded = !_isGeneralExpanded)
                    ),
                    if (_isGeneralExpanded)
                      ...HuntingZoneData.list
                          .where((z) => z.type == ZoneType.general)
                          .map((z) => _buildZoneCard(z)),
                    
                    const SizedBox(height: 16),
                    
                    // --- 특별 사냥터 섹션 ---
                    _buildCategoryHeader(
                      '특별 사냥터', 
                      Icons.auto_awesome, 
                      _isSpecialExpanded, 
                      () => setState(() => _isSpecialExpanded = !_isSpecialExpanded)
                    ),
                    if (_isSpecialExpanded)
                      ...HuntingZoneData.list
                          .where((z) => z.type == ZoneType.special)
                          .map((z) => _buildZoneCard(z)),
                    
                    const SizedBox(height: 100), // 하단 독 여백
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryHeader(String title, IconData icon, bool isExpanded, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white24, size: 20),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const Spacer(),
            Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneCard(HuntingZone zone) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        bool isCurrent = gameState.currentZone.id == zone.id;
        int stage = gameState.zoneStages[zone.id] ?? 1;
        final player = gameState.player;
        final bool isOptimal = player.totalSlotEnhanceLevel >= zone.minEnhance && player.totalSlotEnhanceLevel <= zone.maxEnhance;

        // 배경 이미지 경로 맵핑
        String bgName;
        if (zone.id == ZoneId.goldenRoom) {
          bgName = 'chamber';
        } else if (zone.id == ZoneId.trialRoom) {
          bgName = 'material';
        } else {
          bgName = zone.id.name;
        }
        String bgPath = 'assets/images/backgrounds/bg_$bgName.png';

        return GlassContainer(
          margin: const EdgeInsets.only(bottom: 10),
          borderRadius: 20,
          color: isCurrent 
            ? zone.color.withValues(alpha: 0.35) 
            : Colors.black.withValues(alpha: 0.4), // 배경이 있으므로 기본 색상을 더 어둡게
          backgroundImage: DecorationImage(
            image: AssetImage(bgPath),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: isCurrent ? 0.3 : 0.5), 
              BlendMode.darken
            ),
          ),

          border: Border.all(
            color: isCurrent ? zone.color.withValues(alpha: 0.6) : Colors.white10, 
            width: isCurrent ? 1.5 : 0.5
          ),
          child: InkWell(
            onTap: () {
              // 🆕 [v2.2] 사냥터 입장 조건 체크 (최소 슬롯 강화 수치)
              if (player.totalSlotEnhanceLevel < zone.minEnhance) {
                _showToast('${zone.name} 지역 입장 불가: 슬롯 총합 ${zone.minEnhance}강 이상 필요!', isError: true);
                return;
              }

              if (zone.id == ZoneId.tower) {
                _enterTower(zone);
              } else if (zone.id == ZoneId.goldenRoom || zone.id == ZoneId.trialRoom) {
                _enterSpecialDungeon(zone);
              } else {
                setState(() {
                  gameState.zoneStages[gameState.currentZone.id] = gameState.currentStage;
                  gameState.currentZone = zone;
                  gameState.currentStage = stage;
                  gameState.stageKills = 0;
                  _selectedIndex = 0;
                  gameState.addLog('${zone.name} 지역으로 이동했습니다.', LogType.event);
                  _spawnMonster();
                  _precacheCurrentZoneImages(); // 🆕 지역 이동 시 즉시 캐싱
                });
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                children: [
                    Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            ShadowText(zone.name, fontSize: 16, fontWeight: FontWeight.bold),
                            const SizedBox(width: 10),
                            // 적정 강화 배지
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: isOptimal ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isOptimal ? Colors.greenAccent.withValues(alpha: 0.4) : Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bolt, size: 10, color: isOptimal ? Colors.greenAccent : Colors.white38),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${zone.minEnhance}~${zone.maxEnhance}',
                                    style: TextStyle(
                                      fontSize: 10, 
                                      fontWeight: FontWeight.bold,
                                      color: isOptimal ? Colors.greenAccent : Colors.white,
                                      shadows: [
                                        Shadow(offset: const Offset(1, 1), blurRadius: 2, color: Colors.black.withValues(alpha: 0.8))
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 8),
                            // 티어 드랍 정보
                            _buildTierDropInfo(gameState, zone),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Text(zone.id == ZoneId.tower ? '층 ' : '스테이지 ', style: const TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)),
                          ShadowText('${Monster.getDisplayStage(stage)}', color: zone.color, fontWeight: FontWeight.w900, fontSize: 16),
                        ],
                      ),
                    ],
                  ),

                  if (zone.id != ZoneId.tower && zone.id != ZoneId.goldenRoom && zone.id != ZoneId.trialRoom) ...[
                    const Divider(color: Colors.white10, height: 20),
                    _buildExpeditionSlots(gameState, zone),
                  ],

                ],
              ),
            ),
          ),
        );

      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTierDropInfo(GameState gs, HuntingZone zone) {
    if (zone.id == ZoneId.tower || zone.id == ZoneId.goldenRoom || zone.id == ZoneId.trialRoom) return const SizedBox.shrink();

    String tierRange = "";
    switch (zone.id) {
      case ZoneId.grassland: tierRange = "T1"; break;
      case ZoneId.forest: tierRange = "T1~T2"; break;
      case ZoneId.mine: tierRange = "T1~T3"; break;
      case ZoneId.dungeon: tierRange = "T1~T4"; break;
      case ZoneId.volcano: tierRange = "T1~T5"; break;
      case ZoneId.snowfield:
      case ZoneId.abyss: tierRange = "T1~T6"; break;
      default: break;
    }
    
    if (tierRange.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.purpleAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 10, color: Colors.purpleAccent),
          const SizedBox(width: 4),
          Text(
            tierRange,
            style: const TextStyle(
              fontSize: 10, 
              fontWeight: FontWeight.bold,
              color: Colors.purpleAccent,
            ),
          ),
        ],
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // 🆕 [v0.6.2] 펫 탐사 슬롯 UI 및 시스템
  // ---------------------------------------------------------------------------
  Widget _buildExpeditionSlots(GameState gs, HuntingZone zone) {
    if (zone.id == ZoneId.tower || zone.id == ZoneId.goldenRoom || zone.id == ZoneId.trialRoom) return const SizedBox.shrink(); // 특별 던전 제외
    
    final zoneKey = zone.id.name;
    final maxStage = gs.zoneStages[zone.id] ?? 0;
    final dispatchData = gs.player.zoneExpeditions[zoneKey] ?? [null, null, null];
    final rewards = gs.calculateZoneExpeditionReward(zone.id);
    
    // 슬롯별 해금 조건
    final List<int> milestones = [300, 500, 1000];

    return Row(
      children: [
        // --- 펫 슬롯 3개 ---
        ...List.generate(3, (index) {
          final isUnlocked = maxStage >= milestones[index];
          final petId = dispatchData[index];
          Pet? pet;
          if (petId != null) {
            try {
              pet = gs.player.pets.firstWhere((p) => p.id == petId);
            } catch (_) {}
          }

          return GestureDetector(
            onTap: () {
              if (!isUnlocked) {
                _showToast('${milestones[index]} 스테이지 달성 시 해금됩니다.');
                return;
              }

              if (pet != null) {
                _showRecallConfirm(gs, zone.id, index, pet);
              } else {
                _showPetDispatchSheet(gs, zone.id, index);
              }
            },
            child: Container(
              width: 32, height: 32,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isUnlocked ? (pet != null ? pet.grade.color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)) : Colors.black26,
                border: Border.all(
                  color: isUnlocked ? (pet != null ? pet.grade.color : Colors.white24) : Colors.white10,
                  width: pet != null ? 1.5 : 1
                ),
              ),
              child: Center(
                child: !isUnlocked 
                  ? const Icon(Icons.lock, size: 12, color: Colors.white24)
                  : (pet != null 
                    ? Text(pet.iconEmoji, style: const TextStyle(fontSize: 14))
                    : const Icon(Icons.add, size: 14, color: Colors.white24)),
              ),
            ),
          );
        }),

        const Spacer(),

        // --- 실시간 수확 보상 정보 ---
        if (rewards.isNotEmpty)
          GestureDetector(
            onTap: () {
              final rewards = gs.claimExpeditionRewards(zone.id);
              if (rewards.isNotEmpty) {
                _showExpeditionResult(context, rewards, zone.name);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.amber.shade400.withValues(alpha: 0.1), Colors.orange.shade400.withValues(alpha: 0.2)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                   const Icon(Icons.monetization_on, size: 12, color: Colors.amber),
                   const SizedBox(width: 4),
                   Text(
                     NumberFormat.compact().format(rewards['gold']), 
                     style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)
                   ),
                   const SizedBox(width: 6),
                   const Icon(Icons.arrow_forward_ios, size: 8, color: Colors.white38),
                ],
              ),
            ),
          )
        else if (dispatchData.any((id) => id != null))
          const Text('수확 중...', style: TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic)),
      ],
    );
  }

  void _showPetDispatchSheet(GameState gs, ZoneId zoneId, int slotIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        final availablePets = gs.player.pets.where((p) {
          if (gs.player.activePet?.id == p.id) return false;
          return !gs.player.zoneExpeditions.values.any((list) => list.contains(p.id));
        }).toList();

        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('탐사 파견할 펫 선택', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white54)),
                ],
              ),
              const Text('전투에 참여하지 않는 펫을 파견하여 재화를 수확합니다.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 24),
              if (availablePets.isEmpty)
                const Expanded(child: Center(child: Text('파견 가능한 펫이 없습니다.', style: TextStyle(color: Colors.white24))))
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, 
                      mainAxisSpacing: 12, 
                      crossAxisSpacing: 12, 
                      childAspectRatio: 2.2
                    ),
                    itemCount: availablePets.length,
                    itemBuilder: (context, index) {
                      final pet = availablePets[index];
                      return InkWell(
                        onTap: () {
                          final error = gs.dispatchPetToZone(zoneId, slotIndex, pet.id);
                          if (error != null) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: pet.grade.color.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Text(pet.iconEmoji, style: const TextStyle(fontSize: 24)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(pet.name, style: TextStyle(color: pet.grade.color, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                    Text('효율 ${pet.dispatchEfficiency.toStringAsFixed(1)}x', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showRecallConfirm(GameState gs, ZoneId zoneId, int slotIndex, Pet pet) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${pet.iconEmoji} ${pet.name} 회수', style: const TextStyle(color: Colors.white)),
        content: const Text('펫을 회수하시겠습니까? 회수 시 지금까지 쌓인 보상은 자동 정산됩니다.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () {
              gs.recallPetFromZone(zoneId, slotIndex);
              Navigator.pop(context);
            }, 
            child: const Text('회수하기', style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );
  }

  /// 🧺 탐사 수확 결과 팝업
  void _showExpeditionResult(BuildContext context, Map<String, int> rewards, String zoneName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: 32,
          color: const Color(0xFF10121D).withOpacity(0.95),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 48),
              const SizedBox(height: 16),
              Text('[$zoneName] 탐사 보상', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('${rewards['minutes']}분 동안의 탐사 결과입니다.', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
                children: [
                  if (rewards['gold']! > 0) _buildExpRewardItem('💰', '골드', rewards['gold']!, Colors.amberAccent),
                  if (rewards['shards'] != null && rewards['shards']! > 0) _buildExpRewardItem('🧩', '연성 파편', rewards['shards']!, Colors.cyanAccent),
                  if (rewards['abyssalPowder'] != null && rewards['abyssalPowder']! > 0) _buildExpRewardItem('✨', '심연의 가루', rewards['abyssalPowder']!, Colors.orangeAccent),
                  if (rewards['stone'] != null && rewards['stone']! > 0) _buildExpRewardItem('💎', '강화석', rewards['stone']!, Colors.blueAccent),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpRewardItem(String emoji, String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            BigNumberFormatter.format(amount),
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }


  // 👤 CHARACTER TAB - 캐릭터 정보 탭
  // ═══════════════════════════════════════════════════════════════════════════


  // --- 가방 (인벤토리) 메뉴 구현 ---

  // --- 가방 (인벤토리) 메뉴 구현 ---
  // ═══════════════════════════════════════════════════════════════════════════

  // 🔨 [신규 v0.0.60] 제작 탭 (Forge UI)
  Widget _buildCraftTab() {
    return Consumer<GameState>(
      builder: (context, gs, child) {
        return Column(
          children: [
            const SizedBox(height: 12),
            _buildCraftHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  _buildCraftCategory(
                    0, '⚔️ 장비 제작 (리뉴얼 중)', 
                    isLocked: true,
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('장비 제작 시스템 고도화를 위해 잠시 중단되었습니다.\n승급 시스템을 이용해 주세요.', 
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white24, fontSize: 12))),
                    )
                  ),
                  _buildCraftCategory(
                    1, '🧪 소모품 제작 (입장권)', 
                    child: _buildConsumableCraftGrid(),
                  ),
                  _buildCraftCategory(2, '💎 유물 합성 (준비 중)', isLocked: true),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        );
      },
    );
  }


  Widget _buildCraftHeader() {
    int tier = _selectedCraftTier;
    // 장비 제작은 중단되었으므로 가이드를 위해 기본 재료만 표시
    
    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      color: Colors.white.withValues(alpha: 0.04),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('제작 숙련도', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              Text('Lv.${player.craftingMasteryLevel} (공격력 +${(player.craftingMasteryLevel * 0.5).toStringAsFixed(1)}%)', 
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(height: 4, width: double.infinity, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              FractionallySizedBox(
                widthFactor: (player.craftingMasteryExp / player.craftingMasteryNextExp).clamp(0.0, 1.0),
                child: Container(height: 4, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.cyanAccent, Colors.blueAccent]), borderRadius: BorderRadius.circular(2))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('공통 제작 재질', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLargeResourceItem('🧩', '연성 파편', player.shards, 0, Colors.tealAccent),
              Container(width: 1, height: 40, color: Colors.white10),
              _buildLargeResourceItem('✨', '심연의 가루', player.abyssalPowder, 0, Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeResourceItem(String emoji, String label, int current, int req, Color color) {
    bool isOk = current >= req;
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 10)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(_formatNumber(current), style: TextStyle(color: isOk ? color : Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 18)),
            Text(' / ${_formatNumber(req)}', style: const TextStyle(color: Colors.white10, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniResourceItem(String emoji, String label, int count, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 9)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(_formatNumber(count), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildCraftCategory(int index, String title, {Widget? child, bool isLocked = false}) {
    bool isExp = _expandedCraftCategory == index;
    return Column(
      children: [
        PressableScale(
          onTap: isLocked ? null : () => setState(() => _expandedCraftCategory = isExp ? -1 : index),
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            margin: const EdgeInsets.only(bottom: 8),
            borderRadius: 20,
            border: Border.all(color: isExp ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05)),
            color: isExp ? Colors.blueAccent.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.03),
            child: Row(
              children: [
                Text(title, style: TextStyle(color: isLocked ? Colors.white24 : Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isLocked) const Icon(Icons.lock, size: 16, color: Colors.white10)
                else Icon(isExp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white38),
              ],
            ),
          ),
        ),
        if (isExp && child != null) 
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.only(bottom: 20),
            child: child
          ),
      ],
    );
  }

  Widget _buildTierTab() {
    Map<int, int> unlockLevels = { 2: 300, 3: 1000, 4: 3000, 5: 7500, 6: 15000 };
    int currentTotal = player.totalSlotEnhanceLevel;

    // 🆕 [v0.5.38] 실제 해금 순서에 맞는 다음 목표 찾기
    int actualNextTier = 2;
    for (int t = 2; t <= 6; t++) {
      if (currentTotal < (unlockLevels[t] ?? 0)) {
        actualNextTier = t;
        break;
      }
    }
    
    int nextGoal = unlockLevels[actualNextTier] ?? 1;
    double progress = (currentTotal / nextGoal).clamp(0.0, 1.0);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [2, 3, 4, 5, 6].map((t) {
              int reqTotal = unlockLevels[t] ?? 0;
              bool isLocked = currentTotal < reqTotal;
              bool isSel = _selectedCraftTier == t;
              
              return Expanded(
                child: GestureDetector(
                  onTap: isLocked ? null : () => setState(() => _selectedCraftTier = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSel ? Colors.blueAccent.withValues(alpha: 0.8) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 🆕 [v0.5.40] 자동 제작 토글 (A 아이콘)
                          if (!isLocked)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  player.autoCraftTiers[t] = !(player.autoCraftTiers[t] ?? false);
                                });
                                if (player.autoCraftTiers[t] == true) {
                                  _showToast('재료가 모이면 자동으로 제작됩니다', isError: false);
                                } else {
                                  _showToast('T$t 자동 제작 비활성화');
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (player.autoCraftTiers[t] ?? false) ? Colors.greenAccent : Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'AUTO', 
                                  style: TextStyle(
                                    color: (player.autoCraftTiers[t] ?? false) ? Colors.black : Colors.white30, 
                                    fontSize: 7, 
                                    fontWeight: FontWeight.w900
                                  )
                                ),
                              ),
                            ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isLocked) const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.lock, size: 10, color: Colors.white24),
                              ),
                              Text(
                                'T$t', 
                                style: TextStyle(
                                  color: isSel ? Colors.white : (isLocked ? Colors.white10 : Colors.white60),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13
                                )
                              ),
                            ],
                          ),
                        ],
                      )
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // 🆕 해금 프로그레스 바
        if (_selectedCraftTier < 6)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('T$actualNextTier 해금까지 ($currentTotal / $nextGoal)', style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
                    Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildConsumableCraftGrid() {
    return Column(
      children: [
        _buildConsumableItem(
          '황금의 방 입장권', '골드가 가득한 특수 던전에 입장할 수 있습니다.', '🎫',
          500, 200, 
          () => gameState.craftTicket('gold'),
          player.goldDungeonTicket,
        ),
        const SizedBox(height: 12),
        _buildConsumableItem(
          '시련의 방 입장권', '강화석 등 성장 재료를 획득하는 던전에 입장할 수 있습니다.', '🎫',
          2000, 1000, 
          () => gameState.craftTicket('trial'),
          player.trialDungeonTicket,
        ),
      ],
    );
  }

  Widget _buildConsumableItem(String name, String desc, String emoji, int shardCost, int abyssalCost, VoidCallback onCraft, int currentCount) {
    bool canCraft = player.shards >= shardCost && player.abyssalPowder >= abyssalCost;

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      color: Colors.white.withValues(alpha: 0.03),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 8),
                    Text('보유: $currentCount', style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMiniResourceItem('🧩', '파편', shardCost, Colors.tealAccent),
                    const SizedBox(width: 12),
                    _buildMiniResourceItem('✨', '가루', abyssalCost, Colors.orangeAccent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PopBtn('제작', canCraft ? Colors.blueAccent : Colors.white12, onCraft, isFull: false, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
  }

  Widget _buildEquipmentCraftGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, // 3열로 변경하여 더 조밀하게 배치
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 110, // 높이 축소
        ),
        itemCount: ItemType.values.length,
        itemBuilder: (context, idx) {
          final type = ItemType.values[idx];
          return _buildCraftCard(type);
        },
      ),
    );
  }

  Widget _buildCraftCard(ItemType type) {
    int tier = _selectedCraftTier;
    final Map<int, int> shardCosts = { 2: 300, 3: 1000, 4: 3000, 5: 7500, 6: 15000 };
    final Map<int, int> coreCosts = { 2: 5, 3: 10, 4: 30, 5: 30, 6: 30 };
    
    int shardCost = shardCosts[tier] ?? 999999;
    int coreCost = coreCosts[tier] ?? 999999;
    
    bool canCraft = player.shards >= shardCost && player.abyssalPowder >= coreCost;

    return PressableScale(
      onTap: canCraft ? () => _executeCraft(type, tier, shardCost, coreCost) : () {
         _showToast('재료가 부족합니다.', isError: true);
      },
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 12),
        borderRadius: 20,
        border: Border.all(color: canCraft ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05), width: 1.5),
        color: canCraft ? Colors.blueAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyItemIcon(type: type, size: 32),
            const SizedBox(height: 8),
            Text(
              type.nameKr, 
              style: TextStyle(
                fontSize: 13, 
                fontWeight: FontWeight.w900, 
                color: canCraft ? Colors.white : Colors.white24
              )
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: canCraft ? Colors.blueAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                canCraft ? '생성 가능' : '재료 부족',
                style: TextStyle(
                  fontSize: 8, 
                  fontWeight: FontWeight.bold, 
                  color: canCraft ? Colors.white : Colors.white10
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCraftResourceRow(String emoji, int req, int my) {
    bool ok = my >= req;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(_formatNumber(my), style: TextStyle(fontSize: 10, color: ok ? Colors.white70 : Colors.redAccent, fontWeight: FontWeight.bold)),
          Text(' / ${_formatNumber(req)}', style: const TextStyle(fontSize: 10, color: Colors.white24)),
        ],
      ),
    );
  }

  void _executeCraft(ItemType type, int tier, int shardCost, int coreCost) {
    final gs = Provider.of<GameState>(context, listen: false);
    final newItem = gs.craftItem(type, tier, shardCost: shardCost, abyssalCost: coreCost);
    
    if (newItem != null) {
      _showCraftResult(newItem);
    }
  }


  void _showCraftResult(Item item) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadowText('연성 성공!', fontSize: 28, color: Colors.amberAccent, fontWeight: FontWeight.w900),
              const SizedBox(height: 30),
              _buildPremiumItemSlot(item, size: 100, onTap: () {}),
              const SizedBox(height: 20),
              ShadowText(item.name, fontSize: 18, color: item.grade.color, fontWeight: FontWeight.bold),
              const SizedBox(height: 40),
              PopBtn('인벤토리 확인', Colors.blueAccent, () => Navigator.pop(context), isFull: false),
            ],
          ),
        ),
      ),
    );
  }


  // --- 기존 UI 컴포넌트들 ---
  Widget _buildTopDashboard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 왼쪽: 캐릭터 및 사냥터 정보
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShadowText('Lv.', fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold),
                  const SizedBox(width: 4),
                  // 레벨만 전용 감시
                  Selector<GameState, int>(
                    selector: (_, gs) => gs.player.level,
                    builder: (_, lv, __) => ShadowText('$lv', fontSize: 18, color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 12),
                  ShadowText('CP', fontSize: 12, color: Colors.amber.withValues(alpha: 0.8), fontWeight: FontWeight.bold),
                  const SizedBox(width: 4),
                  // 전투력만 전용 감시
                  Selector<GameState, int>(
                    selector: (_, gs) => gs.player.combatPower,
                    builder: (_, cp, __) => ShadowText('$cp', fontSize: 18, color: Colors.amber, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 12),
                  ShadowText('Gold', fontSize: 12, color: Colors.amber.withValues(alpha: 0.6), fontWeight: FontWeight.bold),
                  const SizedBox(width: 4),
                  // 골드만 전용 감시
                  Selector<GameState, int>(
                    selector: (_, gs) => gs.player.gold,
                    builder: (_, gold, __) => ShadowText(_formatNumber(gold), fontSize: 18, color: Colors.amberAccent, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 8),
                  // 클라우드 상태 아이콘 (전체 상태 감시 유지)
                  Selector<GameState, bool>(
                    selector: (_, gs) => gs.isCloudSynced,
                    builder: (_, isSynced, __) => Icon(
                      isSynced ? Icons.cloud_done : Icons.cloud_off,
                      size: 14,
                      color: isSynced ? Colors.greenAccent : Colors.white24,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 오른쪽: 기능 버튼 (상태 변화와 거의 무관하므로 StatelessWidget처럼 동작)
          _buildDashboardActionBtn(
            _displayMode == DisplayMode.normal ? Icons.battery_saver : (_displayMode == DisplayMode.stayAwake ? Icons.light_mode : Icons.nightlight_round), 
            _displayMode == DisplayMode.normal ? '절전' : (_displayMode == DisplayMode.stayAwake ? '유지' : '절전중'), 
            _cycleDisplayMode,
            color: _displayMode == DisplayMode.normal ? Colors.greenAccent : (_displayMode == DisplayMode.stayAwake ? Colors.orangeAccent : Colors.blueAccent)
          ),
        ],
      ),
    );
  }

  // [v0.0.79] 경량화된 점프 애니메이션
  void _triggerJumpEffect() {
    _jumpEffectTimer?.cancel();
    setState(() => _showJumpEffect = true);
    _jumpEffectTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _showJumpEffect = false);
    });
  }

  Widget _buildJumpStageEffect() {
    if (!_showJumpEffect) return const SizedBox.shrink();
    
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _showJumpEffect ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flash_on,
                    color: Colors.amber,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'STAGE JUMP',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPowerSaveOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _cycleDisplayMode, // 단일 터치로 바로 해제
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black,
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 최상단 상태 표시
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.nightlight_round, size: 16, color: Colors.white24),
                    const SizedBox(width: 8),
                    Text('절전 모드 활성화 중', 
                      style: TextStyle(
                        color: Colors.white24, 
                        fontSize: 12, 
                        fontWeight: FontWeight.w900, 
                        letterSpacing: 2
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 60),
                
                // 세션 통계 타이틀
                const Text('현재 세션 획득 통계', 
                  style: TextStyle(color: Colors.white12, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)
                ),
                const SizedBox(height: 24),
                
                // 주요 획득 데이터 (한글화)
                _buildPowerSaveRow('💰 골드', _formatNumber(_sessionGold)),
                _buildPowerSaveRow('✨ 경험치', _formatNumber(_sessionExp)),
                _buildPowerSaveRow('📦 획득 아이템', _formatNumber(_sessionItems)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 100, vertical: 20),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                
                // 재화 상세 데이터 (한글화)
                _buildPowerSaveRow('💎 강화석', _formatNumber(_sessionStones)),
                _buildPowerSaveRow('✨ 마법 가루', _formatNumber(_sessionPowder)),
                _buildPowerSaveRow('🌀 재설정석', _formatNumber(_sessionReroll)),
                _buildPowerSaveRow('🛡️ 보호석', _formatNumber(_sessionProtection)),
                _buildPowerSaveRow('🔮 잠재력 큐브', _formatNumber(_sessionCube)),
                
                const Spacer(),
                
                // 해제 가이드
                const Text('화면을 터치하면 해제됩니다', 
                  style: TextStyle(color: Colors.white10, fontSize: 11, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPowerSaveRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 80),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white30, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(color: Colors.white60, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildDashboardActionBtn(IconData icon, String label, VoidCallback onTap, {Color color = Colors.greenAccent}) {
    return PressableScale(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        borderRadius: 10,
        blur: 5,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }





  Widget _buildStageBarLarge() {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        double progress = (gameState.stageKills / gameState.targetKills).clamp(0, 1);
        bool isBossStage = gameState.currentStage % 50 == 0;
        
        return Container(
          width: double.infinity,
          height: 14, 
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), 
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(7),
            // 보스 스테이지일 경우 바 전체에 미세한 붉은 광운 추가
            boxShadow: isBossStage ? [
              BoxShadow(color: Colors.redAccent.withValues(alpha: 0.15), blurRadius: 8, spreadRadius: 1)
            ] : null,
          ),
          child: Stack(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: progress),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, child) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: isBossStage ? [
                        BoxShadow(color: Colors.redAccent.withValues(alpha: 0.6), blurRadius: 10, spreadRadius: 2)
                      ] : null,
                      gradient: LinearGradient(
                        colors: isBossStage 
                            ? [Colors.redAccent, Colors.red.shade900] 
                            : [Colors.orangeAccent, Colors.orange],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (isBossStage) ...[
                          const Text('👑', style: TextStyle(fontSize: 10)),
                          const SizedBox(width: 4),
                          const Text('(보스) BOSS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.amberAccent, letterSpacing: 1)),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          gameState.currentZone.id == ZoneId.tower 
                            ? '👹 무한의 탑 - ${Monster.getDisplayStage(gameState.currentStage)}층 도전 중' 
                            : '${gameState.currentZone.name} - 스테이지 ${Monster.getDisplayStage(gameState.currentStage)}', 
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, fontStyle: FontStyle.italic)
                        ),
                      ],
                    ),
                    if (gameState.currentZone.id != ZoneId.tower)
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: gameState.autoAdvance ? Colors.greenAccent.withOpacity(0.2) : Colors.orangeAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: (gameState.autoAdvance ? Colors.greenAccent : Colors.orangeAccent).withOpacity(0.5), width: 0.5),
                            ),
                            child: Text(
                              gameState.autoAdvance ? 'AUTO' : 'FARM(고정)',
                              style: TextStyle(
                                color: gameState.autoAdvance ? Colors.greenAccent : Colors.orangeAccent,
                                fontSize: 7,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${gameState.stageKills} / ${gameState.targetKills}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCombatTab() {
    return Stack(
      children: [
        Column(
          children: [
            _buildCombatHeader(), // 진행도와 효율을 가로로 통합한 새로운 헤더
            Expanded(flex: 10, child: _buildBattleScene()), // 전투 비중 극대화 (7 -> 10)
            SkillQuickbar(
              uiTicker: _uiTickerController,
              onNavigateToSkillTab: () => setState(() => _selectedIndex = 5),
            ),
            const SizedBox(height: 80), // 하단 독 공간 확보
          ],
        ),
        
        // 🆕 [v0.5.6] 전리품 알림 레이어 (스킬 퀵바 위로 이동)
        Positioned(
          bottom: 170,
          left: 16,
          width: 200,
          child: _buildLootNotificationList(),
        ),

        // 🆕 전체 로그 버튼 (사냥 화면 우측 상단 플로팅)
        Positioned(
          top: 130,
          right: 16,
          child: _buildFloatingLogBtn(),
        ),
      ],
    );
  }

  Widget _buildFloatingLogBtn() {
    return PressableScale(
      onTap: _showFullLogDialog,
      child: SizedBox(
        width: 36, height: 36,
        child: GlassContainer(
          borderRadius: 10,
          color: Colors.black45,
          child: const Icon(Icons.history, size: 18, color: Colors.white54),
        ),
      ),
    );
  }

  Widget _buildCombatHeader() {
    return Column(
      children: [
        // 1. 경험치 및 스테이지 바 영역 (경험치 비율에 대해서만 Selector 적용)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Selector<GameState, double>(
            selector: (_, gs) => (gs.player.exp / gs.player.maxExp).clamp(0, 1),
            builder: (context, expProgress, child) {
              final player = context.read<GameState>().player;
              String expDetail = '${_formatNumber(player.exp)} / ${_formatNumber(player.maxExp)} (${(expProgress * 100).toStringAsFixed(1)}%)';
              return _buildLargeProgressBar('EXP', expProgress, Colors.blueAccent, trailingLabel: expDetail);
            }
          ),
        ),
        // 2. 콤팩트 통계 카드 (효율 데이터만 감시)
        Selector<GameState, String>(
          selector: (_, gs) => '${gs.goldPerMin}_${gs.expPerMin}_${gs.killsPerMin}_${gs.dmgPerMin}',
          builder: (context, _, child) => _buildEfficiencyCard(),
        ),
      ],
    );
  }

  Widget _buildLargeProgressBar(String label, double progress, Color color, {String? trailingLabel}) {
    return Container(
      width: double.infinity,
      height: 14,
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(7)),
      child: Stack(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, fontStyle: FontStyle.italic)),
                if (trailingLabel != null)
                  Text(trailingLabel, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEfficiencyCard() {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F111A).withValues(alpha: 0.50), // 불투명도 50% 적용
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1), // 살짝 가미된 테두리
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // 균형 잡힌 배치
                children: [
                  Expanded(child: _buildStatItem(Colors.amber, _formatNumber(gameState.goldPerMin), '분당골드')),
                  _buildStatDivider(),
                  Expanded(child: _buildStatItem(Colors.blueAccent, _formatNumber(gameState.expPerMin), '분당EXP')),
                  _buildStatDivider(),
                  Expanded(child: _buildStatItem(Colors.redAccent, gameState.killsPerMin.toStringAsFixed(1), '분당처치')),
                  const SizedBox(width: 8),
                  // 🆕 통합 관제 센터 버튼 (여기에 통합)
                  PressableScale(
                    onTap: _showQuickMenu,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.widgets_outlined, size: 16, color: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(color: Colors.white10, height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: _buildSessionStat('누적골드', _sessionGold, Colors.amber)),
                  const SizedBox(width: 12),
                  Flexible(child: _buildSessionStat('누적EXP', _sessionExp, Colors.blueAccent)),
                  const SizedBox(width: 12),
                  Flexible(child: _buildSessionStat('평균DMG', gameState.dmgPerMin.toInt(), Colors.redAccent)),
                  const SizedBox(width: 4),
                  const Spacer(),

                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _sessionGold = 0;
                        _sessionExp = 0;
                        _sessionMaxDamage = 0; 
                        _recentGains.clear();
                        gameState.resetEfficiency();
                      });

                      _showToast('통계가 초기화되었습니다.');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.refresh, size: 14, color: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(Color color, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)), // 폰트 축소 (16 -> 13)
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)), // 폰트 축소 (11 -> 10)
      ],
    );
  }

  Widget _buildSessionStat(String label, int value, Color color) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)), // 폰트 축소 (12 -> 10)
        Text(_formatNumber(value), style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w900)), // 폰트 축소 (13 -> 11)
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 10, color: Colors.white12); // 높이 축소 (15 -> 10)
  }

  Widget _buildBottomDock() {
    final List<String> emojis = ['⚔️', '👤', '🗺️', '🎒', '🔨', '⚡', '🐾', '💎', '🏆', '⚙️', '🏟️'];
    final List<String> labels = ['전투', '캐릭터', '사냥터', '가방', '제작', '스킬', '펫', '환생', '업적', '설정', '결투장'];
    
    return Container(
      padding: const EdgeInsets.only(bottom: 12, top: 2), // 하단 여백 소폭 조정
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        height: 56, 
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D2E).withValues(alpha: 0.92), // 배경색 통일감 있게 조정
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 15, offset: const Offset(0, 5)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                ui.PointerDeviceKind.touch,
                ui.PointerDeviceKind.mouse, // 마우스 드래그 스크롤 명시적 허용
              },
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: emojis.length,
              itemBuilder: (context, idx) {
                bool isSel = _selectedIndex == idx;
                return PressableScale(
                  onTap: () {
                    if (_selectedIndex != idx) {
                      setState(() {
                        // '가방'(index 3) 탭에 있다가 다른 탭으로 넘어갈 때만 N 마크 해제
                        if (_selectedIndex == 3) {
                          for (var item in player.inventory) {
                            item.isNew = false;
                          }
                        }
                        _selectedIndex = idx;
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 62,
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSel ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: isSel 
                        ? Border.all(color: Colors.blueAccent.withValues(alpha: 0.3), width: 1)
                        : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Text(
                              emojis[idx],
                              style: TextStyle(
                                fontSize: isSel ? 18 : 16,
                                shadows: [
                                  Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 3, offset: const Offset(1, 1))
                                ],
                              ),
                            ),
                            // 🆕 [v0.8.10] 스킬 업그레이드 가능 알림 (레드닷)
                            if (idx == 5)
                              Selector<GameState, bool>(
                                selector: (_, gs) => gs.isAnySkillUpgradeable,
                                builder: (context, canUpgrade, _) {
                                  if (!canUpgrade) return const SizedBox.shrink();
                                  return Positioned(
                                    top: -2,
                                    right: -2,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFF1A1D2E), width: 1.5),
                                        boxShadow: [
                                          BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 4)
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          labels[idx],
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                            color: isSel ? Colors.blueAccent : Colors.white38,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }



  // ═══════════════════════════════════════════════════════════════════════════
  // ⚔️ COMBAT UI - 전투 화면 UI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBattleScene() {
    return AnimatedBuilder(
      animation: Listenable.merge([_uiTickerController, _monsterSpawnController, _monsterDeathController]),
      builder: (context, child) {
        return Stack(
          key: _battleSceneKey,
          fit: StackFit.expand, 
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround, 
              children: [
                // 1. 플레이어 영역 (체력 및 보호막 변화 감시)
                Selector<GameState, (int, int)>(
                  selector: (_, gs) => (gs.playerCurrentHp, gs.playerShield),
                  builder: (context, data, child) => RepaintBoundary(
                    child: _buildActor(
                      gameState.player.name, 
                      gameState.player.level, 
                      data.$1, 
                      gameState.player.maxHp, 
                      'assets/images/warrior.png', 
                      _playerAttackController, 
                      _playerHitController,
                      true,
                      shield: data.$2,
                    ),
                  ),
                ),
                
                // 2. 몬스터 영역 (몬스터 존재 여부 및 체력 변화 감시)
                Center(
                  key: _monsterKey,
                  child: Selector<GameState, (int, double)>(
                    selector: (_, gs) => (gs.monsterCurrentHp, gs.currentMonster?.frozenTimeLeft ?? 0.0),
                    builder: (context, data, child) {
                      final m = gameState.currentMonster;
                      if (m == null) return const SizedBox(width: 100, height: 150);
                      
                      return RepaintBoundary(
                        child: FadeTransition(
                          opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_monsterDeathController),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 1.0, end: 0.5).animate(CurvedAnimation(parent: _monsterDeathController, curve: Curves.easeIn)),
                            child: FadeTransition(
                              opacity: _monsterSpawnController,
                              child: ScaleTransition(
                                scale: CurvedAnimation(parent: _monsterSpawnController, curve: Curves.easeOutBack),
                                child: _buildActor(
                                  m.name, 
                                  m.level, 
                                  data.$1, 
                                  m.maxHp, 
                                  m.imagePath, 
                                  _monsterAttackController, 
                                  _monsterHitController,
                                  false,
                                  isFrozen: data.$2 > 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]
            ),
            
            // 🆕 [v0.5.9] 전투 상태 및 펫 표시 영역 (정적 데이터 위주이므로 Selector 최소화)
            Selector<GameState, String>(
              selector: (_, gs) => gs.player.activePet?.id ?? 'none',
              builder: (context, _, child) => _buildBattleStatusArea(gameState),
            ),
            
            // 데미지 텍스트 레이어 (최적화 유지)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: DamagePainter(
                      texts: damageManager.texts,
                      ticker: _uiTickerController,
                    ),
                  ),
                ),
              ),
            ),

            // 카운트다운 연출
            if (_towerCountdown > 0)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('CHALLENGE', style: TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 4.0)),
                        const SizedBox(height: 10),
                        Text('$_towerCountdown', 
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 120, fontWeight: FontWeight.w900, shadows: [
                            const Shadow(color: Colors.amberAccent, blurRadius: 20)
                          ])),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActor(String n, int lv, int h, int mh, String img, AnimationController atk, AnimationController hit, bool p, {int shield = 0, bool isFrozen = false}) {
    double hpProgress = (h / mh).clamp(0, 1);
    double shieldProgress = (shield / mh).clamp(0, 1);
    return AnimatedBuilder(
      animation: Listenable.merge([atk, hit, _heroPulseController, _heroRotateController, _monsterSpawnController, _monsterDeathController]), 
      builder: (ctx, _) {
        // 1. 공격 애니메이션 강화 (v0.5.24)
        double attackWeight;
        if (atk.value < 0.25) {
          // 0~0.25 구간: Curves.easeOutBack으로 튀어나감
          attackWeight = Curves.easeOutBack.transform(atk.value / 0.25);
        } else {
          // 0.25~1.0 구간: 부드럽게 복귀
          attackWeight = 1.0 - Curves.easeIn.transform((atk.value - 0.25) / 0.75);
        }

        double lunge = attackWeight * 18; // 18px 전진
        double attackScale = 1.0 + (attackWeight * 0.1); // 1.1배 확대
        
        // 방향 결정 (플레이어는 오른쪽(+), 몬스터는 왼쪽(-)이 전진)
        double totalOffset = (p ? lunge : -lunge);
        
        // 2. 등장/사망 연출 결합
        double spawnScale = p ? 1.0 : (_monsterSpawnController.value);
        double deathRotate = p ? 0.0 : (_monsterDeathController.value * 0.5);
        double opacity = p ? 1.0 : (1.0 - _monsterDeathController.value);

        return Transform.translate(
          offset: Offset(totalOffset, 0), 
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: deathRotate,
              child: Transform.scale(
                scale: spawnScale * attackScale,
                child: Column(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              // 1. 이름 및 등급 뱃지
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShadowText(n, fontSize: 13, fontWeight: FontWeight.w900, color: p ? Colors.white : Colors.redAccent),
                  if (!p && gameState.currentMonster != null && gameState.currentMonster!.isBoss) ...[
                    const SizedBox(width: 4),
                    if ((h / mh) < 0.5)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 4)],
                        ),
                        child: const Text('RAGE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ],
              ),
              
              const SizedBox(height: 2),
              if (!p && isFrozen)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.5), blurRadius: 4)],
                  ),
                  child: const Text('FROZEN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                )
              else if (!p && gameState.currentMonster != null && gameState.currentMonster!.trait != BossTrait.none)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _buildTraitBadge(gameState.currentMonster!.trait),
                ),

              const SizedBox(height: 5),
              
              // 2. 프리미엄 컴팩트 HP 바
              Container(
                width: 110, height: 8, // 🆕 너비 85->110, 높이 7->8 상향
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10, width: 0.5),
                ), 
                child: Stack(
                  children: [
                    // A. 기본 HP 레이어
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: hpProgress),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutQuart,
                      builder: (context, value, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft, 
                        widthFactor: value, 
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: p ? [Colors.greenAccent, Colors.green.shade800] : [Colors.redAccent, Colors.red.shade900]
                            ),
                          ),
                        ),
                      ),
                    ),
                    // B. 보호막 레이어 (하늘색 반투명 오버레이)
                    if (shield > 0)
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: shieldProgress),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        builder: (context, sVal, _) => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: sVal,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.lightBlueAccent.withValues(alpha: 0.7), Colors.blue.withValues(alpha: 0.7)]
                              ),
                              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 1),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 0), // 🆕 간격을 0으로 설정하여 최대한 밀착
              
              // 3. ✨ [v0.5.28] 고성능 통합 비주얼 엔진 (HeroEffectPainter)
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                   // 🆕 높이를 150->125로 압축하여 상단 공백 제거
                   IgnorePointer(
                     child: CustomPaint(
                       size: const Size(150, 125),
                       painter: HeroEffectPainter(
                         promotionLevel: p ? gameState.player.promotionLevel : 0,
                         isPlayer: p,
                         pulse: _heroPulseController.value,
                         rotation: _heroRotateController.value,
                       ),
                     ),
                   ),

                   // 🆕 [v0.5.39] 실루엣 중복 레이어 제거 (선명도 최우선)
                   Transform.translate(
                     offset: p ? Offset(0, -6.0 * _heroPulseController.value) : Offset(0, -3.0 * _heroPulseController.value),
                     child: SizedBox(
                       width: 110, height: 110, 
                       child: ColorFiltered(
                         colorFilter: isFrozen 
                           ? const ColorFilter.mode(Colors.lightBlueAccent, BlendMode.modulate) 
                           : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                         child: Image.asset(img, fit: BoxFit.contain),
                       ),
                     ),
                   ),

                   // 🆕 [v2.2.8] 지면 연소 효과 (몬스터 위에 표시되도록 최상단 레이어로 이동)
                   if (!p)
                     Selector<GameState, bool>(
                       selector: (_, gs) => gs.isScorchedGroundActive,
                       builder: (context, isActive, _) {
                         if (!isActive) return const SizedBox.shrink();
                         return IgnorePointer(
                           child: SizedBox(
                             width: 160,
                             height: 60,
                             child: _buildScorchedGroundEffect(),
                           ),
                         );
                       },
                     ),
                 ],
              ),
            ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // OLD _buildCombatParticle REMOVED (Integrated into HeroEffectPainter)

  Widget _buildTraitBadge(BossTrait trait) {
    String label = '';
    Color color = Colors.grey;
    IconData icon = Icons.help_outline;

    switch (trait) {
      case BossTrait.crush:
        label = '파쇄';
        color = Colors.orangeAccent;
        icon = Icons.g_mobiledata_sharp;
        break;
      case BossTrait.corrupt:
        label = '오염';
        color = Colors.greenAccent;
        icon = Icons.bloodtype;
        break;
      case BossTrait.erode:
        label = '침식';
        color = Colors.purpleAccent;
        icon = Icons.timer_off;
        break;
      case BossTrait.none:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildBattleStatusArea(GameState gameState) {
    final pet = gameState.player.activePet;
    final bool isOptimalZone = gameState.isOptimalZone;
    final bool hasBuffs = gameState.isSkillDmgReductionActive || 
                        gameState.isKillAtkBuffActive || gameState.isZoneAtkBuffActive ||
                        gameState.isKillDefBuffActive || gameState.isZoneDefBuffActive;
    
    // 표시할 내용이 전혀 없으면 그리지 않음
    if (pet == null && !isOptimalZone && !gameState.isInSpecialDungeon && !hasBuffs) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _uiTickerController,
      builder: (context, child) {
        final double time = DateTime.now().millisecondsSinceEpoch / 1000.0;
        final double floatingY = sin(time * 2.5) * 6.0; 
        final double floatingX = cos(time * 1.5) * 3.0;
        
        return Align(
          alignment: const Alignment(-0.9, -0.85), // 좌측 상단 부유
          child: Transform.translate(
            offset: Offset(floatingX, floatingY),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 1. 활성화된 펫 표시
                if (pet != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                      border: Border.all(color: pet.grade.color.withValues(alpha: 0.6), width: 2.0),
                      boxShadow: [
                        BoxShadow(color: pet.grade.color.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 2),
                      ],
                    ),
                    child: Text(
                      pet.iconEmoji, 
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),

                // 2. 버프 아이콘들 (스킬 감댐, 공중, 방중 등)
                if (gameState.isSkillDmgReductionActive)
                  _buildBuffIcon(
                    Icons.shield_rounded, 
                    Colors.blueAccent, 
                    '피해감소 -${player.dmgReductionOnSkill.toStringAsFixed(1)}%', 
                    gameState.skillDmgReductionTimeLeft
                  ),
                
                if (gameState.isKillAtkBuffActive || gameState.isZoneAtkBuffActive)
                  _buildBuffIcon(
                    Icons.bolt_rounded, 
                    Colors.redAccent, 
                    '공격력 +${(player.killAtkBonus + player.zoneAtkBonus).toStringAsFixed(1)}%', 
                    max(gameState.killAtkBuffTimeLeft, gameState.zoneAtkBuffTimeLeft)
                  ),

                if (gameState.isKillDefBuffActive || gameState.isZoneDefBuffActive)
                  _buildBuffIcon(
                    Icons.security, 
                    Colors.greenAccent, 
                    '방어력 +${(player.killDefBonus + player.zoneDefBonus).toStringAsFixed(1)}%', 
                    max(gameState.killDefBuffTimeLeft, gameState.zoneDefBuffTimeLeft)
                  ),

                // 🆕 버프 상세 정보 힌트 (배치 순서 고정)
                if (_activeBuffHint != null)
                  AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                        boxShadow: [
                          BoxShadow(color: Colors.black54, blurRadius: 10),
                        ],
                      ),
                      child: Text(
                        _activeBuffHint!,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                // 3. 던전 타이머 (특별 던전 시)
                if (gameState.isInSpecialDungeon)
                  _buildSpecialDungeonTimer(gameState),

                // 4. 적정 사냥터 보너스 표시 (펫 유무 상관없이 노출)
                if (isOptimalZone)
                  GestureDetector(
                    onTap: () {
                      _optimalZoneHintTimer?.cancel();
                      setState(() => _showOptimalZoneHint = true);
                      _optimalZoneHintTimer = Timer(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _showOptimalZoneHint = false);
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.blueAccent, Colors.blueAccent.withValues(alpha: 0.6)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 2),
                            ],
                          ),
                          child: const Icon(
                            Icons.home_rounded, 
                            color: Colors.white, 
                            size: 20,
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: _showOptimalZoneHint ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: EdgeInsets.only(left: _showOptimalZoneHint ? 8 : 0),
                            width: _showOptimalZoneHint ? 90 : 0,
                            height: 36, // 아이콘 크기와 맞춤
                            child: _showOptimalZoneHint ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white10),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '적정사냥터버프',
                                style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                              ),
                            ) : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBuffIcon(IconData icon, Color color, String fullInfo, double timeLeft) {
    return GestureDetector(
      onTap: () {
        _buffHintTimer?.cancel();
        setState(() {
          _activeBuffHint = '$fullInfo (${timeLeft.toStringAsFixed(1)}s)';
        });
        _buffHintTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _activeBuffHint = null);
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8, spreadRadius: 1),
          ],
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _buildSpecialDungeonTimer(GameState gameState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: gameState.specialDungeonTimeLeft <= 10 ? Colors.redAccent : Colors.amberAccent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (gameState.specialDungeonTimeLeft <= 10 ? Colors.redAccent : Colors.amberAccent).withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: gameState.specialDungeonTimeLeft <= 10 ? Colors.redAccent : Colors.amberAccent,
          ),
          const SizedBox(width: 6),
          ShadowText(
            '${gameState.specialDungeonTimeLeft.toStringAsFixed(0)}s',
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: gameState.specialDungeonTimeLeft <= 10 ? Colors.redAccent : Colors.white,
          ),
        ],
      ),
    );
  }

  // OLD SKILL UI REMOVED

  // --- 상세 메뉴 구현 ---



  Widget _buildTabbedLogs({Function(int)? onTabChanged}) {
    List<String> tabs = ['전체', '아이템', '이벤트'];
    
    // 현재 선택된 탭에 따라 보여줄 리스트 결정
    List<CombatLogEntry> currentDisplayLogs;
    switch (_currentLogTab) {
      case 1: currentDisplayLogs = itemLogs; break;
      case 2: currentDisplayLogs = eventLogs; break;
      default: currentDisplayLogs = combatLogs; break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4), // 유리 느낌의 투명도
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          // 탭 바
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: List.generate(tabs.length, (i) {
                // 탭 인덱스 맵핑 (데미지 제거 후 인덱스 0, 1, 2)
                bool isSel = _currentLogTab == i;
                return GestureDetector(
                  onTap: () {
                    setState(() => _currentLogTab = i);
                    onTabChanged?.call(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? Colors.blueAccent.withValues(alpha: 0.8) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      tabs[i], 
                      style: TextStyle(
                        color: isSel ? Colors.white : Colors.white24, 
                        fontSize: 12, 
                        fontWeight: FontWeight.bold
                      )
                    ),
                  )
                );
              }),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          // 로그 리스트
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: currentDisplayLogs.length,
              itemBuilder: (ctx, i) {
                final log = currentDisplayLogs[i];
                return _buildModernLogItem(log);
              },
            ),
          ),
        ],
      ),
    );
  }

  // 화려한 커스텀 로그 아이템 빌더
  Widget _buildModernLogItem(CombatLogEntry log) {
    List<TextSpan> spans = [];

    // [시간] 태그
    spans.add(TextSpan(text: '[${log.time.hour}:${log.time.minute.toString().padLeft(2, '0')}] ', style: const TextStyle(color: Colors.white24, fontSize: 10)));

    // 메시지 분석하여 스타일링
    String msg = log.message;
    
    if (msg.contains('전투 승리')) {
      spans.add(const TextSpan(text: '🏆 ', style: TextStyle(fontSize: 12)));
      spans.add(TextSpan(text: msg, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.orange, blurRadius: 4)])));
    } else if (msg.contains('CRITICAL')) {
      spans.add(const TextSpan(text: '💥 ', style: TextStyle(fontSize: 12)));
      spans.add(TextSpan(text: msg, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.orange, blurRadius: 4)])));
    } else if (msg.contains('[스킬]')) {
      spans.add(const TextSpan(text: '🔥 ', style: TextStyle(fontSize: 12)));
      spans.add(TextSpan(text: msg, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)));
    } else if (msg.contains('[획득]')) {
      spans.add(const TextSpan(text: '🎁 ', style: TextStyle(fontSize: 12)));
      spans.add(TextSpan(text: msg, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)));
    } else if (msg.contains('레벨업')) {
      spans.add(const TextSpan(text: '✨ ', style: TextStyle(fontSize: 12)));
      spans.add(TextSpan(text: msg, style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.white, blurRadius: 8)])));
    } else if (msg.contains('피격') || msg.contains('피해')) {
      // 데미지 수치만 빨갛게 강조하는 로직 (정규식 간단 적용)
      spans.add(TextSpan(text: msg, style: const TextStyle(color: Colors.white70)));
    } else {
      spans.add(TextSpan(text: msg, style: const TextStyle(color: Colors.white70)));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(4),
        ),
        child: RichText(
          text: TextSpan(children: spans, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // 🏆 ACHIEVEMENT SYSTEM - 업적 및 도감 시스템
  // ═══════════════════════════════════════════════════════════════════════════


  // --- 시스템 탭 구현 ---

  // --- 펫 시스템 UI 및 로직 ---
  // ═══════════════════════════════════════════════════════════════════════════
  // 🐾 PET SYSTEM - 펫 시스템
  // ═══════════════════════════════════════════════════════════════════════════


  // --- 시스템 탭 구현 ---




  // --- 시스템 및 관리자 모드 UI ---
  // ═══════════════════════════════════════════════════════════════════════════
  // ⚙️ SYSTEM & ADMIN - 시스템 및 관리자 모드
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSystemTab() {
    if (_isAdminAuthenticated) {
      return _buildAdminPanel();
    }

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(32),
            borderRadius: 30,
            child: Column(
              children: [
                const Icon(Icons.settings, color: Colors.white60, size: 60),
                const SizedBox(height: 24),
                ShadowText('시스템 설정', fontSize: 24, fontWeight: FontWeight.bold),
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                // 🆕 현재 로그인 정보 표시 (정규 로직으로 개선)
                Text(
                  !_authService.isLoggedIn 
                    ? '상태: 로그아웃됨' 
                    : (_authService.isAnonymous 
                        ? '상태: 익명 계정 (보호되지 않음)' 
                        : '상태: ${_authService.userEmail ?? "구글 계정 연동됨"}'),
                  style: TextStyle(
                    color: !_authService.isLoggedIn 
                      ? Colors.grey 
                      : (_authService.isAnonymous ? Colors.orangeAccent : Colors.greenAccent),
                    fontSize: 12,
                    fontWeight: FontWeight.bold
                  )
                ),
                const SizedBox(height: 40),
                // 🆕 구글 로그인 버튼 (로그아웃 상태일 때 표시)
                if (!_authService.isLoggedIn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: PopBtn(
                      '구글 계정으로 로그인', 
                      Colors.white, 
                      () async {
                        _showToast('구글 로그인 창을 띄웁니다...');
                        final success = await _authService.signInWithGoogle();
                        if (success) {
                           _showToast('로그인 성공! 데이터를 불러옵니다...');
                           await gameState.loadGameData();
                        }
                      },
                      icon: Icons.login,
                    ),
                  ),
                // 🆕 구글 계정 보호 버튼 (익명 계정일 때 표시)
                if (_authService.isLoggedIn && _authService.isAnonymous)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: PopBtn(
                      '구글 계정으로 데이터 보호', 
                      Colors.white, 
                      () async {
                        _showToast('구글 로그인 창을 띄웁니다...');
                        final success = await _authService.signInWithGoogle();
                        if (success) {
                           _showToast('계정 보호 완료! 데이터를 불러옵니다...');
                           await gameState.loadGameData();
                        }
                      },
                      icon: Icons.security,
                    ),
                  ),
                // 관리자 모드 진입 버튼
                PopBtn(
                  '관리자 모드', 
                  Colors.redAccent.withValues(alpha: 0.8), 
                  _showAdminPasswordDialog,
                  icon: Icons.admin_panel_settings,
                ),
                const SizedBox(height: 16),
                // 🆕 클라우드 수동 동기화 버튼
                PopBtn(
                  '클라우드 수동 동기화', 
                  Colors.blueAccent.withValues(alpha: 0.8), 
                  () async {
                    await _saveGameData(forceCloud: true);
                    if (_isCloudSynced) {
                      _showToast('클라우드 동기화 완료!', isError: false);
                    } else {
                      _showToast('동기화 실패: 로그인을 확인하세요.');
                    }
                  },
                  icon: Icons.sync,
                ),
                const SizedBox(height: 16),
                PopBtn(
                  '로그아웃', 
                  Colors.white10, 
                  () async {
                    await _authService.signOut();
                    setState(() {
                      _isCloudSynced = false;
                    });
                    _showToast('로그아웃되었습니다.');
                  },
                  icon: Icons.logout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Version: 0.1.0 (Alpha Test)', style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildAdminPanel() {
    // GameState의 현재 값을 동기화
    final gameState = context.read<GameState>();
    _monsterDefenseMultiplier = gameState.monsterDefenseMultiplier;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            color: Colors.redAccent.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bug_report, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 12),
                    ShadowText('관리자 테스트 도구', fontSize: 18, fontWeight: FontWeight.bold),
                  ],
                ),
                PopBtn('인증 해제', Colors.white24, () => setState(() => _isAdminAuthenticated = false)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                _buildAdminResourceCard('골드 (GOLD)', player.gold, (v) => setState(() => player.gold += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('강화석', player.enhancementStone, (v) => setState(() => player.enhancementStone += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('심연의 가루', player.abyssalPowder, (v) => setState(() => player.abyssalPowder += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('재설정석', player.rerollStone, (v) => setState(() => player.rerollStone += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('보호석', player.protectionStone, (v) => setState(() => player.protectionStone += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('잠재력 큐브', player.cube, (v) => setState(() => player.cube += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('영혼석', player.soulStone, (v) => setState(() => player.soulStone += v)),
                const SizedBox(height: 30),
                _buildAdminSliderCard(
                  label: "몬스터 방어력 배율",
                  value: _monsterDefenseMultiplier,
                  onChanged: (val) {
                    setState(() => _monsterDefenseMultiplier = val);
                    // GameState에 즉시 반영
                    context.read<GameState>().monsterDefenseMultiplier = val;
                  },
                ),
                const SizedBox(height: 30),
                // 🆕 재화 대량 지급 버튼
                PopBtn('모든 재화 1억 추가', Colors.amber, () {
                  setState(() {
                    player.gold += 100000000;
                    player.enhancementStone += 1000000;
                    player.abyssalPowder += 1000000; // powder -> abyssalPowder
                    player.rerollStone += 10000;
                    player.protectionStone += 10000;
                    player.cube += 10000;
                    player.soulStone += 10000; // Add soulStone
                  });
                  _showToast('모든 재화를 대량 지급했습니다.', isError: false);
                }, isFull: true),
              ],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildAdminResourceCard(String label, int current, Function(int) onAdd) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              ShadowText(_formatNumber(current), color: Colors.amberAccent, fontWeight: FontWeight.bold),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              PopBtn('+1만', Colors.white12, () => onAdd(10000)),
              PopBtn('+10만', Colors.white12, () => onAdd(100000)),
              PopBtn('+100만', Colors.white24, () => onAdd(1000000)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminSliderCard({required String label, required double value, required Function(double) onChanged}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      color: Colors.blueAccent.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ShadowText('${(value * 100).toInt()}%', color: Colors.cyanAccent, fontWeight: FontWeight.bold),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.cyanAccent,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: Colors.cyanAccent.withOpacity(0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
          const Text(
            '0% 설정 시 몬스터의 방어력이 무시됩니다. (데미지 체감 테스트용)',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _showAdminPasswordDialog() {
    final TextEditingController passController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent, width: 1)),
        title: ShadowText('관리자 인증', fontSize: 18, fontWeight: FontWeight.bold),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('비밀번호 4자리를 입력하세요.', style: TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: passController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 10),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () {
              if (passController.text == '9999') {
                setState(() => _isAdminAuthenticated = true);
                Navigator.pop(context);
                _showToast('관리자 인증에 성공했습니다.', isError: false);
              } else {
                _showToast('비밀번호가 틀렸습니다.');
              }
            }, 
            child: const Text('인증', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }



  // --- 프리미엄 아이템 연출 및 슬롯 로직 ---

  Widget _buildPremiumItemSlot(Item item, {double size = 52, required VoidCallback onTap, bool isPaused = false}) {
    final grade = item.grade;
    return PressableScale(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: grade.bgGradient,
              border: Border.all(
                color: grade.color.withOpacity(0.8),
                width: grade.index >= 4 ? 2.2 : 1.2,
              ),
              boxShadow: [
                if (grade.glowIntensity > 0)
                  BoxShadow(
                    color: grade.glowColor,
                    blurRadius: grade.glowIntensity,
                    spreadRadius: 1,
                  ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // 쉬머 광택 효과 (최상위 등급 전용)
                if (grade == ItemGrade.mythic && !isPaused)
                  Positioned.fill(
                    child: ShimmerSheen(progress: _shimmerController.value),
                  ),

                // 중앙 아이콘 후광 (Glow)
                Center(
                  child: Container(
                    width: size * 0.5,
                    height: size * 0.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: grade.color.withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 4,
                        )
                      ],
                    ),
                  ),
                ),

                // 아이콘 (크기 확대)
                Center(child: ItemIcon(type: item.type, size: size * 0.55)),
        
        // --- 강화 계승/파손 비주얼 레이어 ---
        if (item.isBroken)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.withOpacity(0.2), // 파손 붉은 기운
              ),
              child: Center(
                child: Transform.rotate(
                  angle: -0.5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                    child: const Text('BROKEN', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ),
          ),
        
        // 아이템 등급별 광택/특수효과...
                // 라벨 디자인 (T-뱃지 및 N-마크)
                _buildSlotLabels(item),

                // 강화 수치
                if (item.enhanceLevel > 0)
                  Positioned(
                    bottom: 4, right: 6,
                    child: Text(
                      '+${item.enhanceLevel}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlotLabels(Item item) {
    return Stack(
      children: [
        // 티어 라벨 (좌측 상단 태그)
        Positioned(
          top: 0, left: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: const BorderRadius.only(bottomRight: Radius.circular(8)),
            ),
            child: Text(
              'T${item.tier}',
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ),
        ),
        // 신규 알림 (우측 상단 서클)
        if (item.isNew)
          Positioned(
            top: 3, right: 3,
            child: Container(
              width: 13, height: 13,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  colors: [Colors.amberAccent, Colors.amber],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 4, spreadRadius: 0.5)
                ],
              ),
              child: const Text('N', 
                style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: -0.5)
              ),
            ),
          ),
      ],
    );
  }

  // --- 무한의탑 핵심 시퀀스 메서드 ---

  void _enterTower(HuntingZone towerZone) {
    if (_isEnteringTower) return; // 중복 실행 방지
    _isEnteringTower = true;

    if (_currentZone.id != ZoneId.tower) {
      _previousZone = _currentZone;
      _previousStage = _currentStage;
    }
    
    setState(() {
      _currentZone = towerZone;
      _currentStage = _zoneStages[towerZone.id] ?? 1;
      gameState.stageKills = 0;
      _selectedIndex = 0; // 전투 탭으로 이동
      currentMonster = null; // 카운트다운 동안 몬스터 없음
      _towerCountdown = 3;
    });

    _towerTimer?.cancel();
    _towerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_towerCountdown > 0) {
          _towerCountdown--;
          if (_towerCountdown == 0) {
            timer.cancel();
            _isEnteringTower = false; // 카운트다운 완료 시 해제
            _spawnMonster();
          }
        } else {
          timer.cancel();
          _isEnteringTower = false;
        }
      });
    });
  }

  void _exitTower() {
    if (_previousZone != null) {
      setState(() {
        _currentZone = _previousZone!;
        _currentStage = _previousStage ?? 1;
        gameState.stageKills = 0;
        _spawnMonster();
        _showToast('${_currentZone.name} 지역으로 복귀했습니다.', isError: false);
      });
    }
  }

  // --- 특별 시한 던전 로직 ---

  void _enterSpecialDungeon(HuntingZone zone) {
    if (gameState.isInSpecialDungeon) return;

    // 1. 입장권 확인 및 소모
    if (zone.id == ZoneId.goldenRoom) {
      if (player.goldDungeonTicket < 1) {
        _showToast('황금의 방 입장권이 부족합니다.', isError: true);
        return;
      }
      player.goldDungeonTicket--;
    } else if (zone.id == ZoneId.trialRoom) {
      if (player.trialDungeonTicket < 1) {
        _showToast('시련의 방 입장권이 부족합니다.', isError: true);
        return;
      }
      player.trialDungeonTicket--;
    }

    // 2. 현재 상태 저장
    _previousZone = _currentZone;
    _previousStage = _currentStage;

    // 3. 던전 이동
    setState(() {
      _currentZone = zone;
      _currentStage = player.maxStageReached; // 플레이어의 최고 스테이지 기준으로 난이도 설정
      gameState.stageKills = 0;
      _selectedIndex = 0; // 전투 탭으로 이동
      currentMonster = null;
    });

    // 4. 타이머 시작
    gameState.startSpecialDungeon(zone.id);
    _spawnMonster();
    _showToast('${zone.name}에 진입했습니다! (60초)', isError: false);
  }

  void _exitSpecialDungeon() {
    if (_previousZone != null) {
      gameState.endSpecialDungeon();
      setState(() {
        _currentZone = _previousZone!;
        _currentStage = _previousStage ?? 1;
        gameState.stageKills = 0;
        _spawnMonster();
        _showSuccess('던전 탐험 종료', '보상 정산이 완료되었습니다.');
      });
    }
  }

  void _checkOfflineRewards() async {
    final gameState = context.read<GameState>();
    // 🆕 데이터 로드가 완료될 때까지 대기
    await gameState.initialized;
    
    final prefs = await SharedPreferences.getInstance();
    String? lastSaveStr = prefs.getString('lastSaveTime');
    if (lastSaveStr == null) return;

    DateTime lastSave = DateTime.parse(lastSaveStr);
    int minutes = DateTime.now().difference(lastSave).inMinutes;
    if (minutes < 5) return;

    // 🆕 효율 데이터가 0일 경우를 대비한 최소 보전 로직 (스테이지 기반)
    // 분당 획득량이 기록되지 않았더라도 최소한의 보상은 지급되도록 함
    double effectiveGoldMin = gameState.goldPerMin;
    double effectiveExpMin = gameState.expPerMin;
    double effectiveKillsMin = gameState.killsPerMin;

    if (effectiveKillsMin <= 0) {
      // 처치 수 기록이 없으면 1분당 5마리 기본 가정
      effectiveKillsMin = 5.0; 
    }
    if (effectiveGoldMin <= 0) {
      // 골드 기록이 없으면 현재 스테이지 기준 몬스터 골드의 5배 가정
      effectiveGoldMin = (gameState.currentMonster?.goldReward.toDouble() ?? (gameState.currentStage * 10.0)) * 5.0;
    }
    if (effectiveExpMin <= 0) {
      // 경험치 기록이 없으면 현재 스테이지 기준 몬스터 경험치의 5배 가정
      effectiveExpMin = (gameState.currentMonster?.expReward.toDouble() ?? (gameState.currentStage * 5.0)) * 5.0;
    }

    int zoneTier = 1;
    switch (gameState.currentZone.id) {
      case ZoneId.grassland: zoneTier = 1; break;
      case ZoneId.forest: zoneTier = 2; break;
      case ZoneId.mine: zoneTier = 3; break;
      case ZoneId.dungeon: zoneTier = 4; break;
      case ZoneId.volcano: zoneTier = 5; break;
      case ZoneId.snowfield: zoneTier = 6; break;
      case ZoneId.abyss: zoneTier = 7; break;
      default: zoneTier = 1;
    }

    final rewards = gameState.player.calculateOfflineRewards(
      lastSave, 
      effectiveGoldMin, 
      effectiveExpMin, 
      effectiveKillsMin,
      tier: zoneTier,
    );
    // [v0.8.14] 현재 스테이지 정보를 주입하여 마일스톤 보존
    rewards['maxStage'] = gameState.currentStage;


    if (rewards.isEmpty) return;
    _showOfflineRewardDialog(rewards);
  }

  void _spawnMonster() => context.read<GameState>().spawnMonster();
  Future<void> _saveGameData({bool forceCloud = false}) => context.read<GameState>().saveGameData(forceCloud: forceCloud);



  void _showOfflineRewardDialog(Map<String, dynamic> rewards) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D29),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            const Icon(Icons.bedtime, color: Colors.amberAccent, size: 48),
            const SizedBox(height: 12),
            ShadowText('휴식 보상 도착!', fontSize: 22, fontWeight: FontWeight.bold),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${rewards['minutes']}분 동안의 성과입니다.',
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _buildOfflineRewardItem('💰', '골드', rewards['gold']),
              _buildOfflineRewardItem('✨', '경험치', rewards['exp']),
              _buildOfflineRewardItem('💀', '처치 수', rewards['kills']),
              if (rewards.containsKey('shards'))
                _buildOfflineRewardItem('🧩', '연성 파편', rewards['shards']),
              if (rewards.containsKey('abyssalPowder'))
                _buildOfflineRewardItem('✨', '심연의 가루', rewards['abyssalPowder']),

              if (rewards['bonusStones'] > 0 || rewards.containsKey('rerollStone') || rewards.containsKey('protectionStone') || rewards.containsKey('cube')) ...[
                const Divider(color: Colors.white24, height: 24),
                const Text(
                  '강화 재료',
                  style: TextStyle(color: Colors.blueAccent, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildOfflineRewardItem('💎', '강화석', rewards['bonusStones']),
                if (rewards.containsKey('rerollStone'))
                  _buildOfflineRewardItem('🎲', '재설정석', rewards['rerollStone']),
                if (rewards.containsKey('protectionStone'))
                  _buildOfflineRewardItem('🛡️', '보호석', rewards['protectionStone']),
                if (rewards.containsKey('cube'))
                  _buildOfflineRewardItem('🔮', '잠재력 큐브', rewards['cube']),
              ],
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            onPressed: () {
              context.read<GameState>().player.applyOfflineRewards(rewards);
              _saveGameData();
              context.read<GameState>().refresh();
              Navigator.pop(context);
              _showToast('방치 보상을 획득했습니다!');
            },
            child: const Text('보상 받기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineRewardItem(String emoji, String label, int amount) {
    if (amount <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          Text(
            '+${_formatNumber(amount)}',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // 🆕 [v0.5.27] 승급 성공 전용 팝업 다이얼로그
  void _showPromotionDialog(int level, String name, String bonus) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Promotion',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = Curves.elasticOut.transform(anim1.value);
        return Transform.scale(
          scale: curve,
          child: Opacity(
            opacity: anim1.value,
            child: Dialog(
              backgroundColor: Colors.transparent,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 배경 발광 효과
                  Container(
                    width: 320, height: 450,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.amberAccent.withValues(alpha: 0.15 * anim1.value), blurRadius: 100, spreadRadius: 50),
                      ],
                    ),
                  ),
                  GlassContainer(
                    padding: const EdgeInsets.all(32),
                    borderRadius: 40,
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5), width: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 화려한 아이콘 영역
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(seconds: 1),
                          builder: (context, val, _) => Transform.rotate(
                            angle: val * 2 * pi,
                            child: Icon(Icons.workspace_premium, color: Colors.amberAccent, size: 100 + (10 * sin(val * 2 * pi))),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const ShadowText('🎉 승급 성공! 🎉', fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                        const SizedBox(height: 8),
                        Text('당신의 한계가 다시 한번 확장되었습니다.', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 32),
                        
                        // 새로운 칭호 및 효과 카드
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.amberAccent.withValues(alpha: 0.2),
                                Colors.orangeAccent.withValues(alpha: 0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3), width: 1.5),
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Text('CURRENT TITLE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                              const SizedBox(height: 8),
                              Text(name, style: const TextStyle(color: Colors.amberAccent, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 4, shadows: [Shadow(color: Colors.orange, blurRadius: 10)])),
                              const SizedBox(height: 16),
                              Container(height: 1, width: 60, color: Colors.amberAccent.withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                              const Text('UNLOCK BONUS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(bonus, style: const TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                        PopBtn('새로운 경지 확인', Colors.orangeAccent, () {
                           Navigator.of(context).pop();
                        }, isFull: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showItemPromotionDialog(Item item, int oldTier, int oldStat1, int? oldStat2) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'ItemPromotion',
      barrierColor: Colors.black.withValues(alpha: 0.9),
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = Curves.elasticOut.transform(anim1.value);
        return Transform.scale(
          scale: curve,
          child: Opacity(
            opacity: anim1.value,
            child: Dialog(
              backgroundColor: Colors.transparent,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 배경 레이어 (파티클 느낌 발광)
                  Container(
                    width: 340, height: 500,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: item.grade.color.withValues(alpha: 0.2 * anim1.value), 
                          blurRadius: 120, spreadRadius: 60
                        ),
                      ],
                    ),
                  ),
                  GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    borderRadius: 40,
                    border: Border.all(color: item.grade.color.withValues(alpha: 0.5), width: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 티어 변화 연출
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildStaticTierBadge(oldTier),
                            const SizedBox(width: 12),
                            const Icon(Icons.keyboard_double_arrow_right, color: Colors.white54, size: 24),
                            const SizedBox(width: 12),
                            _buildElevatedTierBadge(item.tier),
                          ],
                        ),
                        const SizedBox(height: 32),
                        
                        // 아이템 이름 및 등급
                        ShadowText(item.name.split(' T')[0], fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                        const SizedBox(height: 8),
                        Text(item.grade.name, style: TextStyle(color: item.grade.color, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
                        
                        const SizedBox(height: 40),
                        
                        // 능력치 변화 리스트 (Before -> After)
                        _buildStatChangeRow(item.mainStatName1, oldStat1, item.effectiveMainStat1),
                        if (item.mainStatName2 != null && oldStat2 != null) ...[
                          const SizedBox(height: 12),
                          _buildStatChangeRow(item.mainStatName2!, oldStat2, item.effectiveMainStat2),
                        ],
                        
                        const SizedBox(height: 40),
                        
                        // 확인 버튼
                        PopBtn('진화된 위력 확인', item.grade.color, () {
                           Navigator.of(context).pop();
                        }, isFull: true),
                      ],
                    ),
                  ),
                  
                  // 상단 장식 아이콘
                  Positioned(
                    top: -10,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(seconds: 2),
                      builder: (context, val, _) => Transform.translate(
                        offset: Offset(0, 10 * sin(val * 2 * pi)),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141622),
                            shape: BoxShape.circle,
                            border: Border.all(color: item.grade.color, width: 2),
                            boxShadow: [BoxShadow(color: item.grade.color.withValues(alpha: 0.5), blurRadius: 15)],
                          ),
                          child: Icon(Icons.auto_awesome, color: item.grade.color, size: 32),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaticTierBadge(int tier) {
     return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
      child: Text('T$tier', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white38)),
    );
  }

  Widget _buildElevatedTierBadge(int tier) {
     return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.2), 
        borderRadius: BorderRadius.circular(14), 
        border: Border.all(color: Colors.blueAccent, width: 2),
        boxShadow: [BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.3), blurRadius: 10)]
      ),
      child: Text('T$tier', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }

  Widget _buildStatChangeRow(String label, int oldVal, int newVal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(BigNumberFormatter.format(oldVal), style: const TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          const Icon(Icons.arrow_right_alt, color: Colors.greenAccent, size: 20),
          const SizedBox(width: 12),
          Text(BigNumberFormatter.format(newVal), style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  void _showTowerResultDialog(bool isSuccess) {

    if (_isTowerResultShowing) return;
    _isTowerResultShowing = true;
    _isEnteringTower = false; // 결과가 나오면 입장 상태 해제

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: GlassContainer(
            padding: const EdgeInsets.all(24),
            borderRadius: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuccess ? Icons.workspace_premium : Icons.dangerous,
                  color: isSuccess ? Colors.amberAccent : Colors.redAccent,
                  size: 64,
                ),
                const SizedBox(height: 16),
                ShadowText(
                  isSuccess ? '무한의 탑 돌파 성공!' : '도전 실패...',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isSuccess ? Colors.amberAccent : Colors.redAccent,
                ),
                const SizedBox(height: 8),
                Text(
                  isSuccess 
                      ? '수호자를 처치하고 다음 층으로 가는 길이 열렸습니다.' 
                      : '탑의 기운에 압도되어 층을 오르지 못했습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                ),
                if (isSuccess) ...[
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 12),
                  const Text('보상 목록', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildRewardChip('영혼석 +10', Colors.purpleAccent),
                      const SizedBox(width: 8),
                      _buildRewardChip('골드 보너스', Colors.amber),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  children: [
                    if (isSuccess) 
                      Expanded(
                        child: PopBtn(
                          '다음 층 도전', 
                          Colors.amberAccent, 
                          () {
                            _isTowerResultShowing = false;
                            Navigator.of(dialogCtx).pop();
                            setState(() {
                                _currentStage++;
                                _zoneStages[ZoneId.tower] = _currentStage;
                                _enterTower(_currentZone);
                            });
                          }
                        ),
                      ),
                    if (isSuccess) const SizedBox(width: 12),
                    Expanded(
                      child: PopBtn(
                        isSuccess ? '포기' : '확인', 
                        isSuccess ? Colors.white12 : Colors.redAccent.withValues(alpha: 0.2), 
                        () {
                          _isTowerResultShowing = false;
                          Navigator.of(dialogCtx).pop();
                          _exitTower();
                        }
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRewardChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _showFullLogDialog() {
    showDialog(
      context: context,
      builder: (context) => Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            height: MediaQuery.of(context).size.height * 0.6,
            margin: const EdgeInsets.all(20),
            child: GlassContainer(
              padding: const EdgeInsets.all(20),
              borderRadius: 24,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const ShadowText('전체 전투 기록 📜', fontSize: 20, fontWeight: FontWeight.bold),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white38)),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  // 🆕 실시간 반영을 위해 StatefulBuilder 적용
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, dialogSetState) {
                        return _buildTabbedLogs(onTabChanged: (idx) => dialogSetState(() {}));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 지능형 전리품 알림 시스템 로직 ---
  void _addLootNotification(String icon, String name, ItemGrade grade, {int amount = 1}) {
    // 1. 중첩 처리 (동일 아이템이 리스트에 이미 있는지 확인)
    for (int i = 0; i < _lootNotifications.length; i++) {
        if (_lootNotifications[i].name == name) {
            setState(() {
                _lootNotifications[i].amount += amount;
                _lootNotifications[i].lastUpdated = DateTime.now();
            });
            return;
        }
    }

    // 2. 신규 생성
    final newNotif = LootNotification(
        icon: icon,
        name: name,
        grade: grade,
        amount: amount,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
    );

    // 3. 개수 제한 (5개 초과 시 가장 오래된 것 삭제)
    if (_lootNotifications.length >= 5) {
        final removed = _lootNotifications.removeAt(0);
        _lootListKey.currentState?.removeItem(0, (context, animation) => _buildLootItemWidget(removed, animation));
    }

    setState(() {
        _lootNotifications.add(newNotif);
        _lootListKey.currentState?.insertItem(_lootNotifications.length - 1);
    });

    // 4. 수명 주기 (3초 후 자동 삭제)
    Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        _removeLootNotification(newNotif);
    });
  }

  void _removeLootNotification(LootNotification item) {
    int idx = _lootNotifications.indexOf(item);
    if (idx != -1) {
        setState(() {
            _lootNotifications.removeAt(idx);
            _lootListKey.currentState?.removeItem(idx, (context, animation) => _buildLootItemWidget(item, animation));
        });
    }
  }

  Widget _buildLootNotificationList() {
    return AnimatedList(
      key: _lootListKey,
      initialItemCount: _lootNotifications.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index, animation) {
        if (index >= _lootNotifications.length) return const SizedBox.shrink();
        return _buildLootItemWidget(_lootNotifications[index], animation);
      },
    );
  }

  Widget _buildLootItemWidget(LootNotification item, Animation<double> animation) {
    // 영웅(Hero/Epic) 등급 이상 강조
    bool isPremium = item.grade.index >= ItemGrade.epic.index;
    
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(Tween<Offset>(begin: const Offset(-0.5, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutBack))),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          alignment: Alignment.centerLeft,
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            borderRadius: 10,
            blur: 10,
            border: Border.all(color: item.grade.color.withValues(alpha: isPremium ? 0.6 : 0.2), width: isPremium ? 1.5 : 0.5),
            color: Colors.black.withValues(alpha: 0.8),
            // GlassContainer does not take boxShadow directly
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.icon, style: TextStyle(fontSize: isPremium ? 16 : 14)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.name, 
                    style: TextStyle(color: item.grade.color.withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  )
                ),
                Text(' x${item.amount}', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ),
    );
  }


  // 🆕 [v0.8.39] 지면 연소 효과 오버레이
  Widget _buildScorchedGroundEffect() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            Colors.orangeAccent.withValues(alpha: 0.5),
            Colors.redAccent.withValues(alpha: 0.2),
            Colors.transparent
          ],
          stops: const [0.3, 0.7, 1.0],
        ),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // 중앙으로 밀집
          children: List.generate(3, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildFlickeringFlame(i),
          )),
        ),
      ),
    );
  }

  Widget _buildFlickeringFlame(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.2),
      duration: Duration(milliseconds: 400 + (index * 100)),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Text('🔥', style: TextStyle(fontSize: 16 + (index % 2 * 4).toDouble(), shadows: [
            Shadow(color: Colors.orange.withValues(alpha: 0.8), blurRadius: 10)
          ])),
        );
      },
    );
  }

  String _formatNumber(num n) {
    return BigNumberFormatter.format(n);
  }
}


enum LootType { gold, exp }
enum DamageType { normal, critical, skill, heal, gold, exp, shield }

/// 🆕 [v0.5.6] 지능형 전리품 알림 모델
class LootNotification {
    final String icon;
    final String name;
    final ItemGrade grade;
    int amount;
    final DateTime createdAt;
    DateTime lastUpdated;

    LootNotification({
        required this.icon,
        required this.name,
        required this.grade,
        required this.amount,
        required this.createdAt,
        required this.lastUpdated,
    });
}

/// 🆕 데미지 텍스트 데이터 모델
class DamageEntry {
  final String text;
  final DamageType type;
  final DateTime createdAt;
  final Offset basePosition;
  final String? skillIcon; // 🆕 스킬 아이콘
  final int? combo; // 🆕 콤보 단계
  // 🆕 최적화: 레이아웃이 완료된 객체를 캐싱
  late final TextPainter textPainter;

  DamageEntry({
    required this.text,
    required this.createdAt,
    required this.type,
    required this.basePosition,
    this.skillIcon,
    this.combo,
  }) {
    // 생성 시점에 텍스트 스타일과 레이아웃을 한 번만 계산합니다.
    final style = _getStaticTextStyle(type, combo: combo);
    
    // 🆕 스킬 아이콘이 있으면 텍스트 앞에 결합
    String displayText = text;
    if (skillIcon != null) {
      displayText = '$skillIcon $text';
    }

    textPainter = TextPainter(
      text: TextSpan(text: displayText, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
  }

  static TextStyle _getStaticTextStyle(DamageType type, {int? combo}) {
    Color color;
    double fontSize = 14.0;
    FontWeight fontWeight = FontWeight.normal;
    
    // 🆕 콤보별 텍스트 변칙 적용 (일반 대미지 기준)
    if (type == DamageType.normal && combo != null && combo > 0) {
      switch (combo) {
        case 2:
          fontSize = 17.0;
          break;
        case 3:
          fontSize = 20.0;
          fontWeight = FontWeight.w600;
          break;
        case 4:
          fontSize = 24.0;
          fontWeight = FontWeight.bold;
          break;
        default:
          fontSize = 14.0;
      }
    } else {
      switch (type) {
        case DamageType.critical: 
          color = const Color(0xFFFF3333); 
          fontSize = 24.0; 
          fontWeight = FontWeight.w900; 
          break;
        case DamageType.skill: 
          color = const Color(0xFF00FBFF); 
          fontSize = 20.0; 
          fontWeight = FontWeight.bold; 
          break;
        case DamageType.heal: 
          color = const Color(0xFF4ADE80); 
          fontSize = 18.0; 
          break;
        case DamageType.gold: 
          color = const Color(0xFFFFD700); 
          fontSize = 17.0; 
          break;
        case DamageType.exp: 
          color = const Color(0xFF60A5FA); 
          fontSize = 17.0; 
          break;
        case DamageType.shield: // 🆕 보호막 데미지 (하늘색)
          color = const Color(0xFF22D3EE); 
          fontSize = 16.0;
          fontWeight = FontWeight.w600;
          break;
        default: 
          color = Colors.white; 
          fontSize = 14.0;
      }
    }

    // 콤보 4타(피니시) 시 색상 강조
    if (type == DamageType.normal && combo == 4) {
      color = Colors.amberAccent;
    } else if (type == DamageType.normal) {
      color = Colors.white;
    } else {
      // 기타 타입 색상은 위 switch에서 결정됨
      color = _getTypeColor(type);
    }

    return GoogleFonts.luckiestGuy(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: 0.5,
      shadows: [
        const Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black54),
      ], 
    );
  }

  static Color _getTypeColor(DamageType type) {
    switch (type) {
      case DamageType.critical: return const Color(0xFFFF3333);
      case DamageType.skill: return const Color(0xFF00FBFF);
      case DamageType.heal: return const Color(0xFF4ADE80);
      case DamageType.gold: return const Color(0xFFFFD700);
      case DamageType.exp: return const Color(0xFF60A5FA);
      case DamageType.shield: return const Color(0xFF22D3EE);
      default: return Colors.white;
    }
  }
}

/// 🆕 데미지 텍스트 생명주기 관리 매니저
class DamageManager {
  final List<DamageEntry> texts = [];
  
  void add(DamageEntry entry) {
    // 🆕 성능 최적화: 최대 텍스트 수를 20개로 제한 (GPU 부하 방지)
    if (texts.length > 20) texts.removeAt(0);
    texts.add(entry);
  }
  
  void update() {
    final now = DateTime.now();
    texts.removeWhere((t) => now.difference(t.createdAt).inMilliseconds >= 800);
  }
}

/// 🆕 고성능 데미지 텍스트 렌더러 (CustomPainter)
class DamagePainter extends CustomPainter {
  final List<DamageEntry> texts;
  final Animation<double> ticker;

  DamagePainter({required this.texts, required this.ticker}) : super(repaint: ticker);

  @override
  void paint(Canvas canvas, Size size) {
    if (texts.isEmpty) return;
    final now = DateTime.now();

    for (var ft in texts) {
      final elapsedMs = now.difference(ft.createdAt).inMilliseconds;
      if (elapsedMs < 0 || elapsedMs >= 800) continue;

      final double progress = elapsedMs / 800; // 0.0 ~ 1.0 (0.8s)
      
      double scale = 1.0;
      double offsetY = 0.0;
      double opacity = 1.0;

      // 1단계: 0~0.16s (0~20%) - 팝업 (투명도 0->1, 크기 0.5->1.2, 살짝 튕김)
      if (progress <= 0.2) {
        final p = progress / 0.2; // 0.0 ~ 1.0
        opacity = p; // 0.0 -> 1.0
        scale = 0.5 + (0.7 * p); // 0.5 -> 1.2
        offsetY = -20 * p; // 0 -> -20px (살짝 튕김)
      } 
      // 2단계: 0.16~0.8s (20~100%) - 상승 소멸 (부드럽게 떠오르며 투명도 1->0)
      else {
        final p = (progress - 0.2) / 0.8; // 0.0 ~ 1.0
        opacity = 1.0 - p; // 1.0 -> 0.0
        scale = 1.2 - (0.2 * p); // 1.2 -> 1.0
        offsetY = -20 - (60 * p); // -20 -> -80px까지 (총 80px 이동)
      }

      // 최종 좌표 계산 (basePosition + 애니메이션 오프셋)
      final position = ft.basePosition + Offset(0, offsetY);

      if (opacity <= 0) continue;
      
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.scale(scale);
      
      // 🆕 성능 최적화: saveLayer 대신 투명도가 적용된 TextStyle 사용을 유도하려 했으나, 
      // 이미 생성된 TextPainter의 색상을 바꾸기 어려우므로 투명도가 낮을 때만 제한적으로 처리 (또는 Opacity 적용)
      // 여기서는 텍스트 페인터의 원본 색상에 투명도를 곱하는 방식이 가장 빠름
      ft.textPainter.paint(canvas, Offset(-ft.textPainter.width / 2, -ft.textPainter.height / 2));
      
      canvas.restore(); // for translate/scale
    }
  }

  @override
  bool shouldRepaint(covariant DamagePainter oldDelegate) => true;
}

/// 🆕 [v0.5.28] 고성능 통합 히어로 효과 렌더러
/// 캐릭터의 모든 비주얼 효과(오라, 마법진, 파티클)를 단일 캔버스에서 처리하여 성능을 극대화함.



class GainRecord {
  final DateTime time;
  final int gold;
  final int exp;
  final int kills;
  final int damage;
  GainRecord(this.time, {this.gold = 0, this.exp = 0, this.kills = 0, this.damage = 0});
}

class GameNotification {
  final String message;
  final bool isError;
  final DateTime time;
  GameNotification(this.message, this.isError, this.time);
}

class SuccessOverlayData {
  final String title;
  final String subtitle;
  SuccessOverlayData(this.title, this.subtitle);
}

class LootParticle {
  final Offset initialPos;
  final LootType type;
  final DateTime startTime;
  final double angle;
  LootParticle(this.initialPos, this.type, this.startTime, Random rand)
      : angle = rand.nextDouble() * 2 * pi;
}

/// 성능 최적화를 위한 파티클 전용 페인터
class LootParticlePainter extends CustomPainter {
  final List<LootParticle> particles;
  final Animation<double> ticker;

  LootParticlePainter({required this.particles, required this.ticker}) : super(repaint: ticker);

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;
    final now = DateTime.now();

    for (var p in particles) {
      final elapsed = now.difference(p.startTime).inMilliseconds;
      if (elapsed < 0 || elapsed > 1000) continue;

      double t = elapsed / 1000;
      double x, y;

      // 궤적 계산 (기존 로직 유지하되 미세하게 부드럽게 조정)
      if (t < 0.3) {
        double subT = t / 0.3;
        double dist = 45 * Curves.easeOutQuart.transform(subT);
        x = p.initialPos.dx + (cos(p.angle) * dist);
        y = p.initialPos.dy + (sin(p.angle) * dist);
      } else {
        double subT = (t - 0.3) / 0.7;
        // 골드는 대시보드 좌측 Gold 문구 위치, EXP는 전투탭 내 파란색 바 위치로 타격
        Offset target = p.type == LootType.gold 
            ? Offset(110, -45) // 대시보드 내 골드 수치 텍스트 정확한 위치
            : Offset(size.width / 2, 10); // 전투 탭 상단 파란색 EXP 바 위치
        
        
        // 유기적인 흔들림 (Wobble) 추가 - 목적지에 가까워질수록 진동 감소
        double wobble = sin(subT * 20) * 12 * (1 - subT);
        
        // 제어점(Control Point) 조절 - 더 완만한 곡선으로 수정
        double centerX = p.initialPos.dx + (target.dx - p.initialPos.dx) * 0.5 + (p.type == LootType.gold ? 60 : -60);
        double centerY = p.initialPos.dy - 120; // 치솟는 높이를 대폭 하향 (-350 -> -120)
        
        double invT = 1 - subT;
        x = invT * invT * p.initialPos.dx + 2 * invT * subT * centerX + subT * subT * target.dx + (p.type == LootType.gold ? -wobble : wobble);
        y = invT * invT * p.initialPos.dy + 2 * invT * subT * centerY + subT * subT * target.dy;
      }

      double opacity = t > 0.8 ? (1.0 - (t - 0.8) / 0.2).clamp(0, 1) : 1.0;
      double scale = (t < 0.2) ? Curves.elasticOut.transform(t / 0.2) : (1.0 + sin(t * 12) * 0.1);
      double rotation = t * 10; // 회전 효과

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.scale(scale);

      if (p.type == LootType.gold) {
        _drawGoldenCoin(canvas, opacity);
      } else {
        _drawExpCrystal(canvas, opacity);
      }
      
      // 주변 반짝임 파티클 (Sparkles)
      if (t > 0.1 && t < 0.9) {
        _drawSparkle(canvas, t, opacity);
      }

      canvas.restore();
    }
  }

  void _drawGoldenCoin(Canvas canvas, double opacity) {
    // 코인 테두리 및 그림자
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.3 * opacity)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(const Offset(1, 1), 7, shadowPaint);

    // 코인 베이스 (그라데이션)
    final coinPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFFFD700).withOpacity(opacity), const Color(0xFFB8860B).withOpacity(opacity)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 7));
    canvas.drawCircle(Offset.zero, 7, coinPaint);

    // 밝은 테두리
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.6 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset.zero, 7, borderPaint);

    // 코인 심볼 ($ 또는 심플 라인)
    final symbolPaint = Paint()
      ..color = Colors.white.withOpacity(0.8 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(0, -3.5), const Offset(0, 3.5), symbolPaint);
  }

  void _drawExpCrystal(Canvas canvas, double opacity) {
    final path = Path();
    path.moveTo(0, -9);
    path.lineTo(6, 0);
    path.lineTo(0, 9);
    path.lineTo(-6, 0);
    path.close();

    // 크리스탈 글로우
    final glowPaint = Paint()..color = Colors.blueAccent.withOpacity(0.4 * opacity)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawPath(path, glowPaint);

    // 크리스탈 바디 (그라데이션)
    final crystalPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF00FFFF).withOpacity(opacity), const Color(0xFF4169E1).withOpacity(opacity)],
      ).createShader(Rect.fromLTWH(-6, -9, 12, 18));
    canvas.drawPath(path, crystalPaint);

    // 밝은 하이라이트
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.8 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, highlightPaint);
  }

  void _drawSparkle(Canvas canvas, double t, double opacity) {
    final sparklePaint = Paint()..color = Colors.white.withOpacity(0.8 * opacity);
    for (int i = 0; i < 2; i++) {
        double angle = (t * 5) + (i * pi);
        double dist = 10 + sin(t * 8) * 3;
        canvas.drawCircle(Offset(cos(angle) * dist, sin(angle) * dist), 1, sparklePaint);
    }
  }

  @override
  bool shouldRepaint(covariant LootParticlePainter oldDelegate) => true;
}

/// 전역 알림(Toast) Overlay 위젯
class _ToastOverlayWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _ToastOverlayWidget({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_ToastOverlayWidget> createState() => _ToastOverlayWidgetState();
}

class _ToastOverlayWidgetState extends State<_ToastOverlayWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 2000), () async {
      if (mounted) {
        await _controller.reverse();
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120,
      left: 50,
      right: 50,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.isError ? Colors.redAccent.withOpacity(0.95) : Colors.blueAccent.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Flexible(child: Text(widget.message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, decoration: TextDecoration.none))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 전역 성공(Success) Overlay 위젯
class _SuccessOverlayWidget extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback onDismiss;
  final Widget Function(String, {double fontSize, Color color, FontWeight fontWeight, TextOverflow? overflow}) shadowTextBuilder;

  const _SuccessOverlayWidget({
    required this.title,
    required this.subtitle,
    required this.onDismiss,
    required this.shadowTextBuilder,
  });

  @override
  State<_SuccessOverlayWidget> createState() => _SuccessOverlayWidgetState();
}

class _SuccessOverlayWidgetState extends State<_SuccessOverlayWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2500), () async {
      if (mounted) {
        await _controller.reverse();
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.5),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)),
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.withValues(alpha: 0.9), Colors.orange.withValues(alpha: 0.9)],
                    ),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          widget.shadowTextBuilder(widget.title, fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          widget.shadowTextBuilder(widget.subtitle, fontSize: 13, color: Colors.white.withOpacity(0.9)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- 화면 모드 관리 (일반 / 화면유지 / 절전) ---
enum DisplayMode { normal, stayAwake, powerSave }

