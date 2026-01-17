import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/player.dart';
import 'models/monster.dart';
import 'models/item.dart';
import 'models/skill.dart';
import 'models/pet.dart';
import 'models/achievement.dart';
import 'models/hunting_zone.dart';
import 'services/update_service.dart';

void main() {
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

class _GameMainPageState extends State<GameMainPage> with TickerProviderStateMixin {
  late Player player;
  Monster? currentMonster;
  DateTime? monsterSpawnTime; // 처치 속도 측정을 위해 추가
  List<CombatLogEntry> combatLogs = [];
  List<CombatLogEntry> damageLogs = [];
  List<CombatLogEntry> itemLogs = [];
  List<CombatLogEntry> eventLogs = [];
  Timer? battleTimer;
  int _selectedIndex = 0; // 0~9
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
  List<FloatingText> floatingTexts = [];

  // 효율 측정용 데이터
  final List<GainRecord> _recentGains = [];
  double _goldPerMin = 0;
  double _expPerMin = 0;
  double _killsPerMin = 0;
  int _sessionGold = 0;
  int _sessionExp = 0;
  Timer? _efficiencyTimer;

  // 스테이지 진행 관련
  int _stageKills = 0;
  final int _targetKills = 10;
  int _currentStage = 1;
  bool _autoAdvance = true; // 스테이지 자동 등반 여부
  // 사냥터 관리
  HuntingZone _currentZone = HuntingZoneData.list[0];
  Map<ZoneId, int> _zoneStages = { for (var z in HuntingZoneData.list) z.id : 1 };

  // 전리품 파티클 시스템
  final List<LootParticle> _lootParticles = [];
  final GlobalKey _monsterKey = GlobalKey();
  final GlobalKey _goldTargetKey = GlobalKey();
  final GlobalKey _expTargetKey = GlobalKey();
  
  // 관리자 모드
  bool _isAdminAuthenticated = false;
  double _monsterDefenseMultiplier = 1.0; // 몬스터 방어력 배율 (0.0 ~ 1.0)

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
    _uiTickerController.addListener(() {
      _updateParticles(); // 매 프레임 파티클 리스트 정기 청소
    });
    
    // 데이터 먼저 불러오기
    _loadGameData().then((_) {
      _spawnMonster();
      _startBattleLoop();
    });

    // 1초마다 효율 갱신
    _efficiencyTimer = Timer.periodic(const Duration(seconds: 10), (t) => _updateEfficiency());
    
    // 오프라인 보상 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOfflineRewards();
      // 자동 업데이트 체크
      UpdateService.checkUpdate(context);
    });
  }

  Future<void> _saveGameData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_save_data', jsonEncode(player.toJson()));
    // 스테이지 정보도 별도 저장
    await prefs.setInt('current_stage', _currentStage);
    await prefs.setString('current_zone_id', _currentZone.id.name);
  }

  Future<void> _loadGameData() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('player_save_data');
    if (data != null) {
      try {
        setState(() {
          player = Player.fromJson(jsonDecode(data));
          playerCurrentHp = player.maxHp;
          _currentStage = prefs.getInt('current_stage') ?? 1;
          String? zoneName = prefs.getString('current_zone_id');
          if (zoneName != null) {
            _currentZone = HuntingZoneData.list.firstWhere((z) => z.id.name == zoneName);
          }
        });
      } catch (e) {
        debugPrint('데이터 로드 실패: $e');
      }
    } else {
      // [신규 플레이어 지원] 데이터가 없는 경우 초기 무기 지급
      setState(() {
        Item starterWeapon = Item(
          id: 'starter_${DateTime.now().millisecondsSinceEpoch}',
          name: '모험가의 목검',
          type: ItemType.weapon,
          grade: ItemGrade.common,
          mainStat: 100, // 리빌딩된 1티어 무기 공격력 (상향)
          subOptions: [],
          enhanceLevel: 0,
          durability: 100,
          maxDurability: 100,
          isNew: false,
        );
        player.equipItem(starterWeapon);
        playerCurrentHp = player.maxHp; // 무기 장착 후 HP 갱신
        _addLog('환영합니다! 모험을 시작하기 위해 [모험가의 목검]을 지급했습니다.', LogType.event);
      });
    }
  }

  Future<void> _checkOfflineRewards() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSaveStr = prefs.getString('lastSaveTime');
    
    if (lastSaveStr != null) {
      final lastTime = DateTime.parse(lastSaveStr);
      // 현재 효율(분당 골드 등) 정보가 없을 경우 대비 기본값 설정 (추후 정교화 가능)
      // 초보자 배려: 최소 효율 보장
      double gMin = _goldPerMin > 0 ? _goldPerMin : 50.0;
      double eMin = _expPerMin > 0 ? _expPerMin : 30.0;
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
    _playerAnimController.dispose();
    _monsterAnimController.dispose();
    _uiTickerController.dispose();
    _shimmerController.dispose();
    _heroPulseController.dispose();
    _heroRotateController.dispose();
    super.dispose();
  }

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
    setState(() {
      currentMonster = Monster.generate(_currentZone, _currentStage);
      monsterSpawnTime = DateTime.now(); // 스폰 시점 기록
      _addLog('새로운 적 ${currentMonster!.name}이(가) 나타났습니다!', LogType.event);
    });
  }

  void _startBattleLoop() {
    battleTimer?.cancel();
    // 공격 속도에 따른 간격 계산 (기본 1.0 = 1000ms, 2.0 = 500ms)
    int intervalMs = (1000 / player.attackSpeed).toInt().clamp(100, 2000); 
    
    battleTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (currentMonster != null) {
        _processCombatTurn();
      }
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
      
      // 3. 최종 데미지: 공격력 * 데미지 배율 (단, 공격력의 최소 10% 보장)
      double rawDamage = player.attack * defenseRating;
      double minDamage = player.attack * 0.1;
      int baseDmg = max(rawDamage, minDamage).toInt().clamp(1, 999999999);

      // 치명타 여부 계산
      bool isCrit = Random().nextDouble() * 100 < player.critChance;
      int pDmg = isCrit ? (baseDmg * player.critDamage / 100).toInt() : baseDmg;

      // 전투 탭(0번)일 때만 애니메이션 연출 실행
      if (_selectedIndex == 0) {
        _playerAnimController.forward().then((_) => _playerAnimController.reverse());
        _addFloatingText(isCrit ? 'CRITICAL $pDmg' : '-$pDmg', true, isCrit: isCrit);
      }
      
      currentMonster!.hp -= pDmg;
      if (isCrit) {
        _addLog('[CRITICAL] ${player.name} -> ${currentMonster!.name} [$pDmg 피격]!!!', LogType.damage);
      }
      
      // 자동 스킬 사용 체크 (준비된 스킬 중 첫 번째 사용)
      final readySkill = player.skills.where((s) => s.type == SkillType.active && s.isUnlocked && s.isReady(player.cdr)).firstOrNull;
      if (readySkill != null) {
        _useSkill(readySkill);
      }
      
      // 스킬 사용 후 몬스터가 이미 죽었을 수 있으므로 null 체크 추가
      if (currentMonster == null) return;
      
      if (currentMonster!.isDead) {
        // HP 바가 0으로 떨어지는 애니메이션 시간을 벌어줌 (250ms)
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && currentMonster != null && currentMonster!.isDead) {
            _handleVictory();
          }
        });
        return;
      }
      
      // 체력 재생 적용 (매 턴마다 소량 회복)
      if (playerCurrentHp < player.maxHp) {
        playerCurrentHp = (playerCurrentHp + player.hpRegen).toInt().clamp(0, player.maxHp);
      }

      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted || currentMonster == null) return;
        setState(() {
          if (_selectedIndex == 0) {
            _monsterAnimController.forward().then((_) => _monsterAnimController.reverse());
            _addFloatingText('-${(currentMonster!.attack - player.defense).clamp(1, 99999)}', false);
          }
          
          // 몬스터의 데미지도 플레이어에게 Soft Cap 공식으로 적용
          double pDefenseRating = 100 / (100 + player.defense);
          double rawMDmg = currentMonster!.attack * pDefenseRating;
          double minMDmg = currentMonster!.attack * 0.1;
          int mDmg = max(rawMDmg, minMDmg).toInt().clamp(1, 999999999);

          playerCurrentHp -= mDmg;
          if (playerCurrentHp <= 0) _handlePlayerDeath();
        });
      });
    });
  }

  void _handleVictory() {
    int finalGold = (currentMonster!.goldReward * player.goldBonus / 100).toInt();
    _addLog('전투 승리! ${currentMonster!.expReward} EXP, $finalGold G 획득', LogType.item);
    
    player.gainExp(currentMonster!.expReward);
    player.gold += finalGold;
    _sessionGold += finalGold;
    _sessionExp += currentMonster!.expReward;
    
    // 드롭 보너스 적용된 확률 계산
    double finalDropChance = currentMonster!.itemDropChance * (player.dropBonus / 100);
    if (Random().nextDouble() < finalDropChance) {
      Item newItem = Item.generate(player.level);
      if (player.addItem(newItem)) {
        _addLog('[획득] ${newItem.name} (${newItem.grade.name})', LogType.item);
        player.totalItemsFound++;
      }
    }
    // 효율 데이터 및 누적 통계 기록
    _recentGains.add(GainRecord(DateTime.now(), gold: finalGold, exp: currentMonster!.expReward, kills: 1));
    player.totalKills++;
    player.totalGoldEarned += finalGold;
    
    _updateLastSaveTime(); // 주기적인 저장

    // 몬스터 위치 계산 후 파티클 생성
    RenderBox? box = _monsterKey.currentContext?.findRenderObject() as RenderBox?;
    Offset spawnPos = const Offset(200, 300); // 대비용 기본값
    if (box != null) {
      // 몬스터 위젯의 중앙 하단(발밑) 부근에서 튀어나오게 조정
      spawnPos = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
      // SafeArea나 다른 레이어 오차 보정 (대략적인 화면 상대 좌표)
      spawnPos = Offset(spawnPos.dx, spawnPos.dy - 150); 
    }
    _spawnLootParticles(finalGold, currentMonster!.expReward, spawnPos);

    // 재료 드롭 (방안 A: 수량형 재료)
    _dropMaterials(currentMonster!.level);

    // 스테이지 진행도 업데이트
    setState(() {
      // 쾌속 등반 (Jump): 몬스터 처치 속도에 따라 스테이지를 건너뜀
      // 1초 미만: 2단계, 2초 미만: 1단계
      int jump = 0;
      if (monsterSpawnTime != null) {
        int killTimeMs = DateTime.now().difference(monsterSpawnTime!).inMilliseconds;
        if (killTimeMs < 1000) jump = 2;
        else if (killTimeMs < 2000) jump = 1;
      }

      _stageKills++;
      if (_stageKills >= _targetKills) {
        if (_autoAdvance) {
          _stageKills = 0;
          _currentStage += (1 + jump); // 점프 적용
          _zoneStages[_currentZone.id] = _currentStage;
          _addLog('스테이지 클리어! [${_currentZone.name}-${Monster.getDisplayStage(_currentStage)}] 진입 ${jump > 0 ? "($jump단계 점프!)" : ""}', LogType.event);
        } else {
          _stageKills = _targetKills - 1; // 꽉 찬 상태 유지 (또는 0으로 리셋 후 반복)
        }
      }
    });

    // 즉시 다음 몬스터 생성 (리스폰 공백 제거)
    _spawnMonster();
    
    // 자동 저장 실행
    _saveGameData(); 
  }

  void _dropMaterials(int monsterLevel) {
    final rand = Random();
    
    // 1. 강화석 드롭 (60% 확률)
    if (rand.nextDouble() < 0.6) {
      int amount = (monsterLevel / 2).ceil() + rand.nextInt(3);
      player.enhancementStone += amount;
      _addLog('[공명] 강화석 $amount개 획득!', LogType.item);
    }
    
    // 2. 가루 드롭 (40% 확률)
    if (rand.nextDouble() < 0.4) {
      int amount = (monsterLevel * 2) + rand.nextInt(10);
      player.powder += amount;
      _addLog('[추출] 신비로운 가루 $amount개 획득!', LogType.item);
    }
    
    // 3. 재설정석 드롭 (10% 확률 - 희귀)
    if (rand.nextDouble() < 0.1) {
      player.rerollStone += 1;
      _addLog('[희귀] 옵션 재설정석 1개 획득!', LogType.item);
    }
    
    // 4. 보호석/큐브 (매우 낮은 확률)
    if (rand.nextDouble() < 0.02) {
      player.protectionStone += 1;
      _addLog('[전설] 강화 보호석 1개 획득!', LogType.item);
    }
  }

  void _handlePlayerDeath() {
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
    if (!mounted || _lootParticles.isEmpty) return;
    final now = DateTime.now();
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

  void _addFloatingText(String text, bool isMonsterTarget, {bool isCrit = false, double? offsetX, double? offsetY}) {
    final rand = Random();
    double ox = offsetX ?? (rand.nextDouble() * 40) - 20; 
    double oy = offsetY ?? (rand.nextDouble() * 30) - 15; 
    
    setState(() { 
      floatingTexts.add(FloatingText(text, isMonsterTarget, DateTime.now(), isCrit: isCrit, offsetX: ox, offsetY: oy)); 
    });
    // 리스트 청소는 효율을 위해 2초 후 실행
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          floatingTexts.removeWhere((t) => DateTime.now().difference(t.createdAt).inMilliseconds >= 1000);
        });
      }
    });
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
                        _buildBodyContent(),
                        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomDock()),
                        // 최적화된 파티클 레이어 (전투 탭에서만 활성화)
                        if (_selectedIndex == 0)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: LootParticlePainter(
                                  particles: _lootParticles,
                                  ticker: _uiTickerController,
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
        ],
      ),
    );
  }

  // --- 알림 시스템 핵심 로직 (Overlay 방식) ---
  void _showToast(String message, {bool isError = true}) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastOverlayWidget(
        message: message,
        isError: isError,
        onDismiss: () => entry.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
  }

  void _showSuccess(String title, String subtitle) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _SuccessOverlayWidget(
        title: title,
        subtitle: subtitle,
        onDismiss: () => entry.remove(),
        shadowTextBuilder: _buildShadowText, // 헬퍼 함수 전달
      ),
    );
    Overlay.of(context).insert(entry);
  }


  Widget _buildBodyContent() {
    switch (_selectedIndex) {
      case 0: return _buildCombatTab();
      case 1: return _buildCharacterTab();
      case 2: return _buildHuntingZoneTab(); // 사냥터 이동 메뉴 연결
      case 3: return _buildInventoryTab(); // 가방 메뉴 연결
      case 4: return _buildMenuPlaceholder('제작');
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
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
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
            child: ListView.builder(
              itemCount: HuntingZoneData.list.length,
              itemBuilder: (context, index) {
                final zone = HuntingZoneData.list[index];
                bool isCurrent = _currentZone.id == zone.id;
                int stage = _zoneStages[zone.id] ?? 1;

                return _buildGlassContainer(
                  margin: const EdgeInsets.only(bottom: 16),
                  borderRadius: 24,
                  color: isCurrent ? zone.color.withOpacity(0.2) : Colors.black,
                  border: Border.all(color: isCurrent ? zone.color.withOpacity(0.5) : Colors.white10, width: isCurrent ? 1.5 : 0.5),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _currentZone = zone;
                        _currentStage = stage;
                        _stageKills = 0;
                        _selectedIndex = 0; // 전투 탭으로 자동 이동
                        _addLog('${zone.name} 지역으로 이동했습니다.', LogType.event);
                        _spawnMonster();
                      });
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
                              _buildShadowText('STAGE', fontSize: 10, color: Colors.white38),
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
              },
            ),
          ),
          const SizedBox(height: 100), // 독 공간
        ],
      ),
    );
  }

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
  Widget _buildInventoryTab() {
    return Column(
      children: [
        // 상단 타이틀 및 가방 카운터 (한 줄 배치)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _buildShadowText('인벤토리', fontSize: 26, fontWeight: FontWeight.bold),
              Text(
                '(${player.inventory.length} / ${player.maxInventory})',
                style: const TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.w600)
              ),
            ],
          ),
        ),
        
        // 재료 바 (이미지 스타일의 콤팩트 한 줄 바)
        _buildResourceBar(),
        
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
      borderRadius: 16,
      color: Colors.white.withOpacity(0.04),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildResourceItem('✨', '가루', player.powder, Colors.greenAccent),
            _buildResourceItem('💎', '강화석', player.enhancementStone, Colors.blueAccent),
            _buildResourceItem('🎲', '재설정', player.rerollStone, Colors.purpleAccent),
            _buildResourceItem('🛡️', '보호', player.protectionStone, Colors.amberAccent),
            _buildResourceItem('🔮', '큐브', player.cube, Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceItem(String emoji, String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 5),
          Text('$label:', style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(width: 5),
          _AnimatedCountText(
            count: count,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.2),
          ),
        ],
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
                  '강화순', 
                  _inventorySortMode == 1 ? Colors.blueAccent : Colors.white.withOpacity(0.05), 
                  () => setState(() => _inventorySortMode = 1),
                  icon: Icons.upgrade,
                  isSelected: _inventorySortMode == 1
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

  void _executeBulkDismantle(ItemGrade maxGrade) {
    int dismantleCount = 0;
    int powderGain = 0;
    int stoneGain = 0;
    int rerollGain = 0;
    int protectionGain = 0;
    int cubeGain = 0;

    setState(() {
      player.inventory.removeWhere((item) {
        // 선택한 등급 이하인 경우 (index 사용)
        if (item.grade.index <= maxGrade.index) {
          dismantleCount++;
          final rand = Random();
          
          // 기본 재료 (100% 확률)
          powderGain += (item.tier * (item.grade.index + 1) * 2);
          if (item.grade.index >= 1) stoneGain += (item.grade.index);
          
          // 추가 재료 (확률 기반)
          // 재설정석: 희귀 이상 30% 확률
          if (item.grade.index >= 2 && rand.nextDouble() < 0.3) {
            rerollGain += 1;
          }
          
          // 보호석: 영웅 이상 20% 확률
          if (item.grade.index >= 3 && rand.nextDouble() < 0.2) {
            protectionGain += 1;
          }
          
          // 큐브: 전설 이상 10% 확률
          if (item.grade.index >= 4 && rand.nextDouble() < 0.1) {
            cubeGain += 1;
          }
          
          return true;
        }
        return false;
      });
      
      player.powder += powderGain;
      player.enhancementStone += stoneGain;
      player.rerollStone += rerollGain;
      player.protectionStone += protectionGain;
      player.cube += cubeGain;
    });

    if (dismantleCount > 0) {
      String rewardText = '가루 +$powderGain, 강화석 +$stoneGain';
      if (rerollGain > 0) rewardText += ', 재설정석 +$rerollGain';
      if (protectionGain > 0) rewardText += ', 보호석 +$protectionGain';
      if (cubeGain > 0) rewardText += ', 큐브 +$cubeGain';
      
      _addLog('${maxGrade.name} 이하 $dismantleCount개 아이템 분해 완료! ($rewardText)', LogType.event);
    } else {
      _addLog('해당 조건의 분해할 아이템이 없습니다.', LogType.event);
    }
    _saveGameData(); // 분해 결과 저장
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

    // 상세창을 열기 전에 신규 마크 해제 (setState 에러 방지)
    if (currentItem.isNew) {
      setState(() {
        currentItem.isNew = false;
      });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isEquipped = player.equipment[currentItem.type]?.id == currentItem.id;
          final currentEquip = player.equipment[currentItem.type];
          
          // 내비게이션 정보 계산
          int currentIndex = contextList?.indexWhere((i) => i.id == currentItem.id) ?? -1;
          bool hasPrev = (contextList != null && currentIndex > 0);
          bool hasNext = (contextList != null && currentIndex >= 0 && currentIndex < contextList.length - 1);

          void navigate(int direction) {
            if (contextList == null) return;
            int nextIdx = currentIndex + direction;
            if (nextIdx >= 0 && nextIdx < contextList.length) {
              setDialogState(() {
                currentItem = contextList[nextIdx];
                if (currentItem.isNew) {
                  setState(() => currentItem.isNew = false);
                }
              });
            }
          }

          return Dialog(
            backgroundColor: const Color(0xFF1A1D2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity! > 500) {
                  if (hasPrev) navigate(-1);
                } else if (details.primaryVelocity! < -500) {
                  if (hasNext) navigate(1);
                }
              },
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 상단 헤더
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 48), // 닫기 버튼과 대칭을 맞추기 위한 빈 공간
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (contextList != null)
                                  Text('${currentIndex + 1} / ${contextList.length}', 
                                    style: const TextStyle(fontSize: 10, color: Colors.white24, fontWeight: FontWeight.bold)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // 이전 아이템 화살표 (이름 옆으로 이동)
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.chevron_left, 
                                        color: hasPrev ? Colors.white70 : Colors.white10,
                                        size: 28,
                                      ),
                                      onPressed: hasPrev ? () => navigate(-1) : null,
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.lock_open, size: 14, color: Colors.white24),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${currentItem.name} ${currentItem.enhanceLevel > 0 ? '+${currentItem.enhanceLevel}' : ''}',
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: currentItem.grade.color),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // 다음 아이템 화살표 (이름 옆으로 이동)
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.chevron_right, 
                                        color: hasNext ? Colors.white70 : Colors.white10,
                                        size: 28,
                                      ),
                                      onPressed: hasNext ? () => navigate(1) : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54), 
                            onPressed: () => Navigator.pop(context)
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 20),

                      // 비교창
                      if (!isEquipped && currentEquip != null)
                        _buildGlassContainer(
                          padding: const EdgeInsets.all(15),
                          margin: const EdgeInsets.only(bottom: 20),
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: 15,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('현재 착용 장비와 비교', style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.bold)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                    child: const Text('VS', style: TextStyle(fontSize: 9, color: Colors.amber, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _getItemIcon(currentEquip.type, size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text('${currentEquip.name} +${currentEquip.enhanceLevel}', style: TextStyle(fontSize: 13, color: currentEquip.grade.color, fontWeight: FontWeight.bold))),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(color: Colors.white12, height: 1),
                              ),
                              _buildCompareStat(currentItem.mainStatName, currentItem.effectiveMainStat.toDouble(), currentEquip.effectiveMainStat.toDouble()),
                              
                              // 부가 옵션 비교
                              ...() {
                                final myOpts = <String, double>{};
                                for (var o in currentItem.subOptions) myOpts[o.name] = (myOpts[o.name] ?? 0) + o.value;
                                
                                final targetOpts = <String, double>{};
                                for (var o in currentEquip.subOptions) targetOpts[o.name] = (targetOpts[o.name] ?? 0) + o.value;
                                
                                final allKeys = {...myOpts.keys, ...targetOpts.keys}.toList();
                                allKeys.sort();

                                return allKeys.map((key) {
                                  final isPerc = currentItem.subOptions.any((o) => o.name == key && o.isPercentage) || 
                                                 currentEquip.subOptions.any((o) => o.name == key && o.isPercentage);
                                  return _buildCompareStat(key, myOpts[key] ?? 0, targetOpts[key] ?? 0, isPercentage: isPerc);
                                }).toList();
                              }(),
                            ],
                          ),
                        ),

                      const SizedBox(height: 10),
                      // 주능력치 표시 (강화 포함 최종치 강조)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.3))
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${currentItem.mainStatName}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                                Text('${currentItem.effectiveMainStat}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
                              ],
                            ),
                            // 반지/목걸이 전용: 고정 체력 옵션 표시
                            if (currentItem.type == ItemType.ring || currentItem.type == ItemType.necklace)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('체력', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                                    Text('${(40 * currentItem.getEnhanceFactor()).toInt()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (currentItem.enhanceLevel > 0 || currentItem.isBroken)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            '기본 ${currentItem.mainStat}${currentItem.enhanceLevel > 0 ? ' + 강화 효과 적용됨' : ''}${currentItem.isBroken ? ' (파손 페널티 -20%)' : ''}', 
                            style: TextStyle(fontSize: 11, color: currentItem.isBroken ? Colors.redAccent : Colors.greenAccent.withOpacity(0.8))
                          ),
                        ),
                      
                      const SizedBox(height: 20),
                      ...currentItem.subOptions.where((opt) {
                        // 반지/목걸이의 경우 상단에 표시된 '체력' 옵션은 리스트에서 제외
                        if (currentItem.type == ItemType.ring || currentItem.type == ItemType.necklace) {
                          return opt.name != '체력';
                        }
                        return true;
                      }).map((opt) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $opt', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      )).toList(),

                      const SizedBox(height: 25),
                      // 강화 정보
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(15)),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('강화 정보 (Next +${currentItem.enhanceLevel + 1})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text('성공률: ${(currentItem.successChance * 100).toInt()}%', 
                                  style: TextStyle(
                                    fontSize: 12, 
                                    color: currentItem.successChance >= 0.7 ? Colors.greenAccent : (currentItem.successChance >= 0.3 ? Colors.orangeAccent : Colors.redAccent), 
                                    fontWeight: FontWeight.bold
                                  )
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.build_circle, size: 12, color: Colors.white54),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: (currentItem.durability / currentItem.maxDurability).clamp(0, 1), 
                                    backgroundColor: Colors.white12, 
                                    color: currentItem.isBroken ? Colors.red : (currentItem.durability < 40 ? Colors.orange : Colors.green), 
                                    minHeight: 4
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${currentItem.durability}/${currentItem.maxDurability}', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('필요 골드: ${_formatNumber(currentItem.enhanceCost)} G', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                Text('강화석: ${currentItem.stoneCost}개', style: const TextStyle(fontSize: 12, color: Colors.blueAccent)),
                              ],
                            ),
                            if (currentItem.enhanceLevel >= 15)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text('※ 실패 시 강화 단계 하락 위험!', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      // 액션 버튼
                      Row(
                        children: [
                          Expanded(child: _buildPopBtn(
                            isEquipped ? '해제하기' : '착용하기', 
                            Colors.lightBlueAccent, 
                            () {
                              setState(() {
                                if (isEquipped) player.unequipItem(currentItem.type);
                                else player.equipItem(currentItem);
                                _saveGameData(); // 착용/해제 상태 저장
                              });
                              Navigator.pop(context);
                            },
                            icon: isEquipped ? Icons.link_off : Icons.link,
                          )),
                          const SizedBox(width: 10),
                          Expanded(
                            child: () {
                              final savedLevel = player.enhancementSuccession[currentItem.tier] ?? 0;
                              
                              if (currentItem.isBroken) {
                                return _buildPopBtn('파손됨', Colors.red.withOpacity(0.3), null, subLabel: '수리 필요', icon: Icons.build_circle_outlined);
                              }
                              
                              if (savedLevel > 0) {
                                // 계승 데이터가 있는 경우: 계승 버튼 노출
                                return _buildPopBtn(
                                  '+$savedLevel 계승하기', 
                                  Colors.cyan, 
                                  () {
                                    setState(() {
                                      currentItem.setEnhanceLevel(savedLevel);
                                      player.enhancementSuccession[currentItem.tier] = 0; // 계승 후 데이터 초기화
                                    });
                                    Navigator.pop(context);
                                    _showSuccess('강화도 계승', '강화도가 +$savedLevel로 계승되었습니다!');
                                  },
                                  icon: Icons.swap_horiz,
                                );
                              } else {
                                // 일반 강화 버튼
                                return _buildPopBtn(
                                  '강화', 
                                  Colors.blueAccent, 
                                  () => _enhanceItem(currentItem, setDialogState),
                                  subLabel: '${_formatNumber(currentItem.enhanceCost)} G',
                                  icon: Icons.auto_fix_high,
                                );
                              }
                            }(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildPopBtn(
                        '아이템 분해', 
                        Colors.red.withOpacity(0.8), 
                        () {
                          setState(() { player.inventory.removeWhere((i) => i.id == currentItem.id); });
                          Navigator.pop(context);
                        }, 
                        isFull: true,
                        icon: Icons.delete_sweep,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
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
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildShadowText('${_currentZone.name}-', fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                  _buildShadowText('스테이지 ${Monster.getDisplayStage(_currentStage)}', fontSize: 13, color: Colors.white70),
                  const SizedBox(width: 12),
                  _buildShadowText('${_formatNumber(player.gold)} Gold', fontSize: 16, color: Colors.amber, fontWeight: FontWeight.w900),
                ],
              ),
            ],
          ),
          // 오른쪽: 기능 버튼
          Row(
            children: [
               _buildDashboardActionBtn(Icons.battery_saver, '절전', () => _showToast('공사 중: 절전 모드')),
               const SizedBox(width: 8),
               _buildDashboardActionBtn(Icons.nights_stay, '방치모드', () => _showToast('공사 중: 방치 모드')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardActionBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: _buildGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        borderRadius: 8,
        blur: 5,
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.greenAccent),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
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
                const Text('STAGE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, fontStyle: FontStyle.italic)),
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
    return Column(
      children: [
        // 1. 스테이지 바 (버튼 제거 및 여백 축소)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _buildLargeProgressBar('EXP', (player.exp / player.maxExp).clamp(0, 1), Colors.blueAccent),
        ),
        // 2. 콤팩트 통계 카드
        _buildEfficiencyCard(),
      ],
    );
  }

  Widget _buildLargeProgressBar(String label, double progress, Color color) {
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
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
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
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _sessionGold = 0;
                    _sessionExp = 0;
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
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse, // 마우스 드래그 스크롤 명시적 허용
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



  Widget _buildBattleScene() {
    return AnimatedBuilder(
      animation: _uiTickerController,
      builder: (context, child) {
        return Stack(fit: StackFit.expand, children: [
          // 기존 중복 배경 제거
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildActor(player.name, player.level, playerCurrentHp, player.maxHp, 'assets/images/warrior.png', _playerAnimController, true),
              Center(
                key: _monsterKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (currentMonster != null)
                      _buildActor(currentMonster!.name, currentMonster!.level, currentMonster!.hp, currentMonster!.maxHp, currentMonster!.imagePath, _monsterAnimController, false)
                    else
                      const SizedBox(width: 100, height: 150), // 몬스터가 없는 동안 빈 공간 유지
                  ],
                ),
              ),
          ]),
          // 플레이어 펫 표시 (전투 장면 최상상위에서 독립적으로 부유)
          if (player.activePet != null)
            _buildIndependentPet(player.activePet!),
          ...floatingTexts.map((ft) => _buildFloatingTextWidget(ft)),
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
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: isUnlocked ? () => _useSkill(skill) : null,
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
    String effectText = "";
    switch (skill.id) {
      case 'act_1': effectText = '공격력의 ${skill.currentValue.toInt()}% 피해 (3연타)'; break;
      case 'pas_1': effectText = '공격 속도 +${skill.currentValue.toInt()}%'; break;
      case 'act_2': effectText = '공격력의 ${skill.currentValue.toInt()}% 강력한 한방'; break;
      case 'pas_2': effectText = '방어력 +${skill.currentValue.toInt()}%'; break;
      case 'act_3': effectText = '공격력의 ${skill.currentValue.toInt()}% 및 빙결'; break;
      case 'pas_3': effectText = '골드/아이템 획득 +${skill.currentValue.toInt()}%'; break;
      case 'act_4': effectText = '공격력의 ${skill.currentValue.toInt()}% 광역 마법'; break;
      case 'pas_4': effectText = '치명타 피해 +${skill.currentValue.toInt()}%'; break;
      case 'act_5': effectText = '공격력의 ${skill.currentValue.toInt()}% 초거대 메테오'; break;
      case 'pas_5': effectText = '데미지의 ${skill.currentValue.toStringAsFixed(1)}% 체력 흡수'; break;
      case 'pas_6': effectText = '스킬 재사용 대기시간 -${skill.currentValue.toInt()}%'; break;
    }

    return Row(
      children: [
        Icon(Icons.flash_on, size: 10, color: skill.isUnlocked ? Colors.cyanAccent : Colors.white10),
        const SizedBox(width: 4),
        Text(
          skill.level == 0 ? '효과: $effectText' : '현재 효과: $effectText', 
          style: TextStyle(color: skill.isUnlocked ? Colors.cyanAccent : Colors.white24, fontSize: 11, fontWeight: FontWeight.w500)
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
        
        for (int i = 0; i < hits; i++) {
          bool isSkillCrit = Random().nextDouble() * 100 < player.critChance;
          int skillDmg = (player.attack * powerMultiplier / 100).toInt();
          int finalDmg = (skillDmg - currentMonster!.defense).clamp(1, 9999999);
          if (isSkillCrit) finalDmg = (finalDmg * player.critDamage / 100).toInt();

          // 흡혈 적용 (패시브)
          if (player.lifesteal > 0) {
            int healAmount = (finalDmg * player.lifesteal / 100).toInt();
            playerCurrentHp = (playerCurrentHp + healAmount).clamp(0, player.maxHp);
          }

          currentMonster!.hp -= finalDmg;
          
          // 다단 히트 시 약간의 지연 효과는 UI 상으로만 표현 (플로팅 텍스트 분산)
          double ox = hits > 1 ? (Random().nextDouble() * 40 - 20) : 0;
          double oy = hits > 1 ? (Random().nextDouble() * 40 - 20) : 0;
          
          _addFloatingText(
            isSkillCrit ? '⚡CRITICAL $finalDmg' : '🔥SKILL $finalDmg', 
            true, 
            isCrit: isSkillCrit,
            offsetX: ox,
            offsetY: oy
          );
          
          if (i == 0) {
            _addLog(
              isSkillCrit 
                ? '[CRITICAL] ${skill.name} 발동! $finalDmg 피해!!! $effectName' 
                : '[스킬] ${skill.name} 사용! $finalDmg 피해! $effectName', 
              LogType.damage
            );
          }
        }
        
        if (currentMonster!.isDead) _handleVictory();
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

  Widget _buildFloatingTextWidget(FloatingText ft) {
    final age = DateTime.now().difference(ft.createdAt).inMilliseconds;
    final progress = (age / 450).clamp(0.0, 1.0); // 수명 450ms로 최적화
    
    if (progress >= 1.0) return const SizedBox();

    // 제안된 프리미엄 웹 감성 로직: easeOutCubic
    final curveValue = Curves.easeOutCubic.transform(progress);
    
    // 위치(Y축 위로), 투명도(사라짐), 스케일(0.9 -> 1.0 미세 변화)
    final translateY = -30 * curveValue;
    final opacity = 1.0 - curveValue;
    final scale = 0.9 + (0.1 * curveValue);
    
    // 데미지 타입별 스타일은 유지
    Color mainColor = Colors.white;
    List<Shadow> textShadows = [const Shadow(blurRadius: 4, color: Colors.black)];
    double fontSize = 22;
    
    if (ft.isCrit == true) {
      if (ft.text.contains('⚡')) { // 스킬 크리티컬 (아이콘 체크 방식 변경 가능)
        mainColor = Colors.cyanAccent;
        fontSize = 32;
        textShadows = [const Shadow(blurRadius: 10, color: Colors.blueAccent)];
      } else { // 일반 크리티컬
        mainColor = Colors.orangeAccent;
        fontSize = 28;
        textShadows = [const Shadow(blurRadius: 10, color: Colors.redAccent)];
      }
    } else {
      if (!ft.isMonsterTarget) { // 플레이어 피격
        mainColor = Colors.redAccent;
        fontSize = 18;
      }
    }

    return Positioned(
      // 몬스터 타격 시(isMonsterTarget: true) 우측 정렬, 플레이어 피격 시(false) 좌측 정렬
      left: ft.isMonsterTarget ? null : (60 + ft.offsetX),
      right: ft.isMonsterTarget ? (60 + ft.offsetX) : null,
      top: 150 + ft.offsetY + translateY,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Stack( 
            alignment: Alignment.center,
            children: [
              // 외곽선 텍스트 (가독성용)
              Text(
                ft.text,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = Colors.black,
                ),
              ),
              // 실제 데미지 텍스트
              Text(
                ft.text,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: mainColor,
                  shadows: textShadows,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAchievementTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.emoji_events, color: Colors.amber, size: 24),
                ),
                const SizedBox(width: 12),
                _buildShadowText('업적 전당', fontSize: 26, fontWeight: FontWeight.bold),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
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
            ),
          ),
          const SizedBox(height: 100),
        ],
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
  Widget _buildPetTab() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // 펫 대시보드 (현재 장착 펫 및 총 보너스)
          _buildPetStatusHeader(),
          const SizedBox(height: 16),
          // 소환 버튼 영역
          _buildPetSummonArea(),
          const SizedBox(height: 16),
          // 보유 펫 리스트
          Expanded(child: _buildOwnedPetList()),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildPetStatusHeader() {
    return _buildGlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      child: Row(
        children: [
          // 현재 펫 아이콘
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: player.activePet?.grade.color.withOpacity(0.5) ?? Colors.white10),
            ),
            child: Center(
              child: Text(
                player.activePet?.iconEmoji ?? '❔',
                style: const TextStyle(fontSize: 40),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShadowText(
                  player.activePet?.name ?? '동행 중인 펫 없음',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: player.activePet?.grade.color ?? Colors.white60,
                ),
                const SizedBox(height: 8),
                Text(
                  '보유 효과: ATK +${player.petAtkBonus.toStringAsFixed(1)}% / HP +${player.petHpBonus.toStringAsFixed(1)}%',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                ),
                if (player.activePet != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '동행 효과: ${player.activePet!.companionSkillName} (${player.activePet!.companionValue.toStringAsFixed(1)}%)',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
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

  Widget _buildPetMiniTag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildOwnedPetList() {
    if (player.pets.isEmpty) {
      return Center(
        child: Text('보유 중인 펫이 없습니다.', style: TextStyle(color: Colors.white.withOpacity(0.2))),
      );
    }
    
    return ListView.builder(
      itemCount: player.pets.length,
      itemBuilder: (context, index) {
        final pet = player.pets[index];
        bool isActive = player.activePet?.id == pet.id;
        
        return _buildGlassContainer(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          border: Border.all(color: isActive ? pet.grade.color.withOpacity(0.5) : Colors.white10, width: isActive ? 2 : 1),
          child: Row(
            children: [
              Text(pet.iconEmoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(pet.name, style: TextStyle(color: pet.grade.color, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 8),
                        _buildGlassContainer(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          borderRadius: 6,
                          color: pet.grade.color.withOpacity(0.1),
                          child: Text(pet.grade.name, style: TextStyle(color: pet.grade.color, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        // 레벨 표시 추가
                        Text('Lv.${pet.level}', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(pet.description, style: TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 6),
                    // 현재 보너스 수치 표시
                    Row(
                      children: [
                        if (pet.ownAtkMultiplier > 0) _buildPetMiniTag('공격 +${pet.currentAtkBonus.toStringAsFixed(1)}%', Colors.orangeAccent),
                        if (pet.ownHpMultiplier > 0) _buildPetMiniTag('체력 +${pet.currentHpBonus.toStringAsFixed(1)}%', Colors.greenAccent),
                        if (pet.ownGoldMultiplier > 0) _buildPetMiniTag('골드 +${pet.currentGoldBonus.toStringAsFixed(1)}%', Colors.yellowAccent),
                      ],
                    ),
                  ],
                ),
              ),
              _buildPopBtn(
                isActive ? '해제' : '동행', 
                isActive ? Colors.redAccent : Colors.greenAccent, 
                () {
                  setState(() {
                    if (isActive) player.activePet = null;
                    else player.activePet = pet;
                    _saveGameData(); // 펫 동행 변경 후 저장
                  });
                }
              ),
            ],
          ),
        );
      },
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
      List<Pet> pool = PetData.getInitialPets();
      
      for (int i = 0; i < count; i++) {
        double rand = Random().nextDouble() * 100;
        Pet selected;
        if (rand < 0.1) selected = pool[5]; // 전설 (Mythic)
        else if (rand < 1.0) selected = pool[4]; // 유물 (Legendary)
        else if (rand < 5.0) selected = pool[3]; // 고대 (Epic)
        else if (rand < 15.0) selected = pool[2]; // 희귀 (Rare)
        else if (rand < 40.0) selected = pool[1]; // 고급 (Uncommon)
        else selected = pool[0]; // 일반 (Common)

        // 중복 체크 및 추가 (동일한 인스턴스가 아닌 새 인스턴스로 관리 필요할 수 있으나 여기서는 ID 기반)
        if (!player.pets.any((p) => p.id == selected.id)) {
          player.pets.add(selected);
          _addLog('펫 획득! [${selected.grade.name}] ${selected.name}', LogType.event);
        } else {
          // 이미 있으면 레벨업 처리 (간소화된 성장 시스템)
          player.pets.firstWhere((p) => p.id == selected.id).level++;
        }
      }
      
      _showSuccess('소환 완료', '${count}회의 소환을 완료했습니다.');
    });
  }


  // --- 시스템 및 관리자 모드 UI ---
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
                Text('게임 환경 설정 및 데이터 관리', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
                const SizedBox(height: 40),
                // 관리자 모드 진입 버튼
                _buildPopBtn(
                  '관리자 모드', 
                  Colors.redAccent.withOpacity(0.8), 
                  _showAdminPasswordDialog,
                  icon: Icons.admin_panel_settings,
                ),
                const SizedBox(height: 16),
                _buildPopBtn(
                  '로그아웃', 
                  Colors.white10, 
                  () => _showToast('준비 중인 기능입니다.'),
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


  void _showOfflineRewardDialog(Map<String, dynamic> rewards) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25), side: const BorderSide(color: Colors.white10)),
        title: Column(
          children: [
            const Icon(Icons.nightlight_round, color: Colors.blueAccent, size: 40),
            const SizedBox(height: 10),
            _buildShadowText('부재 중 성과 리포트', fontSize: 20, fontWeight: FontWeight.bold),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${rewards['minutes']}분 동안 용사가 쉬지 않고 사냥했습니다!', style: const TextStyle(fontSize: 12, color: Colors.white60)),
            const SizedBox(height: 25),
            _buildRewardItem(Icons.monetization_on, '획득 골드', '${rewards['gold']} G', Colors.amber),
            _buildRewardItem(Icons.auto_awesome, '획득 경험치', '${rewards['exp']} EXP', Colors.blueAccent),
            _buildRewardItem(Icons.bolt, '처치 수', '${rewards['kills']} 마리', Colors.redAccent),
            _buildRewardItem(Icons.diamond, '보너스 강화석', '${rewards['bonusStones']} 개', Colors.greenAccent),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                setState(() => player.applyOfflineRewards(rewards));
                _updateLastSaveTime();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text('보상 모두 수령', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildRewardItem(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ],
          ),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
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
}

enum LogType { damage, item, event }
enum LootType { gold, exp }
class CombatLogEntry { final String message; final LogType type; final DateTime time; CombatLogEntry(this.message, this.type, this.time); }
class FloatingText {
  final String text;
  final bool isMonsterTarget;
  final DateTime createdAt;
  final bool isCrit;
  final double offsetX;
  final double offsetY;
  FloatingText(this.text, this.isMonsterTarget, this.createdAt, {this.isCrit = false, this.offsetX = 0, this.offsetY = 0});
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
    return Positioned.fill(
      child: GestureDetector(
        onTap: () async {
          await _controller.reverse();
          widget.onDismiss();
        },
        child: Material(
          color: Colors.black54,
          child: FadeTransition(
            opacity: _controller,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stars, color: Colors.amber, size: 80),
                    const SizedBox(height: 20),
                    widget.shadowTextBuilder(widget.title, fontSize: 32, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                    const SizedBox(height: 10),
                    widget.shadowTextBuilder(widget.subtitle, fontSize: 18),
                    const SizedBox(height: 40),
                    const Text('터치하여 닫기', style: TextStyle(color: Colors.white38, fontSize: 12)),
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

