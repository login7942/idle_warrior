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
  });

  // 사냥터와 스테이지에 따른 몬스터 생성기
  factory Monster.generate(HuntingZone zone, int stage) {
    final rand = Random();
    
    // 지역별 몬스터 이름 무작위 선택
    String species = zone.monsterNames[rand.nextInt(zone.monsterNames.length)];
    int totalLevel = (zone.minLevel + stage);

    // DOC_GAME_DESIGN.md 3.3. 몬스터 성장 공식 (Monster Scaling) 반영
    // 스테이지(stage)를 S로 치환하여 계산
    double s = stage.toDouble();
    double multiplier;

    if (s <= 200) {
      // 1구간 (S ≤ 200): [선형] Multiplier = 1 + (S * 0.15)
      multiplier = 1 + (s * 0.15);
    } else if (s <= 1500) {
      // 2구간 (200 < S ≤ 1500): [지수] Multiplier = 31 * Math.pow(1.065, (S - 200) / 10)
      multiplier = 31 * pow(1.065, (s - 200) / 10).toDouble();
    } else {
      // 3구간 (S > 1500): [강한 지수 + 벽] 
      // Multiplier = 85000 * Math.pow(1.1, (S - 1500) / 50) * (1 + Floor((S - 1500) / 100) * 0.5)
      double baseMult = 85000 * pow(1.1, (s - 1500) / 50).toDouble();
      double wallMult = 1 + ((s - 1500) / 100).floor() * 0.5;
      multiplier = baseMult * wallMult;
    }

    // 최종 스탯 계산 (기본값에 구간별 multiplier 적용)
    // 기본 수치도 디자인 문서의 의도에 맞게 조정 가능하나, 일단 multiplier 로직을 우선 적용
    int mHp = (100 * multiplier).toInt();
    int mAtk = (10 * multiplier).toInt();
    int mDef = (5 * multiplier).toInt();

    // 보상 배율: 스테이지 배율 * (1 + 층수 / 500)
    double rewardMult = multiplier * (1 + s / 500);

    return Monster(
      name: '$species (Lv.$totalLevel)',
      level: totalLevel,
      maxHp: mHp,
      hp: mHp,
      attack: mAtk,
      defense: mDef,
      expReward: (20 * rewardMult).toInt(),
      goldReward: (50 * rewardMult).toInt(),
      itemDropChance: 0.15, // 디자인 문서 3.2 드랍 확률 반영
    );
  }

  bool get isDead => hp <= 0;
}
