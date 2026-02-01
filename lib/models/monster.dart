import 'dart:math';
import 'hunting_zone.dart';

enum BossTrait {
  none,
  crush,   // 파쇄: 피해감소/보호막 50% 무시
  corrupt, // 오염: 회복량 50% 감소
  erode    // 침식: 피격 시 스킬 쿨타임 증가
}

class Monster {
  final String name;
  final int level;
  int hp;
  final int maxHp;
  final int attack;
  final int defense;
  final int expReward;
  final int goldReward;
  final String imagePath;
  final double itemDropChance; // 아이템 드롭 확률 (0.0 ~ 1.0)
  final bool isElite; // 엘리트 몬스터 여부
  final bool isBoss;  // 🆕 보스 몬스터 여부
  final double eliteMultiplier; // 엘리트 배율 (1.5 ~ 3.0)
  final BossTrait trait; // 🆕 보스 특수 능력
  double frozenTimeLeft = 0; // 🆕 빙결 남은 시간 (초)

  bool get isFrozen => frozenTimeLeft > 0;

  Monster({
    required this.name,
    required this.level,
    required this.hp,
    required this.maxHp,
    required this.attack,
    required this.defense,
    required this.expReward,
    required this.goldReward,
    this.imagePath = 'assets/images/slime.png',
    this.itemDropChance = 0.2, // 기본 20%
    this.isElite = false,
    this.isBoss = false,
    this.eliteMultiplier = 1.0,
    this.trait = BossTrait.none,
  });

  // 🆕 [v0.5.55] 이미지 매칭 맵을 클래스 상수로 통합하여 메모리 낭비 제거
  static const Map<String, String> monsterImgMap = {
    // 초원
    '슬라임': 'slime.png', '뿔토끼': 'horn_rabbit.png', '들쥐': 'field_rat.png', '풀숲뱀': 'grass_snake.png', '꼬마벌': 'small_bee.png',
    // 숲
    '고블린': 'goblin.png', '늑대': 'wolf.png', '식인식물': 'man_eater.png', '숲의요정': 'forest_fairy.png', '거대거미': 'giant_spider.png',
    // 광산
    '골렘': 'golem.png', '박쥐': 'bat.png', '미믹': 'mimic.png', '코볼트': 'kobold.png', '광산두더지': 'mine_mole.png',
    // 던전
    '스켈레톤': 'skeleton.png', '유령': 'ghost.png', '해골궁수': 'skeleton_archer.png', '좀비': 'zombie.png', '가고일': 'gargoyle.png',
    // 화산
    '파이어드레이크': 'fire_drake.png', '라바스피릿': 'lava_spirit.png', '불타는 골렘': 'fire_golem.png', '화염도마뱀': 'fire_lizard.png', '지옥견': 'hell_hound.png',
    // 설원
    '아이스자이언트': 'ice_giant.png', '설인': 'yeti.png', '서리늑대': 'frost_wolf.png', '눈보라정령': 'blizzard_spirit.png', '얼음펭귄': 'ice_penguin.png',
    // 심연
    '그림자 군단': 'shadow_legion.png', '어둠의 화신': 'dark_avatar.png', '공허의 수호자': 'void_guardian.png', '심연의 눈': 'abyss_eye.png', '카오스 기사': 'chaos_knight.png',
    // 타워
    '탑의 수호자': 'tower_guardian.png', '심판자': 'judge.png', '고대 병기': 'ancient_weapon.png', '차원 감시자': 'dimension_watcher.png', '타락한 신관': 'fallen_priest.png',
    // 🆕 황금의 방 / 시련의 방
    '황금 슬라임': 'slime.png', '보물 상자': 'mimic.png', '황금 박쥐': 'bat.png', '골드 미믹': 'mimic.png', '황금 골렘': 'golem.png',
    '시련의 정령': 'blizzard_spirit.png', '마력 결정체': 'lava_spirit.png', '푸른 번개': 'blizzard_spirit.png', '결빙된 영혼': 'ghost.png', '시련의 수호자': 'gargoyle.png',
  };

