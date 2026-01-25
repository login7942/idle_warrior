import 'dart:math';
import 'hunting_zone.dart';

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
  final double eliteMultiplier; // 엘리트 배율 (1.5 ~ 3.0)

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
    this.eliteMultiplier = 1.0,
  });

  // 사냥터와 스테이지에 따른 몬스터 생성기
  factory Monster.generate(HuntingZone zone, int stage, {bool isFinal = false}) {
    final rand = Random();
    double s = stage.toDouble();
    
    // 1. 성장 배율(Multiplier) 계산 (3단계 구간)
    double multiplier;
    if (s <= 200) {
      multiplier = 1 + (s * 0.15);
    } else if (s <= 1500) {
      multiplier = 31 * pow(1.065, (s - 200) / 10).toDouble();
    } else {
      multiplier = 85000 * pow(1.1, (s - 1500) / 50).toDouble() * (1 + ((s.toInt() - 1500) ~/ 100) * 0.5);
    }

    // 맵 난이도 계수 적용
    multiplier *= zone.difficultyMultiplier;

    // 2. 몬스터 유형 결정 (보스 / 엘리트 / 일반)
    // 매 50 스테이지의 마지막(10번째) 몬스터만 보스로 출현
    bool isBoss = (stage % 50 == 0) && isFinal;
    bool isTower = zone.id == ZoneId.tower;
    
    // 타워는 매 층이 보스급이거나 특수 강화됨
    bool isElite = !isBoss && (isTower || rand.nextDouble() < 0.10);

    // 3. 베이스 스탯 결정
    double baseHp;
    double baseAtk;
    double baseDef;
    double baseGold;
    double baseExp;
    String species = zone.monsterNames[rand.nextInt(zone.monsterNames.length)];

    if (isBoss) {
      baseHp = 800;
      baseAtk = 35;
      baseDef = 15;
      baseGold = 500;
      baseExp = 500;
    } else {
      // 일반 몬스터 베이스 (랜덤 범위)
      baseHp = 60 + rand.nextInt(41).toDouble();    // 60~100
      baseAtk = 8 + rand.nextInt(7).toDouble();     // 8~14
      baseDef = 3 + rand.nextInt(4).toDouble();     // 3~6
      baseGold = 20 + rand.nextInt(16).toDouble();  // 20~35
      baseExp = 15 + rand.nextInt(11).toDouble();   // 15~25
    }

    // 4. 엘리트/타워 보정 적용
    double eliteMult = 1.0;
    if (isTower) {
      // 🆕 [v0.5.49] 무한의 탑 전용 성장: 층당 5%씩 복리 증가 + 기본 스탯 대폭 상향
      double towerScaling = pow(1.05, s).toDouble();
      multiplier *= towerScaling;
      
      baseHp *= 3.0;   // 맷집 3배
      baseAtk *= 2.0;  // 공격력 2배
      baseDef *= 1.5;  // 방어력 1.5배
      
      // 타워 보상은 효율보다 상징성 (층당 고정 보상 위주)
      baseGold *= 5.0;
      baseExp *= 5.0;
    } else if (isElite) {
      baseHp *= 1.5;
      baseAtk *= 1.3;
      baseDef *= 1.2;
      // 보상 2~5배 랜덤
      eliteMult = 2.0 + rand.nextDouble() * 3.0;
      baseGold *= eliteMult;
      baseExp *= eliteMult;
    }

    // 5. 최종 스탯 산출 (베이스 * 배율)
    int mHp = (baseHp * multiplier).toInt();
    int mAtk = (baseAtk * multiplier).toInt();
    int mDef = (baseDef * multiplier).toInt();

    // 스테이지 보상 가속화 배율 적용: multiplier * (1 + stage / 500)
    double rewardMultiplier = multiplier * (1 + s / 500);
    int mGold = (baseGold * rewardMultiplier).toInt();
    int mExp = (baseExp * rewardMultiplier).toInt();

    // 6. 이름 및 비주얼 설정
    String displayName;
    if (isBoss) {
      displayName = '👑 $species (BOSS)';
    } else if (isTower) {
      displayName = '👹 [TOWER] $species ($stage층)';
    } else if (isElite) {
      displayName = '⭐ $species (Elite)';
    } else {
      displayName = species;
    }

    int totalLevel = (zone.minLevel + stage - 1);
    
    // 🆕 [v0.5.35] 몬스터 종류별 이미지 매칭 및 가드 로직
    String imagePath = 'assets/images/slime.png'; // 기본 fallback용 슬라임
    final Map<String, String> monsterImgMap = {
      // 초원
      '슬라임': 'slime.png', 
      '뿔토끼': 'horn_rabbit.png', '들쥐': 'field_rat.png', '풀숲뱀': 'grass_snake.png', '꼬마벌': 'small_bee.png',
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
    };

    if (monsterImgMap.containsKey(species)) {
      final fileName = monsterImgMap[species]!;
      // 슬라임만 기존 루트 폴더, 나머지는 monsters 폴더
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
      isElite: isElite || isBoss,
      eliteMultiplier: isElite ? eliteMult : 1.0,
    );
  }

  bool get isDead => hp <= 0;

  /// 내부 전투 단계를 표시 단계로 변환 (가속 없이 1:1 매칭)
  static int getDisplayStage(int combatStage) {
    return combatStage;
  }
}
