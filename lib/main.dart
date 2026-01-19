import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'models/player.dart';
import 'models/monster.dart';
import 'models/item.dart';
import 'models/skill.dart';
import 'models/pet.dart';
import 'models/achievement.dart';
import 'models/hunting_zone.dart';
import 'services/update_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'services/auth_service.dart';
import 'services/cloud_save_service.dart';

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
    return MaterialApp(
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
  // 🆕 Supabase 서비스
  final AuthService _authService = AuthService();
  final CloudSaveService _cloudSaveService = CloudSaveService();
  bool _isCloudSynced = false; // 클라우드 동기화 상태
  DateTime? _lastCloudSaveTime; // 🆕 마지막 클라우드 저장 시간 기록
  
  late Player player;
  Monster? currentMonster;
  DateTime? monsterSpawnTime; // 처치 속도 측정을 위해 추가
  List<CombatLogEntry> combatLogs = [];
  List<CombatLogEntry> damageLogs = [];
  List<CombatLogEntry> itemLogs = [];
  List<CombatLogEntry> eventLogs = [];
  Timer? battleTimer;
  Timer? _monsterAttackTimer; // 몬스터 독립 공격 타이머 추가
  Timer? _regenTimer; // 체력 재생 전용 타이머 추가
  int _selectedIndex = 0; // 0~9
  int _achievementMenuTab = 0; // 0: 업적, 1: 도감
  int playerCurrentHp = 100;
  int _currentLogTab = 0;

  // 가방 필터 및 정렬용
  ItemType? _inventoryFilter;
  int _inventorySortMode = 0; // 0: 등급순, 1: 강화순
  bool _isInventoryScrolling = false; // 스크롤 중 애니메이션 정지용
  Timer? _scrollStopTimer;

  late AnimationController _playerAnimController;
  late AnimationController _monsterAnimController;
  late AnimationController _uiTickerController; // 60FPS UI 갱신용
  late AnimationController _shimmerController; // 프리미엄 아이템 광택용
  late AnimationController _heroPulseController; // 캐릭터 숨쉬기/후광용
  late AnimationController _heroRotateController; // 헤일로 회전용
  late AnimationController _monsterSpawnController; // 몬스터 등장 연출
  late AnimationController _monsterDeathController; // 몬스터 사망 연출
  final DamageManager damageManager = DamageManager(); // 🆕 데미지 매니저
  static const int _maxDamageTexts = 10; // 🆕 최대 동시 표시 개수 제한 (10개)

  // 효율 측정용 데이터
  final List<GainRecord> _recentGains = [];
  double _goldPerMin = 0;
  double _expPerMin = 0;
  double _killsPerMin = 0;
  int _sessionGold = 0;
  int _sessionExp = 0;
  int _sessionMaxDamage = 0; // 🆕 1회 최대 데미지 기록용
  Timer? _efficiencyTimer;


  // 스테이지 진행 관련
  int _stageKills = 0;
  final int _targetKills = 10;
  int _currentStage = 1;
  bool _autoAdvance = true; // 스테이지 자동 등반 여부
  bool _isProcessingVictory = false; // 승리 처리 중복 방지 플래그 추가
  // 사냥터 관리
  HuntingZone _currentZone = HuntingZoneData.list[0];
  Map<ZoneId, int> _zoneStages = { for (var z in HuntingZoneData.list) z.id : 1 };

  // 전리품 파티클 시스템
  final List<LootParticle> _lootParticles = [];
  final GlobalKey _battleSceneKey = GlobalKey(); // 🆕 배틀 장면 좌표 기준키
  final GlobalKey _monsterKey = GlobalKey();
  final GlobalKey _goldTargetKey = GlobalKey();
  final GlobalKey _expTargetKey = GlobalKey();
  
  // 관리자 모드
  bool _isAdminAuthenticated = false;
  double _monsterDefenseMultiplier = 1.0; // 몬스터 방어력 배율 (0.0 ~ 1.0)

  // 화면 모드 관리
  DisplayMode _displayMode = DisplayMode.normal;
  
  // 세션 통합 통계 (절전 모드용)
  int _sessionItems = 0;
  int _sessionStones = 0;
  int _sessionPowder = 0;
  int _sessionReroll = 0;
  int _sessionCube = 0;
  int _sessionProtection = 0;

  // 스테이지 가속(점프) 시스템 관련
  DateTime? _lastMonsterSpawnTime;
  
  // 알림 중첩 방지용
  OverlayEntry? _activeNotification;
  bool _showJumpEffect = false;
  int _jumpEffectId = 0; // 애니메이션 재시작을 위한 ID
  Timer? _jumpEffectTimer;
  int monsterCurrentHp = 0;

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
  int _autoDismantleLevel = 0; // 0: 사용안함, 1: 일반, 2: 고급이하, 3: 희귀이하, 4: 전체

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔄 LIFECYCLE & DATA MANAGEMENT - 생명주기 및 데이터 관리
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    player = Player();
    playerCurrentHp = player.maxHp;
    _playerAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 70));
    _monsterAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 70));
    _uiTickerController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _shimmerController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _heroPulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _heroRotateController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    
    // 이벤트 기반 전투를 위한 신규 컨트롤러 (지연시간 제거용)
    _monsterSpawnController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _monsterDeathController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _uiTickerController.addListener(() {
      _updateParticles(); // 매 프레임 파티클 리스트 정기 청소
      damageManager.update(); // 🆕 데미지 텍스트 상태 업데이트 (+800ms 만료 처리)
    });
    
    // 🆕 게임 초기화 실행 (Supabase 로그인 + 데이터 로드)
    _initializeGame();

    // 1초마다 효율 갱신
    _efficiencyTimer = Timer.periodic(const Duration(seconds: 10), (t) => _updateEfficiency());
    
    // 1초마다 체력 재생 적용 (공어속과 분리)
    _regenTimer = Timer.periodic(const Duration(seconds: 1), (t) => _applyRegen());
    
    // 오프라인 보상 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOfflineRewards();
      // 자동 업데이트 체크
      UpdateService.checkUpdate(context);
    });
  }

  // 🆕 게임 초기화 로직
  Future<void> _initializeGame() async {
    try {
      // 1. Supabase 익명 로그인 시도
      if (!_authService.isLoggedIn) {
        await _authService.signInAnonymously();
      }
      
      // 2. 데이터 로드 (로컬 + 클라우드 비교)
      await _loadGameData();
      
      // 3. 전투 시작
      if (mounted) {
        _spawnMonster();
        _startBattleLoop();
      }
    } catch (e) {
      debugPrint('초기화 중 오류 발생: $e');
      // 오류 발생 시에도 기본 데이터로 시작
      await _loadGameData();
      if (mounted) {
        _spawnMonster();
        _startBattleLoop();
      }
    }
  }

  Future<void> _saveGameData({bool forceCloud = false}) async {
    final nowTime = DateTime.now();
    final nowStr = nowTime.toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    
    final saveData = {
      'player': player.toJson(),
      'current_stage': _currentStage,
      'current_zone_id': _currentZone.id.name,
      'last_save_time': nowStr,
      'zone_stages': _zoneStages.map((k, v) => MapEntry(k.name, v)),
      'auto_advance': _autoAdvance,
      // 🆕 오프라인 보상 정확도를 위한 전투 효율 데이터 추가
      'gold_per_min': _goldPerMin,
      'exp_per_min': _expPerMin,
      'kills_per_min': _killsPerMin,
      // [v0.0.61] 자동 분해 설정
      'auto_dismantle_level': _autoDismantleLevel,
    };

    // 1. 로컬 저장 (항상 즉시 수행)
    await prefs.setString('player_save_data', jsonEncode(saveData['player']));
    await prefs.setInt('current_stage', _currentStage);
    await prefs.setString('current_zone_id', _currentZone.id.name);
    await prefs.setString('lastSaveTime', nowStr);
    
    // 로컬 효율 데이터 별도 저장
    await prefs.setDouble('gold_per_min', _goldPerMin);
    await prefs.setDouble('exp_per_min', _expPerMin);
    await prefs.setDouble('kills_per_min', _killsPerMin);
    await prefs.setInt('auto_dismantle_level', _autoDismantleLevel);
    
    // 2. 클라우드 저장 (최소 30초 간격 또는 강제 실행 시)
    if (_authService.isLoggedIn) {
      final bool shouldSaveToCloud = forceCloud || 
          _lastCloudSaveTime == null || 
          nowTime.difference(_lastCloudSaveTime!).inSeconds >= 30;

      if (shouldSaveToCloud) {
        _lastCloudSaveTime = nowTime;
        _cloudSaveService.saveToCloud(saveData).then((success) {
          if (mounted) {
            setState(() {
              _isCloudSynced = success;
            });
          }
        });
      }
    }
  }

  Future<void> _loadGameData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 로컬 데이터 로드 시도
    String? localData = prefs.getString('player_save_data');
    String? localTime = prefs.getString('lastSaveTime');
    
    Map<String, dynamic>? cloudDataMap;
    String? cloudTime;

    // 2. 클라우드 데이터 로드 시도
    if (_authService.isLoggedIn) {
      final cloudSave = await _cloudSaveService.loadFromCloud();
      if (cloudSave != null) {
        cloudDataMap = cloudSave['data'] as Map<String, dynamic>;
        cloudTime = cloudSave['timestamp'] as String;
      }
    }

    // 3. 비교 후 최신 데이터 결정
    Map<String, dynamic>? targetData;
    bool isFromCloud = false;

    if (cloudDataMap != null && _isCloudNewer(cloudTime, localTime)) {
      // 클라우드가 더 최신이거나 로컬이 없음
      targetData = cloudDataMap;
      isFromCloud = true;
    } else if (localData != null) {
      // 로컬이 더 최신이거나 클라우드가 없음 (현재 로컬 데이터만 로드)
      // 단, 로컬은 기존 구조(JSON string) 그대로 로드
      try {
        setState(() {
          player = Player.fromJson(jsonDecode(localData));
          playerCurrentHp = player.maxHp;
          _currentStage = prefs.getInt('current_stage') ?? 1;
          String? zoneName = prefs.getString('current_zone_id');
          if (zoneName != null) {
            _currentZone = HuntingZoneData.list.firstWhere((z) => z.id.name == zoneName);
          }
          // 로컬 효율 데이터 복구
          _goldPerMin = prefs.getDouble('gold_per_min') ?? 0;
          _expPerMin = prefs.getDouble('exp_per_min') ?? 0;
          _killsPerMin = prefs.getDouble('kills_per_min') ?? 0;
        });
        _isCloudSynced = !isFromCloud && cloudDataMap != null; // 로컬이 최신인데 클라우드도 있으면 아직 동기화 전
        return; 
      } catch (e) {
        debugPrint('로컬 데이터 파싱 실패: $e');
      }
    }

    // 4. 결정된 타겟 데이터 적용 (클라우드 기반 로드)
    if (targetData != null) {
      try {
        setState(() {
          player = Player.fromJson(targetData!['player']);
          playerCurrentHp = player.maxHp;
          _currentStage = targetData['current_stage'] ?? 1;
          String? zoneName = targetData['current_zone_id'];
          if (zoneName != null) {
            _currentZone = HuntingZoneData.list.firstWhere((z) => z.id.name == zoneName);
          }
          
          // 추가 정보 복구 (있는 경우에만)
          if (targetData.containsKey('auto_advance')) {
            _autoAdvance = targetData['auto_advance'];
          }
          if (targetData.containsKey('zone_stages')) {
            var zs = Map<String, dynamic>.from(targetData['zone_stages']);
            zs.forEach((k, v) {
              try {
                final zid = ZoneId.values.byName(k);
                _zoneStages[zid] = v as int;
              } catch (_) {}
            });
          }

          // 클라우드 효율 데이터 복구
          _goldPerMin = (targetData['gold_per_min'] ?? 0).toDouble();
          _expPerMin = (targetData['exp_per_min'] ?? 0).toDouble();
          _killsPerMin = (targetData['kills_per_min'] ?? 0).toDouble();
          _autoDismantleLevel = targetData['auto_dismantle_level'] ?? 0;
          
          _isCloudSynced = true;
        });
        if (isFromCloud) _addLog('클라우드에서 데이터를 불러왔습니다.', LogType.event);
      } catch (e) {
        debugPrint('타겟 데이터 적용 실패: $e');
      }
    } else {
      // [신규 플레이어 지원] 데이터가 전혀 없는 경우
      _initializeStarterData();
    }
  }

  void _initializeStarterData() {
    setState(() {
      Item starterWeapon = Item(
        id: 'starter_${DateTime.now().millisecondsSinceEpoch}',
        name: '모험가의 목검',
        type: ItemType.weapon,
        grade: ItemGrade.common,
        tier: 1,
        mainStat1: 12, // T1 목검 공격력 12 (v0.0.58 개편)
        subOptions: [],
        enhanceLevel: 0,
        durability: 100,
        maxDurability: 100,
        isNew: false,
      );
      player.equipItem(starterWeapon);
      playerCurrentHp = player.maxHp;
      _addLog('환영합니다! 모험을 시작하기 위해 [모험가의 목검]을 지급했습니다.', LogType.event);
    });
  }

  bool _isCloudNewer(String? cloudTime, String? localTime) {
    if (cloudTime == null) return false;
    if (localTime == null) return true;
    try {
      final cloud = DateTime.parse(cloudTime);
      final local = DateTime.parse(localTime);
      return cloud.isAfter(local);
    } catch (_) {
      return true;
    }
  }

  Future<void> _checkOfflineRewards() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSaveStr = prefs.getString('lastSaveTime');
    
    if (lastSaveStr != null) {
      final lastTime = DateTime.parse(lastSaveStr);
      // 현재 효율(분당 골드 등) 정보가 없을 경우 대비 기본값 설정 (추후 정교화 가능)
      // 초보자 배려: 최소 효율 보장
      // 🆕 효율 데이터 신뢰도 향상: 로드된 기록이 없을 경우 '레벨 비례' 최소 보장
      double levelFactor = player.level.toDouble();
      double gMin = _goldPerMin > 0 ? _goldPerMin : (50.0 + levelFactor * 10); // 기본 골드 보정
      double eMin = _expPerMin > 0 ? _expPerMin : (30.0 + levelFactor * 5);   // 기본 경험치 보정
      double kMin = _killsPerMin > 0 ? _killsPerMin : 5.0;

      final rewards = player.calculateOfflineRewards(lastTime, gMin, eMin, kMin);
      if (rewards.isNotEmpty && (rewards['minutes'] as int) >= 1) {
        _showOfflineRewardDialog(rewards);
      }
    }
  }

  Future<void> _updateLastSaveTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastSaveTime', DateTime.now().toIso8601String());
  }

  @override
  void dispose() {
    battleTimer?.cancel();
    _efficiencyTimer?.cancel();
    _scrollStopTimer?.cancel();
    _jumpEffectTimer?.cancel();
    _monsterAttackTimer?.cancel(); // 몬스터 타이머 해제
    _regenTimer?.cancel(); // 재생 타이머 해제
    _playerAnimController.dispose();
    _monsterAnimController.dispose();
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

  void _updateEfficiency() {
    if (!mounted) return;
    final now = DateTime.now();
    _recentGains.removeWhere((g) => now.difference(g.time).inSeconds > 60);
    
    int totalG = 0;
    int totalE = 0;
    int totalK = 0;
    for (var g in _recentGains) {
      totalG += g.gold;
      totalE += g.exp;
      totalK += g.kills;
    }
    
    setState(() {
      _goldPerMin = totalG.toDouble();
      _expPerMin = totalE.toDouble();
      _killsPerMin = totalK.toDouble();
    });
  }

  void _spawnMonster() {
    if (!mounted) return;
    setState(() {
      // [v0.0.56] 10마리 중 마지막인 경우 보스 출현을 위해 isFinal: true 기입
      bool isFinal = (_stageKills >= _targetKills - 1);
      currentMonster = Monster.generate(_currentZone, _currentStage, isFinal: isFinal);
      monsterCurrentHp = currentMonster!.hp; // HP 동기화
      _lastMonsterSpawnTime = DateTime.now(); // 스폰 시간 기록
      _isProcessingVictory = false; // 새로운 몬스터 스폰 시 플래그 초기화
      // 몬스터 스폰 로그 제거 (UI에서 확인 가능하므로 로그창에서는 제외)

    });
    
    _monsterSpawnController.forward(from: 0).whenComplete(() {
      if (mounted) {
        _startBattleLoop();
        _startMonsterAttackLoop(); // 몬스터 공격 루프 시작
      }
    });
  }

  void _startMonsterAttackLoop() {
    _monsterAttackTimer?.cancel();
    if (currentMonster == null || _isProcessingVictory) return;

    // 몬스터는 주인공의 속도와 무관하게 2.0초마다 정직하게 공격 (성장 체감 강화)
    _monsterAttackTimer = Timer.periodic(const Duration(milliseconds: 2000), (timer) {
      if (!mounted || currentMonster == null || _isProcessingVictory) {
        timer.cancel();
        return;
      }
      _monsterPerformAttack();
    });
  }

  void _monsterPerformAttack() {
    if (!mounted || currentMonster == null || _isProcessingVictory) return;
    setState(() {
      // 1. 실제 데미지 계산 (Soft Cap 공식)
      double mVariance = 0.9 + (Random().nextDouble() * 0.2);
      double pDefenseRating = 100 / (100 + player.defense);
      double rawMDmg = (currentMonster!.attack * pDefenseRating) * mVariance;
      double minMDmg = (currentMonster!.attack * 0.1) * mVariance;
      int mDmg = max(rawMDmg, minMDmg).toInt().clamp(1, 999999999);

      // 2. 애니메이션 및 화면 표시 (계산된 mDmg 사용)
      if (_selectedIndex == 0) {
        _monsterAnimController.forward().then((_) => _monsterAnimController.reverse());
        _addFloatingText('-$mDmg', false);
      }
      
      // 3. 실제 체력 차감
      playerCurrentHp -= mDmg;
      if (playerCurrentHp <= 0) _handlePlayerDeath();
    });
  }

  void _startBattleLoop() {
  battleTimer?.cancel();
  
  // 첫 공격 즉시 시도 (이벤트 기반으로 스폰 직후 도달)
  if (!mounted || currentMonster == null || _isProcessingVictory) return;
  _processCombatTurn();
  
  // 이후 공속 주기에 맞춰 실행 (1 / 공격속도 공식 적용)
  battleTimer = Timer.periodic(Duration(milliseconds: (1000 / player.attackSpeed).toInt()), (timer) {
    if (!mounted || currentMonster == null || _isProcessingVictory) {
      timer.cancel();
      return;
    }
    _processCombatTurn();
  });
}

  void _processCombatTurn() {
    if (currentMonster == null) return;
    setState(() {
      // DOC_GAME_DESIGN.md 3.1 데미지 및 방어력 공식 적용
      // 1. 방어 상산 방식 (Soft Cap): 데미지 배율 = 100 / (100 + 실질 방어력)
      // 2. 실질 방어력: (몬스터 방어력 * 관리자 배율) * (1 - 방어 관통 %) -> 현재 방관 0으로 가정
      double effectiveDefense = currentMonster!.defense * _monsterDefenseMultiplier;
      double defenseRating = 100 / (100 + effectiveDefense);
      
      // 3. 최종 데미지: 공격력 * 데미지 배율 (±10% 분산 적용)
      double variance = 0.9 + (Random().nextDouble() * 0.2); // 0.9 ~ 1.1 분산
      double rawDamage = (player.attack * defenseRating) * variance * player.potentialFinalDamageMult;
      double minDamage = (player.attack * 0.1) * variance * player.potentialFinalDamageMult;
      int baseDmg = max(rawDamage, minDamage).toInt().clamp(1, 999999999);

      // 치명타 여부 계산
      bool isCrit = Random().nextDouble() * 100 < player.critChance;
      int pDmg = isCrit ? (baseDmg * player.critDamage / 100).toInt() : baseDmg;

      // 최대 데미지 갱신
      if (pDmg > _sessionMaxDamage) _sessionMaxDamage = pDmg;


      // 전투 탭(0번)일 때만 애니메이션 연출 실행
      if (_selectedIndex == 0) {
        _playerAnimController.forward().then((_) => _playerAnimController.reverse());
        _addFloatingText(isCrit ? 'CRITICAL $pDmg' : '-$pDmg', true, isCrit: isCrit);
      }
      
      currentMonster!.hp -= pDmg;
    monsterCurrentHp = currentMonster!.hp; // UI용 변수 동기화
      // 치명타 로그 제거 (플로팅 텍스트로 대체)

      
      // 자동 스킬 사용 체크 (준비된 스킬 중 첫 번째 사용)
      final readySkill = player.skills.where((s) => s.type == SkillType.active && s.isUnlocked && s.isReady(player.cdr)).firstOrNull;
      if (readySkill != null) {
        _useSkill(readySkill);
      }
      
      // 스킬 사용 후 몬스터가 이미 죽었을 수 있으므로 null 체크 추가
      if (currentMonster == null) return;
      
      if (currentMonster!.isDead) {
        if (_isProcessingVictory) return;
        _isProcessingVictory = true; 
        
        battleTimer?.cancel();
        _monsterAttackTimer?.cancel();

        final killDuration = _lastMonsterSpawnTime != null 
            ? DateTime.now().difference(_lastMonsterSpawnTime!) 
            : null;

        _handleVictory(killDuration);
        
        _monsterDeathController.forward(from: 0).whenComplete(() {
          if (mounted) {
            _monsterDeathController.reset();
            // 무한의탑은 사용자가 선택할 때까지 리젠하지 않음
            if (_currentZone.id != ZoneId.tower) {
              _spawnMonster();
            }
          }
        });
        return;
      }
      
      // 실제 흡혈(Lifesteal) 적용 (공격 시에만 발동)
      if (player.lifesteal > 0 && playerCurrentHp < player.maxHp) {
        int lifestealAmt = (pDmg * player.lifesteal / 100).toInt();
        if (lifestealAmt > 0) {
          playerCurrentHp = (playerCurrentHp + lifestealAmt).clamp(0, player.maxHp);
          if (_selectedIndex == 0) {
            _addFloatingText('+$lifestealAmt', false, isHeal: true, offsetX: -20); // 위치 약간 조정
          }
        }
      }
    });
  }

  // 매 1초마다 정직하게 실행되는 체력 재생 로직
  void _applyRegen() {
    if (!mounted || playerCurrentHp <= 0 || playerCurrentHp >= player.maxHp) return;
    
    setState(() {
      double regenAmount = player.maxHp * (player.hpRegen / 100);
      int finalRegen = regenAmount.toInt();
      
      if (finalRegen > 0) {
        playerCurrentHp = (playerCurrentHp + finalRegen).clamp(0, player.maxHp);
        if (_selectedIndex == 0) {
          _addFloatingText('+$finalRegen', false, isHeal: true, offsetX: 20); // 흡혈과 겹치지 않게 우측으로
        }
      }
    });
  }

  // 장비 도감 진행도 체크 및 갱신
  void _checkEncyclopedia(Item item) {
    String key = 'T${item.tier}_${item.type.name}';
    int currentMax = player.encyclopediaProgress[key] ?? -1;
    
    if (item.enhanceLevel > currentMax) {
      setState(() {
        player.encyclopediaProgress[key] = item.enhanceLevel;
        // 첫 획득(+0)이나 신규 최고 기록 달성 시 로그
        if (currentMax == -1) {
          _addLog('도감 등록! [${item.tier} ${item.name}]', LogType.event);
        }
      });
    }
  }

  // 도감 보상 수령 로직
  void _claimEncyclopediaReward(String key, int level) {
    if (player.encyclopediaClaims[key]?.contains(level) ?? false) return;
    
    int currentProgress = player.encyclopediaProgress[key] ?? -1;
    if (level > currentProgress) {
      _showToast('아직 달성하지 못한 강화 단계입니다.');
      return;
    }

    // 증가될 스탯 미리 계산 (유저 피드백용)
    String tierStr = key.split('_')[0].replaceAll('T', '');
    int tier = int.tryParse(tierStr) ?? 1;
    String rewardDetail = "";
    
    if (tier <= 4) {
      int atkInc = pow(2, tier - 1).toInt();
      int hpInc = atkInc * 10;
      rewardDetail = "공격력 +$atkInc, 체력 +$hpInc 영구 증가!";
    } else {
      double step = (tier == 5) ? 0.01 : 0.05;
      rewardDetail = "공격력 +${step.toStringAsFixed(2)}%, 체력 +${step.toStringAsFixed(2)}% 영구 증가!";
    }

    setState(() {
      if (player.encyclopediaClaims[key] == null) {
        player.encyclopediaClaims[key] = [];
      }
      player.encyclopediaClaims[key]!.add(level);
      
      // 보상 연출 (프리미엄 팝업으로 변경)
      _showSuccess('도감 보상 수령 완료', rewardDetail);
      _saveGameData();
    });
  }

  void _handleVictory(Duration? killDuration) {
    // 1. 즉시 처리해야 하는 UI 정보 업데이트 (골드/경험치 수치만)
    int finalGold = (currentMonster!.goldReward * player.goldBonus / 100).toInt();
    int expReward = currentMonster!.expReward;
    
    player.gainExp(expReward);
    player.gold += finalGold;
    _sessionGold += finalGold;
    _sessionExp += expReward;
    player.totalKills++;
    player.totalGoldEarned += finalGold;

    // 2. 몬스터 위치 계산 및 파티클 생성 (시점 중요)
    RenderBox? box = _monsterKey.currentContext?.findRenderObject() as RenderBox?;
    Offset spawnPos = const Offset(200, 300);
    if (box != null) {
      spawnPos = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
      spawnPos = Offset(spawnPos.dx, spawnPos.dy - 150); 
    }
    _spawnLootParticles(finalGold, expReward, spawnPos);


    // 3. 스테이지 업데이트 (즉시 반영 필요)
    setState(() {
      bool isTower = _currentZone.id == ZoneId.tower;
      bool jumped = false;
      
      // [v0.0.54] 무한의탑은 여기서 스테이지를 올리지 않음 (결과 팝업에서 처리)
      if (!isTower) {
        if (killDuration != null && killDuration.inMilliseconds < 1500) {
          _currentStage += 1;
          _stageKills = 0;
          _zoneStages[_currentZone.id] = _currentStage;
          jumped = true;
          _showJumpEffect = true;
          _jumpEffectId++;
          _jumpEffectTimer?.cancel();
          _jumpEffectTimer = Timer(const Duration(milliseconds: 2000), () {
            if (mounted) setState(() => _showJumpEffect = false);
          });
        }

        if (!jumped) {
          _stageKills++;
          if (_stageKills >= _targetKills) {
            if (_autoAdvance) {
              _stageKills = 0;
              _currentStage += 1;
              _zoneStages[_currentZone.id] = _currentStage;
            } else {
              _stageKills = _targetKills - 1; 
            }
          }
        }
      }
    });

    // 4. 무거운 로직 분산 처리 (200ms 지연)
    // 몬스터 사망 애니메이션이 한창 진행 중일 때 CPU 부하를 피함
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      
      // 드롭 로직
      double finalDropChance = currentMonster!.itemDropChance * (player.dropBonus / 100);
      if (Random().nextDouble() < finalDropChance) {
        Item newItem = Item.generate(player.level);
        
        // [v0.0.61] 자동 분해 체크
        if (_shouldAutoDismantleItem(newItem)) {
          // 즉시 분해하여 파편으로 전환
          Map<String, int> rewards = _calculateDismantleRewards(newItem);
          player.gold += rewards['gold']!;
          player.powder += rewards['powder']!;
          player.enhancementStone += rewards['stone']!;
          player.rerollStone += rewards['reroll']!;
          player.protectionStone += rewards['protection']!;
          player.cube += rewards['cube']!;
          
          int tier = rewards['tier']!;
          int shards = rewards['shards']!;
          player.tierShards[tier] = (player.tierShards[tier] ?? 0) + shards;
          
          _addLog('[자동분해] ${newItem.name} → 파편 +$shards', LogType.item);
        } else {
          // 일반적으로 인벤토리에 추가
          if (player.addItem(newItem)) {
            _addLog('[획득] ${newItem.name} (${newItem.grade.name})', LogType.item);
            player.totalItemsFound++;
            _sessionItems++;
            _checkEncyclopedia(newItem);
          }
        }
      }

      // 로그 및 기타 로직
      // 전역 승리 로그 제거 (성능 및 가독성 최적화)

      
      _recentGains.add(GainRecord(DateTime.now(), gold: finalGold, exp: expReward, kills: 1));
      _dropMaterials(currentMonster!.level);

      // [v0.0.52] 무한의탑 승리 팝업: 모든 보상 처리 후 노출하여 보상 누락 방지
      if (_currentZone.id == ZoneId.tower) {
        battleTimer?.cancel(); // 확실하게 전투 루프 중단
        _monsterAttackTimer?.cancel();
        // [v0.0.53] 프레임 외부에서 안전하게 팝업 호출
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTowerResultDialog(true);
        });
      }
      
      _updateLastSaveTime(); // 저장 로직은 가장 마지막에
    });
  }

  void _dropMaterials(int monsterLevel) {
    final rand = Random();
    
    // 1. 강화석 드롭 (60% 확률)
    if (rand.nextDouble() < 0.6) {
      int amount = (monsterLevel / 2).ceil() + rand.nextInt(3);
      player.enhancementStone += amount;
      _sessionStones += amount; // 세션 강화석 증가
      _addLog('[공명] 강화석 $amount개 획득!', LogType.item);
    }
    
    // 2. 가루 드롭 (40% 확률)
    if (rand.nextDouble() < 0.4) {
      int amount = (monsterLevel * 2) + rand.nextInt(10);
      player.powder += amount;
      _sessionPowder += amount; // 세션 가루 증가
      _addLog('[추출] 신비로운 가루 $amount개 획득!', LogType.item);
    }
    
    // 3. 재설정석 드롭 (10% 확률 - 희귀)
    if (rand.nextDouble() < 0.1) {
      int amount = 1;
      player.rerollStone += amount;
      _sessionReroll += amount; // 세션 재설정석 증가
      _addLog('[희귀] 옵션 재설정석 $amount개 획득!', LogType.item);
    }
    
    // 4. 보호석/큐브 (매우 낮은 확률)
    if (rand.nextDouble() < 0.02) {
      int amount = 1;
      player.protectionStone += amount;
      _sessionProtection += amount; // 세션 보호석 증가
      _addLog('[전설] 강화 보호석 $amount개 획득!', LogType.item);
    }

    // 5. 강화 큐브 드롭 (0.1% 확률)
    if (rand.nextDouble() < 0.001) {
      int amount = 1;
      player.cube += amount;
      _sessionCube += amount; // 세션 큐브 증가
      _addLog('[신화] 강화 큐브 $amount개 획득!', LogType.item);
    }

    // --- [신규 v0.0.60] 스펙 기반 게이트 드랍 (심연의 구슬) ---
    double avgLv = player.averageEnhanceLevel;
    
    // T2 코어: 평균 13강 이상 시 3% 확률로 드랍
    if (avgLv >= 13.0 && rand.nextDouble() < 0.03) {
      player.tierCores[2] = (player.tierCores[2] ?? 0) + 1;
      _addLog('[게이트] 심연의 구슬 [T2] 획득!', LogType.event);
    }
    // T3 코어: 평균 15강 이상 시 1% 확률로 드랍
    if (avgLv >= 15.0 && rand.nextDouble() < 0.01) {
      player.tierCores[3] = (player.tierCores[3] ?? 0) + 1;
      _addLog('[게이트] 심연의 구슬 [T3] 획득!', LogType.event);
    }
  }

  void _handlePlayerDeath() {
    if (_currentZone.id == ZoneId.tower) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTowerResultDialog(false);
      });
      return;
    }
    _addLog('사망... 마을에서 부활 중 (스테이지 하락!)', LogType.event);
    
    setState(() {
      // 5스테이지 하락 (최소 1스테이지)
      _currentStage = max(1, _currentStage - 5);
      _zoneStages[_currentZone.id] = _currentStage;
      _stageKills = 0; // 진행도 초기화
      
      playerCurrentHp = player.maxHp;
      currentMonster = null;
    });

    // 부활 대기 시간을 0.5초로 단축
    Timer(const Duration(milliseconds: 500), () { if (mounted) _spawnMonster(); });
  }

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
    setState(() {
      final entry = CombatLogEntry(msg, type, DateTime.now());
      
      // 전체 로그 저장 (최대 100개)
      combatLogs.insert(0, entry);
      if (combatLogs.length > 100) combatLogs.removeLast();
      
      // 타입별 개별 저장 (최대 100개)
      switch (type) {
        case LogType.damage:
          damageLogs.insert(0, entry);
          if (damageLogs.length > 100) damageLogs.removeLast();
          break;
        case LogType.item:
          itemLogs.insert(0, entry);
          if (itemLogs.length > 100) itemLogs.removeLast();
          break;
        case LogType.event:
          eventLogs.insert(0, entry);
          if (eventLogs.length > 100) eventLogs.removeLast();
          break;
      }
    });
  }

  // 🆕 데미지 텍스트 추가 API (통합 관리)
  void _addFloatingText(String text, bool isMonsterTarget, {
    bool isCrit = false, 
    bool isHeal = false, 
    bool isGold = false, 
    bool isExp = false, 
    double? offsetX, 
    double? offsetY
  }) {
    final rand = Random();
    
    // 타입 결정
    DamageType type = DamageType.normal;
    if (isCrit) type = DamageType.critical;
    else if (isHeal) type = DamageType.heal;
    else if (isGold) type = DamageType.gold;
    else if (isExp) type = DamageType.exp;

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
    
    // 수치 값 추출
    double val = double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

    damageManager.add(DamageEntry(
      text: text,
      value: val,
      isMonsterTarget: isMonsterTarget,
      createdAt: DateTime.now(),
      type: type,
      basePosition: basePos + Offset(ox, oy),
    ));

    // 최대 개수 초과 시 오래된 것 제거
    if (damageManager.texts.length > _maxDamageTexts) {
      damageManager.texts.removeAt(0);
    }
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
                        RepaintBoundary(child: _buildBodyContent()),
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
        shadowTextBuilder: _buildShadowText,
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
      case 3: return _buildInventoryTab(); // 가방 메뉴 연결
      case 4: return _buildCraftTab();
      case 5: return _buildSkillTab();
      case 6: return _buildPetTab();
      case 7: return _buildMenuPlaceholder('유물 (환생)');
      case 8: return _buildAchievementTab(); // Changed to achievement tab
      case 9: return _buildSystemTab(); // 실제 시스템/관리자 모드 연결
      default: return _buildCombatTab();
    }
  }

  Widget _buildMenuPlaceholder(String name) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildGlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: Column(
            children: [
              const Icon(Icons.construction, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 16),
              Text('$name 메뉴 준비 중', style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              _buildPopBtn('전투로 돌아가기', Colors.blueAccent, () => setState(() => _selectedIndex = 0), isFull: false, icon: Icons.sports_martial_arts),
            ],
          ),
        ),
      ],
    ));
  }

  // --- 프리미엄 전용 디자인 헬퍼 ---
  Widget _buildGlassContainer({
    required Widget child,
    double borderRadius = 20,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? color,
    double blur = 10,
    Border? border,
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? Colors.black.withOpacity(0.7), // 기본 0.7, 외부 주입 시 해당 색상 사용
              borderRadius: BorderRadius.circular(borderRadius),
              border: border ?? Border.all(color: Colors.white.withOpacity(0.15), width: 0.8), // 테두리 명확화
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.02), // 그라데이션 하단 광택 조절
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🗺️ HUNTING ZONE - 사냥터 시스템
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHuntingZoneTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 16),
            child: _buildShadowText('사냥터 이동', fontSize: 28, fontWeight: FontWeight.bold),
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
    bool isCurrent = _currentZone.id == zone.id;
    int stage = _zoneStages[zone.id] ?? 1;

    return _buildGlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: 24,
      color: isCurrent ? zone.color.withOpacity(0.2) : Colors.black,
      border: Border.all(color: isCurrent ? zone.color.withOpacity(0.5) : Colors.white10, width: isCurrent ? 1.5 : 0.5),
      child: InkWell(
        onTap: () {
          if (zone.id == ZoneId.tower) {
            _enterTower(zone);
          } else {
            setState(() {
              _currentZone = zone;
              _currentStage = stage;
              _stageKills = 0;
              _selectedIndex = 0; // 전투 탭으로 자동 이동
              _addLog('${zone.name} 지역으로 이동했습니다.', LogType.event);
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
                        _buildShadowText(zone.name, fontSize: 22, fontWeight: FontWeight.bold),
                        if (isCurrent) const SizedBox(width: 8),
                        if (isCurrent) Icon(Icons.location_on, color: zone.color, size: 18),
                        if (zone.type == ZoneType.special) 
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                            child: const Text('도전', style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(zone.description, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: zone.keyDrops.map((drop) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
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
                  _buildShadowText(zone.id == ZoneId.tower ? 'FLOOR' : 'STAGE', fontSize: 10, color: Colors.white38),
                  _buildShadowText('${Monster.getDisplayStage(stage)}', color: zone.color, fontWeight: FontWeight.bold, fontSize: 24),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                    child: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 👤 CHARACTER TAB - 캐릭터 정보 탭
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCharacterTab() {
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
  }

  Widget _buildHeroShowcase() {
    return _buildGlassContainer(
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
                  Text('MYTHIC WARRIOR', style: TextStyle(color: Colors.blueAccent.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  const SizedBox(height: 4),
                  _buildShadowText(player.name, fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white),
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
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.05), width: 1),
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
                              color: Colors.blueAccent.withOpacity(0.12 * (1 - _heroPulseController.value)),
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
                              color: Colors.cyanAccent.withOpacity(0.15),
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
                              color: Colors.black.withOpacity(0.3 + (0.1 * _heroPulseController.value)),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
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
    return _buildGlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      borderRadius: 18,
      color: Colors.white.withOpacity(0.04),
      border: Border.all(color: Colors.blueAccent.withOpacity(0.2), width: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('COMBAT READINESS', style: TextStyle(color: Colors.blueAccent.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 2),
              _buildShadowText('OVERPOWERING', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ],
          ),
          _buildShadowText('${player.combatPower}', fontSize: 32, fontWeight: FontWeight.w900, color: Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, IconData icon, Color color, List<Widget> children) {
    return _buildGlassContainer(
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
    return _buildGlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory, size: 18, color: Colors.orangeAccent), 
              const SizedBox(width: 10), 
              _buildShadowText('희귀 자원 현황', fontSize: 16, fontWeight: FontWeight.bold)
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
  // 🎒 INVENTORY SYSTEM - 인벤토리 시스템
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInventoryTab() {
    return Column(
      children: [
        // 상단 타이틀 제거 및 카운터 이동 (공간 확보)
        const SizedBox(height: 12),
        
        // 재료 바 (이미지 스타일의 콤팩트 한 줄 바)
        _buildResourceBar(),
        
        // 자동 분해 설정 패널
        _buildAutoDismantlePanel(),
        
        // 장착 슬롯
        _buildEquippedSlots(),
        
        // 필터 및 버튼
        _buildInventoryControls(),
        
        // 아이템 그리드
        Expanded(child: _buildInventoryGrid()),
        
        const SizedBox(height: 100), // 하단 독 공간
      ],
    );
  }

  Widget _buildResourceBar() {
    return _buildGlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: 20,
      color: Colors.white.withOpacity(0.04),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('보유 재화', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(
                '가방 ${player.inventory.length}/${player.maxInventory}',
                style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 1줄로 압축된 재화 정보
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCompactResource('✨', player.powder, Colors.greenAccent),
              _buildCompactResource('💎', player.enhancementStone, Colors.blueAccent),
              _buildCompactResource('🎲', player.rerollStone, Colors.purpleAccent),
              _buildCompactResource('🛡️', player.protectionStone, Colors.amberAccent),
              _buildCompactResource('🔮', player.cube, Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactResource(String emoji, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          _formatNumber(count),
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _buildAutoDismantlePanel() {
    return _buildGlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: 16,
      color: Colors.white.withOpacity(0.03),
      border: Border.all(color: _autoDismantleLevel > 0 ? Colors.blueAccent.withOpacity(0.3) : Colors.white10),
      child: Row(
        children: [
          Icon(
            Icons.auto_delete_outlined,
            size: 16,
            color: _autoDismantleLevel > 0 ? Colors.blueAccent : Colors.white38,
          ),
          const SizedBox(width: 8),
          const Text(
            '자동 분해',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButton<int>(
              value: _autoDismantleLevel,
              isDense: true,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF1a1d2e),
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              items: const [
                DropdownMenuItem(value: 0, child: Text('사용 안 함')),
                DropdownMenuItem(value: 1, child: Text('T1 일반')),
                DropdownMenuItem(value: 2, child: Text('T1 고급 이하')),
                DropdownMenuItem(value: 3, child: Text('T1 희귀 이하')),
                DropdownMenuItem(value: 4, child: Text('T1 전체')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _autoDismantleLevel = v);
                  _saveGameData();
                  String msg = v == 0 ? '자동 분해를 비활성화했습니다.' : 'T1 ${_getAutoDismantleName(v)} 자동 분해 활성화';
                  _showToast(msg);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getAutoDismantleName(int level) {
    switch (level) {
      case 1: return '일반';
      case 2: return '고급 이하';
      case 3: return '희귀 이하';
      case 4: return '전체';
      default: return '';
    }
  }

  Widget _buildResourceItem(String emoji, String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)),
                _AnimatedCountText(
                  count: count,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
    return _buildGlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      color: Colors.white.withOpacity(0.04),
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
        _PressableScale(
          onTap: isLocked ? null : () => setState(() => _expandedCraftCategory = isExp ? -1 : index),
          child: _buildGlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            margin: const EdgeInsets.only(bottom: 8),
            borderRadius: 20,
            border: Border.all(color: isExp ? Colors.blueAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
            color: isExp ? Colors.blueAccent.withOpacity(0.05) : Colors.white.withOpacity(0.03),
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
          
          return _PressableScale(
            onTap: isLocked ? null : () => setState(() => _selectedCraftTier = t),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSel ? Colors.blueAccent : (isLocked ? Colors.black26 : Colors.white.withOpacity(0.05)),
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

    return _buildGlassContainer(
      padding: const EdgeInsets.all(12),
      borderRadius: 20,
      color: Colors.white.withOpacity(0.03),
      child: Column(
        children: [
          Row(
            children: [
              _getEmptyIcon(type, size: 24),
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
      _saveGameData();
      _showCraftResult(newItem);
    });
  }

  void _showCraftResult(Item item) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildShadowText('연성 성공!', fontSize: 28, color: Colors.amberAccent, fontWeight: FontWeight.w900),
            const SizedBox(height: 30),
            _buildPremiumItemSlot(item, size: 100, onTap: () {}),
            const SizedBox(height: 20),
            _buildShadowText(item.name, fontSize: 18, color: item.grade.color, fontWeight: FontWeight.bold),
            const SizedBox(height: 40),
            _buildPopBtn('인벤토리 확인', Colors.blueAccent, () => Navigator.pop(context), isFull: false),
          ],
        ),
      ),
    );
  }

  Widget _buildEquippedSlots() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 아이콘 크기를 적절히 고정하고 간격을 좁힙니다.
          double slotSize = 52.0; 

          return Row(
            mainAxisAlignment: MainAxisAlignment.center, // 중앙으로 밀집
            children: ItemType.values.map((type) {
              final item = player.equipment[type];
              bool isEmpty = item == null;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2), // 좌우 2px씩, 총 4px 간격
                child: isEmpty 
                  ? SizedBox(
                      width: slotSize, 
                      height: slotSize,
                      child: _buildGlassContainer(
                        borderRadius: 12,
                        color: Colors.black26,
                        border: Border.all(color: Colors.white10),
                        child: Center(
                          child: Opacity(
                            opacity: 0.5,
                            child: _getEmptyIcon(type, size: slotSize * 0.5)
                          )
                        ),
                      ),
                    )
                  : _buildPremiumItemSlot(
                      item, 
                      size: slotSize,
                      onTap: () {
                        final equipList = ItemType.values.map((t) => player.equipment[t]).whereType<Item>().toList();
                        _showItemDetail(item, contextList: equipList);
                      },
                    ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  // 빈 슬롯용 흐릿한 실루엣 아이콘
  Widget _getEmptyIcon(ItemType t, {double size = 20}) {
    IconData icon;
    switch (t) {
      case ItemType.weapon: icon = Icons.skateboarding; break;
      case ItemType.helmet: icon = Icons.smart_toy; break;
      case ItemType.armor: icon = Icons.shield; break;
      case ItemType.boots: icon = Icons.not_started; break;
      case ItemType.ring: icon = Icons.adjust; break;
      case ItemType.necklace: icon = Icons.all_out; break;
    }
    return Icon(icon, color: Colors.white24, size: size);
  }

  // 스킬 전용 아이콘 빌더
  Widget _getSkillIcon(String id, {double size = 24}) {
    final skill = player.skills.firstWhere((s) => s.id == id);
    return Text(skill.iconEmoji, style: TextStyle(fontSize: size));
  }

  Widget _buildInventoryControls() {
    return _buildGlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      borderRadius: 24,
      child: Column(
        children: [
          // 필터 탭 (슬림 디자인)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterChip(null, '전체'),
                ...ItemType.values.map((t) => _buildFilterChip(t, t.nameKr)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 액션 버튼 (통합 레이아웃)
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  '등급순', 
                  _inventorySortMode == 0 ? Colors.blueAccent : Colors.white.withOpacity(0.05), 
                  () => setState(() => _inventorySortMode = 0),
                  icon: Icons.sort,
                  isSelected: _inventorySortMode == 0
                )
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(
                  '전투력순', 
                  _inventorySortMode == 1 ? Colors.amberAccent : Colors.white.withOpacity(0.05), 
                  () => setState(() => _inventorySortMode = 1),
                  icon: Icons.bolt,
                  isSelected: _inventorySortMode == 1
                )
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(
                  '강화순', 
                  _inventorySortMode == 2 ? Colors.blueAccent : Colors.white.withOpacity(0.05), 
                  () => setState(() => _inventorySortMode = 2),
                  icon: Icons.upgrade,
                  isSelected: _inventorySortMode == 2
                )
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: _buildActionBtn(
                  '일괄분해', 
                  Colors.redAccent.withOpacity(0.8), 
                  _showBulkDismantleDialog,
                  icon: Icons.auto_delete_outlined,
                )
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(ItemType? type, String label) {
    bool isSel = _inventoryFilter == type;
    return _PressableScale(
      onTap: () => setState(() => _inventoryFilter = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? Colors.blueAccent.withOpacity(0.2) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? Colors.blueAccent.withOpacity(0.5) : Colors.white.withOpacity(0.05),
            width: 1
          ),
          boxShadow: isSel ? [
            BoxShadow(color: Colors.blueAccent.withOpacity(0.1), blurRadius: 8, spreadRadius: 0)
          ] : [],
        ),
        child: Text(
          label, 
          style: TextStyle(
            color: isSel ? Colors.blueAccent : Colors.white38, 
            fontSize: 11, 
            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 0.5
          )
        ),
      ),
    );
  }

  Widget _buildActionBtn(String label, Color color, VoidCallback onTap, {bool isSelected = false, IconData? icon}) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: 34,
        width: 90, // _buildPopBtn과 동일하게 90으로 통일
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSelected ? color : color.withOpacity(0.1),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : Colors.white.withOpacity(0.05),
            width: 1
          ),
          gradient: isSelected ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.7)],
          ) : null,
          boxShadow: isSelected ? [
            BoxShadow(color: color.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))
          ] : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) Icon(icon, size: 12, color: isSelected ? Colors.white : color),
            if (icon != null) const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label, 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 11, 
                    color: isSelected ? Colors.white : color.withOpacity(0.8),
                    letterSpacing: 0.5
                  )
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryGrid() {
    List<Item> filtered = _inventoryFilter == null 
        ? List.from(player.inventory) 
        : player.inventory.where((i) => i.type == _inventoryFilter).toList();

    // 정렬 적용
    if (_inventorySortMode == 0) {
      // 등급순 (mythic -> common)
      filtered.sort((a, b) => b.grade.index.compareTo(a.grade.index));
    } else if (_inventorySortMode == 1) {
      // 전투력순
      filtered.sort((a, b) => b.combatPower.compareTo(a.combatPower));
    } else {
      // 강화순
      filtered.sort((a, b) => b.enhanceLevel.compareTo(a.enhanceLevel));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          if (!_isInventoryScrolling) setState(() => _isInventoryScrolling = true);
        } else if (notification is ScrollEndNotification) {
          _scrollStopTimer?.cancel();
          _scrollStopTimer = Timer(const Duration(milliseconds: 200), () {
            if (mounted) setState(() => _isInventoryScrolling = false);
          });
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7, // 5개에서 7개로 확장
          mainAxisSpacing: 8, 
          crossAxisSpacing: 8,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final item = filtered[i];
          return _buildPremiumItemSlot(
            item,
            isPaused: _isInventoryScrolling,
            onTap: () => _showItemDetail(item, contextList: filtered),
          );
        },
      ),
    );
  }

  // [v0.0.61] 자동 분해 판별 로직
  bool _shouldAutoDismantleItem(Item item) {
    if (_autoDismantleLevel == 0) return false; // 비활성화
    if (item.tier != 1) return false; // T1만 대상
    
    switch (_autoDismantleLevel) {
      case 1: // T1 일반만
        return item.grade == ItemGrade.common;
      case 2: // T1 고급 이하
        return item.grade.index <= ItemGrade.uncommon.index;
      case 3: // T1 희귀 이하
        return item.grade.index <= ItemGrade.rare.index;
      case 4: // T1 전체
        return true;
      default:
        return false;
    }
  }

  void _showBulkDismantleDialog() {
    ItemGrade selectedGrade = ItemGrade.uncommon; // 기본값

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1D2E),
          title: const Text('일괄 분해 설정', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('선택한 등급 이하의 모든 아이템을 분해합니다.', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: ItemGrade.values.map((grade) {
                    bool isSel = selectedGrade == grade;
                    // 부모 너비에서 마진을 뺀 3분할 너비 계산
                    return InkWell(
                      key: ValueKey('bulk_grade_${grade.index}'),
                      onTap: () => setDialogState(() => selectedGrade = grade),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 85, // 고정 너비로 3x2 대칭 유지
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSel ? grade.color.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? grade.color : Colors.white10,
                            width: isSel ? 2 : 1,
                          ),
                          boxShadow: isSel ? [
                            BoxShadow(color: grade.color.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)
                          ] : [],
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isSel) Icon(Icons.check, size: 14, color: grade.color),
                            if (isSel) const SizedBox(width: 4),
                            Text(
                              grade.name,
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.white38,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              Text('${selectedGrade.name} 등급 이하를 모두 분해하시겠습니까?', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                // UI 트리를 안정화하기 위해 먼저 팝업을 닫고 데이터를 처리
                Navigator.pop(context);
                _executeBulkDismantle(selectedGrade);
              },
              child: const Text('분해 실행', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, int> _calculateDismantleRewards(Item item) {
    final rand = Random();
    int gold = item.tier * (item.grade.index + 1) * 500;
    int powder = item.tier * (item.grade.index + 1) * 2;
    int stone = item.grade.index >= 1 ? item.grade.index : 0;
    int reroll = (item.grade.index >= 2 && rand.nextDouble() < 0.3) ? 1 : 0;
    int protection = (item.grade.index >= 3 && rand.nextDouble() < 0.2) ? 1 : 0;
    int cube = (item.grade.index >= 4 && rand.nextDouble() < 0.1) ? 1 : 0;

    // 티어 파편 (등급별 차등)
    int shards = 0;
    switch (item.grade) {
      case ItemGrade.common: shards = 1; break;
      case ItemGrade.uncommon: shards = 3; break;
      case ItemGrade.rare: shards = 10; break;
      case ItemGrade.epic: shards = 30; break;
      case ItemGrade.legendary: shards = 100; break;
      case ItemGrade.mythic: shards = 500; break;
    }

    return {
      'gold': gold,
      'powder': powder,
      'stone': stone,
      'reroll': reroll,
      'protection': protection,
      'cube': cube,
      'shards': shards,
      'tier': item.tier,
    };
  }

  void _executeBulkDismantle(ItemGrade maxGrade) {
    int dismantleCount = 0;
    int totalGold = 0;
    int totalPowder = 0;
    int totalStone = 0;
    int totalReroll = 0;
    int totalProtection = 0;
    int totalCube = 0;

    setState(() {
      player.inventory.removeWhere((item) {
        if (item.grade.index <= maxGrade.index && !item.isLocked) {
          dismantleCount++;
          var rewards = _calculateDismantleRewards(item);
          totalGold += rewards['gold']!;
          totalPowder += rewards['powder']!;
          totalStone += rewards['stone']!;
          totalReroll += rewards['reroll']!;
          totalProtection += rewards['protection']!;
          totalCube += rewards['cube']!;
          
          // 파편 추가
          int tier = rewards['tier']!;
          int shards = rewards['shards']!;
          player.tierShards[tier] = (player.tierShards[tier] ?? 0) + shards;
          
          return true;
        }
        return false;
      });
      
      player.gold += totalGold;
      player.powder += totalPowder;
      player.enhancementStone += totalStone;
      player.rerollStone += totalReroll;
      player.protectionStone += totalProtection;
      player.cube += totalCube;
    });

    if (dismantleCount > 0) {
      _showDismantleResultDialog(
        dismantleCount,
        totalGold,
        totalPowder,
        totalStone,
        totalReroll,
        totalProtection,
        totalCube,
      );
      
      String rewardText = '골드 +${_formatNumber(totalGold)}, 가루 +$totalPowder, 강화석 +$totalStone';
      if (totalReroll > 0) rewardText += ', 재설정석 +$totalReroll';
      // 일괄 분해 로그 제거

    } else {
      _showToast('해당 조건의 분해할 아이템이 없습니다.');
    }
    _saveGameData(); 
  }

  void _showDismantleResultDialog(int count, int gold, int powder, int stone, int reroll, int protection, int cube) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Center(
        child: SizedBox(
          width: 320,
          child: _buildGlassContainer(
            padding: const EdgeInsets.all(24),
            borderRadius: 28,
            color: const Color(0xFF1A1D2D).withOpacity(0.9),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 40),
                const SizedBox(height: 16),
                _buildShadowText('분해 완료', fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                _buildShadowText('$count개의 장비를 분해했습니다', fontSize: 13, color: Colors.white54),
                const SizedBox(height: 24),
                
                // 결과 리스트
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildResultRow('💰', '골드', _formatNumber(gold), Colors.amberAccent),
                      _buildResultRow('✨', '마법 가루', powder.toString(), Colors.blueAccent),
                      _buildResultRow('🧩', '티어 파편', '획득 완료', Colors.tealAccent),
                      if (stone > 0) _buildResultRow('💎', '강화석', stone.toString(), Colors.cyanAccent),
                      if (reroll > 0) _buildResultRow('🌀', '재설정석', reroll.toString(), Colors.purpleAccent),
                      if (protection > 0) _buildResultRow('🛡️', '보호석', protection.toString(), Colors.orangeAccent),
                      if (cube > 0) _buildResultRow('📦', '강화 큐브', cube.toString(), Colors.redAccent),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // 확인 버튼
                _buildPopBtn(
                  '확인', 
                  Colors.blueAccent, 
                  () => Navigator.pop(context),
                  isFull: true,
                  icon: Icons.check,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultRow(String emoji, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Text('+$value', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }


  Widget _getItemIcon(ItemType t, {double size = 20, Color? color}) {
    String iconStr;
    switch (t) {
      case ItemType.weapon: iconStr = '🗡️'; break;
      case ItemType.helmet: iconStr = '🪖'; break;
      case ItemType.armor: iconStr = '🛡️'; break;
      case ItemType.boots: iconStr = '👢'; break;
      case ItemType.ring: iconStr = '💍'; break;
      case ItemType.necklace: iconStr = '🧿'; break;
    }
    
    return Text(
      iconStr,
      style: TextStyle(
        fontSize: size,
        shadows: const [
          Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
        ],
      ),
    );
  }

  // --- 아이템 상세 정보 팝업 ---
  void _showItemDetail(Item initialItem, {List<Item>? contextList}) {
    Item currentItem = initialItem;
    if (currentItem.isNew) setState(() => currentItem.isNew = false);

    showDialog(
      context: context,
      builder: (context) {
        bool isCompareExpanded = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isEquipped = player.equipment[currentItem.type]?.id == currentItem.id;
            final currentEquip = player.equipment[currentItem.type];
            int currentIndex = contextList?.indexWhere((i) => i.id == currentItem.id) ?? -1;
            bool hasPrev = (contextList != null && currentIndex > 0);
            bool hasNext = (contextList != null && currentIndex >= 0 && currentIndex < contextList.length - 1);

            void navigate(int dir) {
              if (contextList == null) return;
              int nextIdx = currentIndex + dir;
              if (nextIdx >= 0 && nextIdx < contextList.length) {
                setDialogState(() {
                  currentItem = contextList[nextIdx];
                  if (currentItem.isNew) setState(() => currentItem.isNew = false);
                });
              }
            }

            return Dialog(
              backgroundColor: const Color(0xFF141622),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: currentItem.grade.color.withOpacity(0.4), width: 1.5),
              ),
              child: Container(
                width: 350,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFF1A1D2E), const Color(0xFF0F111A)],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: GestureDetector(
                    onHorizontalDragEnd: (details) {
                      if (details.primaryVelocity! > 500) {
                        if (hasPrev) navigate(-1);
                      } else if (details.primaryVelocity! < -500) {
                        if (hasNext) navigate(1);
                      }
                    },
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // --- [상단 헤더 영역] ---
                          Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                    colors: [currentItem.grade.color.withOpacity(0.12), Colors.transparent],
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        _buildNavArrow(hasPrev, () => navigate(-1), Icons.chevron_left),
                                        Expanded(
                                          child: Center(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  GestureDetector(
                                                    onTap: () => setDialogState(() {
                                                      currentItem.isLocked = !currentItem.isLocked;
                                                      _saveGameData();
                                                    }),
                                                    child: Icon(
                                                      currentItem.isLocked ? Icons.lock : Icons.lock_open, 
                                                      size: 18, 
                                                      color: currentItem.isLocked ? Colors.amberAccent : Colors.white24
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  _buildTierBadge(currentItem.tier),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '${currentItem.name.replaceAll(RegExp(r" T[1-6]$"), "")} +${currentItem.enhanceLevel}',
                                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: currentItem.grade.color, letterSpacing: -0.5),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        _buildNavArrow(hasNext, () => navigate(1), Icons.chevron_right),
                                       ],
                                    ),
                                  ],
                                ),
                              ),
                              // 우측 상단: 전투력 + 닫기 버튼
                              Positioned(
                                right: 12,
                                top: 12,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.amberAccent.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.bolt, size: 12, color: Colors.amberAccent),
                                          const SizedBox(width: 4),
                                          Text(
                                            NumberFormat('#,###').format(currentItem.combatPower),
                                            style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: const Icon(Icons.close, color: Colors.white24, size: 20),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
  
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // --- [비교 카드 (확장형)] ---
                                if (!isEquipped && currentEquip != null)
                                  _buildExpandableCompareCard(currentItem, currentEquip, isCompareExpanded, (v) => setDialogState(() => isCompareExpanded = v)),
                                
                                const SizedBox(height: 12),
                                // --- [주 능력치 섹션] ---
                                _buildMainStatSection(currentItem),
                                
                                const SizedBox(height: 16),
                                // --- [보조 옵션 리스트] ---
                                const Text('아이템 옵션', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.0)),
                                const SizedBox(height: 8),
                                ...currentItem.subOptions.map((opt) {
                                  bool isFixedHp = (currentItem.type == ItemType.ring || currentItem.type == ItemType.necklace) && opt.name == '체력';
                                  if (isFixedHp) return const SizedBox();
                                  return _buildDenseOptionRow(opt, setDialogState);
                                }).toList(),
  
                                // --- [잠재능력 섹션] ---
                                if (currentItem.potential != null)
                                  _buildPotentialSection(currentItem.potential!),
  
                                const SizedBox(height: 20),
                                // --- [기능 버튼 그룹] ---
                                _buildActionButtonsGrid(currentItem, setDialogState),
                                
                                const SizedBox(height: 16),
                                // --- [강화 상세 정보 카드] ---
                                _buildEnhanceInfoCard(currentItem),
  
                                const SizedBox(height: 24),
                                // --- [하단 착용/분해 액션] ---
                                Row(
                                  children: [
                                    Expanded(child: _buildPrimaryActionBtn(
                                      isEquipped ? '해제하기' : '착용하기', 
                                      isEquipped ? Colors.white24 : Colors.lightBlueAccent,
                                      () {
                                        setState(() {
                                          if (isEquipped) player.unequipItem(currentItem.type);
                                          else player.equipItem(currentItem);
                                          _saveGameData();
                                          _startBattleLoop();
                                        });
                                        Navigator.pop(context);
                                      },
                                      icon: isEquipped ? Icons.link_off : Icons.link,
                                    )),
                                    const SizedBox(width: 10),
                                    _buildDismantleBtn(currentItem, setDialogState),
                                  ],
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- [UI HELPER WIDGETS] ---

  Widget _buildNavArrow(bool active, VoidCallback onTap, IconData icon) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: active ? Colors.white70 : Colors.white10, size: 28),
      onPressed: active ? onTap : null,
    );
  }

  Widget _buildTierBadge(int tier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Text(
        'Tier $tier', 
        style: const TextStyle(
          fontSize: 11, 
          fontWeight: FontWeight.w900, 
          color: Colors.white,
          letterSpacing: 0.5
        )
      ),
    );
  }

  Widget _buildCPBadge(int cp) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.amberAccent.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.amberAccent.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, size: 16, color: Colors.amberAccent),
          const SizedBox(width: 6),
          Text(NumberFormat('#,###').format(cp), style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildExpandableCompareCard(Item item, Item equip, bool expanded, Function(bool) onToggle) {
    final diff = item.combatPower - equip.combatPower;
    final isBetter = diff >= 0;

    return GestureDetector(
      onTap: () => onToggle(!expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: expanded ? Colors.white24 : Colors.transparent),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _getItemIcon(equip.type, size: 14),
                const SizedBox(width: 8),
                const Text('착용 장비와 비교', style: TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  '${isBetter ? '+' : ''}${NumberFormat('#,###').format(diff)}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isBetter ? Colors.greenAccent : Colors.redAccent),
                ),
                Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: Colors.white24),
              ],
            ),
            if (expanded) ...[
              const Divider(color: Colors.white12, height: 20),
              ...() {
                final myStats = <String, double>{};
                final targetStats = <String, double>{};
                myStats[item.mainStatName1] = (myStats[item.mainStatName1] ?? 0) + item.effectiveMainStat1.toDouble();
                if (item.mainStat2 != null) {
                  myStats[item.mainStatName2!] = (myStats[item.mainStatName2!] ?? 0) + item.effectiveMainStat2.toDouble();
                }
                for (var o in item.subOptions) myStats[o.name] = (myStats[o.name] ?? 0) + o.value;

                targetStats[equip.mainStatName1] = (targetStats[equip.mainStatName1] ?? 0) + equip.effectiveMainStat1.toDouble();
                if (equip.mainStat2 != null) {
                  targetStats[equip.mainStatName2!] = (targetStats[equip.mainStatName2!] ?? 0) + equip.effectiveMainStat2.toDouble();
                }
                for (var o in equip.subOptions) targetStats[o.name] = (targetStats[o.name] ?? 0) + o.value;
                final allKeys = {...myStats.keys, ...targetStats.keys}.toList()..sort();
                return allKeys.map((k) {
                  final isPerc = (item.subOptions.any((o) => o.name == k && o.isPercentage)) || (equip.subOptions.any((o) => o.name == k && o.isPercentage)) || (k == '공격 속도' || k.contains('%') || k.contains('확률') || k.contains('피해'));
                  return _buildCompareStat(k, myStats[k] ?? 0, targetStats[k] ?? 0, isPercentage: isPerc);
                }).toList();
              }(),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildMainStatSection(Item item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(item.mainStatName1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
              Text(NumberFormat('#,###').format(item.effectiveMainStat1), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
            ],
          ),
          if (item.mainStat2 != null) ...[
            const Divider(color: Colors.white10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(item.mainStatName2!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
                Text(NumberFormat('#,###').format(item.effectiveMainStat2), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDenseOptionRow(ItemOption opt, StateSetter setDialogState) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: opt.isLocked ? Colors.amberAccent.withOpacity(0.04) : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: opt.isLocked ? Colors.amberAccent.withOpacity(0.2) : Colors.transparent),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                _getStatIcon(opt.name, color: opt.isLocked ? Colors.amberAccent : Colors.cyanAccent),
                const SizedBox(width: 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Text(opt.toString(), style: TextStyle(color: opt.isLocked ? Colors.amberAccent : Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        // 별점 표시
                        Row(
                          children: List.generate(opt.stars, (index) => Icon(Icons.star, size: 10, color: _getStarColor(opt.stars))),
                        ),
                        if (opt.maxValue > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '(Max: ${opt.isPercentage ? '${opt.maxValue.toStringAsFixed(1)}%' : (opt.name == '공격 속도' ? opt.maxValue.toStringAsFixed(1) : opt.maxValue.toInt().toString())})',
                              style: TextStyle(color: Colors.white10.withOpacity(0.15), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setDialogState(() => opt.isLocked = !opt.isLocked),
            child: Icon(opt.isLocked ? Icons.lock : Icons.lock_open, size: 16, color: opt.isLocked ? Colors.amberAccent : Colors.white12),
          ),
        ],
      ),
    );
  }

  Color _getStarColor(int stars) {
    switch (stars) {
      case 1: return Colors.white38;
      case 2: return Colors.greenAccent;
      case 3: return Colors.blueAccent;
      case 4: return Colors.purpleAccent;
      case 5: return Colors.amberAccent;
      default: return Colors.white38;
    }
  }

  Widget _buildActionButtonsGrid(Item item, StateSetter setDialogState) {
    int lockCount = item.subOptions.where((o) => o.isLocked).length;
    int powderCost = lockCount == 0 ? 0 : (1000 * pow(10, lockCount - 1)).toInt();
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildCompactActionBtn(
              '옵션 재설정 (${item.rerollCount}/5)', Icons.refresh, Colors.cyanAccent, 
              (player.rerollStone >= 1 && player.powder >= powderCost && item.rerollCount < 5 && !item.isLocked),
              () => setDialogState(() {
                player.rerollStone -= 1; player.powder -= powderCost;
                item.rerollCount += 1; item.rerollSubOptions(Random());
                _saveGameData();
                _addLog('[아이템] ${item.name} 옵션 재설정 완료!', LogType.item);
              }),
              costTitle: '재설정석 1개',
              costSub: lockCount > 0 ? '${_formatNumber(powderCost)} 가루' : null,
            )),
            const SizedBox(width: 8),
            Expanded(child: _buildCompactActionBtn(
              '잠재능력', Icons.auto_awesome, Colors.purpleAccent,
              (player.cube >= 10 && !item.isLocked),
              () => setDialogState(() {
                player.cube -= 10; item.awakenPotential(Random());
                _saveGameData();
                _showSuccess('잠재능력 개방', '새로운 힘이 각성했습니다.');
              }),
              costTitle: '큐브 10개',
            )),
          ],
        ),
        const SizedBox(height: 8),
        _buildEnhanceBtn(item, setDialogState),
      ],
    );
  }

  Widget _buildCompactActionBtn(String title, IconData icon, Color color, bool enabled, VoidCallback onTap, {required String costTitle, String? costSub}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(enabled ? 0.1 : 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(enabled ? 0.3 : 0.05)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color.withOpacity(enabled ? 1.0 : 0.2)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.withOpacity(enabled ? 1.0 : 0.3))),
            const SizedBox(height: 4),
            Text(costTitle, style: TextStyle(fontSize: 9, color: Colors.white38)),
            if (costSub != null) Text(costSub, style: const TextStyle(fontSize: 8, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhanceBtn(Item item, StateSetter setDialogState) {
    final savedLevel = player.enhancementSuccession[item.tier] ?? 0;
    bool enabled = !item.isLocked && !item.isBroken;
    
    if (item.isBroken) return _buildPrimaryActionBtn('파손됨 (수리 필요)', Colors.red, null, icon: Icons.build_circle);
    if (savedLevel > 0) {
      return _buildPrimaryActionBtn('+$savedLevel 계승하기', Colors.cyanAccent, () => setDialogState(() {
        item.setEnhanceLevel(savedLevel); player.enhancementSuccession[item.tier] = 0;
        Navigator.pop(context); _showSuccess('강화 계승', '강화도가 성공적으로 계승되었습니다!');
      }), icon: Icons.swap_horiz);
    }

    return _buildPrimaryActionBtn(
      '장비 강화', Colors.blueAccent, enabled ? () => _enhanceItem(item, setDialogState) : null,
      subLabel: '${_formatNumber(item.enhanceCost)} G / 강화석 ${item.stoneCost}개',
      icon: Icons.flash_on,
    );
  }

  Widget _buildPotentialSection(ItemOption? potential) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.purpleAccent.withOpacity(0.15), Colors.pinkAccent.withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purpleAccent.withOpacity(0.4), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.purpleAccent.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.stars, color: Colors.purpleAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('잠재능력', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(potential!.toString(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    // 별점 표시
                    Row(
                      children: List.generate(potential!.stars, (index) => Icon(Icons.star, size: 10, color: _getStarColor(potential!.stars))),
                    ),
                    if (potential!.maxValue > 0 && !potential!.isSpecial)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '(Max: ${potential!.isPercentage ? '${potential!.maxValue.toStringAsFixed(1)}%' : (potential!.name == '공격 속도' ? potential!.maxValue.toStringAsFixed(1) : potential!.maxValue.toInt().toString())})',
                          style: TextStyle(color: Colors.white10.withOpacity(0.15), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhanceInfoCard(Item item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('내구도 및 성공률', style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.bold)),
              Text('${(item.successChance * 100).toInt()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: item.successChance > 0.5 ? Colors.greenAccent : Colors.redAccent)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (item.durability / item.maxDurability).clamp(0, 1),
              minHeight: 6, backgroundColor: Colors.white12,
              color: item.durability < 30 ? Colors.redAccent : (item.durability < 60 ? Colors.orangeAccent : Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionBtn(String title, Color color, VoidCallback? onTap, {String? subLabel, IconData? icon}) {
    bool enabled = onTap != null;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(enabled ? 0.2 : 0.05),
        foregroundColor: color.withOpacity(enabled ? 1.0 : 0.3),
        elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withOpacity(enabled ? 0.4 : 0.1))),
      ),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          if (subLabel != null) ...[const SizedBox(height: 2), Text(subLabel, style: const TextStyle(fontSize: 10, color: Colors.white38))],
        ],
      ),
    );
  }

  Widget _buildDismantleBtn(Item item, StateSetter setDialogState) {
    bool locked = item.isLocked;
    return GestureDetector(
      onTap: locked ? null : () {
        var rewards = _calculateDismantleRewards(item);
        setState(() {
          player.inventory.removeWhere((i) => i.id == item.id);
          player.gold += rewards['gold']!; player.powder += rewards['powder']!;
          player.enhancementStone += rewards['stone']!; player.rerollStone += rewards['reroll']!;
          player.protectionStone += rewards['protection']!; player.cube += rewards['cube']!;
          
          // 파편 추가
          int tier = rewards['tier']!;
          int shards = rewards['shards']!;
          player.tierShards[tier] = (player.tierShards[tier] ?? 0) + shards;
        });
        Navigator.pop(context);
        _showToast('분해 완료! 보상을 획득했습니다.', isError: false);
        _saveGameData();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(locked ? 0.05 : 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withOpacity(locked ? 0.1 : 0.3)),
        ),
        child: Icon(locked ? Icons.lock : Icons.delete_sweep, color: Colors.redAccent.withOpacity(locked ? 0.3 : 1.0), size: 24),
      ),
    );
  }

  Widget _getStatIcon(String name, {Color? color}) {
    IconData icon;
    if (name.contains('공격력')) icon = Icons.colorize;
    else if (name.contains('체력') || name.contains('HP')) icon = Icons.favorite;
    else if (name.contains('방어력')) icon = Icons.shield;
    else if (name.contains('속도')) icon = Icons.speed;
    else if (name.contains('치명타')) icon = Icons.gps_fixed;
    else if (name.contains('획득')) icon = Icons.monetization_on;
    else icon = Icons.add_circle_outline;
    return Icon(icon, size: 14, color: color ?? Colors.white54);
  }

  Widget _buildCompareStat(String label, double val, double cur, {bool isPercentage = false}) {
    double diff = val - cur;
    if (diff.abs() < 0.01) return const SizedBox.shrink(); // 차이가 거의 없으면 미표시

    String sign = diff > 0 ? '+' : '';
    String diffText = isPercentage ? '$sign${diff.toStringAsFixed(1)}%' : '$sign${diff.toInt()}';
    Color color = diff > 0 ? Colors.greenAccent : Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
          Row(
            children: [
              Icon(diff > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 16, color: color),
              Text(diffText, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPopBtn(String label, Color color, VoidCallback? onTap, {String? subLabel, bool isFull = false, IconData? icon}) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        width: isFull ? double.infinity : 90, // 고정 너비로 통일감 부여
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              color.withOpacity(0.7),
            ],
          ),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) Icon(icon, size: 14, color: Colors.white),
                  if (icon != null) const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label, 
                        style: const TextStyle(
                          fontWeight: FontWeight.bold, 
                          fontSize: 15, 
                          color: Colors.white,
                          letterSpacing: 0.5,
                        )
                      ),
                    ),
                  ),
                ],
              ),
              if (subLabel != null) 
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: FittedBox( // 금액이 커져도 버튼 크기를 유지하기 위해 FittedBox 적용
                    fit: BoxFit.scaleDown,
                    child: Text(
                      subLabel, 
                      style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 아이템 상세 다이얼로그 전용 버튼 (크기 고정)
  Widget _buildItemDetailBtn(String label, Color color, VoidCallback? onTap, {String? subLabel, bool isFull = false, IconData? icon}) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        // 고정 높이 제거 - 패딩으로만 크기 조정
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              color.withOpacity(0.7),
            ],
          ),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), // 패딩 증가
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) Icon(icon, size: 14, color: Colors.white),
                  if (icon != null) const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label, 
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 13, 
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (subLabel != null) 
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subLabel, 
                    style: TextStyle(
                      fontSize: 10, 
                      color: Colors.white.withOpacity(0.8), 
                      fontWeight: FontWeight.bold
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                  _buildShadowText('Lv.', fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold),
                  const SizedBox(width: 4),
                  _buildShadowText('${player.level}', fontSize: 18, color: Colors.white, fontWeight: FontWeight.w900),
                  const SizedBox(width: 12),
                  _buildShadowText('CP', fontSize: 12, color: Colors.amber.withOpacity(0.8), fontWeight: FontWeight.bold),
                  const SizedBox(width: 4),
                  _buildShadowText('${player.combatPower}', fontSize: 18, color: Colors.amber, fontWeight: FontWeight.w900),
                  const SizedBox(width: 12),
                  _buildShadowText('Gold', fontSize: 12, color: Colors.amber.withOpacity(0.6), fontWeight: FontWeight.bold),
                  const SizedBox(width: 4),
                  _buildShadowText(_formatNumber(player.gold), fontSize: 18, color: Colors.amberAccent, fontWeight: FontWeight.w900),
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
  }

  Widget _buildJumpStageEffect() {
    return IgnorePointer(
      key: ValueKey('jump_effect_$_jumpEffectId'),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1600), // 총 지속 시간 (Entrance 0.5s + Sustain 0.8s + Exit 0.3s)
          builder: (context, value, child) {
            double opacity = 1.0;
            double scale = 1.0;
            double translateY = 0.0;

            // 1. 등장 (0% ~ 30%, 약 480ms)
            if (value < 0.3) {
              double t = value / 0.3;
              opacity = t;
              // easeOutBack 느낌의 스케일 (0.85 -> 1.05 -> 1.0)
              if (t < 0.7) {
                scale = 0.85 + (0.2 * (t / 0.7)); // 0.85 -> 1.05
              } else {
                scale = 1.05 - (0.05 * ((t - 0.7) / 0.3)); // 1.05 -> 1.0
              }
            } 
            // 2. 유지 (30% ~ 80%, 약 800ms)
            else if (value < 0.8) {
              opacity = 1.0;
              scale = 1.0;
              translateY = 0.0;
            } 
            // 3. 퇴장 (80% ~ 100%, 약 320ms)
            else {
              double t = (value - 0.8) / 0.2;
              opacity = 1.0 - t;
              translateY = -20 * t;
              scale = 1.0;
            }

            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, translateY),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.65),
                          Colors.black.withOpacity(0.4),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, color: Colors.amberAccent, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          'JUMP STAGE!!',
                          style: GoogleFonts.outfit( // 현대적인 산세리프 폰트
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: const Color(0xFFFFD700), // 연한 골드
                            shadows: const [
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 2,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
    return _PressableScale(
      onTap: onTap,
      child: _buildGlassContainer(
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

  Widget _buildTopSmallIconButton(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
      child: Icon(icon, size: 12, color: Colors.white70),
    );
  }

  Widget _buildMiniResource(IconData icon, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          _formatNumber(count),
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMiniInventoryCounter() {
    bool isFull = player.inventory.length >= player.maxInventory;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.inventory_2, size: 10, color: isFull ? Colors.redAccent : Colors.white54),
        const SizedBox(width: 3),
        Text(
          '${player.inventory.length}',
          style: TextStyle(
            color: isFull ? Colors.redAccent : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // 가독성을 위한 그림자 텍스트 헬퍼
  Widget _buildShadowText(String text, {double fontSize = 14, Color color = Colors.white, FontWeight fontWeight = FontWeight.normal, TextOverflow? overflow}) {
    return Text(
      text,
      overflow: overflow,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black)],
      ),
    );
  }

  Widget _buildTopSmallButton(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [Icon(icon, size: 10, color: Colors.greenAccent), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 9))]),
    );
  }

  Widget _buildStageBarLarge() {
    double progress = (_stageKills / _targetKills).clamp(0, 1);
    return Container(
      width: double.infinity,
      height: 14, 
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), 
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(7), 
      ),
      child: Stack(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: progress),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  gradient: const LinearGradient(
                    colors: [Colors.orangeAccent, Colors.orange],
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
                Text(
                  _currentZone.id == ZoneId.tower 
                    ? '👹 무한의 탑 - ${Monster.getDisplayStage(_currentStage)}층 도전 중' 
                    : '${_currentZone.name} - 스테이지 ${Monster.getDisplayStage(_currentStage)}', 
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, fontStyle: FontStyle.italic)
                ),
                if (_currentZone.id != ZoneId.tower)
                  Text('$_stageKills / $_targetKills', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombatTab() {
    return Column(
      children: [
        _buildCombatHeader(), // 진행도와 효율을 가로로 통합한 새로운 헤더
        Expanded(flex: 7, child: _buildBattleScene()), // 전투 비중 확대
        _buildSkillQuickbar(),
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
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(7)),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A).withOpacity(0.50), // 불투명도 50% 적용
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1), // 살짝 가미된 테두리
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(Colors.amber, _goldPerMin.toInt().toString(), '분당골드'),
              _buildStatDivider(),
              _buildStatItem(Colors.blueAccent, _expPerMin.toInt().toString(), '분당EXP'),
              _buildStatDivider(),
              _buildStatItem(Colors.redAccent, _killsPerMin.toStringAsFixed(1), '분당처치'),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(color: Colors.white10, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSessionStat('누적골드', _sessionGold, Colors.amber),
              const SizedBox(width: 20),
              _buildSessionStat('누적EXP', _sessionExp, Colors.blueAccent),
              const SizedBox(width: 20),
              _buildSessionStat('최대DMG', _sessionMaxDamage, Colors.redAccent), // 🆕 최대 데미지 추가
              const Spacer(),

              GestureDetector(
                onTap: () {
                  setState(() {
                    _sessionGold = 0;
                    _sessionExp = 0;
                    _sessionMaxDamage = 0; // 초기화 시 최대 데미지도 리셋
                    _recentGains.clear();
                  });

                  _showToast('통계가 초기화되었습니다.');
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.refresh, size: 14, color: Colors.blueAccent),
                ),
              ),
            ],
          ),
        ],
      ),
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
        Text(_formatNumber(value), style: TextStyle(color: color.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.w900)), // 폰트 축소 (13 -> 11)
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
          color: const Color(0xFF1A1D2E).withOpacity(0.92), // 배경색 통일감 있게 조정
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5)),
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
                return _PressableScale(
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
                      color: isSel ? Colors.blueAccent.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: isSel 
                        ? Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 1)
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
                              Shadow(color: Colors.black.withOpacity(0.4), blurRadius: 3, offset: const Offset(1, 1))
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
    return AnimatedBuilder(
      animation: Listenable.merge([_uiTickerController, _monsterSpawnController, _monsterDeathController]),
      builder: (context, child) {
        return Stack(
          key: _battleSceneKey,
          fit: StackFit.expand, 
          children: [
          // 기존 중복 배경 제거
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildActor(player.name, player.level, playerCurrentHp, player.maxHp, 'assets/images/warrior.png', _playerAnimController, true),
              Center(
                key: _monsterKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (currentMonster != null)
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
                                child: _buildActor(currentMonster!.name, currentMonster!.level, monsterCurrentHp, currentMonster!.maxHp, currentMonster!.imagePath, _monsterAnimController, false),
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
          if (player.activePet != null)
            _buildIndependentPet(player.activePet!),
          
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
                color: Colors.black.withOpacity(0.5),
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
        ]);
      },
    );
  }

  Widget _buildActor(String n, int lv, int h, int mh, String img, AnimationController c, bool p) {
    double hpProgress = (h / mh).clamp(0, 1);
    return AnimatedBuilder(
      animation: Listenable.merge([c, _heroPulseController, _heroRotateController]), 
      builder: (ctx, _) {
        return Transform.translate(
          offset: Offset(c.value * (p ? 30 : -30), 0), 
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              // 1. 이름 및 등급 뱃지
              _buildShadowText(n, fontSize: 13, fontWeight: FontWeight.w900, color: p ? Colors.white : Colors.redAccent),
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
                        border: Border.all(color: p ? Colors.cyan.withOpacity(0.08) : Colors.red.withOpacity(0.05), width: 0.5),
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
                          color: p ? Colors.blueAccent.withOpacity(0.25) : Colors.red.withOpacity(0.2),
                          blurRadius: 20 + (15 * _heroPulseController.value),
                          spreadRadius: 2,
                        ),
                        // Outer Bloom
                        BoxShadow(
                          color: p ? Colors.cyan.withOpacity(0.12) : Colors.redAccent.withOpacity(0.1),
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
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: const BorderRadius.all(Radius.elliptical(55, 10)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 12)],
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
                            child: Image.asset(img, fit: BoxFit.contain, color: p ? Colors.blueAccent.withOpacity(0.15) : Colors.red.withOpacity(0.1), colorBlendMode: BlendMode.srcATop),
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
                    border: Border.all(color: pet.grade.color.withOpacity(0.6), width: 2.0),
                    boxShadow: [
                      BoxShadow(color: pet.grade.color.withOpacity(0.3), blurRadius: 10, spreadRadius: 2),
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

  Widget _buildSkillQuickbar() {
    final activeSkills = player.skills.where((s) => s.type == SkillType.active).toList();
    return Container(
      height: 80, // 레벨 텍스트 공간 확보를 위해 높이 증가
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          if (i < activeSkills.length) {
            final skill = activeSkills[i];
            bool isUnlocked = skill.level > 0;
            
            // 업그레이드 가능 여부 체크 (레벨 조건 & 골드 조건)
            bool canUpgrade = (player.level >= skill.unlockLevel) && (player.gold >= skill.upgradeCost);
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: (canUpgrade || !isUnlocked) 
                    ? () => setState(() => _selectedIndex = 5) // 업그레이드 가능하거나 잠김 시 스킬탭 이동
                    : (isUnlocked ? () => _useSkill(skill) : null), // 해금되었고 업그레이드 불가 시 사용
                  child: Container(
                    width: 50, height: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: skill.isUnlocked ? Colors.white24 : Colors.white10),
                      boxShadow: skill.isUnlocked ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.1), blurRadius: 4)] : null,
                    ),
                    child: Stack(
                      children: [
                        Center(child: Opacity(opacity: skill.isUnlocked ? 1.0 : 0.3, child: _getSkillIcon(skill.id, size: 28))),
                        if (skill.isUnlocked)
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _uiTickerController,
                              builder: (context, child) {
                                final progress = skill.getCooldownProgress(player.cdr);
                                return FractionallySizedBox(
                                  alignment: Alignment.bottomCenter,
                                  heightFactor: skill.isReady(player.cdr) ? 0.0 : (1.0 - progress),
                                  child: Container(color: Colors.black54),
                                );
                              },
                            ),
                          ),
                        if (skill.isUnlocked && !skill.isReady(player.cdr))
                          Center(
                            child: AnimatedBuilder(
                              animation: _uiTickerController,
                              builder: (context, child) {
                                return Text(
                                  '${skill.getRemainingSeconds(player.cdr).toStringAsFixed(1)}s',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                                  ),
                                );
                              },
                            ),
                          ),
                        if (!skill.isUnlocked)
                          Center(child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                               const Icon(Icons.lock, size: 14, color: Colors.white24),
                               Text('Lv.${skill.unlockLevel}', style: const TextStyle(fontSize: 8, color: Colors.white24)),
                             ],
                           )),

                        // 업그레이드 가능 알림 배지 (Red Dot)
                        if (canUpgrade)
                          Positioned(
                            top: 4, right: 4,
                            child: Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 4, spreadRadius: 1)
                                ],
                                border: Border.all(color: Colors.white.withOpacity(0.5), width: 0.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // 레벨 표시 및 스킬 탭 이동 기능
                GestureDetector(
                  onTap: () => setState(() => _selectedIndex = 5), // 스킬 탭으로 이동
                  child: Text(
                    isUnlocked ? 'Lv.${skill.level}' : '잠김',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isUnlocked ? Colors.white70 : Colors.white24,
                      shadows: const [Shadow(blurRadius: 2, color: Colors.black)],
                    ),
                  ),
                ),
              ],
            );
          }
          return Container(width: 50, height: 50, margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 15), decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)), child: const Icon(Icons.add, size: 14, color: Colors.white10));
        }),
      ),
    );
  }

  // --- 스킬 상세 메뉴 구현 ---
  // ═══════════════════════════════════════════════════════════════════════════
  // ⚡ SKILL SYSTEM - 스킬 시스템
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSkillTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [Tab(text: '액티브 스킬'), Tab(text: '패시브 스킬')],
            indicatorColor: Colors.orangeAccent,
            labelColor: Colors.orangeAccent,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSkillList(SkillType.active),
                _buildSkillList(SkillType.passive),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillList(SkillType type) {
    final list = player.skills.where((s) => s.type == type).toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final skill = list[i];
        bool canLevelUp = player.gold >= skill.upgradeCost;
        bool isLevelMet = player.level >= skill.unlockLevel;
        
        return _buildGlassContainer(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          border: Border.all(color: skill.isUnlocked ? Colors.orangeAccent.withOpacity(0.3) : Colors.white10),
          child: Row(
            children: [
              // 스킬 아이콘 영역
              _buildSkillIconSlot(skill, isLevelMet),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(skill.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
                        const SizedBox(width: 8),
                        if (skill.isUnlocked)
                          _buildGlassContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            borderRadius: 6,
                            color: Colors.orangeAccent.withOpacity(0.2),
                            child: Text('Lv.${skill.level}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          )
                        else
                          Text('해금 Lv.${skill.unlockLevel}', style: TextStyle(color: isLevelMet ? Colors.greenAccent : Colors.white24, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(skill.description, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                    const SizedBox(height: 6),
                    _buildSkillEffectInfo(skill),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildPopBtn(
                skill.isUnlocked ? '강화' : '개방',
                !isLevelMet ? Colors.grey : (skill.isUnlocked ? Colors.orangeAccent : Colors.blueAccent),
                () {
                  if (!isLevelMet) {
                    _showToast('레벨이 부족합니다! (필정: ${skill.unlockLevel})', isError: true);
                  } else if (!canLevelUp) {
                    _showToast('골드가 부족합니다!', isError: true);
                  } else {
                    _upgradeSkill(skill);
                  }
                },
                subLabel: '${_formatNumber(skill.upgradeCost)} G',
              ),
            ],
          ),
        );
      },
    );
  }

  void _upgradeSkill(Skill skill) {
    int cost = skill.upgradeCost;
    if (player.gold < cost) {
      _showToast('골드가 부족합니다! (필요: ${_formatNumber(cost)} G)', isError: true);
      return;
    }
    if (player.level < skill.unlockLevel) {
      _showToast('레벨이 부족합니다! (해금 Lv.${skill.unlockLevel})', isError: true);
      return;
    }

    setState(() {
      player.gold -= cost;
      skill.level++;
      _addLog('[스킬] ${skill.name} ${skill.level}레벨 달성!', LogType.event);
      _saveGameData(); // 스킬 업글 후 저장
      _startBattleLoop(); // 공격 속도 변화 즉시 반영
    });
  }

  // 스킬 전용 헬퍼 위젯들
  Widget _buildSkillIconSlot(Skill skill, bool isLevelMet) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: Colors.black38, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skill.isUnlocked ? Colors.orangeAccent.withOpacity(0.5) : Colors.white10),
      ),
      child: Center(
        child: Opacity(
          opacity: isLevelMet ? 1.0 : 0.2,
          child: Text(skill.iconEmoji, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }

  Widget _buildSkillEffectInfo(Skill skill) {
    double effVal = player.getSkillValue(skill.id);
    int bonus = player.potentialSkillBonus;

    String effectText = "";
    switch (skill.id) {
      case 'act_1': effectText = '공격력의 ${effVal.toInt()}% 피해 (3연타)'; break;
      case 'pas_1': effectText = '공격 속도 +${effVal.toInt()}%'; break;
      case 'act_2': effectText = '공격력의 ${effVal.toInt()}% 강력한 한방'; break;
      case 'pas_2': effectText = '방어력 +${effVal.toInt()}%'; break;
      case 'act_3': effectText = '공격력의 ${effVal.toInt()}% 및 빙결'; break;
      case 'pas_3': effectText = '골드/아이템 획득 +${effVal.toInt()}%'; break;
      case 'act_4': effectText = '공격력의 ${effVal.toInt()}% 광역 마법'; break;
      case 'pas_4': effectText = '치명타 피해 +${effVal.toInt()}%'; break;
      case 'act_5': effectText = '공격력의 ${effVal.toInt()}% 초거대 메테오'; break;
      case 'pas_5': effectText = '데미지의 ${effVal.toStringAsFixed(1)}% 체력 흡수'; break;
      case 'pas_6': effectText = '스킬 재사용 대기시간 -${effVal.toInt()}%'; break;
    }

    return Row(
      children: [
        Icon(Icons.flash_on, size: 10, color: skill.isUnlocked ? Colors.cyanAccent : Colors.white10),
        const SizedBox(width: 4),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(color: skill.isUnlocked ? Colors.cyanAccent : Colors.white24, fontSize: 11, fontWeight: FontWeight.w500),
              children: [
                TextSpan(text: skill.level == 0 ? '효과: $effectText' : '현재 효과: $effectText'),
                if (bonus > 0 && skill.isUnlocked)
                  const TextSpan(text: ' (잠재 보너스 적용 중)', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _useSkill(Skill skill) {
    if (!skill.isReady(player.cdr)) return;

    setState(() {
      skill.lastUsed = DateTime.now();
      player.totalSkillsUsed++;

      // 공통 데미지 계산 로직
      void applySkillDamage(double powerMultiplier, {int hits = 1, String effectName = ""}) {
        if (currentMonster == null) return;
        
        // 다단 히트는 시간차를 두고 적용 (타격감 향상)
        for (int i = 0; i < hits; i++) {
          final hitDelay = i * 100; // 각 히트마다 100ms 간격
          
          Future.delayed(Duration(milliseconds: hitDelay), () {
            if (!mounted || currentMonster == null) return;
            
            setState(() {
              bool isSkillCrit = Random().nextDouble() * 100 < player.critChance;
              double sVariance = 0.9 + (Random().nextDouble() * 0.2); // ±10% 분산
              int skillDmg = (player.attack * powerMultiplier / 100 * sVariance * player.potentialFinalDamageMult).toInt();
              int finalDmg = (skillDmg - currentMonster!.defense).clamp(1, 9999999);
              if (isSkillCrit) finalDmg = (finalDmg * player.critDamage / 100).toInt();

              // 최대 데미지 갱신 (스킬)
              if (finalDmg > _sessionMaxDamage) _sessionMaxDamage = finalDmg;


              // 흡혈 적용 (패시브)
              if (player.lifesteal > 0) {
                int healAmount = (finalDmg * player.lifesteal / 100).toInt();
                playerCurrentHp = (playerCurrentHp + healAmount).clamp(0, player.maxHp);
              }

              currentMonster!.hp -= finalDmg;
              
              // 다단 히트 시 플로팅 텍스트 분산
              double ox = hits > 1 ? (Random().nextDouble() * 40 - 20) : 0;
              double oy = hits > 1 ? (Random().nextDouble() * 40 - 20) : 0;
              
              _addFloatingText(
                isSkillCrit ? '⚡CRITICAL $finalDmg' : '🔥SKILL $finalDmg', 
                true, 
                isCrit: isSkillCrit,
                offsetX: ox,
                offsetY: oy
              );
              
              // 스킬 사용 로그 제거 (플로팅 텍스트로 대체)

              
              if (currentMonster!.isDead) {
                if (_isProcessingVictory) return;
                _isProcessingVictory = true;

                battleTimer?.cancel();
                _monsterAttackTimer?.cancel();

                final killDuration = _lastMonsterSpawnTime != null 
                    ? DateTime.now().difference(_lastMonsterSpawnTime!) 
                    : null;
                
                _handleVictory(killDuration);

                _monsterDeathController.forward(from: 0).whenComplete(() {
                  if (mounted) {
                    _monsterDeathController.reset();
                    _spawnMonster();
                  }
                });
              }
            });
          });
        }
      }

      // 스킬 ID별 개별 효과 적용
      switch (skill.id) {
        case 'act_1': // 바람 베기 (3연타)
          applySkillDamage(skill.currentValue, hits: 3);
          break;
        case 'act_2': // 강격 (강력한 한방)
          applySkillDamage(skill.currentValue, effectName: "(강타!)");
          break;
        case 'act_3': // 얼음 화살 (빙결 - 일단 데미지만)
          applySkillDamage(skill.currentValue, effectName: "(빙결!)");
          break;
        case 'act_4': // 화염구 (광역 느낌의 고데미지)
          applySkillDamage(skill.currentValue, effectName: "(폭발!)");
          break;
        case 'act_5': // 메테오 (최종 결전기)
          _spawnLootParticles(0, 0, _monsterKey.currentContext?.findRenderObject() as RenderBox != null ? (_monsterKey.currentContext!.findRenderObject() as RenderBox).localToGlobal(Offset.zero) : Offset.zero); // 연출용
          applySkillDamage(skill.currentValue, effectName: "!!!최후의 심판!!!");
          break;
      }
    });
  }

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
        color: Colors.black.withOpacity(0.4), // 유리 느낌의 투명도
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
    Color textColor = Colors.white70;
    FontWeight fontWeight = FontWeight.normal;
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
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(4),
        ),
        child: RichText(
          text: TextSpan(children: spans, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }


  Widget _buildDockIcon(int idx, IconData icon, String label) {
    bool isSel = _selectedIndex == idx;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: isSel ? Colors.amberAccent : Colors.white54, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: isSel ? Colors.amberAccent : Colors.white38, fontSize: 9)),
        ]),
      ),
    );
  }



  // ═══════════════════════════════════════════════════════════════════════════
  // 🏆 ACHIEVEMENT SYSTEM - 업적 및 도감 시스템
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAchievementTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 메뉴 선택 버튼
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildSubTabBtn('업적 전당', 0, Icons.emoji_events),
                ),
                Expanded(
                  child: _buildSubTabBtn('장비 도감', 1, Icons.auto_stories),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _achievementMenuTab == 0 
              ? _buildAchievementList() 
              : _buildEquipmentEncyclopedia(),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSubTabBtn(String label, int index, IconData icon) {
    bool isSelected = _achievementMenuTab == index;
    return GestureDetector(
      onTap: () => setState(() => _achievementMenuTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: Colors.amber.withOpacity(0.5)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.amber : Colors.white24),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              color: isSelected ? Colors.amberAccent : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementList() {
    return ListView.builder(
      itemCount: AchievementData.list.length,
      itemBuilder: (context, index) {
        final achievement = AchievementData.list[index];
        
        int progress = 0;
        switch (achievement.type) {
          case AchievementType.monsterKill: progress = player.totalKills; break;
          case AchievementType.goldEarned: progress = player.totalGoldEarned; break;
          case AchievementType.playerLevel: progress = player.level; break;
          case AchievementType.itemAcquired: progress = player.totalItemsFound; break;
          case AchievementType.skillUsed: progress = player.totalSkillsUsed; break;
        }

        int currentStep = player.achievementSteps[achievement.id] ?? 0;
        int target = achievement.getTargetForStep(currentStep);
        double percent = (progress / target).clamp(0.0, 1.0);
        int reward = achievement.getRewardForStep(currentStep);

        return _buildGlassContainer(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            borderRadius: 24,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildShadowText(achievement.title, fontSize: 18, fontWeight: FontWeight.bold),
                  _buildGlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    borderRadius: 8,
                    color: Colors.amber.withOpacity(0.15),
                    child: _buildShadowText('${currentStep + 1}단계', color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(achievement.description, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
              const SizedBox(height: 20),
              // 프리미엄 단계 바
              Stack(
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(7), border: Border.all(color: Colors.white10)),
                  ),
                  FractionallySizedBox(
                    widthFactor: percent,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Colors.orange, Colors.amber]),
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8)],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Text('$progress / $target', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars, color: Colors.blueAccent, size: 14),
                      const SizedBox(width: 4),
                      Text('보상: $reward 강화석', style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  _buildPopBtn('수령하기', percent >= 1.0 ? Colors.greenAccent : Colors.white12, () {
                    if (percent >= 1.0) {
                      _claimAchievement(achievement);
                    } else {
                      _showToast('아직 목표에 도달하지 못했습니다.');
                    }
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // 장비 도감 UI (티어별 아코디언 형태)
  Widget _buildEquipmentEncyclopedia() {
    return ListView.builder(
      itemCount: 6, // T1 ~ T6
      itemBuilder: (context, index) {
        int tier = index + 1;
        return _buildTierSection(tier);
      },
    );
  }

  Widget _buildTierSection(int tier) {
    return _buildGlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 16,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TIER $tier 장비 도감', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              _buildProgressBadge(tier),
            ],
          ),
          const SizedBox(height: 16),
          // 6가지 부위 아이콘 그리드
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: ItemType.values.map((type) => _buildEncyclopediaItemIcon(tier, type)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBadge(int tier) {
    int total = 6 * 21; // 6종 * (0~20강)
    int completed = 0;
    
    for (var type in ItemType.values) {
      String key = 'T${tier}_${type.name}';
      completed += player.encyclopediaClaims[key]?.length ?? 0;
    }
    
    double percent = completed / total;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${(percent * 100).toInt()}%', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEncyclopediaItemIcon(int tier, ItemType type) {
    String key = 'T${tier}_${type.name}';
    int maxLevelAchieved = player.encyclopediaProgress[key] ?? -1;
    bool hasUnlockedAny = maxLevelAchieved >= 0;
    
    // 수령 가능한 보상이 있는지 체크
    int claimedCount = player.encyclopediaClaims[key]?.length ?? 0;
    bool hasRewardToClaim = (maxLevelAchieved + 1) > claimedCount;

    return GestureDetector(
      onTap: () => _showEncyclopediaDetail(tier, type),
      child: _buildGlassContainer(
        padding: const EdgeInsets.all(8),
        borderRadius: 12,
        color: hasUnlockedAny ? Colors.white.withOpacity(0.05) : Colors.black26,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    hasUnlockedAny ? Colors.transparent : Colors.grey,
                    hasUnlockedAny ? BlendMode.dst : BlendMode.saturation,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [_getItemIcon(type, size: 28, color: hasUnlockedAny ? null : Colors.white24)],
                  ),
                ),
                if (hasRewardToClaim)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_getItemTypeName(type), style: TextStyle(color: hasUnlockedAny ? Colors.white70 : Colors.white24, fontSize: 11)),
            Text('${claimedCount}/21', style: TextStyle(color: hasUnlockedAny ? Colors.cyanAccent : Colors.white10, fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  String _getItemTypeName(ItemType type) {
    switch (type) {
      case ItemType.weapon: return '무기';
      case ItemType.helmet: return '투구';
      case ItemType.armor: return '갑옷';
      case ItemType.boots: return '신발';
      case ItemType.ring: return '반지';
      case ItemType.necklace: return '목걸이';
    }
  }

  void _showEncyclopediaDetail(int tier, ItemType type) {
    String key = 'T${tier}_${type.name}';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          int currentMax = player.encyclopediaProgress[key] ?? -1;
          List<int> claimed = player.encyclopediaClaims[key] ?? [];

          return AlertDialog(
            backgroundColor: const Color(0xFF161B2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                _getItemIcon(type, size: 24, color: Colors.cyanAccent),
                const SizedBox(width: 12),
                Text('T$tier ${_getItemTypeName(type)} 도감', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: 21,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, lv) {
                  bool isReached = lv <= currentMax;
                  bool isClaimed = claimed.contains(lv);
                  
                  return GestureDetector(
                    onTap: () {
                      if (isReached && !isClaimed) {
                        _claimEncyclopediaReward(key, lv);
                        setDialogState(() {});
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isClaimed 
                          ? Colors.cyanAccent.withOpacity(0.1) 
                          : (isReached ? Colors.orangeAccent.withOpacity(0.1) : Colors.white10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isClaimed 
                            ? Colors.cyanAccent.withOpacity(0.5) 
                            : (isReached ? Colors.orangeAccent.withOpacity(0.5) : Colors.transparent),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('+$lv', style: TextStyle(
                            color: isReached ? Colors.white : Colors.white24,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          )),
                          if (isClaimed)
                            const Icon(Icons.check_circle, color: Colors.cyanAccent, size: 12)
                          else if (isReached)
                            const Icon(Icons.card_giftcard, color: Colors.orangeAccent, size: 12)
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기', style: TextStyle(color: Colors.white60))),
            ],
          );
        }
      ),
    );
  }
  void _claimAchievement(Achievement achievement) {
    int currentStep = player.achievementSteps[achievement.id] ?? 0;
    int target = achievement.getTargetForStep(currentStep);
    int reward = achievement.getRewardForStep(currentStep);
    
    int progress = 0;
    switch (achievement.type) {
      case AchievementType.monsterKill: progress = player.totalKills; break;
      case AchievementType.goldEarned: progress = player.totalGoldEarned; break;
      case AchievementType.playerLevel: progress = player.level; break;
      case AchievementType.itemAcquired: progress = player.totalItemsFound; break;
      case AchievementType.skillUsed: progress = player.totalSkillsUsed; break;
    }

    if (progress >= target) {
      setState(() {
        String? msg = player.checkAchievement(achievement.id, progress, target, reward);
        if (msg != null) {
          _addLog(msg, LogType.event);
          _showSuccess('업적 달성!', msg);
        }
      });
    }
  }

  // --- 펫 시스템 UI 및 로직 ---
  // ═══════════════════════════════════════════════════════════════════════════
  // 🐾 PET SYSTEM - 펫 시스템
  // ═══════════════════════════════════════════════════════════════════════════

  int _petFilterIdx = 0; // 0: 전체, 1: 일반, 2: 고급, 3: 희귀, 4: 고대의, 5: 유물의, 6: 전설의

  Widget _buildPetTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _buildPetStatusHeader(),
          const SizedBox(height: 16),
          _buildPetSummonArea(),
          const SizedBox(height: 16),
          _buildPetFilterArea(),
          const SizedBox(height: 12),
          Expanded(child: _buildOwnedPetGrid()),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildPetStatusHeader() {
    final activePet = player.activePet;
    return _buildGlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      border: Border.all(color: activePet?.grade.color.withOpacity(0.3) ?? Colors.white10),
      child: Row(
        children: [
          // 현재 펫 아이콘
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: activePet?.grade.bgGradient,
              color: activePet == null ? Colors.white10 : null,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                if (activePet != null)
                  BoxShadow(color: activePet.grade.color.withOpacity(0.2), blurRadius: 10),
              ],
            ),
            child: Center(
              child: Text(
                activePet?.iconEmoji ?? '❔',
                style: const TextStyle(fontSize: 34),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShadowText(
                  activePet?.name ?? '동행 중인 펫 없음',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: activePet?.grade.color ?? Colors.white60,
                ),
                const SizedBox(height: 6),
                Text(
                  '전체 보유 효과: ATK +${player.petAtkBonus.toStringAsFixed(1)}% / HP +${player.petHpBonus.toStringAsFixed(1)}%',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                ),
                if (activePet != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '동행 효과: ${activePet.companionSkillName} (${activePet.companionValue.toStringAsFixed(1)}%)',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPetSummonArea() {
    return _buildGlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('펫 소환', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('다양한 동료를 모아보세요!', style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
          Row(
            children: [
              _buildPopBtn('1회 소환', Colors.blueGrey, () => _summonPet(1), subLabel: '10,000 G'),
              const SizedBox(width: 8),
              _buildPopBtn('10회 소환', Colors.deepPurple, () => _summonPet(10), subLabel: '90,000 G'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPetFilterArea() {
    final List<String> filters = ['전체', '일반', '고급', '희귀', '고대의', '유물의', '전설의'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(filters.length, (index) {
          bool isSelected = _petFilterIdx == index;
          Color filterColor = Colors.white24;
          if (index > 0) {
            filterColor = PetGrade.values[index - 1].color;
          }

          return GestureDetector(
            onTap: () => setState(() => _petFilterIdx = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? filterColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? filterColor : Colors.white10,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                filters[index],
                style: TextStyle(
                  color: isSelected ? filterColor : Colors.white38,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOwnedPetGrid() {
    // 필터링된 펫 목록 생성
    final List<Pet> allInitialPets = PetData.getInitialPets();
    List<Pet> displayPets = allInitialPets.where((p) {
      if (_petFilterIdx == 0) return true;
      return p.grade == PetGrade.values[_petFilterIdx - 1];
    }).toList();

    if (displayPets.isEmpty) {
      return Center(child: Text('해당 등급의 펫이 없습니다.', style: TextStyle(color: Colors.white24)));
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.82,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: displayPets.length,
      itemBuilder: (context, index) {
        final petData = displayPets[index];
        // 플레이어가 해당 펫을 보유 중인지 확인
        final ownedPet = player.pets.firstWhere((p) => p.id == petData.id, orElse: () => petData);
        bool isOwned = player.pets.any((p) => p.id == petData.id);
        bool isActive = player.activePet?.id == petData.id;

        return _buildPetCard(ownedPet, isOwned, isActive);
      },
    );
  }

  Widget _buildPetCard(Pet pet, bool isOwned, bool isActive) {
    return _PressableScale(
      onTap: () => _showPetDetailDialog(pet, isOwned, isActive),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isOwned ? pet.grade.bgGradient : null,
          color: isOwned ? null : Colors.black45,
          border: Border.all(
            color: isActive ? Colors.cyanAccent : (isOwned ? pet.grade.color.withOpacity(0.5) : Colors.white10),
            width: isActive ? 2 : 1.2,
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(color: Colors.cyanAccent.withOpacity(0.3), blurRadius: 10, spreadRadius: 1),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 펫 아이콘 (미보유 시 흑백)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   ColorFiltered(
                    colorFilter: isOwned 
                      ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                      : const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                    child: Text(pet.iconEmoji, style: const TextStyle(fontSize: 32)),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      pet.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isOwned ? Colors.white : Colors.white24,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isOwned)
                    Text(
                      'Lv.${pet.level}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            
            // 미보유 잠금 표시
            if (!isOwned)
              Positioned(
                top: 6, right: 6,
                child: Icon(Icons.lock, color: Colors.white24, size: 12),
              ),

            // 장착 중 표시
            if (isActive)
              Positioned(
                top: 0, left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: const BoxDecoration(
                    color: Colors.cyanAccent,
                    borderRadius: BorderRadius.only(bottomRight: Radius.circular(10)),
                  ),
                  child: const Text('ON', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPetDetailDialog(Pet pet, bool isOwned, bool isActive) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(
            opacity: anim1.value,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: pet.grade.color.withOpacity(0.5))),
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 상단 헤더
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: pet.grade.bgGradient,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      children: [
                        Text(pet.iconEmoji, style: const TextStyle(fontSize: 60)),
                        const SizedBox(height: 12),
                        _buildShadowText(pet.name, fontSize: 24, fontWeight: FontWeight.bold),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.24), borderRadius: BorderRadius.circular(12)),
                          child: Text(pet.grade.name, style: TextStyle(color: pet.grade.color, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  
                  // 정보 영역
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pet.description, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 20),
                        
                        _buildDetailInfoTile('보유 효과', [
                          if (pet.ownAtkMultiplier > 0) '공격력 +${pet.currentAtkBonus.toStringAsFixed(1)}%',
                          if (pet.ownHpMultiplier > 0) '체력 +${pet.currentHpBonus.toStringAsFixed(1)}%',
                          if (pet.ownGoldMultiplier > 0) '골드 +${pet.currentGoldBonus.toStringAsFixed(1)}%',
                        ], Colors.orangeAccent),
                        
                        const SizedBox(height: 12),
                        
                        _buildDetailInfoTile('동행 효과 (${pet.companionSkillName})', [
                          pet.companionSkillDesc,
                          if (pet.companionValue > 0) '기준 수치: ${pet.companionValue.toStringAsFixed(1)}%',
                        ], Colors.cyanAccent),
                        
                        const SizedBox(height: 24),
                        
                        // 버튼 영역
                        Row(
                          children: [
                            Expanded(
                              child: _buildPopBtn('닫기', Colors.white10, () => Navigator.pop(context)),
                            ),
                            if (isOwned) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildPopBtn(
                                  isActive ? '해제' : '동행',
                                  isActive ? Colors.redAccent : Colors.greenAccent,
                                  () {
                                    setState(() {
                                      if (isActive) player.activePet = null;
                                      else player.activePet = pet;
                                      _saveGameData();
                                    });
                                    Navigator.pop(context);
                                  }
                                ),
                              ),
                            ],
                          ],
                        ),
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

  Widget _buildDetailInfoTile(String title, List<String> details, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 3, height: 14, color: color),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 6),
        ...details.map((d) => Padding(
          padding: const EdgeInsets.only(left: 11, bottom: 2),
          child: Text('• $d', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        )),
      ],
    );
  }

  void _enhanceItem(Item item, StateSetter setDialogState) {
    if (item.isBroken) {
      _showToast('아이템이 파손되었습니다! 마을에서 수리하세요.', isError: true);
      return;
    }
    if (player.gold < item.enhanceCost) {
      _showToast('골드가 부족합니다! (필요: ${_formatNumber(item.enhanceCost)} G)', isError: true);
      return;
    }
    if (player.enhancementStone < item.stoneCost) {
      _showToast('강화석이 부족합니다! (필요: ${item.stoneCost}개)', isError: true);
      return;
    }

    setState(() {
      player.gold -= item.enhanceCost;
      player.enhancementStone -= item.stoneCost;
      
      bool isSuccess = Random().nextDouble() < item.successChance;
      String resultMsg = item.processEnhance(isSuccess);
      
      // [강화 계승 로직] 파손 시 플레이어 데이터 업데이트
      if (!isSuccess && item.isBroken) {
        int successionLevel = (item.enhanceLevel * 0.7).floor();
        player.enhancementSuccession[item.tier] = successionLevel;
        resultMsg = "아이템 파손! 능력치 20% 감소 및 ${item.tier}티어 ${successionLevel}강 계승 데이터 저장됨";
      }
      
      if (isSuccess) {
        _addLog(resultMsg, LogType.event);
        _showSuccess('강화 성공!', '+${item.enhanceLevel} 단계를 달성했습니다.');
        _checkEncyclopedia(item); // 강화 성공 시 도감 체크
      } else {
        _addLog(resultMsg, LogType.event);
        _showToast(resultMsg, isError: true);
      }
    });
    setDialogState(() {}); // 다이얼로그 UI 즉시 갱신
    _saveGameData(); // 강화 시도 후 결과 즉시 저장
  }

  void _summonPet(int count) {
    int cost = count == 1 ? 10000 : 90000;
    if (player.gold < cost) {
      _showToast('골드가 부족합니다!', isError: true);
      return;
    }

    setState(() {
      player.gold -= cost;
      List<Pet> allPets = PetData.getInitialPets();
      
      for (int i = 0; i < count; i++) {
        double rand = Random().nextDouble() * 100;
        Pet selected;
        int subIdx = Random().nextInt(5); // 각 등급별 5종 중 하나 선택

        if (rand < 0.05) {
          // 신화 (Mythic) - 0.05%
          selected = allPets[25 + subIdx];
        } else if (rand < 0.5) {
          // 유물 (Legendary) - 0.45%
          selected = allPets[20 + subIdx];
        } else if (rand < 3.0) {
          // 고대 (Epic) - 2.5%
          selected = allPets[15 + subIdx];
        } else if (rand < 10.0) {
          // 희귀 (Rare) - 7.0%
          selected = allPets[10 + subIdx];
        } else if (rand < 40.0) {
          // 고급 (Uncommon) - 30.0%
          selected = allPets[5 + subIdx];
        } else {
          // 일반 (Common) - 60.0%
          selected = allPets[0 + subIdx];
        }

        // 중복 체크 및 추가
        if (!player.pets.any((p) => p.id == selected.id)) {
          player.pets.add(selected);
          _addLog('펫 획득! [${selected.grade.name}] ${selected.name}', LogType.event);
        } else {
          // 이미 있으면 레벨업 처리
          player.pets.firstWhere((p) => p.id == selected.id).level++;
        }
      }

      
      _showSuccess('소환 완료', '${count}회의 소환을 완료했습니다.');
    });
  }


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
          _buildGlassContainer(
            padding: const EdgeInsets.all(32),
            borderRadius: 30,
            child: Column(
              children: [
                const Icon(Icons.settings, color: Colors.white60, size: 60),
                const SizedBox(height: 24),
                _buildShadowText('시스템 설정', fontSize: 24, fontWeight: FontWeight.bold),
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
                    child: _buildPopBtn(
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
                    child: _buildPopBtn(
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
                _buildPopBtn(
                  '관리자 모드', 
                  Colors.redAccent.withOpacity(0.8), 
                  _showAdminPasswordDialog,
                  icon: Icons.admin_panel_settings,
                ),
                const SizedBox(height: 16),
                // 🆕 클라우드 수동 동기화 버튼
                _buildPopBtn(
                  '클라우드 수동 동기화', 
                  Colors.blueAccent.withOpacity(0.8), 
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
                _buildPopBtn(
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
          Text('Version: 0.1.0 (Alpha Test)', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildAdminPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _buildGlassContainer(
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
                    _buildShadowText('관리자 테스트 도구', fontSize: 18, fontWeight: FontWeight.bold),
                  ],
                ),
                _buildPopBtn('인증 해제', Colors.white24, () => setState(() => _isAdminAuthenticated = false)),
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
                  onChanged: (val) => setState(() => _monsterDefenseMultiplier = val),
                ),
                const SizedBox(height: 30),
                _buildPopBtn('모든 재화 1억 추가', Colors.amber, () {
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
    return _buildGlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              _buildShadowText(_formatNumber(current), color: Colors.amberAccent, fontWeight: FontWeight.bold),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildPopBtn('+1만', Colors.white12, () => onAdd(10000)),
              _buildPopBtn('+10만', Colors.white12, () => onAdd(100000)),
              _buildPopBtn('+100만', Colors.white24, () => onAdd(1000000)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminSliderCard({required String label, required double value, required Function(double) onChanged}) {
    return _buildGlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      color: Colors.blueAccent.withOpacity(0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              _buildShadowText('${(value * 100).toInt()}%', color: Colors.cyanAccent, fontWeight: FontWeight.bold),
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
        title: _buildShadowText('관리자 인증', fontSize: 18, fontWeight: FontWeight.bold),
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
    return _PressableScale(
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
                    child: _ShimmerSheen(progress: _shimmerController.value),
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
                Center(child: _getItemIcon(item.type, size: size * 0.55)),
        
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
      _stageKills = 0;
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
        _stageKills = 0;
        _spawnMonster();
        _showToast('${_currentZone.name} 지역으로 복귀했습니다.', isError: false);
      });
    }
  }

  void _showOfflineRewardDialog(Map<String, dynamic> rewards) {
    int minutes = rewards['minutes'] as int;
    int hours = minutes ~/ 60;
    int mins = minutes % 60;
    String timeStr = hours > 0 ? '$hours시간 ${mins}분' : '$mins분';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        title: Row(
          children: [
            const Icon(Icons.bedtime, color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            Text(
              '방치 보상 ($timeStr)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '게임을 떠나 있는 동안 획득한 보상입니다!',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _buildOfflineRewardItem('💰', '골드', rewards['gold']),
              _buildOfflineRewardItem('⭐', '경험치', rewards['exp']),
              _buildOfflineRewardItem('⚔️', '처치 수', rewards['kills']),
              const Divider(color: Colors.white24, height: 24),
              const Text(
                '제작 재료',
                style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (rewards.containsKey('tierShards')) ...[
                ...((rewards['tierShards'] as Map<int, int>).entries.map((e) =>
                    _buildOfflineRewardItem('🧩', 'T${e.key} 파편', e.value)
                )),
              ],
              if (rewards.containsKey('powder'))
                _buildOfflineRewardItem('✨', '가루', rewards['powder']),
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
              player.applyOfflineRewards(rewards);
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
      builder: (dialogCtx) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: _buildGlassContainer(
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
                _buildShadowText(
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
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
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
                        child: _buildPopBtn(
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
                      child: _buildPopBtn(
                        isSuccess ? '포기' : '확인', 
                        isSuccess ? Colors.white12 : Colors.redAccent.withOpacity(0.2), 
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

enum LogType { damage, item, event }
enum LootType { gold, exp }
class CombatLogEntry { final String message; final LogType type; final DateTime time; CombatLogEntry(this.message, this.type, this.time); }
enum DamageType { normal, critical, skill, heal, gold, exp }

/// 🆕 데미지 텍스트 데이터 모델
class DamageEntry {
  final String text;
  final double value;
  final bool isMonsterTarget;
  final DateTime createdAt;
  final DamageType type;
  final Offset basePosition;
  
  DamageEntry({
    required this.text,
    required this.value,
    required this.isMonsterTarget,
    required this.createdAt,
    required this.type,
    required this.basePosition,
  });
}

/// 🆕 데미지 텍스트 생명주기 관리 매니저
class DamageManager {
  final List<DamageEntry> texts = [];
  
  void add(DamageEntry entry) {
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
      double opacity = 1.0;
      double offsetY = 0.0;

      // 1단계: 0~0.16s (0~20%) - Bounce Bounce (튀어오름)
      if (progress <= 0.2) {
        final p = progress / 0.2; // 0.0 ~ 1.0
        scale = 0.5 + (0.7 * p); // 0.5 -> 1.2
        opacity = p; // 0.0 -> 1.0
        offsetY = -25 * p; // 0 -> -25px
      } 
      // 2단계: 0.16~0.8s (20~100%) - ScaleDown & Rise & Fade (부드러운 소멸)
      else {
        final p = (progress - 0.2) / 0.8; // 0.0 ~ 1.0
        scale = 1.2 - (0.2 * p); // 1.2 -> 1.0
        opacity = 1.0 - p; // 1.0 -> 0.0
        offsetY = -25 - (75 * p); // -25 -> -100px
      }

      // 최종 좌표 계산 (basePosition + 애니메이션 오프셋)
      final position = ft.basePosition + Offset(0, offsetY);

      // 텍스트 스타일 설정 (FontWeight.w800 적용으로 웅장함 강조)
      TextStyle style = _getTextStyle(ft.type, opacity);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: ft.text, 
          style: style,
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      
      textPainter.layout();

      // 2. 텍스트 바디 렌더링
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.scale(scale);
      
      // 메인 텍스트 그리기 (TextStyle 내의 Shadow로 충분하므로 중복 그림자 제거)
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();
    }
  }

  TextStyle _getTextStyle(DamageType type, double opacity) {
    Color color;
    double fontSize;
    
    switch (type) {
      case DamageType.critical:
        color = const Color(0xFFEF4444); // 더 강렬한 빨간색
        fontSize = 22;
        break;
      case DamageType.skill:
        color = const Color(0xFFF97316);
        fontSize = 22;
        break;
      case DamageType.heal:
        color = const Color(0xFF22C55E);
        fontSize = 18;
        break;
      case DamageType.gold:
        color = const Color(0xFFEAB308);
        fontSize = 17;
        break;
      case DamageType.exp:
        color = const Color(0xFF3B82F6);
        fontSize = 17;
        break;
      case DamageType.normal:
      default:
        color = Colors.white;
        fontSize = 18;
    }

    return GoogleFonts.luckiestGuy(
      color: color.withOpacity(opacity),
      fontSize: fontSize,
      letterSpacing: 0.5,
      shadows: [
        Shadow(
          blurRadius: 4.0,
          color: Colors.black.withOpacity(opacity * 0.5),
          offset: const Offset(1.5, 1.5),
        ),
      ],
    );
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
        
        // 목적지 근처에서 더 강력하게 끌려가는 자석 효과 (Exponential)
        double magnetT = Curves.easeInQuint.transform(subT);
        
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
                    colors: [Colors.amber.withOpacity(0.9), Colors.orange.withOpacity(0.9)],
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

/// 수치 변화 애니메이션 위젯 (Count-up)
class _AnimatedCountText extends StatefulWidget {
  final int count;
  final TextStyle style;
  final String suffix;

  const _AnimatedCountText({
    required this.count,
    required this.style,
    this.suffix = '',
  });

  @override
  State<_AnimatedCountText> createState() => _AnimatedCountTextState();
}

class _AnimatedCountTextState extends State<_AnimatedCountText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.count;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = Tween<double>(begin: _currentValue.toDouble(), end: widget.count.toDouble()).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo),
    );
  }

  @override
  void didUpdateWidget(_AnimatedCountText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _animation = Tween<double>(
        begin: _currentValue.toDouble(),
        end: widget.count.toDouble(),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        _currentValue = _animation.value.toInt();
        return Text(
          '${_formatNumber(_currentValue)}${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }
}

/// 클릭 시 크기 변화 애니메이션 위젯 (Press Scale)
class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PressableScale({required this.child, this.onTap});

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // 터치 영역 확장
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) {
        _controller.forward();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

// --- 쉬머 광택 효과 위젯 ---
// --- 쉬머 광택 효과 위젯 ---
class _ShimmerSheen extends StatelessWidget {
  final double progress;
  const _ShimmerSheen({required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // -1.5 ~ 2.5 범위로 이동하여 자연스러운 순환 구현
        final double slide = (progress * 4) - 2;
        
        return Transform.translate(
          offset: Offset(w * slide, h * slide),
          child: Transform.rotate(
            angle: pi / 4,
            child: Container(
              width: w * 0.4,
              height: h * 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0),
                    Colors.white.withOpacity(0.4),
                    Colors.white.withOpacity(0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


// --- 화면 모드 관리 (일반 / 화면유지 / 절전) ---
enum DisplayMode { normal, stayAwake, powerSave }
