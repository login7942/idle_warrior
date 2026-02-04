import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player.dart';
import '../models/monster.dart';
import '../models/item.dart';
import '../models/skill.dart';
import '../models/hunting_zone.dart';
import '../models/pet.dart';
import '../models/achievement.dart';
import '../models/quest.dart';
import '../models/npc.dart';
import '../services/auth_service.dart';
import '../models/pvp_snapshot.dart';
import '../services/pvp_manager.dart';

import '../services/cloud_save_service.dart';

enum LogType { damage, item, event }

/// 🆕 앱 초기화 상태
enum AppInitializationState {
  initializing, // 초기화 중
  needsLogin,    // 로그인 필요 (신규 또는 로그아웃 상태)
  loadingData,   // 데이터 로드 중 (클라우드/로컬)
  ready          // 준비 완료 (게임 시작 가능)
}

class CombatLogEntry {
  final String message;
  final LogType type;
  final DateTime time;

  CombatLogEntry(this.message, this.type) : time = DateTime.now();
}

class PendingHit {
  final int damage;
  final bool isSkill;
  final double offsetX;
  final double offsetY;
  final DateTime scheduledTime;
  final bool shouldAnimate;
  final String? skillIcon; // 🆕 스킬 아이콘(이모지) 저장
  final int? combo; // 🆕 콤보 정보 저장

  PendingHit({
    required this.damage,
    required this.isSkill,
    required this.offsetX,
    required this.offsetY,
    required this.scheduledTime,
    this.shouldAnimate = true,
    this.skillIcon,
    this.combo, // 🆕 콤보 정보 추가
  });
}

class GameState extends ChangeNotifier {
  // 🆕 배치 업데이트 제어용 플래그
  bool _suppressNotify = false;
  bool _needsNotify = false;

  @override
  void notifyListeners() {
    if (_suppressNotify) {
      _needsNotify = true;
    } else {
      super.notifyListeners();
    }
  }

  /// 🆕 프레임당 단 1번의 notifyListeners()를 보장하기 위한 배치 업데이트 시작
  void beginBatchUpdate() {
    _suppressNotify = true;
    _needsNotify = false;
  }

  /// 🆕 배치 업데이트 종료 및 변경 사항이 있을 경우 UI 갱신 트리거
  void endBatchUpdate() {
    _suppressNotify = false;
    if (_needsNotify) {
      notifyListeners();
      _needsNotify = false;
    }
  }

  // --- 서비스 레이어 ---
  final AuthService authService = AuthService();
  final CloudSaveService _cloudSaveService = CloudSaveService();
  final PvPManager pvpManager = PvPManager(); // 🆕 PvP 매니저 인스턴스 추가

  // --- 플레이어 및 전투 상태 ---
  Player player = Player();
  int _playerCurrentHp = 0;
  int get playerCurrentHp => _playerCurrentHp;
  set playerCurrentHp(int val) {
    if (_playerCurrentHp == val) return;
    _playerCurrentHp = val;
    notifyListeners();
  }

  int _playerShield = 0; // [v2.0] 보호막 시스템 추가
  int get playerShield => _playerShield;
  set playerShield(int val) {
    if (_playerShield == val) return;
    _playerShield = val;
    notifyListeners();
  }

  // 🆕 앱 초기화 상태 관리
  AppInitializationState _initState = AppInitializationState.initializing;
  AppInitializationState get initState => _initState;

  void _updateInitState(AppInitializationState newState) {
    if (_initState == newState) return;
    _initState = newState;
    debugPrint('[GameState] InitState 변경: $newState');
    notifyListeners();
  }

  // 🆕 게스트 모드로 시작 (로컬 데이터 로드)
  Future<void> startAsGuest() async {
    _updateInitState(AppInitializationState.loadingData);
    await loadGameData();
  }

  // 🆕 구글 로그인 시작
  Future<void> startWithGoogle() async {
    final success = await authService.signInWithGoogle();
    if (!success) {
      _updateInitState(AppInitializationState.needsLogin);
    }
    // 성공 시 Auth 리스너가 감감지하여 loadGameData를 호출함
  }

  Monster? currentMonster;
  int _monsterCurrentHp = 0;
  int get monsterCurrentHp => _monsterCurrentHp;
  set monsterCurrentHp(int val) {
    if (_monsterCurrentHp == val) return;
    _monsterCurrentHp = val;
    notifyListeners();
  }
  
  // --- 진행 데이터 ---
  int _currentStage = 1;
  int get currentStage => _currentStage;
  set currentStage(int val) {
    _currentStage = val;
    notifyListeners();
  }

  HuntingZone _currentZone = HuntingZoneData.list[0];
  HuntingZone get currentZone => _currentZone;
  set currentZone(HuntingZone val) {
    bool isChanged = _currentZone.id != val.id;
    _currentZone = val;
    
    // [v2.0] 지역 이동 시 공격력/방어력 버프 발동
    if (isChanged) {
      if (player.zoneAtkBonus > 0) {
        player.zoneAtkBuffEndTime = DateTime.now().add(const Duration(seconds: 30));
        addLog('⚔️ 지역 효과: 공격력이 일시적으로 상승합니다!', LogType.event);
      }
      if (player.zoneDefBonus > 0) {
        player.zoneDefBuffEndTime = DateTime.now().add(const Duration(seconds: 30));
        addLog('🛡️ 지역 효과: 방어력이 일시적으로 상승합니다!', LogType.event);
      }
    }
    
    notifyListeners();
  }

  final Map<ZoneId, int> zoneStages = { for (var v in ZoneId.values) v : 1 };
  
  bool autoAdvance = true;
  int _stageKills = 0;
  int get stageKills => _stageKills;
  set stageKills(int val) {
    _stageKills = val;
    notifyListeners();
  }
  final int targetKills = 10;
  
  // --- 효율 데이터 ---
  double goldPerMin = 0;
  double expPerMin = 0;
  double killsPerMin = 0;
  double dmgPerMin = 0;

  void updateEfficiency(double gold, double exp, double kills, double dmg) {
    goldPerMin = gold;
    expPerMin = exp;
    killsPerMin = kills;
    dmgPerMin = dmg;
    notifyListeners();
  }

  void resetEfficiency() {
    goldPerMin = 0;
    expPerMin = 0;
    killsPerMin = 0;
    dmgPerMin = 0;
    notifyListeners();
  }

  int autoDismantleGrade = -1; // -1: 사용안함, 0: 일반, 1: 고급, 2: 희귀, 3: 영웅, 4: 고유, 5: 전설
  int autoDismantleTier = -1;  // -1: 사용안함, 1: T1, 2: T2, 3: T3, 4: T4, 5: T5, 6: T6
  
  // --- 관리자 설정 ---
  double monsterDefenseMultiplier = 0.0; // 몬스터 방어력 배율 (0.0 ~ 1.0)

  // --- 전투 로그 ---
  List<CombatLogEntry> logs = [];
  final int maxLogs = 50;

  // --- 시스템 상태 ---
  bool isProcessingVictory = false;
  bool isCloudSynced = false;
  bool isDataLoaded = false; // 🆕 데이터가 완전히 로드되었는지 여부
  DateTime? lastCloudSaveTime;
  StreamSubscription<AuthState>? _authSubscription; // 🆕 인증 상태 구독
  
  // --- 무투회(토너먼트) 상태 (v2.2) ---
  List<TournamentNPC> tournamentNPCs = [];
  int tournamentRound = 0; // 0: 대기, 1: 16강, 2: 8강, 3: 4강, 4: 결승, 5: 종료
  TournamentNPC? currentOpponent;
  bool isArenaMode = false; 

  // --- PvP 랭킹 시스템 (v2.7.4) ---
  bool isPvPMode = false;
  double _pvpCountdown = 0.0;
  double get pvpCountdown => _pvpCountdown;
  PvPSnapshot? defenderSnapshot;
  int _defenderCurrentHp = 0;
  int get defenderCurrentHp => _defenderCurrentHp;
  set defenderCurrentHp(int val) {
    if (_defenderCurrentHp == val) return;
    _defenderCurrentHp = val;
    notifyListeners();
  }
  int _defenderShield = 0;
  int get defenderShield => _defenderShield;
  set defenderShield(int val) {
    if (_defenderShield == val) return;
    _defenderShield = val;
    notifyListeners();
  }
  DateTime? lastDefenderAttackTime;
  int _defenderSkillIndex = 0;
  int _defenderNormalCombo = 0;

  List<bool> tournamentResults = []; // 승패 기록
  DateTime? lastMonsterSpawnTime;
  int _skillRoundRobinIndex = 0;
  int _normalAttackCombo = 0; // 🆕 일반 공격 콤보 단계 (0~3)
  
  // --- 애니메이션 전용 상태 (Shared Animation States) ---
  double _shimmerProgress = 0.0;
  double get shimmerProgress => _shimmerProgress;
  double _heroPulse = 1.0;
  double get heroPulse => _heroPulse;
  double _heroRotate = 0.0;
  double get heroRotate => _heroRotate;
  double _animTimeTotal = 0.0;
  
  // 🆕 연타 스킬 처리용 큐
  final Queue<PendingHit> pendingHits = Queue<PendingHit>();
  
  // 🆕 몬스터 소환 대기 플래그 (GameLoop에서 접근)
  bool pendingMonsterSpawn = false;
  DateTime? monsterSpawnScheduledTime;
  
  
  // --- [최적화] 배치 저장용 ---
  int _victoryCountSinceSave = 0;
  Timer? _autoSaveTimer;
  Timer? _specialDungeonTimer; // 🆕 특별 던전 타이머
  double _specialDungeonTimeLeft = 0; // 🆕 남은 시간 (초)
  double _skillDmgReductionTimeLeft = 0; // 🆕 [v2.0] 스킬 사용 후 피해 감소 남은 시간 (초)
  double _scorchedGroundTimeLeft = 0; // 🆕 화염구 지면 연소 남은 시간 (초)
  int _burnDmgPerTick = 0; // 연소 틱당 데미지
  double _burnAccumulator = 0; // 연소 틱 주기용 누적기
  double _defenderSkillDmgReductionTimeLeft = 0; // 🆕 PvP 방어자의 피해 감소 남은 시간
  double _defenderStunTimeLeft = 0;     // 🆕 방어자 기절 남은 시간
  double _defenderFrozenTimeLeft = 0;   // 🆕 방어자 빙결 남은 시간
  double _defenderJudgmentTimeLeft = 0; // 🆕 방어자 심판(방무) 남은 시간
  
  // 🆕 플레이어 상태 이상 (PvP 등에서 피격 시 사용)
  double _playerStunTimeLeft = 0;
  double _playerFrozenTimeLeft = 0;
  double _playerJudgmentTimeLeft = 0;
  double _playerBurnTimeLeft = 0; // 화염구 등에 의한 도트 데미지 상태

  bool get isDefenderStunned => _defenderStunTimeLeft > 0;
  bool get isDefenderFrozen => _defenderFrozenTimeLeft > 0;
  bool get isDefenderJudged => _defenderJudgmentTimeLeft > 0;

  bool get isPlayerStunned => _playerStunTimeLeft > 0;
  bool get isPlayerFrozen => _playerFrozenTimeLeft > 0;
  bool get isPlayerJudged => _playerJudgmentTimeLeft > 0;
  bool get isPlayerBurned => _playerBurnTimeLeft > 0;

  // 🆕 [v2.4.3] 통합 애니메이션 시스템 (AnimationController 대체)
  bool _pulseExpanding = true;

  // [v2.0] 신규 버프 타이머 변수들
  double _killAtkBuffTimeLeft = 0.0;
  double _killDefBuffTimeLeft = 0.0;
  double _zoneAtkBuffTimeLeft = 0.0;
  double _zoneDefBuffTimeLeft = 0.0;

  // [v2.0] 개별 버프가 활성화되어 있는지 확인하는 게터들
  bool get isSkillDmgReductionActive => _skillDmgReductionTimeLeft > 0;
  bool get isKillAtkBuffActive => _killAtkBuffTimeLeft > 0;
  bool get isKillDefBuffActive => _killDefBuffTimeLeft > 0;
  bool get isZoneAtkBuffActive => _zoneAtkBuffTimeLeft > 0;
  bool get isZoneDefBuffActive => _zoneDefBuffTimeLeft > 0;
  
  double get skillDmgReductionTimeLeft => _skillDmgReductionTimeLeft;
  double get killAtkBuffTimeLeft => _killAtkBuffTimeLeft;
  double get killDefBuffTimeLeft => _killDefBuffTimeLeft;
  double get zoneAtkBuffTimeLeft => _zoneAtkBuffTimeLeft;
  double get zoneDefBuffTimeLeft => _zoneDefBuffTimeLeft;

  double get specialDungeonTimeLeft => _specialDungeonTimeLeft;
  bool get isInSpecialDungeon => _specialDungeonTimeLeft > 0;
  bool get isScorchedGroundActive => _scorchedGroundTimeLeft > 0;
  double get scorchedGroundTimeLeft => _scorchedGroundTimeLeft;
  
  // --- UI 통신용 콜백 ---
  // --- UI 통신용 콜백 ---
  Function(String text, int damage, bool isCrit, bool isSkill, {bool isPlayerTarget, double? ox, double? oy, bool shouldAnimate, String? skillIcon, int? combo})? onDamageDealt;
  Function(int damage, {bool isShield, bool shouldAnimate})? onPlayerDamageTaken;
  Function(String imagePath)? onMonsterSpawned; // 🆕 몬스터 소환 콜백 (프리캐싱용)
  void Function(int gold, int exp)? onVictory;
  void Function(bool isVictory, int scoreChange)? onPvPResult; // 🆕 PvP 결과 알림용 콜백
  void Function(bool win)? onPvPDeath; // 🆕 HP 0 도달 시 즉시 호출되는 사망 연출용 콜백
  VoidCallback? onStageCleared;
  Function(int healAmount, {bool isPlayerTarget})? onHeal;
  VoidCallback? onStageJump; // [v0.0.79] 스테이지 점프 발생 시 호출
  Function(String title, String message)? onSpecialEvent; // 🆕 럭키 스트릭 등 특수 연출용
  Function(String icon, String name, ItemGrade grade, {int amount})? onLootAcquired; // 🆕 아이콘 기반 알림용
  VoidCallback? onPlayerDeath; // 🆕 사망 연출 및 팝업용
  Function(int level, String name, String bonus)? onPromotionSuccess; // 🆕 [v0.5.27] 승급 성공 전용 콜백
  Function(Item item, int oldTier, int oldStat1, int? oldStat2)? onItemPromotionSuccess; // 🆕 [v0.5.58] 아이템 승급 성공 콜백
  VoidCallback? onSpecialDungeonEnd; // 🆕 특별 던전 종료 콜백


  // 🆕 [v0.5.26] 승급 로직
  void promote() {
    int totalLv = player.totalSlotEnhanceLevel;
    int nextLevel = player.promotionLevel + 1;
    
    if (nextLevel < Player.promotionSteps.length) {
      int req = Player.promotionSteps[nextLevel]['req'];
      if (totalLv >= req) {
        player.promotionLevel = nextLevel;
        final step = Player.promotionSteps[nextLevel];
        onPromotionSuccess?.call(nextLevel, step['name'], step['bonus']);
        
        // 🆕 [v0.5.58] 퀘스트 체크: 캐릭터 승급
        checkQuestProgress(QuestType.promotion, player.promotionLevel);
        
        saveGameData(forceCloud: true);
        notifyListeners();

      } else {
        onSpecialEvent?.call('승급 불가', '슬롯 강화 총합이 부족합니다. (필요: $req)');
      }
    } else {
      onSpecialEvent?.call('최고 단계', '이미 최고 단계에 도달하셨습니다.');
    }
  }

  // 🆕 초기화 완료 여부 확인용
  final Completer<void> initializationCompleter = Completer<void>();
  Future<void> get initialized => initializationCompleter.future;

  // 🆕 [v0.3.6] 적정 강화 구간 보너스 판정
  bool get isOptimalZone {
    int totalLv = player.totalSlotEnhanceLevel;
    return totalLv >= currentZone.minEnhance && totalLv <= currentZone.maxEnhance;
  }

  // 🆕 [v0.8.10] 업그레이드 가능한 스킬이 있는지 확인
  bool get isAnySkillUpgradeable {
    return player.skills.any((s) => 
      player.level >= s.unlockLevel && 
      player.gold >= s.upgradeCost && 
      s.level < s.maxLevel
    );
  }

  // 🆕 [v0.8.36] 보스 광폭화 등에 따른 공격 주기 가변 적용
  double get monsterAttackInterval {
    if (currentMonster != null && currentMonster!.isBoss) {
      double hpPerc = (currentMonster!.hp / currentMonster!.maxHp);
      if (hpPerc < 0.5) return 1.0; // 보스 체력 50% 미만 시 1.0초로 단축
    }
    return 1.5;
  }

