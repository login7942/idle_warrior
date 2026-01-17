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
    int totalLevel = (zone.minLevel + stage - 1);

    // --- [2026-01-17] 스테이지 가속 및 밸런스 개편 ---
    // 파라미터 stage는 내부 '전투 단계(Combat Stage)'입니다.
    double s = stage.toDouble();
    
    // HP(stage) = 900 × stage^1.25 (11스테이지 기준) - 성취감을 위해 기존 1.15에서 1.25로 상향
    double baseHp = (900 * pow(s, 1.25)).toDouble();
    
    // 초반 구간 체력 완화 로직 (Smoothing) 적용
    double mHpFinal;
    if (s <= 5) {
      mHpFinal = baseHp * 0.15; // 1~5층: 15% 수준
    } else if (s <= 10) {
      mHpFinal = baseHp * 0.4;  // 6~10층: 40% 수준
    } else {
      mHpFinal = baseHp;        // 11층부터 온전한 위력
    }
    int mHp = mHpFinal.toInt();
    
    // ATK(stage) = 90 × stage^1.1 - 가속된 표시 단계에 맞게 위력 상향
    int mAtk = (90 * pow(s, 1.1)).toInt();
    
    // 방어력은 0으로 고정 (이전 설정 유지)
    int mDef = 0;

    // 보상 배율: 체력 성장에 비례하되 너무 가파르지 않게 조정 (기존 multiplier 개념 대체)
    double growthFactor = mHp / 900.0;
    double rewardMult = growthFactor * (1 + s / 500);

    return Monster(
      name: '$species (Lv.$totalLevel)',
      level: totalLevel,
      maxHp: mHp,
      hp: mHp,
      attack: mAtk,
      defense: mDef,
      expReward: (20 * rewardMult).toInt(),
      goldReward: (50 * rewardMult).toInt(),
      itemDropChance: 0.2, // 디자인 문서 리빌딩: 드랍 확률 20% 반영
    );
  }

  bool get isDead => hp <= 0;

  /// 내부 전투 단계를 가속된 표시 단계로 변환하는 공식 (A안 가속 적용)
  static int getDisplayStage(int combatStage) {
    if (combatStage <= 1) return 1;
    double s = combatStage.toDouble();
    // 가속 공식: (S^1.6 + (S-1)*2).floor
    return (pow(s, 1.6) + (s - 1) * 2).floor();
  }
}
