import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player.dart';
import '../models/monster.dart';
import '../models/item.dart';
import '../models/skill.dart';
import '../models/hunting_zone.dart';
import '../models/pet.dart';
import '../services/auth_service.dart';
import '../services/cloud_save_service.dart';

enum LogType { damage, item, event }

class CombatLogEntry {
  final String message;
  final LogType type;
  final DateTime time;

  CombatLogEntry(this.message, this.type) : time = DateTime.now();
}

// 🆕 연타 스킬 타격 정보 (Ticker 기반 처리용)
class PendingHit {
  final int damage;
  final bool isSkill;
  final double offsetX;
  final double offsetY;
  final DateTime scheduledTime;

  PendingHit({
    required this.damage,
    required this.isSkill,
    required this.offsetX,
    required this.offsetY,
    required this.scheduledTime,
  });
}

class GameState extends ChangeNotifier {
  // --- 서비스 레이어 ---
  final AuthService authService = AuthService();
  final CloudSaveService _cloudSaveService = CloudSaveService();

  // --- 플레이어 및 전투 상태 ---
  Player player = Player();
  int _playerCurrentHp = 0;
  int get playerCurrentHp => _playerCurrentHp;
  set playerCurrentHp(int val) {
    if (_playerCurrentHp == val) return;
    _playerCurrentHp = val;
    // 💡 최적화: 전투 중 소량 변화는 Ticker가 처리하므로, 
    // 유의미한 상태 변화가 있을 때만 명시적으로 알리거나 
    // 외부에서 알림 주기를 제어하도록 유도
  }

  Monster? currentMonster;
  int _monsterCurrentHp = 0;
  int get monsterCurrentHp => _monsterCurrentHp;
  set monsterCurrentHp(int val) {
    if (_monsterCurrentHp == val) return;
    _monsterCurrentHp = val;
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
    _currentZone = val;
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
  int autoDismantleLevel = 0;
  
  // --- 관리자 설정 ---
  double monsterDefenseMultiplier = 1.0; // 몬스터 방어력 배율 (0.0 ~ 1.0)

  // --- 전투 로그 ---
  List<CombatLogEntry> logs = [];
  final int maxLogs = 50;

  // --- 시스템 상태 ---
  bool isProcessingVictory = false;
  bool isCloudSynced = false;
  DateTime? lastCloudSaveTime;
  DateTime? lastMonsterSpawnTime;
  int _skillRoundRobinIndex = 0;
  
  // 🆕 연타 스킬 처리용 큐
  final Queue<PendingHit> pendingHits = Queue<PendingHit>();
  
  // 🆕 몬스터 소환 대기 플래그 (GameLoop에서 접근)
  bool pendingMonsterSpawn = false;
  DateTime? monsterSpawnScheduledTime;
  
  
  // --- [최적화] 배치 저장용 ---
  int _victoryCountSinceSave = 0;
  Timer? _autoSaveTimer;
  
  // --- UI 통신용 콜백 ---
  Function(String text, bool isCrit, bool isSkill, {double? ox, double? oy})? onDamageDealt;
  Function(int damage)? onPlayerDamageTaken;
  VoidCallback? onMonsterSpawned;
  Function(int gold, int exp)? onVictory;
  Function(int healAmount)? onHeal;
  VoidCallback? onStageJump; // [v0.0.79] 스테이지 점프 발생 시 호출

  // 🆕 초기화 완료 여부 확인용
  final Completer<void> initializationCompleter = Completer<void>();
  Future<void> get initialized => initializationCompleter.future;

  // --- 초기화 ---
  GameState() {
    _initializeGame();
    // 🆕 10초마다 자동 저장 타이머 시작
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_victoryCountSinceSave > 0) {
        saveGameData(); 
      }
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    try {
      if (!authService.isLoggedIn) {
        await authService.signInAnonymously();
      }
      await loadGameData();
    } catch (e) {
      debugPrint('초기화 중 오류 발생: $e');
      await loadGameData();
    } finally {
      // 🆕 초기화 완료 알림 (성공/실패 무관하게 완료 처리)
      if (!initializationCompleter.isCompleted) {
        initializationCompleter.complete();
      }
    }
  }