  // 사냥터와 스테이지에 따른 몬스터 생성기
  factory Monster.generate(HuntingZone zone, int stage, {bool isFinal = false}) {
    final rand = Random();
    double s = stage.toDouble();
    
    // 1. 성장 배율 계산
    double multiplier;
    if (s <= 200) {
      multiplier = 1 + (s * 0.15);
    } else if (s <= 1500) {
      multiplier = 31 * pow(1.065, (s - 200) / 10).toDouble();
    } else {
      multiplier = 85000 * pow(1.1, (s - 1500) / 50).toDouble() * (1 + ((s.toInt() - 1500) ~/ 100) * 0.5);
    }
    multiplier *= zone.difficultyMultiplier;

    // 2. 몬스터 유형 결정
    bool isBoss = (stage % 50 == 0) && isFinal;
    bool isTower = zone.id == ZoneId.tower;
    bool isGolden = zone.id == ZoneId.goldenRoom;
    bool isTrial = zone.id == ZoneId.trialRoom;
    bool isSpecialTimeDungeon = isGolden || isTrial;
    bool isElite = !isBoss && (isTower || isSpecialTimeDungeon || rand.nextDouble() < 0.10);

    // 3. 베이스 스탯 결정
    double baseHp, baseAtk, baseDef, baseGold, baseExp;
    String species = zone.monsterNames[rand.nextInt(zone.monsterNames.length)];

    if (isBoss) {
      baseHp = 2500; 
      baseAtk = 70; // 🆕 보스 공격력 상향 (45 -> 70)
      baseDef = 25; // 🆕 보스 방어력 상향 (15 -> 25)
      baseGold = 500; baseExp = 500;
    } else {
      baseHp = 60 + rand.nextInt(41).toDouble();
      baseAtk = 15 + rand.nextInt(10).toDouble(); // 🆕 일반 몬스터 공격력 상향 (10~16 -> 15~24)
      baseDef = 5 + rand.nextInt(5).toDouble(); // 🆕 일반 몬스터 방어력 상향 (3~7 -> 5~10)
      baseGold = 20 + rand.nextInt(16).toDouble();
      baseExp = 15 + rand.nextInt(11).toDouble();
    }

    // 4. 엘리트/타워/특별 던전 보정
    double eliteMult = 1.0;
    if (isTower) {
      multiplier *= pow(1.05, s).toDouble();
      baseHp *= 3.0; baseAtk *= 2.0; baseDef *= 1.5; baseGold *= 5.0; baseExp *= 5.0;
    } else if (isSpecialTimeDungeon) {
      // 🆕 특별 시간 던전: 체력은 적당히, 공격력은 매우 낮음 (샌드백)
      baseHp *= 1.2; baseAtk *= 0.1; baseDef *= 0.8;
      
      if (isGolden) {
        baseGold *= 30.0; // 골드 효율 상향 (20배 -> 30배)
        baseExp = 0;      // 황금의 방은 경험치 없음 🆕
      } else if (isTrial) {
        baseGold = 0;     // 시련의 방은 골드 없음 🆕
        baseExp = 0;      // 시련의 방은 경험치 없음 🆕
      }
    } else if (isElite) {
      baseHp *= 1.5; baseAtk *= 1.3; baseDef *= 1.2;
      eliteMult = 2.0 + rand.nextDouble() * 3.0;
      baseGold *= eliteMult; baseExp *= eliteMult;
    }

    // 5. 최종 스탯 산출
    int mHp = (baseHp * multiplier).toInt();
    
    // 🆕 [v0.5.56] 공격력 전용 스테이지 가속 (Atk Scaling) 도입
    // 스테이지가 올라갈수록 공격력이 체력보다 더 가파르게 상승 (200층당 +100%)
    double atkScaling = 1.0 + (s / 200);
    int mAtk = (baseAtk * multiplier * atkScaling).toInt();
    
    // 🆕 [v0.8.36] 방어력 스케일링 강화: 스테이지당 1.5%씩 추가 복리 적용
    double defScaling = pow(1.015, s).toDouble();
    int mDef = (baseDef * multiplier * defScaling).toInt();
    
    double rewardMultiplier = multiplier * (1 + s / 500);
    int mGold = (baseGold * rewardMultiplier).toInt();
    int mExp = (baseExp * rewardMultiplier).toInt();

    // 🆕 보스 특수 능력 결정 (50층 단위 순차 적용)
    BossTrait trait = BossTrait.none;
    if (isBoss) {
      int bossIndex = (stage ~/ 50 - 1) % 3;
      switch (bossIndex) {
        case 0: trait = BossTrait.crush; break;
        case 1: trait = BossTrait.corrupt; break;
        case 2: trait = BossTrait.erode; break;
      }
    }

    // 6. 이름 및 비주얼 설정
    String prefix = '';
    if (isBoss) prefix = '👑 ';
    else if (isTower) prefix = '👹 [TOWER] ';
    else if (isGolden) prefix = '💰 [GOLD] ';
    else if (isTrial) prefix = '✨ [TRIAL] ';
    else if (isElite) prefix = '⭐ ';

    String displayName = '$prefix$species' + (isBoss ? ' (BOSS)' : (isTower ? ' ($stage층)' : (isElite ? ' (Elite)' : '')));
    int totalLevel = (zone.minLevel + stage - 1);
    
    // 이미지 경로 설정 최적화
    String imagePath = 'assets/images/slime.png';
    final fileName = monsterImgMap[species];
    if (fileName != null) {
      imagePath = (species == '슬라임') ? 'assets/images/slime.png' : 'assets/images/monsters/$fileName';
    }

    return Monster(
      name: displayName,
      level: totalLevel,
      maxHp: mHp,
      hp: mHp,
      attack: mAtk,
      defense: mDef,
      expReward: mExp,
      goldReward: mGold,
      imagePath: imagePath,
      itemDropChance: isBoss ? 1.0 : (isElite ? 0.5 : 0.2),
      isElite: isElite,
      isBoss: isBoss,
      eliteMultiplier: isElite ? eliteMult : 1.0,
      trait: trait,
    );
  }

  bool get isDead => hp <= 0;

  /// 내부 전투 단계를 표시 단계로 변환 (가속 없이 1:1 매칭)
  static int getDisplayStage(int combatStage) {
    return combatStage;
  }
}