  // --- 초기화 ---
  GameState() {
    _initializeGame();
    // 🆕 10초마다 자동 저장 타이머 시작
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      // 🆕 데이터가 로드된 상태에서만 자동 저장을 시도하여 데이터 유실 방지
      if (_victoryCountSinceSave > 0 && isDataLoaded) {
        saveGameData(); 
      }
    });

    // 🆕 인증 상태 변경 감지 리스너 추가
    _authSubscription = authService.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.tokenRefreshed) {
        debugPrint('[Auth] 로그인 또는 세션 갱신 감지됨: ${data.session?.user.id}');
        if (_initState == AppInitializationState.needsLogin) {
          _updateInitState(AppInitializationState.loadingData);
        }
        loadGameData(); // 로그인 시 클라우드 데이터를 즉시 동기화
      } else if (event == AuthChangeEvent.signedOut) {
        _updateInitState(AppInitializationState.needsLogin);
        isDataLoaded = false;
        isCloudSynced = false;
        notifyListeners();
      }
    });
  }

  /// 🆕 통합 로그아웃 처리
  Future<void> signOut() async {
    try {
      await authService.signOut();
      
      // 상태 명시적 초기화 (리스너에서도 처리되지만 즉각 반응을 위해)
      _initState = AppInitializationState.needsLogin;
      isDataLoaded = false;
      isCloudSynced = false;
      lastCloudSaveTime = null;

      // 게임 플레이 데이터 초기화
      player = Player();
      _playerCurrentHp = 0;
      currentMonster = null;
      _monsterCurrentHp = 0;
      currentStage = 1;
      stageKills = 0;
      
      // 지역 스테이지 초기화
      zoneStages.clear();
      for (var v in ZoneId.values) {
        zoneStages[v] = 1;
      }
      _currentZone = HuntingZoneData.list[0];

      // 로컬 세이브 데이터 삭제
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('player_save_data');
      await prefs.remove('current_stage');
      await prefs.remove('current_zone_id');
      await prefs.remove('zone_stages');
      await prefs.remove('lastSaveTime');

      debugPrint('[GameState] 로그아웃 및 데이터 초기화 완료');
      notifyListeners();
    } catch (e) {
      debugPrint('[GameState] 로그아웃 중 에러: $e');
    }
  }

  /// 🆕 캐릭터 이름 변경 및 저장
  void updatePlayerName(String newName) {
    if (newName.isEmpty) return;
    player.name = newName;
    
    // 🆕 퀘스트 체크: 이름 변경
    checkQuestProgress(QuestType.changeName, 1);
    
    saveGameData(forceCloud: true); // 즉시 저장 반영
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _specialDungeonTimer?.cancel();
    _authSubscription?.cancel(); // 🆕 구독 해제
    super.dispose();
  }

  Future<void> _initializeGame() async {
    _updateInitState(AppInitializationState.initializing);
    try {
      // 🆕 세션 확인 및 초기화 흐름 제어
      if (authService.isLoggedIn) {
        _updateInitState(AppInitializationState.loadingData);
        await loadGameData();
      } else {
        _updateInitState(AppInitializationState.needsLogin);
      }
    } catch (e) {
      debugPrint('초기화 중 오류 발생: $e');
      _updateInitState(AppInitializationState.needsLogin);
    } finally {
      if (!initializationCompleter.isCompleted) {
        initializationCompleter.complete();
      }
    }
  }

  // --- [v2.3.6] 환생 관련 로직 ---
  int get reincarnationPointsEarned => max(0, player.level - 200);

  Future<void> executeReincarnation() async {
    if (player.level < 200) return;

    final points = reincarnationPointsEarned;
    
    // 1. 환생 데이터 업데이트
    player.reincarnation.reincarnationCount++;
    player.reincarnation.points += points;
    player.reincarnation.totalPointsEarned += points;

    // 2. 캐릭터 초기화
    player.level = 1;
    player.exp = 0;
    player.maxExp = 100;
    player.gold = 0;

    // 3. 스테이지 초기화 (전체 사냥터 개방 상태는 유지되나 도달 층수는 1로 초기화)
    currentStage = 1;
    stageKills = 0;
    zoneStages.forEach((id, _) => zoneStages[id] = 1);
    
    // 4. 상태 초기화
    _playerCurrentHp = player.maxHp;
    _monsterCurrentHp = 0;
    currentMonster = null;
    isProcessingVictory = false;

    // 5. 저장 및 알림
    await saveGameData(forceCloud: true);
    addLog('✨ 환생 성공! 원래의 자리로 돌아가 새로운 힘을 얻었습니다. (+$points 포인트)', LogType.event);
    
    notifyListeners();
  }

  void upgradeReincarnationPerk(String perkId) {
    if (player.reincarnation.points <= 0) return;
    
    try {
      final perk = player.reincarnation.perks.firstWhere((p) => p.id == perkId);
      perk.level++;
      player.reincarnation.points--;
      
      saveGameData();
      notifyListeners();
    } catch (_) {}
  }

  // --- 데이터 관리 ---
  Future<void> saveGameData({bool forceCloud = false}) async {
    if (!isDataLoaded) return; // 🆕 데이터 로드 전 저장을 방지하여 유실 예방
    
    final nowTime = DateTime.now();
    final nowStr = nowTime.toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    
    final saveData = {
      'player': player.toJson(),
      'current_stage': currentStage,
      'current_zone_id': currentZone.id.name,
      'last_save_time': nowStr,
      'zone_stages': zoneStages.map((k, v) => MapEntry(k.name, v)),
      'autoAdvance': autoAdvance, // 🆕 자동 진행 상태 저장
      'gold_per_min': goldPerMin,
      'exp_per_min': expPerMin,
      'kills_per_min': killsPerMin,
      'autoDismantleGrade': autoDismantleGrade,
      'autoDismantleTier': autoDismantleTier,
    };

    await prefs.setString('player_save_data', jsonEncode(saveData['player']));
    await prefs.setInt('current_stage', currentStage);
    await prefs.setString('current_zone_id', currentZone.id.name);
    await prefs.setString('lastSaveTime', nowStr);
    await prefs.setDouble('gold_per_min', goldPerMin);
    await prefs.setDouble('exp_per_min', expPerMin);
    await prefs.setDouble('kills_per_min', killsPerMin);
    await prefs.setInt('autoDismantleGrade', autoDismantleGrade);
    await prefs.setInt('autoDismantleTier', autoDismantleTier);
    await prefs.setBool('autoAdvance', autoAdvance); // 🆕 자동 진행 상태 저장
    await prefs.setString('zone_stages', jsonEncode(zoneStages.map((k, v) => MapEntry(k.name, v))));
    
    if (authService.isLoggedIn) {
      final bool shouldSaveToCloud = forceCloud || 
          lastCloudSaveTime == null || 
          nowTime.difference(lastCloudSaveTime!).inSeconds >= 300; // 300초 (5분)

      if (shouldSaveToCloud) {
        lastCloudSaveTime = nowTime;
        final success = await _cloudSaveService.saveToCloud(saveData);
        isCloudSynced = success;
        notifyListeners();
      }
    }
  }

  Future<void> loadGameData() async {
    final prefs = await SharedPreferences.getInstance();
    String? localData = prefs.getString('player_save_data');
    String? localTime = prefs.getString('lastSaveTime');
    
    Map<String, dynamic>? cloudDataMap;
    String? cloudTime;

    if (authService.isLoggedIn) {
      final cloudSave = await _cloudSaveService.loadFromCloud();
      if (cloudSave != null) {
        cloudDataMap = cloudSave['data'] as Map<String, dynamic>;
        cloudTime = cloudSave['timestamp'] as String;
      }
    }

    Map<String, dynamic>? targetData;
    bool isFromCloud = false;

    if (cloudDataMap != null && _isCloudNewer(cloudTime, localTime)) {
      targetData = cloudDataMap;
      isFromCloud = true;
    } else if (localData != null) {
      // 로컬 데이터가 최신이거나 클라우드 데이터가 없는 경우
      targetData = {
        'player': jsonDecode(localData),
        'current_stage': prefs.getInt('current_stage') ?? 1,
        'current_zone_id': prefs.getString('current_zone_id'),
        'gold_per_min': prefs.getDouble('gold_per_min') ?? 0,
        'exp_per_min': prefs.getDouble('exp_per_min') ?? 0,
        'kills_per_min': prefs.getDouble('kills_per_min') ?? 0,
        'autoDismantleGrade': prefs.getInt('autoDismantleGrade') ?? -1,
        'autoDismantleTier': prefs.getInt('autoDismantleTier') ?? -1,
        'autoAdvance': prefs.getBool('autoAdvance') ?? true, // 🆕 자동 진행 상태 로드
        'zone_stages': jsonDecode(prefs.getString('zone_stages') ?? '{}'),
      };
    }

    if (targetData != null) {
      _applyLoadedData(targetData);
      isDataLoaded = true; // 🆕 로드 완료 표시
      if (isFromCloud) {
        addLog('클라우드에서 데이터를 불러왔습니다.', LogType.event);
        isCloudSynced = true;
      } else {
        isCloudSynced = cloudDataMap != null;
      }
    } else {
      // 🆕 데이터가 아예 없는 신규 유저의 경우에만 익명 로그인을 제안하거나 최소 데이터 생성
      _initializeStarterData();
      isDataLoaded = true; 
    }

    // 데이터 로드 후 첫 몬스터 생성
    spawnMonster();
    _updateInitState(AppInitializationState.ready); // 🆕 로드 완료 시 준비 상태로 변경
    notifyListeners();
  }

  void _applyLoadedData(Map<String, dynamic> targetData) {
    player = Player.fromJson(targetData['player']);
    playerCurrentHp = player.maxHp;
    currentStage = targetData['current_stage'] ?? 1;
    String? zoneName = targetData['current_zone_id'];
    if (zoneName != null) {
      currentZone = HuntingZoneData.list.firstWhere((z) => z.id.name == zoneName);
    }
    
    autoAdvance = targetData['autoAdvance'] ?? true; // 🆕 자동 진행 상태 로드
    if (targetData.containsKey('zone_stages')) {
      var zs = Map<String, dynamic>.from(targetData['zone_stages']);
      zs.forEach((k, v) {
        try {
          final zid = ZoneId.values.byName(k);
          zoneStages[zid] = v as int;
        } catch (_) {}
      });
    }

    goldPerMin = (targetData['gold_per_min'] ?? 0).toDouble();
    expPerMin = (targetData['exp_per_min'] ?? 0).toDouble();
    killsPerMin = (targetData['kills_per_min'] ?? 0).toDouble();
    autoDismantleGrade = targetData['autoDismantleGrade'] ?? -1;
    autoDismantleTier = targetData['autoDismantleTier'] ?? -1;
    
    isCloudSynced = true;
    notifyListeners();
  }

  void _initializeStarterData() {
    Item starterWeapon = Item(
      id: 'starter_${DateTime.now().millisecondsSinceEpoch}',
      name: '모험가의 목검',
      type: ItemType.weapon,
      grade: ItemGrade.common,
      tier: 1,
      mainStat1: 12,
      subOptions: [],
      enhanceLevel: 0,
      durability: 100,
      maxDurability: 100,
      isNew: false,
    );
    player.equipItem(starterWeapon);
    playerCurrentHp = player.maxHp;
    addLog('환영합니다! 모험을 시작하기 위해 [모험가의 목검]을 지급했습니다.', LogType.event);
    notifyListeners();
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

  // --- 전투 로직 ---
  // 🆕 [v2.2.1] 애니메이션 종료 후 전투 시작 허용
  void completeMonsterSpawn() {
    if (isProcessingVictory) {
      isProcessingVictory = false;
      notifyListeners();
    }
  }

  void spawnMonster() {
    // 🆕 [v2.2.1] 일반 사냥터인 경우 애니메이션 종료 콜백을 기다림
    // 무한의 탑이나 무투회는 기존처럼 즉시 전투 가능 상태로 변경
    if (currentZone.id == ZoneId.tower || isArenaMode) {
      isProcessingVictory = false;
    } else {
      isProcessingVictory = true; // 등장 애니메이션 동안 잠금
    }
    pendingMonsterSpawn = false; 

    if (isArenaMode) return; // 무투회 중에는 일반 몬스터 스폰 금지
    bool isFinal = (stageKills >= targetKills - 1);
    currentMonster = Monster.generate(currentZone, currentStage, isFinal: isFinal);
    monsterCurrentHp = currentMonster!.hp;
    lastMonsterSpawnTime = DateTime.now();
    
    // 🆕 [v2.4.7] 이미지 프리캐싱을 위해 경로 전달하며 콜백 호출
    onMonsterSpawned?.call(currentMonster!.imagePath);
    
    notifyListeners();
  }

  void processCombatTurn() {
    // 🆕 PvP 모드일 때는 몬스터가 없어도 진행 가능
    if ((currentMonster == null && !isPvPMode) || isProcessingVictory) return;

    // 🆕 플레이어 행동 불능 상태 체크 (PvP 등)
    if (isPlayerStunned || isPlayerFrozen) return;

    // [v2.0] 스킬 가용성 체크 시 공용 쿨감 + 특정 스킬 전용 쿨감 합산 적용
    final allActiveSkills = player.skills.where((s) => s.type == SkillType.active).toList();
    final activeSkills = allActiveSkills.where((s) => s.isUnlocked).toList();
    Skill? selectedSkill;

    if (activeSkills.isNotEmpty) {
      int startIndex = _skillRoundRobinIndex % activeSkills.length;
      for (int i = 0; i < activeSkills.length; i++) {
        int checkIdx = (startIndex + i) % activeSkills.length;
        final s = activeSkills[checkIdx];
        
        // 해당 스킬의 고유 번호 찾기 (1~6)
        int skillSlotIdx = allActiveSkills.indexOf(s) + 1;
        double totalCdrForSkill = player.cdr + player.getSpecificSkillCdr(skillSlotIdx);

        if (s.isReady(totalCdrForSkill)) {
          selectedSkill = s;
          _skillRoundRobinIndex = (checkIdx + 1) % activeSkills.length;
          break;
        }
      }
    }

    if (selectedSkill != null) {
      _useSkill(selectedSkill);
    } else {
      _performBasicAttack();
    }
  }

  void _performBasicAttack() {
    // 🆕 PvP 모드일 때는 몬스터가 없어도 공격 가능
    if (currentMonster == null && !isPvPMode) return;
    
    // 🆕 일반 공격 콤보 단계 증가 (1~4타 순환)
    _normalAttackCombo = (_normalAttackCombo % 4) + 1;
    
    // 콤보 단계별 데미지 배율 결정 (v0.5.26 승급 보너스 반영)
    double comboMultiplier;
    switch (_normalAttackCombo) {
      case 2: 
        comboMultiplier = 1.3; 
        if (player.promotionLevel >= 4) comboMultiplier *= 1.1; // 4단계: 1,2타 +10%
        break;
      case 3: 
        comboMultiplier = 1.7; 
        if (player.promotionLevel >= 5) comboMultiplier *= 1.1; // 5단계: 3타 +10%
        break;
      case 4: 
        comboMultiplier = 2.2; 
        if (player.promotionLevel >= 6) comboMultiplier *= 1.1; // 6단계: 4타 +10%
        break;
      default: 
        comboMultiplier = 1.0; // 1타
        if (player.promotionLevel >= 4) comboMultiplier *= 1.1; // 4단계: 1,2타 +10%
    }

    // 몬스터/방어자 방어력에 배율 적용 (관리자 설정)
    double effectiveDefense;
    if (isPvPMode) {
      effectiveDefense = isDefenderJudged ? 0 : defenderSnapshot!.defense.toDouble();
    } else {
      effectiveDefense = (currentMonster?.isJudged == true) ? 0 : (currentMonster!.defense * monsterDefenseMultiplier);
    }
    double defenseRating = 100 / (100 + effectiveDefense);
    double variance = 0.9 + (Random().nextDouble() * 0.2);
    
    // 콤보 배율 적용 (세트 효과: 최종 데미지 증폭 반영)
    double rawDamage = (player.attack * defenseRating) * variance * 
                       player.potentialFinalDamageMult * 
                       player.setFinalDamageMult * 
                       comboMultiplier;
    int baseDmg = max(rawDamage.toInt(), (player.attack * 0.1 * variance).toInt()).clamp(1, 999999999);

    // [v2.0] 2연타(Double Hit) 발동 여부 체크
    bool isDoubleHit = false;
    if (player.doubleHitChance > 0) {
      if (Random().nextDouble() * 100 < player.doubleHitChance) {
        isDoubleHit = true;
      }
    }
    
    // 통합된 데미지 처리 (2연타 여부 전달)
    if (isPvPMode) {
      damageDefender(baseDmg, false, false, combo: _normalAttackCombo, isDoubleHit: isDoubleHit);
    } else {
      damageMonster(baseDmg, false, false, combo: _normalAttackCombo, isDoubleHit: isDoubleHit);
    }
  }

  void damageDefender(int baseDmg, bool _, bool isSkill, {double? ox, double? oy, bool shouldAnimate = true, String? skillIcon, int? combo, bool isDoubleHit = false}) {
    if (!isPvPMode || defenderSnapshot == null || isProcessingVictory) {
      if (isProcessingVictory) debugPrint('[PvP] 승리 처리 중 방어자 타격 무시');
      return;
    }

    int finalDmg = baseDmg;
    bool isCrit = false;

    // 1. 치명타 확률 체크 및 데미지 계산
    if (Random().nextDouble() * 100 < player.critChance) {
      isCrit = true;
      finalDmg = (finalDmg * player.critDamage / 100).toInt();
    }

    // [v2.0] 치명타 시 스킬 쿨감 (50% 확률)
    if (isCrit && player.critCdrAmount > 0) {
      if (Random().nextDouble() < 0.5) {
        _reduceAllSkillCooldowns(player.critCdrAmount);
      }
    }

    // [v2.7.10] 2. 처형(Execute) 삭제 및 반사 데미지 전조 (반사는 피격 시 계산)
    bool isExec = false; // logic removed

    // 3. 2연타 처리 (데미지 직접 가산 대신 추가 타격 예약으로 대체하여 중복 방지)
    int displayDmg = finalDmg;
    // [v2.0.1] 2연타 시 실데미지를 여기서 2배로 하지 않고, 아래 pendingHits에서 분산 처리함

    // 4. 보호막 처리
    int remainingDmg = finalDmg;
    if (defenderShield > 0) {
      if (defenderShield >= remainingDmg) {
        defenderShield -= remainingDmg;
        remainingDmg = 0;
      } else {
        remainingDmg -= defenderShield;
        defenderShield = 0;
      }
    }

    // 5. 실제 HP 차감
    int actualHpLoss = remainingDmg;
    defenderCurrentHp = (defenderCurrentHp - actualHpLoss).clamp(0, defenderSnapshot!.maxHp);

    // [v2.7.7] lethal damage 시 즉시 승격 처리 (회복으로 인한 불사 방지)
    if (defenderCurrentHp <= 0) {
      debugPrint('[PvP] 상대방 HP 0 도달! 승리 처리 시작');
      _processPvPVictory();
      return;
    }

    // 6. 방어자의 피격 시 회복(Recover on Damaged) 처리
    if (actualHpLoss > 0 && defenderSnapshot!.recoverOnDamagedPerc > 0 && defenderCurrentHp > 0) {
      int recoverAmt = (actualHpLoss * defenderSnapshot!.recoverOnDamagedPerc / 100).toInt();
      if (recoverAmt > 0) {
        defenderCurrentHp = (defenderCurrentHp + recoverAmt).clamp(0, defenderSnapshot!.maxHp);
      }
    }

    // 7. UI 알림 (Floating Text)
    String text = (isDoubleHit ? '-${displayDmg} X2' : '-$displayDmg');
    onDamageDealt?.call(text, finalDmg, isCrit, isSkill, 
      isPlayerTarget: false, // 적군(방어자)이 맞음
      skillIcon: skillIcon, 
      combo: combo
    );

    // 🆕 7.5 방어자의 가시(Reflect) 효과 처리
    if (actualHpLoss > 0 && defenderSnapshot!.reflectPerc > 0) {
      int reflectDmg = (actualHpLoss * defenderSnapshot!.reflectPerc / 100).toInt();
      if (reflectDmg > 0) {
        _playerTakePvPDamage(reflectDmg, isSkill: false, skillIcon: '🌵', shouldAnimate: false); // 🌵 반사 데미지는 애니메이션 제외
        addLog('🌵 상대의 가시! ${reflectDmg}의 피해를 반사당했습니다.', LogType.damage);
      }
    }

    // 8. 흡혈 처리
    if (player.lifesteal > 0 && playerCurrentHp < player.maxHp) {
      int lifestealAmt = (finalDmg * player.lifesteal / 100).toInt();
      if (lifestealAmt > 0) {
        playerCurrentHp = (playerCurrentHp + lifestealAmt).clamp(0, player.maxHp);
        onHeal?.call(lifestealAmt, isPlayerTarget: true);
      }
    }

    // 9. 공격 시 보호막 생성 발동 체크
    if (player.gainShieldChance > 0) {
      if (Random().nextDouble() * 100 < player.gainShieldChance) {
        int shieldAmt = (player.maxHp * 0.05).toInt();
        playerShield = (playerShield + shieldAmt).clamp(0, player.maxHp);
        onHeal?.call(shieldAmt); 
      }
    }

    // 10. 2연타 발동 시 0.1초 뒤 추가 타격 예약
    if (isDoubleHit && !isExec) {
      pendingHits.add(PendingHit(
        damage: (displayDmg * 0.7).toInt(), // 2타는 70% 위력
        isSkill: isSkill,
        offsetX: (ox ?? 50) + (Random().nextDouble() * 20 - 10),
        offsetY: (oy ?? -50) + (Random().nextDouble() * 20 - 10),
        scheduledTime: DateTime.now().add(const Duration(milliseconds: 100)),
        skillIcon: skillIcon,
      ));
    }

    if (defenderCurrentHp <= 0) {
      debugPrint('[PvP] 상대방 HP 0 도달! 승리 처리 시작');
      _processPvPVictory();
    }
  }

  void _useSkill(Skill skill) {
    // 🆕 PvP 모드일 때는 몬스터가 없어도 스킬 사용 가능
    if (currentMonster == null && !isPvPMode) return;
    skill.lastUsed = DateTime.now();
    player.totalSkillsUsed++;

    // [v2.0] 스킬 사용 시 피해 감소 발동 체크 (수치는 확률(%)로 작동, 고정 20% 감소, 3초 지속)
    if (player.dmgReductionOnSkill > 0) {
      if (Random().nextDouble() * 100 < player.dmgReductionOnSkill) {
        _skillDmgReductionTimeLeft = 3.0;
        addLog('🛡️ 스킬 효과: 피해 감소 버프 활성화! (3초)', LogType.event);
      }
    }
    
    // 🆕 스킬 사용 시 일반 공격 콤보 초기화
    _normalAttackCombo = 0;

    // [v2.2] 스킬 잔향(Skill Echo) 발동 체크
    bool isEchoed = false;
    if (player.skillEchoChance > 0) {
      if (Random().nextDouble() * 100 < player.skillEchoChance) {
        isEchoed = true;
      }
    }

    // 스킬별 기본 타격 횟수 정의
    int baseHits = 1;
    if (skill.id == 'act_1') baseHits = 3; // 바람 베기는 3연타
    if (skill.id == 'act_1_5') baseHits = 2; // 🆕 쌍룡참은 2연타

    // 잔향 발동 시 타격 횟수 2배
    int totalHits = isEchoed ? baseHits * 2 : baseHits;
    if (isEchoed) {
      addLog('✨ 스킬 추가 발동: ${skill.name}이(가) 한 번 더 발동됩니다!', LogType.event);
    }

    // [v2.3.0] 스킬별 특수 효과(Proc) 발동 체크 (20% 확률 + 환생 보너스)
    final rand = Random();
    final double procChance = 0.2 + (player.reincarnation.getBonus('skill_proc') / 100);

    if (skill.id == 'act_1' && rand.nextDouble() < procChance) {
      player.skillAtkSpdBuffEndTime = DateTime.now().add(const Duration(seconds: 2));
      addLog('🌪️ 바람베기 효과: 공격 속도 증가! (2초)', LogType.event);
    } else if (skill.id == 'act_2' && rand.nextDouble() < procChance) {
      if (isPvPMode) {
        _defenderStunTimeLeft = 2.0;
        addLog('🔨 강격 효과: 방어자 기절! (2초)', LogType.event);
      } else {
        currentMonster?.stunTimeLeft = 2.0;
        addLog('🔨 강격 효과: 몬스터 기절! (2초)', LogType.event);
      }
    } else if (skill.id == 'act_1_5' && rand.nextDouble() < procChance) {
      player.skillCritBuffEndTime = DateTime.now().add(const Duration(seconds: 2));
      addLog('⚔️ 쌍룡참 효과: 치명타 확률 증가! (2초)', LogType.event);
    } else if (skill.id == 'act_5' && rand.nextDouble() < procChance) {
      if (isPvPMode) {
        _defenderJudgmentTimeLeft = 2.0;
        addLog('🌠 메테오 효과: 심판! 방어자 방어력 무력화! (2초)', LogType.event);
      } else {
        currentMonster?.judgmentTimeLeft = 2.0;
        addLog('🌠 메테오 효과: 심판! 몬스터 방어력 무력화! (2초)', LogType.event);
      }
    }

    // 몬스터/방어자 방어력에 배율 적용 (관리자 설정)
    // 🆕 [v2.3.0] 심판 상태인 경우 방어력 0 적용
    double effectiveDefense;
    if (isPvPMode) {
      effectiveDefense = isDefenderJudged ? 0 : defenderSnapshot!.defense.toDouble();
    } else {
      effectiveDefense = (currentMonster?.isJudged == true) ? 0 : (currentMonster!.defense * monsterDefenseMultiplier);
    }
    double defenseRating = 100 / (100 + effectiveDefense);
    
    // 연타 스킬의 경우, 각 타격의 UI 위치를 미리 계산
    List<Offset> offsets = List.generate(totalHits, (index) => Offset(
      totalHits > 1 ? (Random().nextDouble() * 60 - 30) : 0,
      totalHits > 1 ? (Random().nextDouble() * 40 - 20) : 0,
    ));

    // 🆕 Ticker 기반 처리: 각 타격을 큐에 추가
    final now = DateTime.now();
    for (int i = 0; i < totalHits; i++) {
      double variance = 0.9 + (Random().nextDouble() * 0.2);
      double powerMult = skill.currentValue;
      
      // 세트 효과: 스킬 데미지 증폭 및 최종 데미지 증폭 반영
      double rawDmg = (player.attack * ((powerMult * player.setSkillDamageMult) / 100) * defenseRating) * 
                       variance * player.potentialFinalDamageMult * player.setFinalDamageMult;
      int baseDmg = max(rawDmg.toInt(), (player.attack * 0.1 * variance).toInt()).clamp(1, 999999999);

      
      // 타격 시간 예약 (연타 간격 150ms 유지)
      // 잔향 타격들은 기본 타격들이 끝난 뒤 순차적으로 발생
      final scheduledTime = now.add(Duration(milliseconds: i * 150));
      
      pendingHits.add(PendingHit(
        damage: baseDmg,
        isSkill: true,
        offsetX: offsets[i].dx,
        offsetY: offsets[i].dy,
        scheduledTime: scheduledTime,
        shouldAnimate: i == 0 || i == baseHits, // 잔향 시작 시에도 애니메이션 트리거
        skillIcon: skill.iconEmoji, // 🆕 스킬 아이콘 전달
        combo: 0, // 스킬 사용 시 콤보 초기화
      ));
    }

    // 🆕 [얼음 화살] 빙결 효과 부여
    if (skill.id == 'act_3' && (currentMonster != null || isPvPMode)) {
      if (isPvPMode) {
        _defenderFrozenTimeLeft = 3.0;
        addLog('❄️ 빙결! 방어자의 행동이 3초간 정지됩니다.', LogType.event);
      } else {
        currentMonster!.frozenTimeLeft = 3.0; // 3초간 빙결
        addLog('❄️ 빙결! ${currentMonster!.name}의 행동이 3초간 정지됩니다.', LogType.event);
      }
      notifyListeners();
    }

    // 🆕 [화염구] 지면 연소 효과 부여
    if (skill.id == 'act_4' && (currentMonster != null || isPvPMode)) {
      _scorchedGroundTimeLeft = 5.0; // 5초간 연소
      // 초당 데미지: 플레이어 공격력의 약 50% (0.5초당 25%)
      _burnDmgPerTick = (player.attack * 0.25).toInt();
      _burnAccumulator = 0;
      addLog('🔥 지면 연소! 5초간 주변 대상에게 화상 피해를 입힙니다.', LogType.event);
      notifyListeners();
    }
  }

  // 🆕 데미지 처리 통합 헬퍼 (최적화) - GameLoop에서도 접근 가능하도록 public
  void damageMonster(int baseDmg, bool isMonsterAtk, bool isSkill, {double ox = 0, double oy = 0, bool shouldAnimate = true, String? skillIcon, int? combo, bool isDoubleHit = false}) {
    if (currentMonster == null || currentMonster!.isDead) return;

    // 치명타 적용
    bool isCrit = Random().nextDouble() * 100 < player.critChance;
    
    // [v2.7.10] 1. 처형(Execute) 삭제
    bool isExec = false;
    double hpPerc = (currentMonster!.hp / currentMonster!.maxHp) * 100;

    int finalDmg = isCrit ? (baseDmg * player.critDamage / 100).toInt() : baseDmg;
    
    // [v2.3.6] 환생 보너스 (보스 피해량 증가)
    if (currentMonster != null && currentMonster!.isBoss) {
      finalDmg = (finalDmg * (1.0 + player.reincarnation.getBonus('boss_damage') / 100)).toInt();
    }

    if (isExec) {
      // Logic removed
    }

    // [v2.0] 2연타 시 표시용 데미지와 실데미지 분리
    int displayDmg = finalDmg;
    if (isDoubleHit) {
      finalDmg *= 2; 
    }

    // [v2.0] 치명타 시 스킬 쿨감 (50% 확률)
    if (isCrit && player.critCdrAmount > 0) {
      if (Random().nextDouble() < 0.5) {
        _reduceAllSkillCooldowns(player.critCdrAmount);
      }
    }

    // 실제 HP 차감
    currentMonster!.hp -= finalDmg;
    _monsterCurrentHp = currentMonster!.hp;

    // UI 알림 (Floating Text)
    String text = (isDoubleHit ? '-${displayDmg} X2' : '-$displayDmg');
    onDamageDealt?.call(text, finalDmg, isCrit, isSkill, 
      isPlayerTarget: false, // 🆕 적군(몬스터)이 맞음
      ox: ox, oy: oy, shouldAnimate: shouldAnimate, skillIcon: skillIcon, combo: combo
    );

    // 흡혈 처리
    if (!isMonsterAtk && player.lifesteal > 0 && playerCurrentHp < player.maxHp) {
      int lifestealAmt = (finalDmg * player.lifesteal / 100).toInt();
      if (lifestealAmt > 0) {
        _playerCurrentHp = (_playerCurrentHp + lifestealAmt).clamp(0, player.maxHp);
        onHeal?.call(lifestealAmt, isPlayerTarget: true);
      }
    }

    // 🆕 [v2.2] 공격 시 보호막 생성 발동 체크
    if (!isMonsterAtk && player.gainShieldChance > 0) {
      if (Random().nextDouble() * 100 < player.gainShieldChance) {
        int shieldAmt = (player.maxHp * 0.05).toInt(); // 🆕 최대 체력의 5% 보호막 생성
        playerShield = (playerShield + shieldAmt).clamp(0, player.maxHp);
        onHeal?.call(shieldAmt); 
      }
    }

    // [세트 효과] 태고의 신 (T6) 4세트: 공격 시 5% 확률 광역 번개 (무한 루프 방지를 위해 스킬/몬스터 공격 아닐때만 발동)
    if (!isMonsterAtk && !isSkill && player.isSetEffectActive('ancient', 4)) {
      if (Random().nextDouble() < 0.05) {
        int lightningDmg = (player.attack * 5.0).toInt();
        // 번개 데미지는 재귀를 피하기 위해 직접 처리
        currentMonster!.hp -= lightningDmg;
        _monsterCurrentHp = currentMonster!.hp;
        onDamageDealt?.call('⚡-$lightningDmg', lightningDmg, true, true, skillIcon: '⚡');
        
        // 🆕 번개 데미지로 사망할 수 있으므로 체크 추가
        _checkMonsterDeath();
      }
    }


    // 사망 체크
    _checkMonsterDeath();

    // 🆕 무투회 NPC 특수 능력: 데미지 반사 (Reflect)
    if (isArenaMode && currentOpponent != null && !isMonsterAtk && currentOpponent!.reflectPerc > 0) {
      int reflectDmg = (finalDmg * currentOpponent!.reflectPerc / 100).toInt();
      if (reflectDmg > 0) {
        playerCurrentHp = (playerCurrentHp - reflectDmg).clamp(0, player.maxHp);
        onPlayerDamageTaken?.call(reflectDmg, shouldAnimate: false); // 🌵 반사 데미지는 애니메이션 제외
        // 반사 데미지 로그 (너무 자주 나오면 지저분하므로 확률적 또는 조건부 노출)
        if (Random().nextDouble() < 0.2) {
          addLog('⚡ NPC 반사 효과: ${reflectDmg}의 데미지를 돌려받았습니다!', LogType.damage);
        }
      }
    }
  }

  void _checkMonsterDeath() {
    if (currentMonster == null || !currentMonster!.isDead || isProcessingVictory) return;
    
    isProcessingVictory = true; 
    final killDuration = lastMonsterSpawnTime != null 
        ? DateTime.now().difference(lastMonsterSpawnTime!) 
        : null;

    handleVictory(killDuration);
    notifyListeners();
  }

  // --- PvP 전용 방어자 턴 로직 ---
  void processDefenderTurn() {
    if (!isPvPMode || defenderSnapshot == null || isProcessingVictory) return;

    // 🆕 상태 이상(기절/빙결) 체크
    if (isDefenderStunned || isDefenderFrozen) return;

    final activeSkills = defenderSnapshot!.activeSkills.where((s) => s.isUnlocked).toList();
    Skill? selectedSkill;

    if (activeSkills.isNotEmpty) {
      int startIndex = _defenderSkillIndex % activeSkills.length;
      for (int i = 0; i < activeSkills.length; i++) {
        int checkIdx = (startIndex + i) % activeSkills.length;
        final s = activeSkills[checkIdx];
        
        // 방어자는 고유 번호 기반 쿨감 생략 (단순화)
        if (s.isReady(defenderSnapshot!.cdr)) {
          selectedSkill = s;
          _defenderSkillIndex = (checkIdx + 1) % activeSkills.length;
          break;
        }
      }
    }

    if (selectedSkill != null) {
      _useDefenderSkill(selectedSkill);
    } else {
      _performDefenderBasicAttack();
    }
  }

  void _performDefenderBasicAttack() {
    if (defenderSnapshot == null) return;
    _defenderNormalCombo = (_defenderNormalCombo % 4) + 1;
    
    double comboMultiplier = 1.0;
    if (_defenderNormalCombo == 2) comboMultiplier = 1.3;
    if (_defenderNormalCombo == 3) comboMultiplier = 1.7;
    if (_defenderNormalCombo == 4) comboMultiplier = 2.2;

    double defenseRating = 100 / (100 + player.defense);
    double variance = 0.9 + (Random().nextDouble() * 0.2);
    
    double rawDamage = (defenderSnapshot!.attack * defenseRating) * variance * comboMultiplier;
    int baseDmg = max(rawDamage.toInt(), (defenderSnapshot!.attack * 0.1 * variance).toInt());

    // 🆕 방어자 치명타 확률 체크
    bool isCrit = false;
    int finalDmg = baseDmg;
    if (Random().nextDouble() * 100 < defenderSnapshot!.critChance) {
      isCrit = true;
      finalDmg = (finalDmg * defenderSnapshot!.critDamage / 100).toInt();
    }

    // 🆕 방어자 아이템 효과: 공격 시 보호막 생성
    if (defenderSnapshot!.gainShieldChance > 0) {
      if (Random().nextDouble() * 100 < defenderSnapshot!.gainShieldChance) {
        int shieldAmt = (defenderSnapshot!.maxHp * 0.05).toInt();
        defenderShield = (defenderShield + shieldAmt).clamp(0, defenderSnapshot!.maxHp);
      }
    }

    // 🆕 방어자 아이템 효과: 2연타 발동 체크
    bool isDoubleHit = false;
    if (defenderSnapshot!.doubleHitChance > 0) {
      if (Random().nextDouble() * 100 < defenderSnapshot!.doubleHitChance) {
        isDoubleHit = true;
      }
    }

    // [v2.0.1] 2연타 시 실데미지 중복 방지 (pendingHits에서 처리)

    // 방어자 공격 시 플레이어 피격 처리
    _playerTakePvPDamage(finalDmg, isCrit: isCrit, combo: _defenderNormalCombo, isDoubleHit: isDoubleHit);

    // 🆕 방어자 아이템 효과: 흡혈 (생명력 회복)
    if (defenderSnapshot!.lifesteal > 0 && defenderCurrentHp < defenderSnapshot!.maxHp) {
      int lifestealAmt = (finalDmg * defenderSnapshot!.lifesteal / 100).toInt();
      if (lifestealAmt > 0) {
        defenderCurrentHp = (defenderCurrentHp + lifestealAmt).clamp(0, defenderSnapshot!.maxHp);
      }
    }
  }

  void _useDefenderSkill(Skill skill) {
    if (defenderSnapshot == null) return;
    skill.lastUsed = DateTime.now();

    // 🆕 방어자 스킬 사용 시 피해 감소 발동 체크
    if (defenderSnapshot!.dmgReductionOnSkill > 0) {
      if (Random().nextDouble() * 100 < defenderSnapshot!.dmgReductionOnSkill) {
        // 방어자는 단순화를 위해 별도 타이머 대신 확률적으로 반감 처리하거나 로직 확장 가능
        // 현재는 플레이어와 동일하게 3초간 피해감소 로직이 GameState에 있으나 방어자 전용 타이머 필요
        _defenderSkillDmgReductionTimeLeft = 3.0;
      }
    }

    // 🆕 방어자 스킬 잔향(Skill Echo) 발동 체크
    bool isEchoed = false;
    if (defenderSnapshot!.skillEchoChance > 0) {
      if (Random().nextDouble() * 100 < defenderSnapshot!.skillEchoChance) {
        isEchoed = true;
      }
    }

    int baseHits = 1;
    if (skill.id == 'act_1') baseHits = 3;
    if (skill.id == 'act_1_5') baseHits = 2;

    int totalHits = isEchoed ? baseHits * 2 : baseHits;

    for (int i = 0; i < totalHits; i++) {
      double variance = 0.9 + (Random().nextDouble() * 0.2);
      double defenseRating = 100 / (100 + player.defense);
      int dmg = (defenderSnapshot!.attack * skill.currentValue / 100 * defenseRating * variance).toInt();
      
      bool isCrit = false;
      if (Random().nextDouble() * 100 < defenderSnapshot!.critChance) {
        isCrit = true;
        dmg = (dmg * defenderSnapshot!.critDamage / 100).toInt();
      }

      // 🆕 방어자 2연타 발동 체크 (스킬에는 2연타가 보통 안붙지만 옵션이 있다면 적용)
      bool isDoubleHit = false;
      if (defenderSnapshot!.doubleHitChance > 0 && i == totalHits -1) {
         if (Random().nextDouble() * 100 < defenderSnapshot!.doubleHitChance) {
           isDoubleHit = true;
         }
      }

      _playerTakePvPDamage(dmg, isCrit: isCrit, isSkill: true, skillIcon: skill.iconEmoji, isDoubleHit: isDoubleHit);

      // 🆕 방어자 아이템 효과: 스킬 사용 시에도 보호막 생성 및 흡혈 체크
      if (defenderSnapshot!.gainShieldChance > 0) {
        if (Random().nextDouble() * 100 < defenderSnapshot!.gainShieldChance) {
          int shieldAmt = (defenderSnapshot!.maxHp * 0.05).toInt();
          defenderShield = (defenderShield + shieldAmt).clamp(0, defenderSnapshot!.maxHp);
        }
      }
      if (defenderSnapshot!.lifesteal > 0 && defenderCurrentHp < defenderSnapshot!.maxHp) {
        int lifestealAmt = (dmg * defenderSnapshot!.lifesteal / 100).toInt();
        if (lifestealAmt > 0) {
          defenderCurrentHp = (defenderCurrentHp + lifestealAmt).clamp(0, defenderSnapshot!.maxHp);
        }
      }

      // 🆕 [v2.7.10] 방어자 스킬 특수 효과(Proc) 적용 로직 추가
      // 방어자 정보 기반으로 확률 계산 (기본 20% + 보정)
      final double procChance = 0.2; // 방어자는 단순화를 위해 고정 확률 적용
      final rand = Random();

      if (skill.id == 'act_2' && rand.nextDouble() < procChance) {
        _playerStunTimeLeft = 2.0;
        addLog('🔨 상대의 강격! 2초간 기절합니다.', LogType.event);
      } else if (skill.id == 'act_5' && rand.nextDouble() < procChance) {
        _playerJudgmentTimeLeft = 2.0;
        addLog('🌠 상대의 메테오! 2초간 방어력이 무력화됩니다.', LogType.event);
      } else if (skill.id == 'act_3' && rand.nextDouble() < procChance) {
        _playerFrozenTimeLeft = 3.0;
        addLog('❄️ 상대의 얼음 화살! 3초간 빙결됩니다.', LogType.event);
      } else if (skill.id == 'act_4' && rand.nextDouble() < procChance) {
        _playerBurnTimeLeft = 5.0;
        addLog('🔥 상대의 화염구! 5초간 화상 피해를 입습니다.', LogType.event);
      }
    }
  }

  void _playerTakePvPDamage(int damage, {bool isCrit = false, bool isSkill = false, String? skillIcon, int? combo, bool isDoubleHit = false, bool shouldAnimate = true}) {
    if (isProcessingVictory) {
      debugPrint('[PvP] 승리 처리 중 플레이어 피해 무시');
      return;
    }
    // 보호막 처리
    int remainingDmg = damage;
    if (playerShield > 0) {
      if (playerShield >= remainingDmg) {
        playerShield -= remainingDmg;
        remainingDmg = 0;
      } else {
        remainingDmg -= playerShield;
        playerShield = 0;
      }
    }

    playerCurrentHp = (playerCurrentHp - remainingDmg).clamp(0, player.maxHp);
    
    // [v2.7.7] lethal damage 시 즉시 사망 처리 (회복으로 인한 불사 방지)
    if (playerCurrentHp <= 0) {
      debugPrint('[PvP] 플레이어 치명상(HP 0) 도달! 패배 처리');
      _processPvPDefeat();
      return; 
    }

    // 🆕 [v2.7.10] 플레이어의 가시(Reflect) 효과 처리
    if (damage > 0 && player.reflectPerc > 0 && !isProcessingVictory) {
      int reflectDmg = (damage * player.reflectPerc / 100).toInt();
      if (reflectDmg > 0 && defenderCurrentHp > 0) {
        defenderCurrentHp = (defenderCurrentHp - reflectDmg).clamp(0, defenderSnapshot!.maxHp);
        onDamageDealt?.call('🌵$reflectDmg', reflectDmg, false, false, oy: -20, shouldAnimate: false); // 🌵 반사는 애니메이션 제외
        addLog('🌵 가시 발동! ${reflectDmg}의 피해를 반사했습니다.', LogType.damage);
        if (defenderCurrentHp <= 0) _processPvPVictory();
      }
    }
    
    // 🆕 플레이어 피격 시 회복(Recover on Damaged) 처리
    if (remainingDmg > 0 && player.recoverOnDamagedPerc > 0) {
      int recoverAmt = (remainingDmg * player.recoverOnDamagedPerc / 100).toInt();
      if (recoverAmt > 0) {
        playerCurrentHp = (playerCurrentHp + recoverAmt).clamp(0, player.maxHp);
        onHeal?.call(recoverAmt, isPlayerTarget: true);
      }
    }

    // 플레이어 피격 연출 (UI에서 위치를 자동으로 잡도록 오프셋 제거)
    onDamageDealt?.call('', damage, isCrit, isSkill, 
      isPlayerTarget: true, // 플레이어가 맞음
       shouldAnimate: shouldAnimate, skillIcon: skillIcon, combo: combo
    );

    // 2연타 처리
    if (isDoubleHit) {
      pendingHits.add(PendingHit(
        damage: (damage * 0.7).toInt(),
        isSkill: isSkill,
        offsetX: -50 + (Random().nextDouble() * 20 - 10),
        offsetY: -80 + (Random().nextDouble() * 20 - 10),
        scheduledTime: DateTime.now().add(const Duration(milliseconds: 100)),
        skillIcon: skillIcon,
      ));
    }

    if (playerCurrentHp <= 0) {
      debugPrint('[PvP] 플레이어 HP 0 도달! 패배 처리 시작');
      _processPvPDefeat();
    }
  }

  void _processPvPVictory() async {
    if (isProcessingVictory) return; // 중복 실행 방지
    isProcessingVictory = true;
    addLog('🏆 PvP 승리! 상대방을 제압했습니다.', LogType.event);
    
    // 🆕 즉시 사망 연출 트리거 (DB 대기 전)
    onPvPDeath?.call(true);
    notifyListeners();

    int scoreChange = 20;
    try {
      // 🆕 전투 로그 저장: 로그인 여부와 관계없이 모두 기록
      await pvpManager.saveBattleLog(
        player.name.isEmpty ? 'Warrior' : player.name,
        defenderSnapshot?.username ?? 'Unknown',
        true
      );

      final user = authService.currentUser;
      if (user != null) {
        final result = await pvpManager.updatePvPResult(user.id, true);
        scoreChange = result?['scoreChange'] ?? 20;
      }
    } catch (e) {
      debugPrint('PvP Victory Update Error: $e');
    } finally {
      onPvPResult?.call(true, scoreChange);
      notifyListeners();
    }
  }

  void _processPvPDefeat() async {
    if (isProcessingVictory) return; // 중복 실행 방지
    isProcessingVictory = true; // 패배도 승리 프로세스와 동일하게 처리 중단용으로 사용
    addLog('💀 PvP 패배... 다음 기회를 노리세요.', LogType.event);
    
    // 🆕 즉시 사망 연출 트리거 (DB 대기 전)
    onPvPDeath?.call(false);
    notifyListeners();

    int scoreChange = -10;
    try {
      // 🆕 전투 로그 저장: 로그인 여부와 관계없이 모두 기록
      await pvpManager.saveBattleLog(
        player.name.isEmpty ? 'Warrior' : player.name,
        defenderSnapshot?.username ?? 'Unknown',
        false
      );

      final user = authService.currentUser;
      if (user != null) {
        final result = await pvpManager.updatePvPResult(user.id, false);
        scoreChange = result?['scoreChange'] ?? -10;
      }
    } catch (e) {
      debugPrint('PvP Defeat Update Error: $e');
    } finally {
      onPvPResult?.call(false, scoreChange);
      notifyListeners();
    }
  }

  // --- PvP 대전 제어 ---
  void startPvPBattle(PvPSnapshot snapshot) {
    isPvPMode = true;
    defenderSnapshot = snapshot;
    defenderCurrentHp = snapshot.maxHp;
    defenderShield = 0; // 🆕 임시 보호막 제거 (아이템 옵션으로 생성되도록)
    
    playerCurrentHp = player.maxHp;
    playerShield = 0; // 🆕 본인도 아이템 옵션으로 생성

    _pvpCountdown = 3.0; // 🆕 3초 카운트다운 시작
    _resetAllSkillsToCooldown(); // 🆕 스킬 즉시 사용 방지

    _defenderSkillIndex = 0;
    _defenderNormalCombo = 0;
    isProcessingVictory = false;
    currentMonster = null;

    addLog('⚔️ ${snapshot.username} 유저와 대전을 시작합니다!', LogType.event);
    notifyListeners();
  }

  void endPvPBattle() {
    isPvPMode = false;
    defenderSnapshot = null;
    isProcessingVictory = false; // 🆕 승리 처리 플래그 초기화
    
    // 플레이어 체력 완전 회복 (정비)
    playerCurrentHp = player.maxHp;
    
    spawnMonster(); // 다시 일반 몬스터 스폰
    notifyListeners();
  }

  void handleVictory(Duration? killDuration) {
    if (isArenaMode) {
      _resolveArenaVictory();
      return;
    }
    int finalGold = (currentMonster!.goldReward * player.goldBonus / 100).toInt();
    
    // [v0.3.6] 적정 강화 구간 보너스: 골드 +30%
    if (isOptimalZone) {
      finalGold = (finalGold * 1.3).toInt();
    }

    int expReward = currentMonster!.expReward;
    
    player.gainExp(expReward);
    player.gold += finalGold;
    player.totalKills++;
    player.totalGoldEarned += finalGold;


    // [v2.0] 처치 시 공격력/방어력 버프 발동 (보호막 로직 제거됨)
    if (player.killAtkBonus > 0) {
      player.killAtkBuffEndTime = DateTime.now().add(const Duration(seconds: 30));
    }
    if (player.killDefBonus > 0) {
      player.killDefBuffEndTime = DateTime.now().add(const Duration(seconds: 30));
    }

    // [v0.8.14] 스테이지 마일스톤 가속 보너스용 최고 스테이지 갱신
    if (currentStage > player.maxStageReached) {
      player.maxStageReached = currentStage;
    }

    onVictory?.call(finalGold, expReward);

    bool isTower = currentZone.id == ZoneId.tower;
    if (isTower) {
      player.soulStone += 10; // 🆕 무한의 탑 승리 시 영혼석 10개 확정 지급
      addLog('무한의 탑 돌파! 영혼석 10개를 획득했습니다.', LogType.event);
      
      // 🆕 [v0.7.2] 퀘스트 체크: 무한의 탑 도달 층
      checkQuestProgress(QuestType.reachTowerFloor, currentStage);
    }
    if (!isTower) {
      bool isBossStage = currentStage % 50 == 0;
      bool jumped = false;
      
      if (!isBossStage && killDuration != null && killDuration.inMilliseconds < 1500) {
        currentStage += 1;
        stageKills = 0;
        zoneStages[currentZone.id] = currentStage;
        jumped = true;
        onStageJump?.call(); // [v0.0.79] UI에 점프 발생 알림
      }

      if (isBossStage) {
        // [v0.0.82] 보스 처치 시 즉시 클라우드 저장
        saveGameData(forceCloud: true);
      }

      // 🆕 [v0.5.58] 퀘스트 체크: 스테이지 도달 (중복 체크 제거: 처치 수 증가는 아래에서 처리)
      checkQuestProgress(QuestType.reachStage, currentStage);



      if (!jumped) {
        stageKills++;
        if (stageKills >= targetKills) {
          if (autoAdvance) {
            stageKills = 0;
            currentStage += 1;
            zoneStages[currentZone.id] = currentStage;
          } else {
            stageKills = targetKills - 1;
          }
        }
      }
    }

    // 🆕 [v2.4.7] 성능 최적화: 무거운 루프 및 전리품 계산을 Microtask로 분리하여 처치 순간의 Hitch 해결
    Future.microtask(() {
      _dropMaterials(currentMonster!.level);
      _dropItem();
      
      _victoryCountSinceSave++;
      if (_victoryCountSinceSave >= 10) {
        saveGameData();
        _victoryCountSinceSave = 0;
      }
      _processAutoCraft();
    });
    
    // 🆕 전투 리듬 개선: 대기 후 다음 몬스터 소환 (단, 무한의 탑은 수동 진행이므로 제외)
    if (!isTower) {
      pendingMonsterSpawn = true;
      monsterSpawnScheduledTime = DateTime.now().add(const Duration(milliseconds: 250));
    }
  }


  void _dropItem() {
    // 🆕 [v0.8.37] 특별 던전(황금/시련)에서는 장비가 드랍되지 않음
    if (currentZone.id == ZoneId.goldenRoom || currentZone.id == ZoneId.trialRoom) return;
    
    final rand = Random();
    double dropChance = currentMonster!.itemDropChance * (player.dropBonus / 100);
    
    if (rand.nextDouble() < dropChance) {
      // 🆕 [v2.2] 사냥터별 다중 티어 드롭 시스템 (가중치 방식)
      int dropTier = 1;
      // 🆕 [v2.3.6] 환생 보너스 (아이템 드롭 확률 보정)
      double dropBonus = player.reincarnation.getBonus('drop_rate'); // pt당 0.01%
      final double tierRand = rand.nextDouble() * 100;

      switch (currentZone.id) {
        case ZoneId.grassland:
          dropTier = 1; // T1 (100%)
          break;
        case ZoneId.forest:
          if (tierRand < (1.5 + dropBonus)) dropTier = 2; // T2 (1.5% + @)
          else dropTier = 1;
          break;
        case ZoneId.mine:
          if (tierRand < (1.0 + dropBonus)) dropTier = 3;      // T3 (1.0% + @)
          else if (tierRand < (11.0 + dropBonus * 2)) dropTier = 2; // T2 (10.0% + @)
          else dropTier = 1;
          break;
        case ZoneId.dungeon:
          if (tierRand < (0.5 + dropBonus)) dropTier = 4;       // T4 (0.5% + @)
          else if (tierRand < (10.0 + dropBonus * 2)) dropTier = 3;  // T3 (9.5% + @)
          else if (tierRand < (30.0 + dropBonus * 3)) dropTier = 2; // T2 (20.0% + @)
          else dropTier = 1;
          break;
        case ZoneId.volcano:
          if (tierRand < (0.3 + dropBonus)) dropTier = 5;       // T5 (0.3% + @)
          else if (tierRand < (5.0 + dropBonus * 2)) dropTier = 4;   // T4 (4.7% + @)
          else if (tierRand < (20.0 + dropBonus * 3)) dropTier = 3;  // T3 (15.0% + @)
          else if (tierRand < (50.0 + dropBonus * 4)) dropTier = 2;  // T2 (30.0% + @)
          else dropTier = 1;
          break;
        case ZoneId.snowfield:
          if (tierRand < (0.1 + dropBonus)) dropTier = 6;        // T6 (0.1% + @)
          else if (tierRand < (5.0 + dropBonus * 2)) dropTier = 5;    // T5 (4.9% + @)
          else if (tierRand < (15.0 + dropBonus * 3)) dropTier = 4;   // T4 (10.0% + @)
          else if (tierRand < (35.0 + dropBonus * 4)) dropTier = 3;   // T3 (20.0% + @)
          else if (tierRand < (65.0 + dropBonus * 5)) dropTier = 2;   // T2 (30.0% + @)
          else dropTier = 1;
          break;
        case ZoneId.abyss:
          if (tierRand < (1.0 + dropBonus)) dropTier = 6;        // T6 (1.0% + @)
          else if (tierRand < (15.0 + dropBonus * 2)) dropTier = 5;   // T5 (14.0% + @)
          else if (tierRand < (35.0 + dropBonus * 3)) dropTier = 4;   // T4 (20.0% + @)
          else if (tierRand < (60.0 + dropBonus * 4)) dropTier = 3;   // T3 (25.0% + @)
          else if (tierRand < (80.0 + dropBonus * 5)) dropTier = 2;   // T2 (20.0% + @)
          else dropTier = 1;
          break;
        default:
          dropTier = 1;
      }

      final newItem = Item.generate(player.level, tier: dropTier); 
      
      // [자동 분해 체크] - 계층적 판별 적용 (사용자 설정 티어 이하 & 등급 이하)
      bool shouldAutoDismantle = autoDismantleGrade != -1 && autoDismantleTier != -1 &&
                                newItem.tier <= autoDismantleTier &&
                                newItem.grade.index <= autoDismantleGrade;

      if (shouldAutoDismantle) {
        var rewards = _calculateDismantleRewards(newItem);
        player.gold += rewards['gold']!;
        player.abyssalPowder += rewards['abyssalPowder']!;
        player.enhancementStone += rewards['stone']!;
        player.rerollStone += rewards['reroll']!;
        player.protectionStone += rewards['protection']!;
        player.cube += rewards['cube']!;
        player.shards += rewards['shards']!;
        
        addLog('[자동분해] ${newItem.grade.name} T${newItem.tier} ${newItem.type.nameKr}이(가) 분해되었습니다.', LogType.item);
        onLootAcquired?.call('♻️', '${newItem.grade.name} 분해됨', newItem.grade, amount: 1);
      } else {
        if (player.addItem(newItem)) {
          addLog('[획득] ${newItem.grade.name} 등급의 ${newItem.type.nameKr} 획득!', LogType.item);
          player.totalItemsFound++;
          player.updateEncyclopedia(newItem);
          onLootAcquired?.call(newItem.type.iconEmoji, newItem.name, newItem.grade, amount: 1);
        }
      }
    }
  }

  void _dropMaterials(int monsterLevel) {
    // 🆕 [v0.8.37] 황금의 방에서는 재료가 드랍되지 않음
    if (currentZone.id == ZoneId.goldenRoom) return;

    final rand = Random();
    
    // [v0.3.6] 적정 강화 구간 보너스: 강화 재료 드랍율 +40%
    double matBonus = isOptimalZone ? 1.4 : 1.0;
    
    // [v0.8.17] 시련의 방 보너스: 재료 드랍율 5배 상향
    if (currentZone.id == ZoneId.trialRoom) matBonus *= 5.0;
    
    // 1. 강화석 드롭 (기본 10% -> 보너스 적용 시 14%)
    if (rand.nextDouble() < (0.1 * matBonus)) {
      int amount = 1 + (monsterLevel / 50).floor() + rand.nextInt(3);
      player.enhancementStone += amount;
      addLog('[공명] 강화석 $amount개 획득!', LogType.item);
      onLootAcquired?.call('💎', '강화석', ItemGrade.rare, amount: amount);
    }
    
    // 2. 가루 드롭 (기본 40% -> 보너스 적용 시 56%)
    if (rand.nextDouble() < (0.4 * matBonus)) {
      int amount = (monsterLevel / 5).ceil() + rand.nextInt(10);
      player.abyssalPowder += amount;
      addLog('[추출] 심연의 가루 $amount개 획득!', LogType.item);
      onLootAcquired?.call('✨', '심연의 가루', ItemGrade.uncommon, amount: amount);
    }
    
    // 3. 재설정석 드롭 (v0.4.8: 숲 이상 사냥터에서만 드롭)
    bool canDropReroll = currentZone.id.index >= ZoneId.forest.index;
    if (canDropReroll && rand.nextDouble() < (0.1 * matBonus)) {
      player.rerollStone += 1;
      addLog('[희귀] 옵션 재설정석 획득!', LogType.item);
      onLootAcquired?.call('🌀', '재설정석', ItemGrade.rare, amount: 1);
    }
    
    // 4. 보호석 (기본 2% -> 보너스 적용 시 2.8%)
    if (rand.nextDouble() < (0.02 * matBonus)) {
      player.protectionStone += 1;
      addLog('[전설] 강화 보호석 획득!', LogType.item);
      onLootAcquired?.call('🛡️', '보호석', ItemGrade.legendary, amount: 1);
    }

    // 5. 잠재력 큐브 드롭 (v0.4.8: 광산 이상 사냥터에서만 드롭)
    bool canDropCube = currentZone.id.index >= ZoneId.mine.index;
    if (canDropCube && rand.nextDouble() < (0.001 * matBonus)) {
      player.cube += 1;
      addLog('[신화] 잠재력 큐브 획득!', LogType.item);
      onLootAcquired?.call('🔮', '잠재력 큐브', ItemGrade.mythic, amount: 1);
    }

    // --- [v0.3.8] 티어 재료 해금 + 지역 연동 드랍 시스템 --- (드랍 시스템 개편으로 제거)
  }

  void addLog(String message, LogType type) {
    logs.insert(0, CombatLogEntry(message, type));
    if (logs.length > maxLogs) logs.removeLast();
    notifyListeners();
  }

  void applyRegen() {
    if (playerCurrentHp > 0 && playerCurrentHp < player.maxHp) {
      // [v2.0] 회복 상한선 적용 (기본 5% + 옵션 보너스)
      double maxRegen = player.maxHp * (player.hpRegenCap / 100);
      double regenAmount = player.maxHp * (player.hpRegen / 100);
      
      int finalRegen = min(regenAmount, maxRegen).toInt();

      if (finalRegen > 0) {
        playerCurrentHp = (playerCurrentHp + finalRegen).clamp(0, player.maxHp);
        onHeal?.call(finalRegen, isPlayerTarget: true);
      }
    }
    
    // 🆕 PvP 방어자 재생 처리
    if (isPvPMode && defenderSnapshot != null && defenderCurrentHp > 0 && defenderCurrentHp < defenderSnapshot!.maxHp) {
      double maxRegen = defenderSnapshot!.maxHp * (defenderSnapshot!.hpRegenCap / 100);
      double regenAmount = defenderSnapshot!.maxHp * (defenderSnapshot!.hpRegen / 100);
      
      int finalRegen = min(regenAmount, maxRegen).toInt();

      if (finalRegen > 0) {
        defenderCurrentHp = (defenderCurrentHp + finalRegen).clamp(0, defenderSnapshot!.maxHp);
        onHeal?.call(finalRegen, isPlayerTarget: false); // 🆕 방어자 회복 텍스트 추가
      }
    }

    notifyListeners();
  }

  void monsterPerformAttack() {
    if (currentMonster == null || isProcessingVictory) return;
    
    // 🆕 빙결/기절 상태 체크: 행동 불가 시 공격 스킵
    if (currentMonster!.isFrozen || currentMonster!.isStunned) {
      return;
    }
    double mVariance = 0.9 + (Random().nextDouble() * 0.2);
    double pDefenseRating = 100 / (100 + player.defense);
    double rawMDmg = (currentMonster!.attack * pDefenseRating) * mVariance;
    
    // 🆕 보스 광폭화: 공격력 1.2배 증가
    if (currentMonster!.isBoss && (currentMonster!.hp / currentMonster!.maxHp) < 0.5) {
      rawMDmg *= 1.2;
    }

    // [v2.0] 스킬 사용 후 피해 감소 적용 (고정 20% 감소)
    if (_skillDmgReductionTimeLeft > 0) {
      double drBonus = 20.0; // 고정 20% 감소
      // 🆕 보스 특수 능력 [파쇄]: 피해 감소 효율 50% 무시
      if (currentMonster?.trait == BossTrait.crush) {
        drBonus *= 0.5;
      }
      rawMDmg *= (1.0 - drBonus / 100);
    }

    // 🆕 [v0.8.18] 최소 데미지 하한선 조정 (10% -> 15%: 방어 무적 방지)
    int mDmg = max(rawMDmg.toInt(), (currentMonster!.attack * 0.15 * mVariance).toInt()).clamp(1, 999999999);

    // [v2.0] 보호막(Shield) 우선 소모 로직
    int damageToHp = mDmg;
    if (playerShield > 0) {
      // 🆕 보스 특수 능력 [파쇄]: 보호막 50% 관통 (절반의 데미지는 항상 HP로 전달)
      if (currentMonster?.trait == BossTrait.crush) {
        int pierceDmg = (mDmg * 0.5).toInt();
        damageToHp = pierceDmg;
        int remainingDmg = mDmg - pierceDmg;
        
        if (playerShield >= remainingDmg) {
          playerShield -= remainingDmg;
        } else {
          damageToHp += (remainingDmg - playerShield);
          playerShield = 0;
        }
      } else {
        if (playerShield >= mDmg) {
          playerShield -= mDmg;
          damageToHp = 0;
        } else {
          damageToHp -= playerShield;
          playerShield = 0;
        }
      }
    }

    if (mDmg > 0) {
      if (damageToHp > 0) {
        playerCurrentHp -= damageToHp;
        onPlayerDamageTaken?.call(damageToHp, isShield: false);
      } else {
        // 🆕 보호막이 모든 피해를 흡수한 경우에도 데미지 표시
        onPlayerDamageTaken?.call(mDmg, isShield: true);
      }

      // 🆕 [v2.7.10] 플레이어의 가시(Reflect) 효과 처리 (몬스터 대상)
      if (player.reflectPerc > 0 && currentMonster != null && !currentMonster!.isDead) {
        int reflectDmg = (mDmg * player.reflectPerc / 100).toInt();
        if (reflectDmg > 0) {
          currentMonster!.hp -= reflectDmg;
          _monsterCurrentHp = currentMonster!.hp;
          onDamageDealt?.call('🌵$reflectDmg', reflectDmg, false, false, oy: -25, shouldAnimate: false); // 🌵 반사는 애니메이션 제외
          addLog('🌵 가시 발동! ${reflectDmg}의 피해를 반사했습니다.', LogType.damage);
          _checkMonsterDeath();
        }
      }
    }
    
    // 🆕 무투회 NPC 특수 능력: 흡혈 (Lifesteal)
    if (isArenaMode && currentOpponent != null && mDmg > 0 && currentOpponent!.lifestealPerc > 0) {
      int npcHeal = (mDmg * currentOpponent!.lifestealPerc / 100).toInt();
      if (npcHeal > 0) {
        currentMonster!.hp = (currentMonster!.hp + npcHeal).clamp(0, currentMonster!.maxHp);
        _monsterCurrentHp = currentMonster!.hp;
        // NPC 힐 연출을 위해 플레이어 힐 이펙트 재활용 (UI에서 몬스터 위치로 표시되진 않지만 로직은 동작)
        // onHeal (monster용)은 없으므로 일단 로그로 대체
        if (Random().nextDouble() < 0.3) {
          addLog('🩸 NPC 흡혈 효과: 체력을 ${npcHeal} 회복했습니다!', LogType.damage);
        }
      }
    }

    // 🆕 무투회 NPC 특수 능력: 처형 (Execute) 삭제 (가시 등으로 대체 가능하나 일단 제거)

    // [v2.0] 피격 데미지 비례 즉시 회복
    if (player.recoverOnDamagedPerc > 0) {
      double recPerc = player.recoverOnDamagedPerc;
      // 🆕 보스 특수 능력 [오염]: 피격 회복 효율 50% 감소
      if (currentMonster?.trait == BossTrait.corrupt) {
        recPerc *= 0.5;
      }
      int healAmt = (mDmg * recPerc / 100).toInt();
      if (healAmt > 0) {
        _playerCurrentHp = (_playerCurrentHp + healAmt).clamp(0, player.maxHp);
        onHeal?.call(healAmt, isPlayerTarget: true);
      }
    }

    // 🆕 보스 특수 능력 [침식]: 피격 시 모든 스킬 쿨타임 0.3초 증가
    if (currentMonster?.trait == BossTrait.erode && mDmg > 0) {
      _increaseAllSkillCooldowns(0.3);
      if (Random().nextDouble() < 0.3) {
        addLog('⏳ [침식] 보스의 공격으로 스킬 쿨타임이 늘어납니다!', LogType.event);
      }
    }

    // [세트 효과] 광산의 수호자 (T3) 4세트: 피격 시 10% 확률로 HP 5% 회복
    if (player.isSetEffectActive('mine', 4) && Random().nextDouble() < 0.1) {
      int healAmt = (player.maxHp * 0.05).toInt();
      _playerCurrentHp = (_playerCurrentHp + healAmt).clamp(0, player.maxHp);
      onHeal?.call(healAmt, isPlayerTarget: true);
      addLog('🛡️ [세트효과] 광산의 가호로 체력을 회복했습니다.', LogType.event);
    }
    
    if (playerCurrentHp <= 0) {
      playerCurrentHp = 0;
      handlePlayerDeath();
    }
    notifyListeners();
  }

  void handlePlayerDeath() {
    if (isArenaMode) {
      _resolveArenaLoss();
      return;
    }
    bool isTower = currentZone.id == ZoneId.tower;
    
    if (isTower) {
      // 무한의 탑에서는 후퇴하지 않고 즉시 멈춤
      currentMonster = null;
      isProcessingVictory = true; // 더 이상 공격 받지 않도록
    } else {
      playerCurrentHp = player.maxHp;
      currentStage = max(1, currentStage - 5);
      zoneStages[currentZone.id] = currentStage;
      addLog('사망했습니다. 안전을 위해 5스테이지 이전으로 후퇴합니다.', LogType.event);
      spawnMonster();
    }
    
    onPlayerDeath?.call();
    notifyListeners();
  }

  // --- [v0.0.85] 아이템 및 펫 비즈니스 로직 ---

  void equipItem(Item item) {
    player.equipItem(item);
    // 🆕 [v0.5.58] 퀘스트 체크: 장비 장착
    checkQuestProgress(QuestType.equip, 1);
    saveGameData();
    notifyListeners();
  }

  void toggleItemLock(Item item) {

    item.isLocked = !item.isLocked;
    saveGameData();
    notifyListeners();
  }

  void rerollItemOptions(Item item) {
    if (item.rerollCount >= 5 || item.isLocked) return;
    
    int lockCount = item.subOptions.where((o) => o.isLocked).length;
    int powderCost = lockCount == 0 ? 0 : (1000 * pow(10, lockCount - 1)).toInt();
    
    if (player.rerollStone < 1 || player.abyssalPowder < powderCost) return;

    player.rerollStone -= 1;
    player.abyssalPowder -= powderCost;
    
    item.rerollSubOptions(Random());
    
    // 🆕 [v0.5.58] 퀘스트 체크: 옵션 재설정
    checkQuestProgress(QuestType.reroll, 1);

    saveGameData();
    notifyListeners();

  }

  String enhanceItem(Item item, {bool useProtection = false}) {
    if (item.isLocked) return "잠긴 아이템은 강화할 수 없습니다.";
    if (player.gold < item.enhanceCost || player.enhancementStone < item.stoneCost) return "재화가 부족합니다.";
    if (useProtection && player.protectionStone < 1) return "보호석이 부족합니다.";
    if (item.isBroken) return "파손된 장비는 강화할 수 없습니다.";

    player.gold -= item.enhanceCost;
    player.enhancementStone -= item.stoneCost;
    if (useProtection) player.protectionStone -= 1;
    
    // 🆕 [v0.7.1] 퀘스트 체크: 강화 시도 횟수 누적
    player.totalEnhanceAttempts++;
    checkQuestProgress(QuestType.enhanceAttempt, player.totalEnhanceAttempts);

    bool isSuccess = Random().nextDouble() < item.successChance;
    String resultMsg = item.processEnhance(isSuccess, useProtection: useProtection);
    
    if (isSuccess) {
      addLog(resultMsg, LogType.event);
      player.updateEncyclopedia(item);
      // 🆕 [v0.5.58] 퀘스트 체크: 아이템 강화 성공 시 (기존 로직 유지)
      checkQuestProgress(QuestType.enhanceItem, item.enhanceLevel);
    } else {

      addLog(resultMsg, LogType.event);
      if (item.isBroken) {
        int successionLevel = (item.enhanceLevel * 0.7).floor();
        player.enhancementSuccession[item.tier] = successionLevel;
      }
    }
    
    saveGameData();
    notifyListeners();
    return resultMsg;
  }

  void promoteItem(Item item) {
    if (!item.canPromote) return;
    if (player.gold < item.promotionGoldCost || player.enhancementStone < item.promotionStoneCost) return;
    
    player.gold -= item.promotionGoldCost;
    player.enhancementStone -= item.promotionStoneCost;

    
    int oldTier = item.tier;
    int oldStat1 = item.effectiveMainStat1;
    int? oldStat2 = item.mainStat2 != null ? item.effectiveMainStat2 : null;

    item.promote();
    
    // 🆕 [v0.8.11] 승급 시 내구도 보너스 확률 적용 (성공 50%, 대성공 30%, 초대박 20%)
    double durRoll = Random().nextDouble();
    String bonusMsg = "";
    if (durRoll < 0.2) {
      item.durability = (item.durability + 50).clamp(0, item.maxDurability);
      bonusMsg = "[초대박! 내구도 50 회복]";
    } else if (durRoll < 0.5) {
      item.durability = (item.durability + 30).clamp(0, item.maxDurability);
      bonusMsg = "[대성공! 내구도 30 회복]";
    } else {
      bonusMsg = "[성공! 내구도 유지]";
    }

    addLog("[승급 성공] ${item.name}이(가) T$oldTier에서 T${item.tier}로 진화했습니다! $bonusMsg", LogType.event);
    player.updateEncyclopedia(item);
    
    // 🆕 승급 성공 연출 호출
    onItemPromotionSuccess?.call(item, oldTier, oldStat1, oldStat2);
    
    // 🆕 [v0.8.22] 퀘스트 체크: 아이템 승급
    checkQuestProgress(QuestType.itemPromotion, 1);

    saveGameData();
    notifyListeners();

  }

  // --- [v0.3.0] 장착 슬롯 강화 시스템 ---
  
  // 슬롯 강화 비용 및 확률 계산 헬퍼
  Map<String, dynamic> getSlotEnhanceInfo(ItemType type) {
    int currentLevel = player.slotEnhanceLevels[type] ?? 0;
    int failCount = player.slotEnhanceFailCounts[type] ?? 0;
    int streakCount = player.slotEnhanceStreakCounts[type] ?? 0;

    // 1. 비용 계산 (1/10 압축 반영: 10단계 분량의 비용 합산 개념)
    int goldCost = (20000 + pow(currentLevel * 10, 1.9) * 100).toInt();
    int stoneCost = 5 + (currentLevel ~/ 5);

    // [마일스톤] 120 도달 시 강화 비용 -10%
    bool costMilestone = player.slotEnhanceLevels.values.any((v) => v >= 120);
    if (costMilestone) goldCost = (goldCost * 0.9).toInt();

    // 2. 압축된 확률 테이블 (0~300 레벨 범위) - [v2.2.2] 성장 체감 개선을 위해 상향
    double baseChance = 1.0;
    if (currentLevel < 10) {
      baseChance = 1.0;
    } else if (currentLevel < 20) {
      baseChance = 0.8;
    } else if (currentLevel < 30) {
      baseChance = 0.6;
    } else if (currentLevel < 50) {
      baseChance = 0.4;
    } else if (currentLevel < 80) {
      baseChance = 0.25;
    } else if (currentLevel < 100) {
      baseChance = 0.15;
    } else if (currentLevel < 150) {
      baseChance = 0.10;
    } else if (currentLevel < 200) {
      baseChance = 0.08;
    } else {
      baseChance = 0.05;
    }

    // 3. 보너스 확률 및 천장(Pity) 적용
    double bonusChance = 0.0;
    
    // [연속 성공 보너스] 3회 연속 성공 시 다음 강화 성공률 +10%
    if (streakCount >= 3) bonusChance += 0.1;

    double finalChance = baseChance + bonusChance;

    // [소프트 천장] 실패 5회 누적 시 다음 강화 성공 확률 2배
    if (failCount >= 5) finalChance *= 2.0;
    
    // [하드 천장] 실패 10회 누적 시 100% 성공
    bool isGuaranteed = failCount >= 10;
    if (isGuaranteed) finalChance = 1.0;

    return {
      'level': currentLevel,
      'goldCost': goldCost,
      'stoneCost': stoneCost,
      'chance': finalChance.clamp(0.0, 1.0),
      'baseChance': baseChance,
      'bonusChance': bonusChance,
      'failCount': failCount,
      'streakCount': streakCount,
      'isMax': currentLevel >= 300,
      'isGuaranteed': isGuaranteed,
      'hasPity': failCount >= 5,
      'hasStreakBonus': streakCount >= 3,
    };
  }

  void enhanceSlot(ItemType type) {
    var info = getSlotEnhanceInfo(type);
    if (info['isMax']) return;

    int gCost = info['goldCost'];
    int sCost = info['stoneCost'];
    double chance = info['chance'];

    if (player.gold < gCost || player.enhancementStone < sCost) {
      addLog('강화 재료가 부족합니다.', LogType.event);
      return;
    }

    player.gold -= gCost;
    player.enhancementStone -= sCost;

    bool success = Random().nextDouble() < chance;
    
    if (success) {
      int nextLevel = (player.slotEnhanceLevels[type] ?? 0) + 1;
      player.slotEnhanceLevels[type] = nextLevel;
      
      // 연속 성공 카운트 증가 및 실패 카운트 초기화
      int currentStreak = (player.slotEnhanceStreakCounts[type] ?? 0) + 1;
      player.slotEnhanceStreakCounts[type] = currentStreak;
      player.slotEnhanceFailCounts[type] = 0;

      // [연속 성공 보너스] 5연속 성공 시 보상 지급 후 초기화
      if (currentStreak >= 5) {
        int refund = (gCost * 0.5).toInt();
        player.gold += refund;
        player.slotEnhanceStreakCounts[type] = 0; // 초기화하여 다음 3/5 스트릭 기회 부여
        addLog('★ 5연속 성공! 골드 $refund 환급!', LogType.event);
        
        // 🆕 UI에 럭키 스트릭 알림 발생
        onSpecialEvent?.call('LUCKY STREAK!', '5연속 성공! 골드 50% ($refund) 환급 완료!');
      }

      addLog('[슬롯 강화] ${type.nameKr} 슬롯이 +$nextLevel레벨이 되었습니다!', LogType.event);
      
      // 🆕 [v0.5.58] 퀘스트 체크: 슬롯 누적 강화 총합 체크
      checkQuestProgress(QuestType.totalSlotEnhance, player.totalSlotEnhanceLevel);


      // 🆕 천장(Pity)으로 성공한 경우 추가 알림

      if (info['isGuaranteed'] == true) {
        onSpecialEvent?.call('DESTINY SUCCESS!', '천장 도달! 확정 성공으로 슬롯이 강화되었습니다.');
      } else if (info['hasPity'] == true) {
        onSpecialEvent?.call('PITY SUCCESS!', '확률 업 보너스로 강화에 성공했습니다!');
      }
    } else {
      // 연속 성공 초기화 및 실패 카운트 증가
      player.slotEnhanceStreakCounts[type] = 0;
      int currentFail = (player.slotEnhanceFailCounts[type] ?? 0) + 1;
      player.slotEnhanceFailCounts[type] = currentFail;
      
      addLog('[슬롯 강화] ${type.nameKr} 슬롯 강화 실패 (누적 실패: $currentFail)', LogType.event);
    }

    saveGameData();
    notifyListeners();

    // [v0.4.8] 기능 해금 마일스톤 체크
    _checkFeatureUnlockMilestones();
  }

  void _checkFeatureUnlockMilestones() {
    int totalSlotLv = player.totalSlotEnhanceLevel;
    
    // 1. 아이템 강화 해금 (5)
    if (totalSlotLv >= 5 && !player.notifiedMilestones.contains(5)) {
      player.notifiedMilestones.add(5);
      onSpecialEvent?.call('기능 해금!', '슬롯 강화 총합 5 달성! 아이템 강화 기능이 해금되었습니다.');
    }
    // 2. 옵션 재설정 해금 (30)
    if (totalSlotLv >= 30 && !player.notifiedMilestones.contains(30)) {
      player.notifiedMilestones.add(30);
      onSpecialEvent?.call('기능 해금!', '슬롯 강화 총합 30 달성! 옵션 재설정 기능이 해금되었습니다.');
    }
    // 3. 잠재능력 각성 해금 (100)
    if (totalSlotLv >= 100 && !player.notifiedMilestones.contains(100)) {
      player.notifiedMilestones.add(100);
      onSpecialEvent?.call('기능 해금!', '슬롯 강화 총합 100 달성! 잠재능력 각성 기능이 해금되었습니다.');
    }
    
    saveGameData();
  }

  Map<String, int> executeDismantle(Item item) {
    if (item.isLocked) return {};
    
    player.inventory.removeWhere((i) => i.id == item.id);
    var rewards = _calculateDismantleRewards(item);
    
    player.gold += rewards['gold']!;
    player.abyssalPowder += rewards['abyssalPowder']!;
    player.enhancementStone += rewards['stone']!;
    
    addLog('[분해] ${item.name}을(를) 분해하여 재료를 획득했습니다.', LogType.item);
    
    // 🆕 [v0.5.58] 퀘스트 체크: 아이템 분해
    checkQuestProgress(QuestType.dismantle, 1);

    saveGameData();
    notifyListeners();


    return rewards;
  }

  Map<String, int> executeBulkDismantle(int maxGradeIdx, int maxTier) {
    int dismantleCount = 0;
    int totalGold = 0;
    int totalAbyssal = 0;
    int totalStone = 0;
    int totalReroll = 0;
    int totalProtection = 0;
    int totalCube = 0;
    int totalShards = 0;

    player.inventory.removeWhere((item) {
      if (item.tier <= maxTier && item.grade.index <= maxGradeIdx && !item.isLocked) {
        dismantleCount++;
        var rewards = _calculateDismantleRewards(item);
        totalGold += rewards['gold']!;
        totalAbyssal += rewards['abyssalPowder']!;
        totalStone += rewards['stone']!;
        totalReroll += rewards['reroll']!;
        totalProtection += rewards['protection']!;
        totalCube += rewards['cube']!;
        totalShards += rewards['shards']!;
        return true;
      }
      return false;
    });
    
    player.gold += totalGold;
    player.abyssalPowder += totalAbyssal;
    player.enhancementStone += totalStone;
    player.rerollStone += totalReroll;
    player.protectionStone += totalProtection;
    player.cube += totalCube;
    player.shards += totalShards;

    if (dismantleCount > 0) {
      addLog('[일괄분해] $dismantleCount개의 아이템을 분해했습니다.', LogType.item);
      
      // 🆕 [v0.5.58] 퀘스트 체크: 아이템 분해
      checkQuestProgress(QuestType.dismantle, 1);

      saveGameData();
      notifyListeners();
    }


    return {
      'count': dismantleCount,
      'gold': totalGold,
      'abyssalPowder': totalAbyssal,
      'stone': totalStone,
      'reroll': totalReroll,
      'protection': totalProtection,
      'cube': totalCube,
      'shards': totalShards,
    };

  }

  Map<String, int> _calculateDismantleRewards(Item item) {
    final rand = Random();
    int gold = item.tier * (item.grade.index + 1) * 500;
    int powder = item.tier * (item.grade.index + 1) * 2;
    int stone = item.grade.index >= 1 ? item.grade.index : 0;
    int reroll = (item.grade.index >= 2 && rand.nextDouble() < 0.3) ? 1 : 0;
    int protection = (item.grade.index >= 3 && rand.nextDouble() < 0.2) ? 1 : 0;
    int cube = (item.grade.index >= 4 && rand.nextDouble() < 0.1) ? 1 : 0;

    // 🆕 [v0.5.53] 연성 파편 획득량 개편: (기본 * 5) * 2^(티어-1) * ±10%
    int baseShards = 0;
    switch (item.grade) {
      case ItemGrade.common: baseShards = 1; break;
      case ItemGrade.uncommon: baseShards = 3; break;
      case ItemGrade.rare: baseShards = 10; break;
      case ItemGrade.epic: baseShards = 30; break;
      case ItemGrade.unique: baseShards = 60; break;
      case ItemGrade.legendary: baseShards = 150; break;
      case ItemGrade.mythic: baseShards = 500; break;
    }
    
    double tierMultiplier = pow(2, item.tier - 1).toDouble();
    int finalBaseShards = (baseShards * 5 * tierMultiplier).toInt();
    // ±10% 변동폭 적용 (0.9 ~ 1.1)
    int shards = (finalBaseShards * (0.9 + rand.nextDouble() * 0.2)).toInt();

    // 🆕 [v0.5.53] 심연의 구슬 획득 로직 추가: T2 이상 1~5개 랜덤 (+등급 보너스)
    int cores = 0;
    if (item.tier >= 2) {
      cores = (1 + rand.nextInt(5)) + item.grade.index;
    }

    return {
      'gold': gold,
      'abyssalPowder': powder + cores,
      'stone': stone,
      'reroll': reroll,
      'protection': protection,
      'cube': cube,
      'shards': max(1, shards),
    };
  }

  void summonPet(int count) {
    int cost = count == 1 ? 10000 : 90000;
    int soulCost = count; // 🆕 펫 소환 시 소환 횟수만큼 영혼석 소모
    
    if (player.gold < cost || player.soulStone < soulCost) {
      return;
    }

    player.gold -= cost;
    player.soulStone -= soulCost;
    List<Pet> allPets = PetData.getInitialPets();
    
    for (int i = 0; i < count; i++) {
      double rand = Random().nextDouble() * 100;
      Pet selected;
      int subIdx = Random().nextInt(5);

      if (rand < 0.02) {
        selected = allPets[25 + subIdx]; // 신화 (0.02%)
      } else if (rand < 0.2) {
        selected = allPets[20 + subIdx]; // 전설 (0.18%)
      } else if (rand < 2.0) {
        selected = allPets[15 + subIdx]; // 영웅 (1.8%)
      } else if (rand < 5.0) {
        selected = allPets[10 + subIdx]; // 희귀 (3.0%)
      } else if (rand < 20.0) {
        selected = allPets[5 + subIdx];  // 고급 (15.0%)
      } else {
        selected = allPets[0 + subIdx];  // 일반 (80.0%)
      }

      if (!player.pets.any((p) => p.id == selected.id)) {
        player.pets.add(selected);
        addLog('펫 획득! [${selected.grade.name}] ${selected.name}', LogType.event);
      } else {
        player.pets.firstWhere((p) => p.id == selected.id).level++;
      }
    }
    
    // 🆕 [v0.5.58] 퀘스트 체크: 펫 소환
    checkQuestProgress(QuestType.summonPet, 1);

    saveGameData();
    notifyListeners();
  }


  void upgradeSkill(Skill skill) {
    if (player.gold < skill.upgradeCost || player.level < skill.unlockLevel) return;

    player.gold -= skill.upgradeCost;
    skill.level++;
    addLog('[스킬] ${skill.name} ${skill.level}레벨 달성!', LogType.event);

    // 🆕 [v0.8.37] 퀘스트 체크: 스킬 레벨업 (타입별 분기)
    checkQuestProgress(QuestType.learnSkill, skill.level);
    if (skill.type == SkillType.active) {
      checkQuestProgress(QuestType.learnActiveSkill, skill.level);
    } else {
      checkQuestProgress(QuestType.learnPassiveSkill, skill.level);
    }

    saveGameData(); // 스킬 업글 후 저장
    notifyListeners();

  }

  void togglePetActive(Pet? pet) {
    if (player.activePet?.id == pet?.id) {
      player.activePet = null;
    } else {
      player.activePet = pet;
    }
    saveGameData();
    notifyListeners();
  }

  void claimAchievement(Achievement achievement) {
    int currentStep = player.achievementSteps[achievement.id] ?? 0;
    if (currentStep >= achievement.targets.length) return; // 🆕 이미 모든 단계를 완료함

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
      String? msg = player.checkAchievement(achievement.id, progress, target, reward);
      if (msg != null) {
        addLog(msg, LogType.event);
        // UI 알림을 위해 notifyListeners()가 호출되지만, 
        // 팝업 연출은 리턴된 메시지로 UI단에서 처리하도록 유도할 수 있습니다.
        // 여기서는 메시지를 이벤트로 남기는 것에 집중합니다.
      }
      saveGameData();
      notifyListeners();
    }
  }

  void claimEncyclopediaRewards() {
    player.claimAllEncyclopediaRewards();

    // 🆕 [v0.5.58] 퀘스트 체크: 도감 수령
    checkQuestProgress(QuestType.encyclopedia, 1);

    saveGameData();
    notifyListeners();

  }

  /// 🆕 업적 일괄 수령 기능
  int claimAllAchievements() {
    int totalStones = 0;
    int claimCount = 0;
    
    for (var achievement in AchievementData.list) {
      while (true) {
        int currentStep = player.achievementSteps[achievement.id] ?? 0;
        if (currentStep >= achievement.targets.length) break;
        
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
          player.achievementSteps[achievement.id] = currentStep + 1;
          player.enhancementStone += reward;
          totalStones += reward;
          claimCount++;
        } else {
          break; // 현재 단계 목표 미달 시 다음 업적으로
        }
      }
    }
    
    if (claimCount > 0) {
      addLog('[업적 일괄수령] 달성한 모든 업적 단계를 완료하고 강화석을 획득했습니다.', LogType.event);
      saveGameData();
      notifyListeners();
    }
    return claimCount;
  }

  void refresh() => notifyListeners();

  // 🆕 [v0.7.0] 제작 숙련도 경험치 획득 및 레벨업
  void gainCraftingMasteryExp(int amount) {
    player.craftingMasteryExp += amount;
    bool leveledUp = false;
    while (player.craftingMasteryExp >= player.craftingMasteryNextExp && player.craftingMasteryLevel < 100) {
      player.craftingMasteryExp -= player.craftingMasteryNextExp;
      player.craftingMasteryLevel++;
      leveledUp = true;
    }
    if (leveledUp) {
      onSpecialEvent?.call('제작 숙련도 상승', 'Lv.${player.craftingMasteryLevel} 달성!');
    }
    notifyListeners();
  }

  // 🆕 [v0.7.0] 공통 제작 로직 (수동/자동 공용)
  Item? craftItem(ItemType type, int tier, {int shardCost = 0, int abyssalCost = 0}) {
    if (player.inventory.length >= player.maxInventory) return null;
    if (player.shards < shardCost || player.abyssalPowder < abyssalCost) return null;

    player.shards -= shardCost;
    player.abyssalPowder -= abyssalCost;

    // 1. 세트 아이템 결정 (기본 15% + 숙련도 보너스 최대 15%)
    String? setId;
    double setRoll = Random().nextDouble();
    double setChance = 0.15 + (player.craftingMasteryLevel * 0.0015); 
    
    if (setRoll < setChance) {
      setId = _getSetIdForTier(tier);
    }

    // 2. 아이템 생성
    Item newItem = Item.generate(player.level, tier: tier, forcedType: type, setId: setId);
    
    player.inventory.add(newItem);
    player.totalItemsFound++;
    player.updateEncyclopedia(newItem);

    // 🆕 [v0.7.9] 퀘스트 체크: 아이템 제작
    checkQuestProgress(QuestType.craftItem, tier);

    // 3. 숙련도 획득 (티어 * 10)
    gainCraftingMasteryExp(tier * 10);
    
    saveGameData();
    notifyListeners();
    return newItem;
  }

  // 🆕 입장권 제작 로직 (v0.8.15)
  bool craftTicket(String type) {
    int shardCost = (type == 'gold') ? 500 : 2000;
    int abyssalCost = (type == 'gold') ? 200 : 1000;

    if (player.shards < shardCost || player.abyssalPowder < abyssalCost) return false;

    player.shards -= shardCost;
    player.abyssalPowder -= abyssalCost;

    if (type == 'gold') {
      player.goldDungeonTicket++;
      addLog('🎫 황금의 방 입장권을 제작했습니다.', LogType.item);
      // 🆕 [v0.8.37] 퀘스트 체크: 황금의 방 입장권 제작
      checkQuestProgress(QuestType.craftGoldTicket, 1);
    } else {
      player.trialDungeonTicket++;
      addLog('🎫 시련의 방 입장권을 제작했습니다.', LogType.item);
      // 🆕 [v0.8.37] 퀘스트 체크: 시련의 방 입장권 제작
      checkQuestProgress(QuestType.craftTrialTicket, 1);
    }
    
    gainCraftingMasteryExp(50);
    saveGameData();
    notifyListeners();
    return true;
  }

  String? _getSetIdForTier(int tier) {
    switch (tier) {
      case 2: return 'desert';
      case 3: return 'mine';
      case 4: return 'dimension';
      case 5: return 'dragon';
      case 6: return 'ancient';
      default: return null;
    }
  }

  // 🆕 [v0.5.40] 자동 제작 엔진: 재료 충족 시 랜덤 부위 자동 생성
  void _resetAllSkillsToCooldown() {
    final now = DateTime.now();
    for (var skill in player.skills) {
      if (skill.isUnlocked && skill.type == SkillType.active) {
        skill.lastUsed = now; // 즉시 사용 불가 (쿨타임 끝까지 대기)
      }
    }
    // 상대방(방어자) 스킬도 초기화
    if (defenderSnapshot != null) {
      for (var skill in defenderSnapshot!.activeSkills) {
        if (skill.isUnlocked) {
          skill.lastUsed = now;
        }
      }
    }
  }

  void _processAutoCraft() {
    // 🆕 [v2.4.5] 성능 최적화: 무거운 루프 로직을 Microtask로 분리하여 처치 순간의 프레임 드랍 방지
    Future.microtask(() {
      final Map<int, int> shardCosts = { 2: 300, 3: 1000, 4: 3000, 5: 7500, 6: 15000 };
      final Map<int, int> coreCosts = { 2: 5, 3: 10, 4: 30, 5: 30, 6: 30 };

      bool changed = false;
      for (int t = 2; t <= 6; t++) {
        if (player.autoCraftTiers[t] == true) {
          int shardCost = shardCosts[t] ?? 999999;
          int coreCost = coreCosts[t] ?? 999999;

          while (player.shards >= shardCost && 
                 player.abyssalPowder >= coreCost && 
                 player.inventory.length < player.maxInventory) {
            
            final type = ItemType.values[Random().nextInt(6)]; 
            final newItem = craftItem(type, t, shardCost: shardCost, abyssalCost: coreCost);
            
            if (newItem != null) {
              changed = true;
              addLog('[자동제작] T$t ${newItem.type.nameKr} 제작 완료!', LogType.item);
              onLootAcquired?.call('🔨', 'T$t ${newItem.name}', newItem.grade, amount: 1);
            } else {
              break;
            }
          }
        }
      }
      // 데이터가 실제로 변경되었을 때만 UI 상의 알림 등을 위해 최소한으로 호출
      if (changed) notifyListeners();
    });
  }

  // 🆕 [v0.5.58] 길잡이 퀘스트 시스템 로직

  void checkQuestProgress(QuestType type, int value) {
    // 🆕 [v2.4.5] 퀘스트 체크도 Microtask로 분리하여 처치 순간의 부하 분산
    Future.microtask(() {
      if (player.currentQuestIndex >= GuideQuestData.quests.length) return;
      if (player.isQuestRewardClaimable) return;

      final quest = GuideQuestData.quests[player.currentQuestIndex];
      if (quest.type == type) {
        if (value >= quest.targetValue) {
          player.isQuestRewardClaimable = true;
          addLog('★ 퀘스트 완료! [${quest.title}] 보상을 확인하세요.', LogType.event);
          notifyListeners();
        }
      }
    });
  }

  void claimQuestReward() {
    if (!player.isQuestRewardClaimable) return;
    if (player.currentQuestIndex >= GuideQuestData.quests.length) return;

    final quest = GuideQuestData.quests[player.currentQuestIndex];
    final r = quest.reward;

    // 보상 지급
    player.gold += r.gold;
    player.enhancementStone += r.stone;
    player.abyssalPowder += r.abyssalPowder;
    player.shards += r.shards;
    player.cube += r.cube;
    player.soulStone += r.soulStone;
    player.protectionStone += r.protectionStone;

    addLog('[퀘스트 보상] ${quest.title} 완료 보상을 획득했습니다.', LogType.event);
    
    // 다음 퀘스트로 진행
    player.currentQuestIndex++;
    player.isQuestRewardClaimable = false;

    saveGameData();
    notifyListeners();
  }


  // ---------------------------------------------------------------------------
  // 🆕 [v0.8.17] 특별 시간 제한 던전 시스템 (Golden Room, Trial Room)
  // ---------------------------------------------------------------------------

  void startSpecialDungeon(ZoneId zoneId) {
    _specialDungeonTimer?.cancel();
    _specialDungeonTimeLeft = 60.0; // 60초 제한
    
    addLog('[던전 진입] ${currentZone.name}에 진입했습니다! (제한시간 60초)', LogType.event);
    
    // 🆕 [v0.8.37] 퀘스트 체크: 특별 던전 입장 (황금/시련 구분)
    if (zoneId == ZoneId.goldenRoom) {
      checkQuestProgress(QuestType.enterGoldDungeon, 1);
    } else if (zoneId == ZoneId.trialRoom) {
      checkQuestProgress(QuestType.enterTrialDungeon, 1);
    }
    
    notifyListeners();
  }

  void endSpecialDungeon() {
    _specialDungeonTimer?.cancel();
    _specialDungeonTimeLeft = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 🆕 [v0.6.2] 펫 탐사 파견 시스템 (Pet Expedition)
  // ---------------------------------------------------------------------------

  /// 특정 사냥터 슬롯에 펫을 파견합니다.
  String? dispatchPetToZone(ZoneId zoneId, int slotIndex, String petId) {
    // 0. 타워 및 특별 던전 파견 불가
    if (zoneId == ZoneId.tower || zoneId == ZoneId.goldenRoom || zoneId == ZoneId.trialRoom) {
      return "이 지역은 탐사 파견이 불가능합니다.";
    }

    final zoneKey = zoneId.name;
    
    // 1. 해당 펫이 이미 파견 중인지 체크
    bool isAlreadyDispatched = player.zoneExpeditions.values.any((list) => list.contains(petId));
    if (isAlreadyDispatched) return "이미 다른 지역에 파견된 펫입니다.";

    // 2. 메인 동행 펫인지 체크
    if (player.activePet?.id == petId) return "현재 동행 중인 펫은 파견할 수 없습니다.";

    // 3. 기존 보상이 있다면 자동 정산
    claimExpeditionRewards(zoneId);

    // 4. 슬롯 초기화 및 배치
    if (player.zoneExpeditions[zoneKey] == null) {
      player.zoneExpeditions[zoneKey] = [null, null, null];
    }
    player.zoneExpeditions[zoneKey]![slotIndex] = petId;
    
    // 5. 파견 시간 갱신 (최초 파견 시 현재 시간 설정)
    if (player.zoneLastClaimedAt[zoneKey] == null) {
      player.zoneLastClaimedAt[zoneKey] = DateTime.now().toIso8601String();
    }

    saveGameData();
    notifyListeners();
    return null;
  }

  /// 파견된 펫을 회수합니다.
  void recallPetFromZone(ZoneId zoneId, int slotIndex) {
    final zoneKey = zoneId.name;
    if (player.zoneExpeditions[zoneKey] == null) return;

    // 회수 전 보상 정산
    claimExpeditionRewards(zoneId);

    player.zoneExpeditions[zoneKey]![slotIndex] = null;
    
    // 모든 펫이 회수되면 시간 데이터 삭제 (선택 사항)
    bool hasAny = player.zoneExpeditions[zoneKey]!.any((id) => id != null);
    if (!hasAny) {
      player.zoneLastClaimedAt.remove(zoneKey);
    }

    saveGameData();
    notifyListeners();
  }

  /// 특정 사냥터의 탐사 보상을 수령합니다.
  Map<String, int> claimExpeditionRewards(ZoneId zoneId) {
    final zoneKey = zoneId.name;
    final baseRewards = calculateZoneExpeditionReward(zoneId);
    if (baseRewards.isEmpty) return {};

    final rand = Random();
    Map<String, int> actualRewards = Map.from(baseRewards);
    int minutes = baseRewards['minutes'] ?? 0;
    
    // 1. 대성공 체크 (Great Success)
    double greatSuccessChance = 5.0; // 기본 5%
    final petIds = player.zoneExpeditions[zoneKey] ?? [];
    for (var pid in petIds) {
      if (pid == null) continue;
      try {
        final pet = player.pets.firstWhere((p) => p.id == pid);
        if (pet.grade == ItemGrade.unique) greatSuccessChance += 2.0;
        if (pet.grade == ItemGrade.legendary) greatSuccessChance += 5.0;
        if (pet.grade == ItemGrade.mythic) greatSuccessChance += 10.0;
      } catch (_) {}
    }

    bool islandGreatSuccess = rand.nextDouble() * 100 < greatSuccessChance;
    if (islandGreatSuccess) {
      actualRewards['gold'] = (actualRewards['gold']! * 2.0).toInt();
      actualRewards['shards'] = (actualRewards['shards']! * 2.0).toInt();
      actualRewards['abyssalPowder'] = (actualRewards['abyssalPowder']! * 2.0).toInt();
      actualRewards['stone'] = (actualRewards['stone']! * 2.0).toInt();
    }

    // 2. 희귀 전리품 발견 (Rare Finds - 60분당 1회 주사위)
    int rolls = (minutes / 60).floor();
    double rareChanceMult = (zoneId == ZoneId.snowfield || zoneId == ZoneId.abyss) ? 2.0 : 1.0;
    
    int rerollGained = 0;
    int protectionGained = 0;
    int cubeGained = 0;

    for (int i = 0; i < rolls; i++) {
      double r = rand.nextDouble() * 100;
      if (r < 2.0 * rareChanceMult) rerollGained++;
      if (r < 0.5 * rareChanceMult) protectionGained++;
      if (r < 0.1 * rareChanceMult) cubeGained++;
    }

    // 보상 적용
    player.gold += actualRewards['gold'] ?? 0;
    player.shards += actualRewards['shards'] ?? 0;
    player.abyssalPowder += actualRewards['abyssalPowder'] ?? 0;
    player.enhancementStone += actualRewards['stone'] ?? 0;
    player.rerollStone += rerollGained;
    player.protectionStone += protectionGained;
    player.cube += cubeGained;

    // 마지막 수령 시간 갱신
    player.zoneLastClaimedAt[zoneKey] = DateTime.now().toIso8601String();

    String successTxt = islandGreatSuccess ? ' [★대성공★]' : '';
    addLog('[탐사]$successTxt ${HuntingZoneData.list.firstWhere((z) => z.id == zoneId).name} 보상 수령!', LogType.event);
    
    if (rerollGained > 0 || protectionGained > 0 || cubeGained > 0) {
      addLog('✨ 희귀 전리품 발견! (재설정석:$rerollGained, 보호석:$protectionGained, 큐브:$cubeGained)', LogType.item);
    }
    
    saveGameData();
    notifyListeners();
    return actualRewards;
  }

  /// UI 표시 및 정산용 보상 계산 로직
  Map<String, int> calculateZoneExpeditionReward(ZoneId zoneId) {
    final zoneKey = zoneId.name;
    final lastAtStr = player.zoneLastClaimedAt[zoneKey];
    final petIds = player.zoneExpeditions[zoneKey];

    if (lastAtStr == null || petIds == null || petIds.every((id) => id == null)) return {};

    final lastAt = DateTime.tryParse(lastAtStr) ?? DateTime.now();
    int minutes = DateTime.now().difference(lastAt).inMinutes;
    if (minutes < 1) return {};
    if (minutes > 1440) minutes = 1440; // 최대 24시간 제한

    final zone = HuntingZoneData.list.firstWhere((z) => z.id == zoneId);
    int tier = (zone.minLevel ~/ 40) + 1; // 대략적인 티어 계산 (초원 1, 숲 1, 광산 2...)
    if (zone.id == ZoneId.abyss) tier = 6;
    if (zone.id == ZoneId.tower) tier = 1;
    if (zone.id == ZoneId.goldenRoom || zone.id == ZoneId.trialRoom) tier = (player.maxStageReached ~/ 500).clamp(1, 6);

    double totalEfficiency = 0.0;
    for (String? pid in petIds) {
      if (pid == null) continue;
      try {
        final pet = player.pets.firstWhere((p) => p.id == pid);
        totalEfficiency += pet.dispatchEfficiency;
      } catch (_) {}
    }

    if (totalEfficiency <= 0) return {};

    double goldMult = 1.0;
    double shardMult = 1.0;
    double powderMult = 1.0;
    double stoneMult = 1.0;

    switch (zone.id) {
      case ZoneId.grassland:
      case ZoneId.forest: goldMult = 1.5; break;
      case ZoneId.mine: stoneMult = 1.5; break;
      case ZoneId.dungeon: powderMult = 1.5; break;
      case ZoneId.volcano: shardMult = 1.5; break;
      default: break;
    }

    double baseGoldPerMin = 120.0 * tier * goldMult;
    double baseShardPerMin = 0.5 * tier * shardMult;
    double basePowderPerMin = 0.2 * tier * powderMult;
    double baseStonePerMin = 0.2 * tier * stoneMult; // 🆕 0.05 -> 0.2 상향 (4배)
    
    int gold = (minutes * baseGoldPerMin * totalEfficiency).toInt();
    int shards = (minutes * baseShardPerMin * totalEfficiency).toInt();
    int powderReward = (minutes * basePowderPerMin * totalEfficiency).toInt();
    int coreReward = (killsPerMin > 0 && tier >= 2) ? (minutes * 0.1 * totalEfficiency).toInt() : 0;
    int stone = (minutes * baseStonePerMin * totalEfficiency).toInt(); // 🆕 baseStonePerMin 적용으로 광산 보너스(1.5x) 활성화


    return {
      'gold': gold,
      'shards': shards,
      'abyssalPowder': powderReward + coreReward,
      'stone': stone,
      'minutes': minutes,
    };
  }

  // [v2.0] 각종 타이머 업데이트 (GameLoop에서 호출)
  void updateTimers(double dt) {
    // 🆕 공용 애니메이션 수치 업데이트
    _animTimeTotal += dt;
    
    if (_skillDmgReductionTimeLeft > 0) {
      _skillDmgReductionTimeLeft = max(0.0, _skillDmgReductionTimeLeft - dt);
    }
    if (_killAtkBuffTimeLeft > 0) {
      _killAtkBuffTimeLeft = max(0.0, _killAtkBuffTimeLeft - dt);
    }
    if (_killDefBuffTimeLeft > 0) {
      _killDefBuffTimeLeft = max(0.0, _killDefBuffTimeLeft - dt);
    }
    if (_zoneAtkBuffTimeLeft > 0) {
      _zoneAtkBuffTimeLeft = max(0.0, _zoneAtkBuffTimeLeft - dt);
    }
    if (_zoneDefBuffTimeLeft > 0) {
      _zoneDefBuffTimeLeft = max(0.0, _zoneDefBuffTimeLeft - dt);
    }
    if (_specialDungeonTimeLeft > 0) {
      double oldVal = _specialDungeonTimeLeft;
      _specialDungeonTimeLeft = max(0.0, _specialDungeonTimeLeft - dt);
      if (oldVal > 0 && _specialDungeonTimeLeft <= 0) {
        onSpecialDungeonEnd?.call();
      }
    }
    
    // 🆕 몬스터 상태 이상 타이머 업데이트 (빙결/기절/심판)
    if (currentMonster != null) {
      bool changed = false;
      if (currentMonster!.frozenTimeLeft > 0) {
        currentMonster!.frozenTimeLeft = max(0.0, currentMonster!.frozenTimeLeft - dt);
        if (currentMonster!.frozenTimeLeft <= 0) changed = true;
      }
      if (currentMonster!.stunTimeLeft > 0) {
        currentMonster!.stunTimeLeft = max(0.0, currentMonster!.stunTimeLeft - dt);
        if (currentMonster!.stunTimeLeft <= 0) changed = true;
      }
      if (currentMonster!.judgmentTimeLeft > 0) {
        currentMonster!.judgmentTimeLeft = max(0.0, currentMonster!.judgmentTimeLeft - dt);
        if (currentMonster!.judgmentTimeLeft <= 0) changed = true;
      }
      if (changed) notifyListeners();
    }

    // 🆕 PvP 카운트다운 처리
    if (isPvPMode && _pvpCountdown > 0) {
      _pvpCountdown = max(0.0, _pvpCountdown - dt);
      _resetAllSkillsToCooldown(); // 🆕 카운트다운 동안 쿨타임 정지 (시작 직후부터 쿨타임 가동되도록)
      if (_pvpCountdown <= 0) {
        addLog('⚔️ 전투 개시! (FIGHT!)', LogType.event);
      }
      notifyListeners();
    }

    // 🆕 지면 연소 타이머 및 DOT 처리
    if (_scorchedGroundTimeLeft > 0) {
      _scorchedGroundTimeLeft = max(0.0, _scorchedGroundTimeLeft - dt);
      _burnAccumulator += dt;
      if (_burnAccumulator >= 0.5) { // 0.5초마다 틱 발생
        _burnAccumulator = 0;
        if (isPvPMode) {
          // 1. 방어자 DOT (Scorched Ground)
          if (defenderSnapshot != null && defenderCurrentHp > 0 && !isProcessingVictory && _pvpCountdown <= 0) {
            int dmg = _burnDmgPerTick;
            defenderCurrentHp = (defenderCurrentHp - dmg).clamp(0, defenderSnapshot!.maxHp);
            onDamageDealt?.call('🔥$dmg', dmg, false, true, oy: -15, shouldAnimate: false);
            if (defenderCurrentHp <= 0) {
              _processPvPVictory();
            }
          }
          // 2. 플레이어 DOT (Burn Status)
          if (isPlayerBurned && playerCurrentHp > 0 && !isProcessingVictory && _pvpCountdown <= 0) {
            // 상대방 공격력의 일정 비율 혹은 고정 데미지
            int pBurnDmg = (defenderSnapshot!.attack * 0.1).toInt(); // 상대 공격력의 10%
            playerCurrentHp = (playerCurrentHp - pBurnDmg).clamp(0, player.maxHp);
            onDamageDealt?.call('🔥$pBurnDmg', pBurnDmg, false, true, isPlayerTarget: true, shouldAnimate: false);
            if (playerCurrentHp <= 0) {
              _processPvPDefeat();
            }
          }
        } else {
          if (currentMonster != null && !currentMonster!.isDead) {
            int dmg = _burnDmgPerTick;
            currentMonster!.hp -= dmg;
            _monsterCurrentHp = currentMonster!.hp;
            onDamageDealt?.call('🔥$dmg', dmg, false, true, oy: -15, shouldAnimate: false); 
            if (currentMonster!.hp <= 0) {
              handleVictory(null);
            }
          }
        }
      }
      if (_scorchedGroundTimeLeft <= 0) {
        notifyListeners(); // 연소 종료 알림
      }
    }

    // 🆕 [v2.4.3] 통합 애니메이션 값 업데이트
    // 1. Hero Pulse (1초 주기로 0.0 -> 1.0 -> 0.0)
    double pulseSpeed = 1.0; // 1초
    if (_pulseExpanding) {
      _heroPulse += dt * pulseSpeed;
      if (_heroPulse >= 1.0) {
        _heroPulse = 1.0;
        _pulseExpanding = false;
      }
    } else {
      _heroPulse -= dt * pulseSpeed;
      if (_heroPulse <= 0.0) {
        _heroPulse = 0.0;
        _pulseExpanding = true;
      }
    }

    // 2. Hero Rotate (10초 주기로 0.0 -> 1.0)
    _heroRotate = (_heroRotate + dt / 10.0) % 1.0;

    // 3. Shimmer (2초 주기로 0.0 -> 1.0)
    _shimmerProgress = (_shimmerProgress + dt / 2.0) % 1.0;

    // 🆕 방어자 상태 이상 타이머 업데이트
    if (isPvPMode) {
      if (_defenderSkillDmgReductionTimeLeft > 0) _defenderSkillDmgReductionTimeLeft = max(0.0, _defenderSkillDmgReductionTimeLeft - dt);
      if (_defenderStunTimeLeft > 0) _defenderStunTimeLeft = max(0.0, _defenderStunTimeLeft - dt);
      if (_defenderFrozenTimeLeft > 0) _defenderFrozenTimeLeft = max(0.0, _defenderFrozenTimeLeft - dt);
      if (_defenderJudgmentTimeLeft > 0) _defenderJudgmentTimeLeft = max(0.0, _defenderJudgmentTimeLeft - dt);
    }
    
    // 🆕 플레이어 상태 이상 타이머 업데이트
    bool playerConditionChanged = false;
    if (_playerStunTimeLeft > 0) {
      _playerStunTimeLeft = max(0.0, _playerStunTimeLeft - dt);
      if (_playerStunTimeLeft <= 0) playerConditionChanged = true;
    }
    if (_playerFrozenTimeLeft > 0) {
      _playerFrozenTimeLeft = max(0.0, _playerFrozenTimeLeft - dt);
      if (_playerFrozenTimeLeft <= 0) playerConditionChanged = true;
    }
    if (_playerJudgmentTimeLeft > 0) {
      _playerJudgmentTimeLeft = max(0.0, _playerJudgmentTimeLeft - dt);
      if (_playerJudgmentTimeLeft <= 0) playerConditionChanged = true;
    }
    if (_playerBurnTimeLeft > 0) {
      _playerBurnTimeLeft = max(0.0, _playerBurnTimeLeft - dt);
      // 🔥 [v2.7.10] 플레이어 화상 도트 데미지 처리
      _burnAccumulator += dt;
      if (_burnAccumulator >= 0.5) {
        // 이미 2933라인 부근에서 _burnAccumulator가 scorchedGround 로직에 쓰이고 있으므로
        // 별도의 독립적인 accumulator를 쓰거나 로직을 통합해야 함.
        // 여기서는 단순화를 위해 scorched ground DOT 로직 하단에 플레이어 DOT도 통합 처리하도록 함.
      }
      if (_playerBurnTimeLeft <= 0) playerConditionChanged = true;
    }
    if (playerConditionChanged) notifyListeners();

    // 배치 업데이트 중이므로 여기서 notifyListeners를 불러도 endBatchUpdate에서 한 번만 호출됨
    notifyListeners();
  }

  // [v2.0] 모든 액티브 스킬의 쿨타임을 초 단위(seconds)로 감축
  void _reduceAllSkillCooldowns(double seconds) {
    if (seconds <= 0) return;
    for (var s in player.skills) {
      if (s.type == SkillType.active && s.lastUsed != null) {
        // lastUsed를 과거로 밀어내어 쿨타임이 더 빨리 차게 함
        s.lastUsed = s.lastUsed!.subtract(Duration(milliseconds: (seconds * 1000).toInt()));
      }
    }
  }

  void _increaseAllSkillCooldowns(double seconds) {
    if (seconds <= 0) return;
    for (var s in player.skills) {
      if (s.type == SkillType.active && s.lastUsed != null) {
        // lastUsed를 미래로 밀어내어 쿨타임 소모를 지연시킴
        s.lastUsed = s.lastUsed!.add(Duration(milliseconds: (seconds * 1000).toInt()));
      }
    }
  }
  // --- [무투회 로직] ---
  Map<String, dynamic> getPlayerSnapshot() {
    return {
      'attack': player.attack,
      'maxHp': player.maxHp,
      'defense': player.defense,
      'critChance': player.critChance,
      'critDamage': player.critDamage,
      'skillEchoChance': player.skillEchoChance,
      'cdr': player.cdr,
      'shieldChance': player.gainShieldChance,
    };
  }

  void generateTournament() {
    final snapshot = getPlayerSnapshot();
    final rand = Random();
    tournamentNPCs = [];
    
    // 15명의 가상 NPC 생성 (나머지 1명은 플레이어)
    List<String> npcNames = [
      '그림자 자객', '강철의 기사', '번개 마법사', '성스러운 치유사', 
      '무자비한 도끼', '바람의 궁수', '대지의 수호자', '심연의 포식자',
      '황금 용병', '불타는 영혼', '서리 거인', '고독한 검객',
      '신비한 약술사', '강철의 의지', '어둠의 집행자'
    ];
    npcNames.shuffle();

    for (int i = 0; i < 15; i++) {
      // 0.8 ~ 1.3 사이의 배율
      double scale = 0.8 + (rand.nextDouble() * 0.5);
      tournamentNPCs.add(TournamentNPC.generate(npcNames[i], snapshot, scale));
    }
    
    tournamentRound = 1; // 16강 시작
    tournamentResults = [];
    notifyListeners();
  }

  void startArenaMatch(int npcIndex) {
    if (tournamentNPCs.isEmpty || npcIndex >= tournamentNPCs.length) return;
    
    isArenaMode = true;
    isProcessingVictory = false; // 🆕 필수: 이전 사냥터 전투의 종료 대기 상태 해제
    pendingMonsterSpawn = false; // 🆕 필수: 예약된 일반 몬스터 스폰 취소
    
    currentOpponent = tournamentNPCs[npcIndex];
    
    // 🆕 [v2.3] 라운드별 난이도 스케일링 적용
    double roundMult = 1.0;
    bool isFinal = (tournamentRound >= 4);
    
    switch (tournamentRound) {
      case 1: roundMult = 1.0; break; // 16강 (NPC생성 시 배율 유지)
      case 2: roundMult = 1.2; break; // 8강 (20% 강화)
      case 3: roundMult = 1.5; break; // 4강 (50% 강화)
      case 4: roundMult = 2.2; break; // 결승 (120% 강화 + 챔피언 보정 별도)
    }

    // NPC 정보를 기반으로 가상 몬스터 생성 (전투 엔진 재활용)
    currentMonster = Monster(
      name: isFinal ? '👑 챔피언 ${currentOpponent!.name}' : '👹 ${currentOpponent!.name}',
      level: player.level,
      hp: (currentOpponent!.maxHp * roundMult).toInt(),
      maxHp: (currentOpponent!.maxHp * roundMult).toInt(),
      attack: (currentOpponent!.attack * roundMult).toInt(),
      defense: (currentOpponent!.defense * roundMult).toInt(),
      expReward: 0, 
      goldReward: 0, 
      imagePath: isFinal ? 'assets/images/monsters/chaos_knight.png' : 'assets/images/warrior.png',
    );
    monsterCurrentHp = currentMonster!.hp;
    playerCurrentHp = player.maxHp;
    playerShield = 0;
    
    String msg = isFinal 
      ? '🐲 [최종 결전] 오늘의 최강자 ${currentOpponent!.name}와의 결승전이 시작됩니다!'
      : '🏟️ [결투 시작] ${currentOpponent!.name}(${currentOpponent!.category.name})와 대결합니다!';
    addLog(msg, LogType.event);
    notifyListeners();
  }

  void _resolveArenaVictory() {
    isArenaMode = false;
    tournamentResults.add(true);
    addLog('🏆 [결투 승리] ${currentOpponent!.name}을(를) 꺾고 다음 라운드에 진출합니다!', LogType.event);
    
    // 🆕 현재 상대 물리침: 리스트에서 제거 (index 0)
    if (tournamentNPCs.isNotEmpty) {
      tournamentNPCs.removeAt(0); 
    }

    // 🆕 나머지 NPC들의 승패 시뮬레이션: 절반을 제거하여 다음 라운드 대진 구성
    int playersToEliminate = (tournamentNPCs.length / 2).floor();
    for (int i = 0; i < playersToEliminate; i++) {
        if (tournamentNPCs.isNotEmpty) {
            tournamentNPCs.removeAt(Random().nextInt(tournamentNPCs.length));
        }
    }
    
    tournamentRound++;
    if (tournamentRound > 4) {
      // 최종 우승 보상
      player.soulStone += 100;
      addLog('✨✨ [대회 우승] 무투회 최종 우승자로 등극했습니다! 영혼석 100개 획득!', LogType.event);
      tournamentRound = 5; // 종료 상태
    }

    currentMonster = null;
    spawnMonster(); // 일반 사냥터로 복귀 준비
    notifyListeners();
  }

  void _resolveArenaLoss() {
    isArenaMode = false;
    tournamentResults.add(false);
    addLog('❌ [결투 패배] ${currentOpponent!.name}에게 패배하여 무투회에서 탈락했습니다.', LogType.event);
    
    tournamentRound = 5; // 종료 상태
    playerCurrentHp = player.maxHp;
    currentMonster = null;
    spawnMonster(); // 일반 사냥터로 복귀
    notifyListeners();
  }
}
