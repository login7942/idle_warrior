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

    // --- [2026-01-17] 밸런스 최적화: 아이템 티어(100층당 10배)에 맞춘 성장 모델 ---
    double s = stage.toDouble();
    // HP(stage) = 900 × 1.025^stage (100층당 약 11.8배 성장하여 티어 상향과 조화)
    double baseHp = (900 * pow(1.025, s)).toDouble();
    
    // 초반 구간 체력 완화 로직 (Smoothing) 적용
    double mHpFinal;
    if (s <= 5) {
      mHpFinal = baseHp * 0.15;
    } else if (s <= 10) {
      mHpFinal = baseHp * 0.4;
    } else {
      mHpFinal = baseHp;
    }
    int mHp = mHpFinal.toInt();
    
    // ATK(stage) = 90 × 1.02^stage
    int mAtk = (90 * pow(1.02, s)).toInt();
    
    // 방어력은 0으로 고정
    int mDef = 0;

    // --- 보상 공식 분리 (v0.0.39) ---
    // 1. 경험치(EXP): 기존 지수(1.025) 유지하여 레벨업 속도 보존
    double expMult = (pow(1.025, s) * (1 + s / 1000)).toDouble();
    
    // 2. 골드(Gold): 기초 수령액 상향(50->200) 및 후반 지수 억제(1.025->1.017)
    // 환생 시스템 도입 전 인플레이션 방지를 위해 성장을 엄격하게 제한
    double goldMult = pow(1.017, s).toDouble();

    return Monster(
      name: '$species (Lv.$totalLevel)',
      level: totalLevel,
      maxHp: mHp,
      hp: mHp,
      attack: mAtk,
      defense: mDef,
      expReward: (20 * expMult).toInt(),
      goldReward: (200 * goldMult).toInt(),
      itemDropChance: 0.2, // 디자인 문서 리빌딩: 드랍 확률 20% 반영
    );
  }

  bool get isDead => hp <= 0;

  /// 내부 전투 단계를 표시 단계로 변환 (가속 없이 1:1 매칭)
  static int getDisplayStage(int combatStage) {
    return combatStage;
  }
}