  // --- 데이터 관리 ---
  Future<void> saveGameData({bool forceCloud = false}) async {
    final nowTime = DateTime.now();
    final nowStr = nowTime.toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    
    final saveData = {
      'player': player.toJson(),
      'current_stage': currentStage,
      'current_zone_id': currentZone.id.name,
      'last_save_time': nowStr,
      'zone_stages': zoneStages.map((k, v) => MapEntry(k.name, v)),
      'auto_advance': autoAdvance,
      'gold_per_min': goldPerMin,
      'exp_per_min': expPerMin,
      'kills_per_min': killsPerMin,
      'auto_dismantle_level': autoDismantleLevel,
    };

    await prefs.setString('player_save_data', jsonEncode(saveData['player']));
    await prefs.setInt('current_stage', currentStage);
    await prefs.setString('current_zone_id', currentZone.id.name);
    await prefs.setString('lastSaveTime', nowStr);
    await prefs.setDouble('gold_per_min', goldPerMin);
    await prefs.setDouble('exp_per_min', expPerMin);
    await prefs.setDouble('kills_per_min', killsPerMin);
    await prefs.setInt('auto_dismantle_level', autoDismantleLevel);
    
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
        'auto_dismantle_level': prefs.getInt('auto_dismantle_level') ?? 0,
      };
    }

    if (targetData != null) {
      _applyLoadedData(targetData);
      if (isFromCloud) {
        addLog('클라우드에서 데이터를 불러왔습니다.', LogType.event);
        isCloudSynced = true;
      } else {
        isCloudSynced = cloudDataMap != null;
      }
    } else {
      _initializeStarterData();
    }

    // 데이터 로드 후 첫 몬스터 생성
    spawnMonster();
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
    
    autoAdvance = targetData['auto_advance'] ?? true;
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
    autoDismantleLevel = targetData['auto_dismantle_level'] ?? 0;
    
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
  void spawnMonster() {
    bool isFinal = (stageKills >= targetKills - 1);
    currentMonster = Monster.generate(currentZone, currentStage, isFinal: isFinal);
    monsterCurrentHp = currentMonster!.hp;
    lastMonsterSpawnTime = DateTime.now();
    isProcessingVictory = false;
    onMonsterSpawned?.call();
    notifyListeners();
  }

  void processCombatTurn() {
    if (currentMonster == null || isProcessingVictory) return;

    final activeSkills = player.skills.where((s) => s.type == SkillType.active && s.isUnlocked).toList();
    Skill? selectedSkill;

    if (activeSkills.isNotEmpty) {
      int startIndex = _skillRoundRobinIndex % activeSkills.length;
      for (int i = 0; i < activeSkills.length; i++) {
        int checkIdx = (startIndex + i) % activeSkills.length;
        final s = activeSkills[checkIdx];
        if (s.isReady(player.cdr)) {
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
    if (currentMonster == null) return;
    
    // 몬스터 방어력에 배율 적용 (관리자 설정)
    double effectiveDefense = currentMonster!.defense * monsterDefenseMultiplier;
    double defenseRating = 100 / (100 + effectiveDefense);
    double variance = 0.9 + (Random().nextDouble() * 0.2);
    double rawDamage = (player.attack * defenseRating) * variance * player.potentialFinalDamageMult;
    int baseDmg = max(rawDamage.toInt(), (player.attack * 0.1 * variance).toInt()).clamp(1, 999999999);
    
    damageMonster(baseDmg, false, false);
    // notifyListeners(); // 💡 최적화: Ticker가 이미 UI를 60FPS로 갱신 중임
  }

  void _useSkill(Skill skill) {
    if (currentMonster == null) return;
    skill.lastUsed = DateTime.now();
    player.totalSkillsUsed++;

    // 스킬별 타격 횟수 정의
    int hits = 1;
    if (skill.id == 'act_1') hits = 3; // 바람 베기는 3연타

    // 몬스터 방어력에 배율 적용 (관리자 설정)
    double effectiveDefense = currentMonster!.defense * monsterDefenseMultiplier;
    double defenseRating = 100 / (100 + effectiveDefense);
    
    // 연타 스킬의 경우, 각 타격의 UI 위치를 미리 계산
    List<Offset> offsets = List.generate(hits, (index) => Offset(
      hits > 1 ? (Random().nextDouble() * 60 - 30) : 0,
      hits > 1 ? (Random().nextDouble() * 40 - 20) : 0,
    ));

    // 🆕 Ticker 기반 처리: 각 타격을 큐에 추가
    final now = DateTime.now();
    for (int i = 0; i < hits; i++) {
      double variance = 0.9 + (Random().nextDouble() * 0.2);
      double powerMult = skill.currentValue;
      
      double rawDmg = (player.attack * (powerMult / 100) * defenseRating) * variance * player.potentialFinalDamageMult;
      int baseDmg = max(rawDmg.toInt(), (player.attack * 0.1 * variance).toInt()).clamp(1, 999999999);
      
      // 타격 시간 예약 (0ms, 150ms, 300ms)
      final scheduledTime = now.add(Duration(milliseconds: i * 150));
      
      pendingHits.add(PendingHit(
        damage: baseDmg,
        isSkill: true,
        offsetX: offsets[i].dx,
        offsetY: offsets[i].dy,
        scheduledTime: scheduledTime,
      ));
    }
  }

  // 🆕 데미지 처리 통합 헬퍼 (최적화) - GameLoop에서도 접근 가능하도록 public
  void damageMonster(int baseDmg, bool isMonsterAtk, bool isSkill, {double ox = 0, double oy = 0}) {
    if (currentMonster == null || currentMonster!.isDead) return;

    // 치명타 적용
    bool isCrit = Random().nextDouble() * 100 < player.critChance;
    int finalDmg = isCrit ? (baseDmg * player.critDamage / 100).toInt() : baseDmg;

    // 실제 HP 차감
    currentMonster!.hp -= finalDmg;
    _monsterCurrentHp = currentMonster!.hp; // 직접 변수 수정 (notifyListeners 억제)

    // UI 알림 (Floating Text)
    String text = isSkill 
      ? (isCrit ? '⚡CRITICAL $finalDmg' : '🔥SKILL $finalDmg')
      : finalDmg.toString();
    
    onDamageDealt?.call(text, isCrit, isSkill, ox: ox, oy: oy);

    // 흡혈 처리
    if (!isMonsterAtk && player.lifesteal > 0 && playerCurrentHp < player.maxHp) {
      int lifestealAmt = (finalDmg * player.lifesteal / 100).toInt();
      if (lifestealAmt > 0) {
        _playerCurrentHp = (_playerCurrentHp + lifestealAmt).clamp(0, player.maxHp);
        onHeal?.call(lifestealAmt);
      }
    }

    // 사망 체크
    _checkMonsterDeath();
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

  void handleVictory(Duration? killDuration) {
    int finalGold = (currentMonster!.goldReward * player.goldBonus / 100).toInt();
    int expReward = currentMonster!.expReward;
    
    player.gainExp(expReward);
    player.gold += finalGold;
    player.totalKills++;
    player.totalGoldEarned += finalGold;

    onVictory?.call(finalGold, expReward);

    bool isTower = currentZone.id == ZoneId.tower;
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

    _dropMaterials(currentMonster!.level);
    _dropItem();
    
    // 💡 최적화: 매 처치마다 저장하지 않고 배치(Batch) 처리
    _victoryCountSinceSave++;
    if (_victoryCountSinceSave >= 10) {
      saveGameData();
      _victoryCountSinceSave = 0;
    }
    
    // 🆕 전투 리듬 개선: 100ms 대기 후 다음 몬스터 소환 (타격감 확보)
    pendingMonsterSpawn = true;
    monsterSpawnScheduledTime = DateTime.now().add(const Duration(milliseconds: 100));
  }

  void _dropItem() {
    final rand = Random();
    double dropChance = currentMonster!.itemDropChance * (player.dropBonus / 100);
    
    if (rand.nextDouble() < dropChance) {
      final newItem = Item.generate(player.level, tier: 1); 
      if (player.addItem(newItem)) {
        addLog('[획득] ${newItem.grade.name} 등급의 ${newItem.type.nameKr} 획득!', LogType.item);
        player.totalItemsFound++;
        player.updateEncyclopedia(newItem); // [v0.0.78] 획득 시 도감 갱신
      }
    }
  }

  void _dropMaterials(int monsterLevel) {
    final rand = Random();
    
    // 1. 강화석 드롭 (10% 확률로 대폭 하향 - 분해 가치 증대)
    if (rand.nextDouble() < 0.1) {
      int amount = 1 + (monsterLevel / 50).floor() + rand.nextInt(3);
      player.enhancementStone += amount;
      addLog('[공명] 강화석 $amount개 획득!', LogType.item);
    }
    
    // 2. 가루 드롭 (수량 밸런스 조정)
    if (rand.nextDouble() < 0.4) {
      int amount = (monsterLevel / 5).ceil() + rand.nextInt(10);
      player.powder += amount;
      addLog('[추출] 신비로운 가루 $amount개 획득!', LogType.item);
    }
    
    // 3. 재설정석 드롭 (10% 확률 - 희귀)
    if (rand.nextDouble() < 0.1) {
      player.rerollStone += 1;
      addLog('[희귀] 옵션 재설정석 획득!', LogType.item);
    }
    
    // 4. 보호석 (2% 확률)
    if (rand.nextDouble() < 0.02) {
      player.protectionStone += 1;
      addLog('[전설] 강화 보호석 획득!', LogType.item);
    }

    // 5. 강화 큐브 드롭 (0.1% 확률)
    if (rand.nextDouble() < 0.001) {
      player.cube += 1;
      addLog('[신화] 강화 큐브 획득!', LogType.item);
    }

    // --- [v0.0.60] 스펙 기반 게이트 드랍 (심연의 구슬) ---
    double avgLv = player.averageEnhanceLevel;
    if (avgLv >= 13.0 && rand.nextDouble() < 0.03) {
      player.tierCores[2] = (player.tierCores[2] ?? 0) + 1;
      addLog('[게이트] 심연의 구슬 [T2] 획득!', LogType.event);
    }
    if (avgLv >= 15.0 && rand.nextDouble() < 0.01) {
      player.tierCores[3] = (player.tierCores[3] ?? 0) + 1;
      addLog('[게이트] 심연의 구슬 [T3] 획득!', LogType.event);
    }
  }

  void addLog(String message, LogType type) {
    logs.insert(0, CombatLogEntry(message, type));
    if (logs.length > maxLogs) logs.removeLast();
    notifyListeners();
  }

  void applyRegen() {
    if (playerCurrentHp <= 0 || playerCurrentHp >= player.maxHp) return;
    double regenAmount = player.maxHp * (player.hpRegen / 100);
    int finalRegen = regenAmount.toInt();
    if (finalRegen > 0) {
      playerCurrentHp = (playerCurrentHp + finalRegen).clamp(0, player.maxHp);
      onHeal?.call(finalRegen);
      notifyListeners();
    }
  }

  void monsterPerformAttack() {
    if (currentMonster == null || isProcessingVictory) return;
    
    double mVariance = 0.9 + (Random().nextDouble() * 0.2);
    double pDefenseRating = 100 / (100 + player.defense);
    double rawMDmg = (currentMonster!.attack * pDefenseRating) * mVariance;
    int mDmg = max(rawMDmg.toInt(), (currentMonster!.attack * 0.1 * mVariance).toInt()).clamp(1, 999999999);

    playerCurrentHp -= mDmg;
    onPlayerDamageTaken?.call(mDmg);
    
    if (playerCurrentHp <= 0) {
      playerCurrentHp = 0;
      handlePlayerDeath();
    }
    notifyListeners();
  }

  void handlePlayerDeath() {
    playerCurrentHp = player.maxHp;
    currentStage = max(1, currentStage - 5);
    zoneStages[currentZone.id] = currentStage;
    addLog('사망했습니다. 안전을 위해 5스테이지 이전으로 후퇴합니다.', LogType.event);
    spawnMonster();
    notifyListeners();
  }

  // --- [v0.0.85] 아이템 및 펫 비즈니스 로직 ---

  void toggleItemLock(Item item) {
    item.isLocked = !item.isLocked;
    saveGameData();
    notifyListeners();
  }

  void rerollItemOptions(Item item) {
    if (item.rerollCount >= 5 || item.isLocked) return;
    
    int lockCount = item.subOptions.where((o) => o.isLocked).length;
    int powderCost = lockCount == 0 ? 0 : (1000 * pow(10, lockCount - 1)).toInt();
    
    if (player.rerollStone < 1 || player.powder < powderCost) return;

    player.rerollStone -= 1;
    player.powder -= powderCost;
    
    item.rerollSubOptions(Random());
    
    saveGameData();
    notifyListeners();
  }

  void enhanceItem(Item item) {
    if (item.isLocked || player.gold < item.enhanceCost || player.enhancementStone < item.stoneCost) return;

    player.gold -= item.enhanceCost;
    player.enhancementStone -= item.stoneCost;
    
    bool isSuccess = Random().nextDouble() < item.successChance;
    String resultMsg = item.processEnhance(isSuccess);
    
    if (isSuccess) {
      addLog(resultMsg, LogType.event);
      player.updateEncyclopedia(item);
    } else {
      addLog(resultMsg, LogType.event);
      if (item.isBroken) {
        int successionLevel = (item.enhanceLevel * 0.7).floor();
        player.enhancementSuccession[item.tier] = successionLevel;
      }
    }
    
    saveGameData();
    notifyListeners();
  }

  void promoteItem(Item item) {
    if (!item.canPromote) return;
    if (player.gold < item.promotionGoldCost || player.cube < item.promotionCubeCost) return;

    player.gold -= item.promotionGoldCost;
    player.cube -= item.promotionCubeCost;
    
    int oldTier = item.tier;
    item.promote();
    
    addLog("[승급 성공] ${item.name}이(가) T$oldTier에서 T${item.tier}로 진화했습니다! (+10 계승)", LogType.event);
    player.updateEncyclopedia(item);
    
    saveGameData();
    notifyListeners();
  }

  Map<String, int> executeDismantle(Item item) {
    if (item.isLocked) return {};
    
    player.inventory.removeWhere((i) => i.id == item.id);
    var rewards = _calculateDismantleRewards(item);
    
    player.gold += rewards['gold']!;
    player.powder += rewards['powder']!;
    player.enhancementStone += rewards['stone']!;
    player.rerollStone += rewards['reroll']!;
    player.protectionStone += rewards['protection']!;
    player.cube += rewards['cube']!;
    
    int tier = rewards['tier']!;
    int shards = rewards['shards']!;
    player.tierShards[tier] = (player.tierShards[tier] ?? 0) + shards;
    
    addLog('[분해] ${item.name}을(를) 분해하여 재료를 획득했습니다.', LogType.item);
    saveGameData();
    notifyListeners();

    return rewards;
  }

  Map<String, int> executeBulkDismantle(ItemGrade maxGrade) {
    int dismantleCount = 0;
    int totalGold = 0;
    int totalPowder = 0;
    int totalStone = 0;
    int totalReroll = 0;
    int totalProtection = 0;
    int totalCube = 0;
    Map<int, int> totalShards = {}; // 티어별 합산

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
        
        int tier = rewards['tier']!;
        int shards = rewards['shards']!;
        player.tierShards[tier] = (player.tierShards[tier] ?? 0) + shards;
        totalShards[tier] = (totalShards[tier] ?? 0) + shards;
        
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

    if (dismantleCount > 0) {
      addLog('[일괄분해] $dismantleCount개의 아이템을 분해했습니다.', LogType.item);
      saveGameData();
      notifyListeners();
    }

    return {
      'count': dismantleCount,
      'gold': totalGold,
      'powder': totalPowder,
      'stone': totalStone,
      'reroll': totalReroll,
      'protection': totalProtection,
      'cube': totalCube,
      // shards 정보는 복잡하므로 count와 핵심 재화 위주로 반환하거나 필요시 확장
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

  void summonPet(int count) {
    int cost = count == 1 ? 10000 : 90000;
    if (player.gold < cost) return;

    player.gold -= cost;
    List<Pet> allPets = PetData.getInitialPets();
    
    for (int i = 0; i < count; i++) {
      double rand = Random().nextDouble() * 100;
      Pet selected;
      int subIdx = Random().nextInt(5);

      if (rand < 0.05) {
        selected = allPets[25 + subIdx];
      } else if (rand < 0.5) {
        selected = allPets[20 + subIdx];
      } else if (rand < 3.0) {
        selected = allPets[15 + subIdx];
      } else if (rand < 10.0) {
        selected = allPets[10 + subIdx];
      } else if (rand < 40.0) {
        selected = allPets[5 + subIdx];
      } else {
        selected = allPets[0 + subIdx];
      }

      if (!player.pets.any((p) => p.id == selected.id)) {
        player.pets.add(selected);
        addLog('펫 획득! [${selected.grade.name}] ${selected.name}', LogType.event);
      } else {
        player.pets.firstWhere((p) => p.id == selected.id).level++;
      }
    }
    
    saveGameData();
    notifyListeners();
  }

  void refresh() => notifyListeners();
}
