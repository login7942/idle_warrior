import 'dart:async';
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
import 'models/skill.dart';
import 'models/pet.dart';
import 'models/achievement.dart';
import 'models/hunting_zone.dart';
import 'models/monster.dart';
import 'services/update_service.dart';
import 'services/auth_service.dart';
import 'config/supabase_config.dart';
import 'widgets/inventory_panel.dart';
import 'widgets/skill_panel.dart';
import 'widgets/pet_panel.dart';
import 'widgets/achievement_panel.dart';
import 'widgets/common_widgets.dart';
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
  int _achievementMenuTab = 0; // 0: 업적, 1: 도감
  int _currentLogTab = 0;

  // 가방 필터 및 정렬용
  Timer? _scrollStopTimer;

  late AnimationController _playerAttackController;
  late AnimationController _playerHitController;
  late AnimationController _monsterAttackController;
  late AnimationController _monsterHitController;
  late AnimationController _uiTickerController; // 60FPS UI 갱신용
  late AnimationController _shimmerController; // 프리미엄 아이템 광택용
  late AnimationController _heroPulseController; // 캐릭터 숨쉬기/후광용
  late AnimationController _heroRotateController; // 헤일로 회전용
  late AnimationController _monsterSpawnController; // 몬스터 등장 연출
  late AnimationController _monsterDeathController; // 몬스터 사망 연출
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
  double _monsterDefenseMultiplier = 1.0; // 몬스터 방어력 배율 (0.0 ~ 1.0)

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

  // 사냥터 카테고리 관리 상태
  bool _isGeneralExpanded = true;
  bool _isSpecialExpanded = true;

  // 무한의탑 시퀀스 관리
  HuntingZone? _previousZone;
  int? _previousStage;
  int _towerCountdown = 0;
  Timer? _towerTimer;
  bool _isEnteringTower = false; // 🆕 무한의탑 중복 입장/연타 방지 플래그
  bool _isTowerResultShowing = false; // 🆕 결과 팝업 중복 노출 방지

  // --- [신규 v0.0.60] 제작 시스템 상태 ---
  int _selectedCraftTier = 2; // 기본 선택 티어 (T2)
  int _expandedCraftCategory = 0; // 0: 장외 제작, 그 외: 준비 중

  // --- [신규 v0.0.61] 자동 분해 시스템 ---

  // --- [신규 v0.1.x] 라운드 로빈 전투 시스템 ---
  // --- [신규 v0.1.x] 전역 게터 ---
  Player get player => context.read<GameState>().player;
  GameState get gameState => context.read<GameState>();
  AuthService get _authService => context.read<GameState>().authService;
  bool get _isCloudSynced => context.watch<GameState>().isCloudSynced;
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
    
    _playerAttackController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _playerHitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _monsterAttackController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _monsterHitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _uiTickerController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _shimmerController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _heroPulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _heroRotateController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    
    _monsterSpawnController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _monsterDeathController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    
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
    gameState.onDamageDealt = (text, isCrit, isSkill, {ox, oy}) {
      if (!mounted) return;
      // 몬스터 피격 (뒤로 밀림)
      _monsterHitController.forward(from: 0);
      // 플레이어 공격 (앞으로 튀어남)
      _playerAttackController.forward(from: 0);
      // 데미지 텍스트 (isSkill 여부 전달, 오프셋 반영)
      _addFloatingText(text, true, isCrit: isCrit, isSkill: isSkill, offsetX: ox, offsetY: oy);
    };

    gameState.onHeal = (healAmount) {
      if (!mounted) return;
      _addFloatingText('+$healAmount', false, isHeal: true);
    };

    gameState.onPlayerDamageTaken = (damage) {
      if (!mounted) return;
      // 플레이어 피격 (뒤로 밀림)
      _playerHitController.forward(from: 0);
      // 몬스터 공격 (앞으로 튀어나감)
      _monsterAttackController.forward(from: 0);
      // 데미지 텍스트
      _addFloatingText(damage.toString(), false);
    };

    gameState.onMonsterSpawned = () {
      if (!mounted) return;
      // 몬스터 등장 애니메이션 초기화 및 실행
      _monsterDeathController.reset();
      _monsterSpawnController.forward(from: 0);
    };

    gameState.onVictory = (gold, exp) {
      if (!mounted) return;
      
      // 1. 세션 데이터 업데이트 (UI 표시용)
      _recentGains.add(GainRecord(DateTime.now(), gold: gold, exp: exp, kills: 1));
      _sessionGold += gold;
      _sessionExp += exp;

      // 2. 몬스터 사망 애니메이션 실행
      _monsterDeathController.forward(from: 0);

      // 3. 드롭 파티클 연출 (좌표 계산 후 실행)
      final monsterBox = _monsterKey.currentContext?.findRenderObject() as RenderBox?;
      final battleBox = _battleSceneKey.currentContext?.findRenderObject() as RenderBox?;
      
      if (monsterBox != null && battleBox != null) {
        // 몬스터 중심의 글로벌 좌표를 배틀 박스의 로컬 좌표로 변환
        final globalCenter = monsterBox.localToGlobal(monsterBox.size.center(Offset.zero));
        final localPos = battleBox.globalToLocal(globalCenter);
        _spawnLootParticles(gold, exp, localPos);
      }

      // 4. 무한의 탑일 경우 결과창 표시
      if (gameState.currentZone.id == ZoneId.tower) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTowerResultDialog(true);
        });
      }
    };

    // [v0.0.79] 스테이지 점프 콜백 연결
    gameState.onStageJump = () {
      if (!mounted) return;
      _triggerJumpEffect();
    };

    // 초기 실행 시 몬스터가 이미 있다면 등장 애니메이션 실행
    if (gameState.currentMonster != null) {
      _monsterSpawnController.forward(from: 0);
    }
    
    // 🆕 분당 효율 계산 타이머 (5초마다 갱신)
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updateEfficiencyStats();
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOfflineRewards();
      UpdateService.checkUpdate(context);
    });
  }

  // 🆕 분당 효율 통계 계산
  void _updateEfficiencyStats() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 60));
    
    // 60초 이전 데이터 제거
    _recentGains.removeWhere((g) => g.time.isBefore(cutoff));
    
    if (_recentGains.isEmpty) {
      gameState.goldPerMin = 0;
      gameState.expPerMin = 0;
      gameState.killsPerMin = 0;
      return;
    }
    
    // 최근 60초간의 총합 계산
    int totalGold = 0;
    int totalExp = 0;
    int totalKills = 0;
    
    for (var record in _recentGains) {
      totalGold += record.gold;
      totalExp += record.exp;
      totalKills += record.kills;
    }
    
    // 실제 경과 시간 계산 (초 단위)
    final oldestTime = _recentGains.first.time;
    final elapsedSeconds = now.difference(oldestTime).inSeconds;
    
    if (elapsedSeconds > 0) {
      // 분당 환산 (초당 * 60)
      gameState.goldPerMin = (totalGold / elapsedSeconds * 60);
      gameState.expPerMin = (totalExp / elapsedSeconds * 60);
      gameState.killsPerMin = (totalKills / elapsedSeconds * 60);
    }
  }


  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    _jumpEffectTimer?.cancel();
    _playerAttackController.dispose();
    _playerHitController.dispose();
    _monsterAttackController.dispose();
    _monsterHitController.dispose();
    _uiTickerController.dispose();
    _shimmerController.dispose();
    _heroPulseController.dispose();
    _heroRotateController.dispose();
    _monsterSpawnController.dispose();
    _monsterDeathController.dispose();
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


  void _addLog(String msg, LogType type) {
    if (!mounted) return;
    context.read<GameState>().addLog(msg, type);
  }

  // 🆕 데미지 텍스트 추가 API (통합 관리)
  void _addFloatingText(String text, bool isMonsterTarget, {
    bool isCrit = false, 
    bool isSkill = false,
    bool isHeal = false, 
    bool isGold = false, 
    bool isExp = false, 
    double? offsetX, 
    double? offsetY
  }) {
    final rand = Random();
    
    // 타입 결정 (우선순위: 회복 > 스킬 > 크리티컬 > 기타)
    DamageType type = DamageType.normal;
    if (isHeal) { type = DamageType.heal; }
    else if (isSkill) { type = DamageType.skill; }
    else if (isCrit) { type = DamageType.critical; }
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
    
    // 🆕 최적화: 데미지 생성 시 텍스트 스타일과 레이아웃이 1회 계산됨
    damageManager.add(DamageEntry(
      text: text,
      createdAt: DateTime.now(),
      type: type,
      basePosition: basePos + Offset(ox, oy),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 0번 탭(전투)일 때만 전역 사냥터 배경 활성화 (RepaintBoundary 최적화 순서 교정)
          if (_selectedIndex == 0)
            const Positioned.fill(
              child: RepaintBoundary(
                child: Image(
                  image: AssetImage('assets/images/background.png'),
                  fit: BoxFit.cover,
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
                        // 최적화된 파티클 레이어 (전투 탭에서만 활성화)
                        if (_selectedIndex == 0)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: LootParticlePainter(
                                    particles: _lootParticles,
                                    ticker: _uiTickerController,
                                  ),
                                ),
                              ),
                            ),
                          ),
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
      case 1: return _buildCharacterTab();
      case 2: return _buildHuntingZoneTab(); // 사냥터 이동 메뉴 연결
      case 3: return const InventoryPanel(); // 가방 메뉴 연결
      case 4: return _buildCraftTab();
      case 5: return SkillPanel(onShowToast: _showToast);
      case 6: return const PetPanel();
      case 7: return _buildMenuPlaceholder('유물 (환생)');
      case 8: return AchievementPanel(onShowToast: _showToast, onShowSuccess: _showSuccess);
      case 9: return _buildSystemTab(); // 실제 시스템/관리자 모드 연결
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

        return GlassContainer(
          margin: const EdgeInsets.only(bottom: 12),
          borderRadius: 24,
          color: isCurrent ? zone.color.withValues(alpha: 0.2) : Colors.black,
          border: Border.all(color: isCurrent ? zone.color.withValues(alpha: 0.5) : Colors.white10, width: isCurrent ? 1.5 : 0.5),
          child: InkWell(
            onTap: () {
              if (zone.id == ZoneId.tower) {
                _enterTower(zone);
              } else {
                setState(() {
                  // 🐛 버그 수정: 이전 사냥터의 스테이지를 저장
                  gameState.zoneStages[gameState.currentZone.id] = gameState.currentStage;
                  
                  // 새 사냥터로 전환
                  gameState.currentZone = zone;
                  gameState.currentStage = stage;
                  gameState.stageKills = 0;
                  _selectedIndex = 0; // 전투 탭으로 자동 이동
                  gameState.addLog('${zone.name} 지역으로 이동했습니다.', LogType.event);
                  _spawnMonster();
                });
              }
            },
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ShadowText(zone.name, fontSize: 22, fontWeight: FontWeight.bold),
                            if (isCurrent) const SizedBox(width: 8),
                            if (isCurrent) Icon(Icons.location_on, color: zone.color, size: 18),
                            if (zone.type == ZoneType.special) 
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.amberAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                child: const Text('도전', style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(zone.description, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: zone.keyDrops.map((drop) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Text(drop, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ShadowText(zone.id == ZoneId.tower ? 'FLOOR' : 'STAGE', fontSize: 10, color: Colors.white38),
                      ShadowText('${Monster.getDisplayStage(stage)}', color: zone.color, fontWeight: FontWeight.bold, fontSize: 24),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                        child: Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 👤 CHARACTER TAB - 캐릭터 정보 탭
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCharacterTab() {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final player = gameState.player;
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Column(
            children: [
              // 히어로 쇼케이스 카드
              _buildHeroShowcase(),
              const SizedBox(height: 20),
              
              // 능력치 카드 3종
              Row(
                children: [
                  Expanded(child: _buildStatCard('공격', Icons.flash_on, Colors.redAccent, [
                    _buildStatRow('ATK', player.attack.toString()),
                    _buildStatRow('SPD', player.attackSpeed.toStringAsFixed(2)),
                    _buildStatRow('CRIT', '${player.critChance.toStringAsFixed(1)}%'),
                    _buildStatRow('C.DMG', '${player.critDamage.toInt()}%'),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: _buildStatCard('생존', Icons.shield, Colors.blueAccent, [
                    _buildStatRow('HP', player.maxHp.toString()),
                    _buildStatRow('DEF', player.defense.toString()),
                    _buildStatRow('REGEN', '${player.hpRegen.toStringAsFixed(1)}%'),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: _buildStatCard('성장', Icons.trending_up, Colors.lightBlueAccent, [
                    _buildStatRow('GOLD', '${player.goldBonus.toInt()}%'),
                    _buildStatRow('DROP', '${player.dropBonus.toInt()}%'),
                    _buildStatRow('OFF', '${player.offEfficiency}x'),
                  ])),
                ],
              ),
              const SizedBox(height: 20),
              
              // 자산 및 재료 요약
              _buildAssetSummary(),
              
              const SizedBox(height: 120), // 하단 독 여백
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroShowcase() {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      borderRadius: 34,
      child: Column(
        children: [
          // 상단 타이틀 뱃지
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 30, height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.blueAccent]))),
              const SizedBox(width: 12),
              Column(
                children: [
                  Text('MYTHIC WARRIOR', style: TextStyle(color: Colors.blueAccent.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  const SizedBox(height: 4),
                  ShadowText(player.name, fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white),
                ],
              ),
              const SizedBox(width: 12),
              Container(width: 30, height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blueAccent, Colors.transparent]))),
            ],
          ),
          const SizedBox(height: 40),
          
          // 메인 비주얼 엔진
          Stack(
            alignment: Alignment.center,
            children: [
              // 1. 회전하는 매직 헤일로 (Back layer)
              RotationTransition(
                turns: _heroRotateController,
                child: Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.05), width: 1),
                  ),
                  child: Stack(
                    children: List.generate(4, (i) => Align(
                      alignment: Alignment(cos(i * pi/2), sin(i * pi/2)),
                      child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
                    )),
                  ),
                ),
              ),
              
              // 2. 멀티 레이어 펄스 오라 (Glow layer)
              AnimatedBuilder(
                animation: _heroPulseController,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 외곽 광원
                      Container(
                        width: 160 + (30 * _heroPulseController.value),
                        height: 160 + (30 * _heroPulseController.value),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.12 * (1 - _heroPulseController.value)),
                              blurRadius: 60 + (40 * _heroPulseController.value),
                              spreadRadius: 5,
                            )
                          ],
                        ),
                      ),
                      // 핵심 광원
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyanAccent.withValues(alpha: 0.15),
                              blurRadius: 30 + (10 * _heroPulseController.value),
                              spreadRadius: 2,
                            )
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              // 3. 부유 에너지 입자 (Particle simulation)
              ...List.generate(6, (i) => _buildHeroParticle(i)),

              // 4. 캐릭터 본체 (Breathing)
              AnimatedBuilder(
                animation: _heroPulseController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, -8 * _heroPulseController.value),
                    child: SizedBox(
                      height: 190,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // 캐릭터 그림자
                          Container(
                            width: 60 - (10 * _heroPulseController.value),
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3 + (0.1 * _heroPulseController.value)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
                              borderRadius: const BorderRadius.all(Radius.elliptical(60, 10)),
                            ),
                          ),
                          // 캐릭터 이미지
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Image.asset('assets/images/warrior.png', fit: BoxFit.contain),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 40),
          
          // 전투력 요약 바
          _buildHeroScoreBar(),
        ],
      ),
    );
  }

  // 에너지 입자 생성기
  Widget _buildHeroParticle(int index) {
    return AnimatedBuilder(
      animation: _heroPulseController,
      builder: (context, child) {
        final double speed = 0.5 + (index * 0.1);
        final double progress = (_heroPulseController.value * speed + (index / 6)) % 1.0;
        final double angle = (index * 60) * pi / 180;
        final double radius = 80 + (20 * sin(progress * pi));
        
        return Transform.translate(
          offset: Offset(cos(angle) * radius, -40 - (radius * 0.5 * progress)),
          child: Opacity(
            opacity: sin(progress * pi),
            child: Container(
              width: 3, height: 3,
              decoration: BoxDecoration(
                color: index % 2 == 0 ? Colors.cyanAccent : Colors.blueAccent,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.white, blurRadius: 4)],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroScoreBar() {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      borderRadius: 18,
      color: Colors.white.withValues(alpha: 0.04),
      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2), width: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('COMBAT READINESS', style: TextStyle(color: Colors.blueAccent.withValues(alpha: 0.6), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 2),
              ShadowText('OVERPOWERING', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ],
          ),
          ShadowText('${player.combatPower}', fontSize: 32, fontWeight: FontWeight.w900, color: Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, IconData icon, Color color, List<Widget> children) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      borderRadius: 20,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildAssetSummary() {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory, size: 18, color: Colors.orangeAccent), 
              const SizedBox(width: 10), 
              ShadowText('희귀 자원 현황', fontSize: 16, fontWeight: FontWeight.bold)
            ]
          ),
          const SizedBox(height: 20),
          Row(children: [
            _buildAssetItem(Icons.auto_awesome, '가루', player.powder, Colors.orangeAccent),
            _buildAssetItem(Icons.diamond, '강화석', player.enhancementStone, Colors.blueAccent),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _buildAssetItem(Icons.history_edu, '재설정석', player.rerollStone, Colors.purpleAccent),
            _buildAssetItem(Icons.shield, '보호권', player.protectionStone, Colors.amberAccent),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _buildAssetItem(Icons.category, '큐브', player.cube, Colors.redAccent),
            const Expanded(child: SizedBox()), 
          ]),
        ],
      ),
    );
  }

  Widget _buildAssetItem(IconData icon, String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const Spacer(),
            Text(_formatNumber(count), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  // --- 가방 (인벤토리) 메뉴 구현 ---
  // ═══════════════════════════════════════════════════════════════════════════

  // 🔨 [신규 v0.0.60] 제작 탭 (Forge UI)
  Widget _buildCraftTab() {
    return Column(
      children: [
        const SizedBox(height: 12),
        _buildCraftHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _buildCraftCategory(
                0, '⚔️ 장비 제작', 
                child: Column(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('제작 티어 선택', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                            Text(
                              '현재 평균 강화: +${player.averageEnhanceLevel.toStringAsFixed(1)}',
                              style: TextStyle(
                                color: player.averageEnhanceLevel >= 13.0 ? Colors.greenAccent : Colors.white38,
                                fontSize: 10,
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '※ 평균강화 달성 시 상위재료가 드랍됩니다',
                          style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildTierTab(),
                    const SizedBox(height: 16),
                    _buildEquipmentCraftGrid(),
                  ],
                )
              ),
              _buildCraftCategory(1, '🧪 소모품 제작 (준비 중)', isLocked: true),
              _buildCraftCategory(2, '💎 유물 합성 (준비 중)', isLocked: true),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCraftHeader() {
    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      color: Colors.white.withValues(alpha: 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('보유 제작 재료', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMiniResourceItem('🧩', 'T1 파편', player.tierShards[1] ?? 0, Colors.tealAccent),
              const SizedBox(width: 16),
              _buildMiniResourceItem('🧩', 'T2 파편', player.tierShards[2] ?? 0, Colors.blueAccent),
              const SizedBox(width: 16),
              _buildMiniResourceItem('🔮', 'T2 구슬', player.tierCores[2] ?? 0, Colors.purpleAccent),
            ],
          ),
        ],
      ),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [2, 3, 4, 5, 6].map((t) {
          bool isSel = _selectedCraftTier == t;
          double reqAvg = t == 2 ? 13.0 : (t == 3 ? 15.0 : 18.0); // T2: 13, T3: 15, T4+: 18
          bool isLocked = player.averageEnhanceLevel < reqAvg;
          
          return PressableScale(
            onTap: isLocked ? null : () => setState(() => _selectedCraftTier = t),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSel ? Colors.blueAccent : (isLocked ? Colors.black26 : Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSel ? Colors.white24 : Colors.white10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLocked) const Icon(Icons.lock, size: 10, color: Colors.white24),
                      if (isLocked) const SizedBox(width: 4),
                      Text(
                        'Tier $t', 
                        style: TextStyle(
                          color: isSel ? Colors.white : (isLocked ? Colors.white24 : Colors.white60),
                          fontWeight: FontWeight.bold,
                          fontSize: 12
                        )
                      ),
                    ],
                  ),
                  if (isLocked)
                    Text(
                      '평균강화+${reqAvg.toInt()}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEquipmentCraftGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 140,
      ),
      itemCount: ItemType.values.length,
      itemBuilder: (context, idx) {
        final type = ItemType.values[idx];
        return _buildCraftCard(type);
      },
    );
  }

  Widget _buildCraftCard(ItemType type) {
    int tier = _selectedCraftTier;
    // 재료 설정: T2(파편 150, 구슬 5), T3(파편 500, 구슬 10)... 
    // 실제 밸런스에 맞춰 조정 가능
    int shardCost = tier == 2 ? 150 : (tier == 3 ? 500 : 2000);
    int coreCost = tier == 2 ? 5 : (tier == 3 ? 10 : 30);
    
    int myShards = player.tierShards[tier - 1] ?? 0;
    int myCores = player.tierCores[tier] ?? 0;
    
    bool canCraft = myShards >= shardCost && myCores >= coreCost;

    return GlassContainer(
      padding: const EdgeInsets.all(12),
      borderRadius: 20,
      color: Colors.white.withValues(alpha: 0.03),
      child: Column(
        children: [
          Row(
            children: [
              EmptyItemIcon(type: type, size: 24),
              const SizedBox(width: 8),
              Text(type.nameKr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
            ],
          ),
          const Spacer(),
          _buildCraftResourceRow('🧩', shardCost, myShards),
          _buildCraftResourceRow('🔮', coreCost, myCores),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canCraft ? Colors.blueAccent : Colors.white10,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: canCraft ? () => _executeCraft(type, tier, shardCost, coreCost) : null,
              child: const Text('제작하기', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
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
    if (player.inventory.length >= player.maxInventory) {
      _showToast('가방이 가득 찼습니다.');
      return;
    }

    setState(() {
      player.tierShards[tier - 1] = (player.tierShards[tier - 1] ?? 0) - shardCost;
      player.tierCores[tier] = (player.tierCores[tier] ?? 0) - coreCost;
      
      // 아이템 생성 (선택한 티어 및 부위 반영)
      Item newItem = Item.generate(player.level, tier: tier, forcedType: type);
      
      player.inventory.add(newItem);
      _saveGameData(forceCloud: true); // [v0.0.82] 제작 완료 시 즉시 클라우드 저장
      _showCraftResult(newItem);
    });
  }

  void _showCraftResult(Item item) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) => Center(
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
    );
  }


  // --- 기존 UI 컴포넌트들 ---
  Widget _buildTopDashboard() {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
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
                      ShadowText('${gameState.player.level}', fontSize: 18, color: Colors.white, fontWeight: FontWeight.w900),
                      const SizedBox(width: 12),
                      ShadowText('CP', fontSize: 12, color: Colors.amber.withValues(alpha: 0.8), fontWeight: FontWeight.bold),
                      const SizedBox(width: 4),
                      ShadowText('${gameState.player.combatPower}', fontSize: 18, color: Colors.amber, fontWeight: FontWeight.w900),
                      const SizedBox(width: 12),
                      ShadowText('Gold', fontSize: 12, color: Colors.amber.withValues(alpha: 0.6), fontWeight: FontWeight.bold),
                      const SizedBox(width: 4),
                      ShadowText(_formatNumber(gameState.player.gold), fontSize: 18, color: Colors.amberAccent, fontWeight: FontWeight.w900),
                      const SizedBox(width: 8),
                      // 🆕 클라우드 상태 아이콘
                      Icon(
                        _isCloudSynced ? Icons.cloud_done : Icons.cloud_off,
                        size: 14,
                        color: _isCloudSynced ? Colors.greenAccent : Colors.white24,
                      ),
                    ],
                  ),
                ],
              ),
              // 오른쪽: 기능 버튼
              Row(
                children: [
                   _buildDashboardActionBtn(
                     _displayMode == DisplayMode.normal ? Icons.battery_saver : (_displayMode == DisplayMode.stayAwake ? Icons.light_mode : Icons.nightlight_round), 
                     _displayMode == DisplayMode.normal ? '절전' : (_displayMode == DisplayMode.stayAwake ? '유지' : '절전중'), 
                     _cycleDisplayMode,
                     color: _displayMode == DisplayMode.normal ? Colors.greenAccent : (_displayMode == DisplayMode.stayAwake ? Colors.orangeAccent : Colors.blueAccent)
                   ),
                ],
              ),
            ],
          ),
        );
      },
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
                _buildPowerSaveRow('📦 강화 큐브', _formatNumber(_sessionCube)),
                
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
                      Text('${gameState.stageKills} / ${gameState.targetKills}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
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
    return Column(
      children: [
        _buildCombatHeader(), // 진행도와 효율을 가로로 통합한 새로운 헤더
        Expanded(flex: 7, child: _buildBattleScene()), // 전투 비중 확대
        SkillQuickbar(
          uiTicker: _uiTickerController,
          onNavigateToSkillTab: () => setState(() => _selectedIndex = 5),
        ),
        Expanded(flex: 3, child: _buildTabbedLogs()), // 로그 비중 조정
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildCombatHeader() {
    double expProgress = (player.exp / player.maxExp).clamp(0, 1);
    String expDetail = '${_formatNumber(player.exp)} / ${_formatNumber(player.maxExp)} (${(expProgress * 100).toStringAsFixed(1)}%)';
    
    return Column(
      children: [
        // 1. 경험치 및 스테이지 바 영역
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _buildLargeProgressBar('EXP', expProgress, Colors.blueAccent, trailingLabel: expDetail),
        ),
        // 2. 콤팩트 통계 카드
        _buildEfficiencyCard(),
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
                  Expanded(child: _buildStatItem(Colors.amber, gameState.goldPerMin.toInt().toString(), '분당골드')),
                  _buildStatDivider(),
                  Expanded(child: _buildStatItem(Colors.blueAccent, gameState.expPerMin.toInt().toString(), '분당EXP')),
                  _buildStatDivider(),
                  Expanded(child: _buildStatItem(Colors.redAccent, gameState.killsPerMin.toStringAsFixed(1), '분당처치')),
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
                  Flexible(child: _buildSessionStat('최대DMG', _sessionMaxDamage, Colors.redAccent)),
                  const SizedBox(width: 4),
                  const Spacer(),

                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _sessionGold = 0;
                        _sessionExp = 0;
                        _sessionMaxDamage = 0; // 초기화 시 최대 데미지도 리셋
                        _recentGains.clear();
                        
                        // GameState의 효율 데이터도 초기화
                        gameState.goldPerMin = 0;
                        gameState.expPerMin = 0;
                        gameState.killsPerMin = 0;
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
    final List<String> emojis = ['⚔️', '👤', '🗺️', '🎒', '🔨', '⚡', '🐾', '💎', '🏆', '⚙️'];
    final List<String> labels = ['전투', '캐릭터', '사냥터', '가방', '제작', '스킬', '펫', '환생', '업적', '설정'];
    
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
                        Text(
                          emojis[idx],
                          style: TextStyle(
                            fontSize: isSel ? 18 : 16,
                            shadows: [
                              Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 3, offset: const Offset(1, 1))
                            ],
                          ),
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
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        return AnimatedBuilder(
          animation: Listenable.merge([_uiTickerController, _monsterSpawnController, _monsterDeathController]),
          builder: (context, child) {
            return Stack(
              key: _battleSceneKey,
              fit: StackFit.expand, 
              children: [
                // 기존 중복 배경 제거
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _buildActor(
                gameState.player.name, 
                gameState.player.level, 
                gameState.playerCurrentHp, 
                gameState.player.maxHp, 
                'assets/images/warrior.png', 
                _playerAttackController, 
                _playerHitController,
                true
              ),      
                  Center(
                    key: _monsterKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (gameState.currentMonster != null)
                          // 사망 애니메이션 (Fade + Scale Down)
                          FadeTransition(
                            opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_monsterDeathController),
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 1.0, end: 0.5).animate(CurvedAnimation(parent: _monsterDeathController, curve: Curves.easeIn)),
                              child: 
                                // 등장 애니메이션 (Fade + Scale Up)
                                FadeTransition(
                                  opacity: _monsterSpawnController,
                                  child: ScaleTransition(
                                    scale: CurvedAnimation(parent: _monsterSpawnController, curve: Curves.easeOutBack),
                                    child: _buildActor(
                  gameState.currentMonster!.name, 
                  gameState.currentMonster!.level, 
                  gameState.monsterCurrentHp, 
                  gameState.currentMonster!.maxHp, 
                  gameState.currentMonster!.imagePath, 
                  _monsterAttackController, 
                  _monsterHitController,
                  false
                ),
                                  ),
                                ),
                            ),
                          )
                        else
                          const SizedBox(width: 100, height: 150), // 몬스터가 없는 동안 빈 공간 유지
                      ],
                    ),
                  ),
                ]),
                // 플레이어 펫 표시 (전투 장면 최상상위에서 독립적으로 부유)
                if (gameState.player.activePet != null)
                  _buildIndependentPet(gameState.player.activePet!),
                
                // 🆕 고성능 캔버스 기반 데미지 텍스트 레이어 (RepaintBoundary 최적화 적용)
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

                // 🆕 무한의탑 입장 카운트다운 연출
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
      },
    );
  }

  Widget _buildActor(String n, int lv, int h, int mh, String img, AnimationController atk, AnimationController hit, bool p) {
    double hpProgress = (h / mh).clamp(0, 1);
    return AnimatedBuilder(
      animation: Listenable.merge([atk, hit, _heroPulseController, _heroRotateController, _monsterSpawnController, _monsterDeathController]), 
      builder: (ctx, _) {
        // 1. 공격 애니메이션 (앞으로 튀어나갔다 돌아옴)
        double lunge = sin(atk.value * pi) * 25; // 0 -> 25 -> 0
        
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
                scale: spawnScale,
                child: Column(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              // 1. 이름 및 등급 뱃지
              ShadowText(n, fontSize: 13, fontWeight: FontWeight.w900, color: p ? Colors.white : Colors.redAccent),
              const SizedBox(height: 5),
              
              // 2. 프리미엄 컴팩트 HP 바
              Container(
                width: 85, height: 7,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10, width: 0.5),
                ), 
                child: TweenAnimationBuilder<double>(
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
                )
              ),
              const SizedBox(height: 12),
              
              // 3. 전투 비주얼 엔진 (FX Overhaul)
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // 3-1. 발밑 회전 마법진 (Rotating Foot Seal)
                  RotationTransition(
                    turns: _heroRotateController,
                    child: Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: p ? Colors.cyan.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.05), width: 0.5),
                      ),
                      child: Stack(
                        children: List.generate(4, (i) => Align(
                          alignment: Alignment(cos(i * pi/2), sin(i * pi/2)),
                          child: Container(width: 3, height: 3, decoration: BoxDecoration(color: p ? Colors.cyan : Colors.red, shape: BoxShape.circle)),
                        )),
                      ),
                    ),
                  ),

                  // 3-2. 고밀도 더블 레이어 블룸 오라 (Double Bloom Aura)
                  Container(
                    width: 70 + (25 * _heroPulseController.value),
                    height: 80 + (20 * _heroPulseController.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        // Core Glow
                        BoxShadow(
                          color: p ? Colors.blueAccent.withValues(alpha: 0.25) : Colors.red.withValues(alpha: 0.2),
                          blurRadius: 20 + (15 * _heroPulseController.value),
                          spreadRadius: 2,
                        ),
                        // Outer Bloom
                        BoxShadow(
                          color: p ? Colors.cyan.withValues(alpha: 0.12) : Colors.redAccent.withValues(alpha: 0.1),
                          blurRadius: 40 + (30 * _heroPulseController.value),
                          spreadRadius: 5 + (10 * _heroPulseController.value),
                        ),
                      ],
                    ),
                  ),
                  
                  // 3-3. 입체형 바닥 그림자
                  Container(
                    width: 55 - (8 * _heroPulseController.value),
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: const BorderRadius.all(Radius.elliptical(55, 10)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 12)],
                    ),
                  ),

                  // 3-4. 부유 마력 입자 시스템 (Enhanced 8-Particles)
                  if (p)
                    ...List.generate(8, (i) => _buildCombatParticle(i)),

                  // 3-5. 액터 본체 (Breathing + Movement)
                  Transform.translate(
                    offset: p ? Offset(0, -6 * _heroPulseController.value) : Offset(0, -3 * _heroPulseController.value),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 실루엣 이너 글로우 효과 (Shadow Trick)
                          SizedBox(
                            width: 88, height: 88,
                            child: Image.asset(img, fit: BoxFit.contain, color: p ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.1), colorBlendMode: BlendMode.srcATop),
                          ),
                          // 실제 이미지
                          SizedBox(
                            width: 85, height: 85, 
                            child: Image.asset(img, fit: BoxFit.contain)
                          ),
                        ],
                      ),
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
      },
    );
  }

  // 강화된 전투 파티클 알고리즘 (Zig-zag Motion)
  Widget _buildCombatParticle(int index) {
    return AnimatedBuilder(
      animation: _heroPulseController,
      builder: (context, child) {
        final double speed = 0.4 + (index * 0.15);
        final double progress = (_heroPulseController.value * speed + (index / 8)) % 1.0;
        
        // 지그재그 모션 계산
        final double zigZag = sin(progress * pi * 4 + index) * 15.0;
        final double startX = (index - 3.5) * 12.0;
        final double currentY = -20 - (100 * progress);
        
        return Transform.translate(
          offset: Offset(startX + zigZag, currentY),
          child: Opacity(
            opacity: (1 - progress) * 0.8,
            child: Container(
              width: 2.5, height: 2.5,
              decoration: BoxDecoration(
                color: index % 2 == 0 ? Colors.cyanAccent : Colors.blueAccent, 
                shape: BoxShape.circle,
                boxShadow: index % 3 == 0 ? [BoxShadow(color: Colors.white, blurRadius: 4)] : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIndependentPet(Pet pet) {
    return AnimatedBuilder(
      animation: _uiTickerController,
      builder: (context, child) {
        // 시간에 따른 부유 애니메이션 (독립적 박자)
        final double time = DateTime.now().millisecondsSinceEpoch / 1000.0;
        final double floatingY = sin(time * 2.5) * 6.0; 
        final double floatingX = cos(time * 1.5) * 3.0;
        
        return Align(
          alignment: const Alignment(-0.9, -0.85), // 좌측 상단 (캐릭터와 완전히 분리된 독립 영역)
          child: Transform.translate(
            offset: Offset(floatingX, floatingY),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 펫 아이콘 (Emoji) - 프리미엄 원형 카드 스타일
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
                // 이름 제거됨 (향후 하단/옆으로 버프 아이콘 배치 공간 확보)
              ],
            ),
          ),
        );
      },
    );
  }

  // OLD SKILL UI REMOVED

  // --- 상세 메뉴 구현 ---



  Widget _buildTabbedLogs() {
    List<String> tabs = ['전체', '데미지', '아이템', '이벤트'];
    
    // 현재 선택된 탭에 따라 보여줄 리스트 결정
    List<CombatLogEntry> currentDisplayLogs;
    switch (_currentLogTab) {
      case 1: currentDisplayLogs = damageLogs; break;
      case 2: currentDisplayLogs = itemLogs; break;
      case 3: currentDisplayLogs = eventLogs; break;
      default: currentDisplayLogs = combatLogs; break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4), // 유리 느낌의 투명도
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          // 탭 바
          Row(
            children: List.generate(tabs.length, (i) => GestureDetector(
              onTap: () => setState(() => _currentLogTab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: _currentLogTab == i ? Colors.blueAccent : Colors.transparent, width: 2))
                ),
                child: Text(tabs[i], style: TextStyle(color: _currentLogTab == i ? Colors.blueAccent : Colors.white54, fontSize: 11)),
              )
            )),
          ),
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
                // 🆕 현재 로그인 정보 표시
                Text(
                  !_authService.isLoggedIn 
                    ? '상태: 로그아웃됨' 
                    : (_authService.userId!.startsWith('anon') 
                        ? '상태: 익명 계정 (보호되지 않음)' 
                        : '상태: 구글 계정 연동됨'),
                  style: TextStyle(
                    color: !_authService.isLoggedIn 
                      ? Colors.grey 
                      : (_authService.userId!.startsWith('anon') ? Colors.orangeAccent : Colors.greenAccent),
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
                        await _authService.signInWithGoogle();
                      },
                      icon: Icons.login,
                    ),
                  ),
                // 🆕 구글 계정 보호 버튼 (익명 계정일 때 표시)
                if (_authService.isLoggedIn && _authService.userId!.startsWith('anon'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: PopBtn(
                      '구글 계정으로 데이터 보호', 
                      Colors.white, 
                      () async {
                        _showToast('구글 로그인 창을 띄웁니다...');
                        await _authService.signInWithGoogle();
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
                _buildAdminResourceCard('마법 가루', player.powder, (v) => setState(() => player.powder += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('재설정석', player.rerollStone, (v) => setState(() => player.rerollStone += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('보호석', player.protectionStone, (v) => setState(() => player.protectionStone += v)),
                const SizedBox(height: 12),
                _buildAdminResourceCard('잠재의 큐브', player.cube, (v) => setState(() => player.cube += v)),
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
                PopBtn('모든 재화 1억 추가', Colors.amber, () {
                  setState(() {
                    player.gold += 100000000;
                    player.enhancementStone += 1000000;
                    player.powder += 1000000;
                    player.rerollStone += 10000;
                    player.protectionStone += 10000;
                    player.cube += 10000;
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

    final rewards = gameState.player.calculateOfflineRewards(
      lastSave, 
      effectiveGoldMin, 
      effectiveExpMin, 
      effectiveKillsMin
    );

    if (rewards.isEmpty) return;
    _showOfflineRewardDialog(rewards);
  }

  void _spawnMonster() => context.read<GameState>().spawnMonster();
  Future<void> _saveGameData({bool forceCloud = false}) => context.read<GameState>().saveGameData(forceCloud: forceCloud);
  void _startBattleLoop() {} // GameLoop가 관리하므로 빈 함수로 둠



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
              if (rewards.containsKey('tierShards')) ...[
                ...((rewards['tierShards'] as Map<int, int>).entries.map((e) =>
                    _buildOfflineRewardItem('🧩', 'T${e.key} 파편', e.value)
                )),
              ],
              if (rewards.containsKey('powder'))
                _buildOfflineRewardItem('✨', '가루', rewards['powder']),
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
                  _buildOfflineRewardItem('🔮', '큐브', rewards['cube']),
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
                      _buildRewardChip('영혼석 +1', Colors.purpleAccent),
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
}

// ═══════════════════════════════════════════════════════════════════════════
// 🎭 HELPER CLASSES - 헬퍼 클래스 및 열거형
// ═══════════════════════════════════════════════════════════════════════════

enum LootType { gold, exp }
enum DamageType { normal, critical, skill, heal, gold, exp }

/// 🆕 데미지 텍스트 데이터 모델
class DamageEntry {
  final String text;
  final DamageType type;
  final DateTime createdAt;
  final Offset basePosition;
  // 🆕 최적화: 레이아웃이 완료된 객체를 캐싱
  late final TextPainter textPainter;

  DamageEntry({
    required this.text,
    required this.createdAt,
    required this.type,
    required this.basePosition,
  }) {
    // 생성 시점에 텍스트 스타일과 레이아웃을 한 번만 계산합니다.
    final style = _getStaticTextStyle(type);
    textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
  }

  static TextStyle _getStaticTextStyle(DamageType type) {
    Color color;
    double fontSize = 18.0;
    
    switch (type) {
      case DamageType.critical: color = const Color(0xFFEF4444); break;
      case DamageType.skill: color = Colors.white; break;
      case DamageType.heal: color = const Color(0xFF22C55E); break;
      case DamageType.gold: color = const Color(0xFFEAB308); fontSize = 17.0; break;
      case DamageType.exp: color = const Color(0xFF3B82F6); fontSize = 17.0; break;
      default: color = Colors.white;
    }

    return GoogleFonts.luckiestGuy(
      color: color,
      fontSize: fontSize,
      letterSpacing: 0.5,
      shadows: [], 
    );
  }
}

/// 🆕 데미지 텍스트 생명주기 관리 매니저
class DamageManager {
  final List<DamageEntry> texts = [];
  
  void add(DamageEntry entry) {
    // 최대 텍스트 수 제한 (너무 많으면 메모리 부하 방지)
    if (texts.length > 30) texts.removeAt(0);
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

      // 1단계: 0~0.16s (0~20%) - Bounce Bounce (튀어오름)
      if (progress <= 0.2) {
        final p = progress / 0.2; // 0.0 ~ 1.0
        scale = 0.5 + (0.7 * p); // 0.5 -> 1.2
        offsetY = -25 * p; // 0 -> -25px
      } 
      // 2단계: 0.16~0.8s (20~100%) - ScaleDown & Rise & Fade (부드러운 소멸)
      else {
        final p = (progress - 0.2) / 0.8; // 0.0 ~ 1.0
        scale = 1.2 - (0.2 * p); // 1.2 -> 1.0
        offsetY = -25 - (75 * p); // -25 -> -100px
      }

      // 최종 좌표 계산 (basePosition + 애니메이션 오프셋)
      final position = ft.basePosition + Offset(0, offsetY);

      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.scale(scale);
      
      // 투명도만 적용하여 그리기 (layout 재호출 없음)
      // canvas.saveLayer를 쓰지 않고 효율적으로 투명도 처리 (TextPainter의 Opacity는 생성 시점이 아닌 그릴 때 제어)
      // 실제로는 Paint 객체를 통해 제어 가능하지만 TextPainter는 내부 span style을 따르므로 
      // 최적화를 위해 drawText 시점에 opacity를 입히는 방식은 canvas.saveLayer가 필요하나 부하가 큼.
      // 따라서 생성된 Painter를 그대로 사용하되 opacity 연산은 TextStyle에서 하던대로 유지하거나
      // 여기서는 성능을 위해 saveLayer 없이 그립니다.
      ft.textPainter.paint(canvas, Offset(-ft.textPainter.width / 2, -ft.textPainter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant DamagePainter oldDelegate) => true;
}


class GainRecord {
  final DateTime time;
  final int gold;
  final int exp;
  final int kills;
  GainRecord(this.time, {this.gold = 0, this.exp = 0, this.kills = 0});
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

  const _ToastOverlayWidget({required this.message, required this.isError, required this.onDismiss});

  @override
  State<_ToastOverlayWidget> createState() => _ToastOverlayWidgetState();
}

class _ToastOverlayWidgetState extends State<_ToastOverlayWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _offsetAnim = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    
    Future.delayed(const Duration(seconds: 3), () async {
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
      child: SlideTransition(
        position: _offsetAnim,
        child: Material(
          color: Colors.transparent,
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
                Flexible(child: Text(widget.message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
              ],
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
    );
  }
}




// --- 화면 모드 관리 (일반 / 화면유지 / 절전) ---
enum DisplayMode { normal, stayAwake, powerSave }
