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
  factory Monster.generate(HuntingZone zone, int stage) {
    final rand = Random();
    
    // --- [v0.0.51] 무한의탑 전용 스케일링 설계 ---
    bool isTower = zone.id == ZoneId.tower;
    bool isElite = isTower ? true : (rand.nextDouble() < 0.10);
    double eliteMult = isTower 
        ? (5.0 + (stage * 0.1)) // 탑은 기본 5배 + 층당 추가 배율
        : (isElite ? (1.5 + rand.nextDouble() * 1.5) : 1.0);
    
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
    
    // 엘리트 몬스터는 체력 증가
    int mHp = (mHpFinal * eliteMult).toInt();
    
    // ATK(stage) = 90 × 1.02^stage
    int mAtk = (90 * pow(isTower ? 1.04 : 1.02, s)).toInt();
    if (isTower) mAtk = (mAtk * 2.0).toInt(); // 탑은 공격력도 2배 기본 보너스
    
    // 방어력은 0으로 고정
    int mDef = 0;

    // --- 보상 공식 분리 (v0.0.39) ---
    // [v0.0.47] 레벨 1000 시스템: 경험치 선형 증가
    // 기존: 지수 성장 (1.025^s) → 레벨 100 이후 성장 정체
    // 신규: 스테이지 비례 성장 → 레벨 1000까지 균형잡힌 성장
    int expReward = 20 + (s.toInt() * 2); // 스테이지당 +2 경험치
    
    // 2. 골드(Gold): 기초 수령액 상향(50->200) 및 후반 지수 억제(1.025->1.017)
    // 환생 시스템 도입 전 인플레이션 방지를 위해 성장을 엄격하게 제한
    double goldMult = pow(1.017, s).toDouble();
    
    // 엘리트 몬스터는 골드도 배율만큼 증가
    int finalGold = (200 * goldMult * eliteMult).toInt();
    
    // 엘리트 몬스터는 드롭률 상향 (20% -> 50%)
    double dropChance = isElite ? 0.5 : 0.2;
    
    // 몬스터 이름 표식
    String displayName;
    if (isTower) {
      displayName = '👹 [TOWER] $species ($stage층)';
    } else {
      displayName = isElite 
        ? '⭐ $species (Lv.$totalLevel)' 
        : '$species (Lv.$totalLevel)';
    }

    return Monster(
      name: displayName,
      level: totalLevel,
      maxHp: mHp,
      hp: mHp,
      attack: mAtk,
      defense: mDef,
      expReward: expReward,
      goldReward: finalGold,
      itemDropChance: dropChance,
      isElite: isElite,
      eliteMultiplier: eliteMult,
    );
  }

  bool get isDead => hp <= 0;

  /// 내부 전투 단계를 표시 단계로 변환 (가속 없이 1:1 매칭)
  static int getDisplayStage(int combatStage) {
    return combatStage;
  }
}
