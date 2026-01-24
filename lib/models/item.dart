import 'dart:math';
import 'package:flutter/material.dart';

enum ItemType { weapon, helmet, armor, boots, ring, necklace }

extension ItemTypeExtension on ItemType {
  String get nameKr {
    switch (this) {
      case ItemType.weapon: return '무기';
      case ItemType.helmet: return '투구';
      case ItemType.armor: return '갑옷';
      case ItemType.boots: return '신발';
      case ItemType.ring: return '반지';
      case ItemType.necklace: return '목걸이';
    }
  }

  String get iconEmoji {
    switch (this) {
      case ItemType.weapon: return '🗡️';
      case ItemType.helmet: return '🪖';
      case ItemType.armor: return '🛡️';
      case ItemType.boots: return '👢';
      case ItemType.ring: return '💍';
      case ItemType.necklace: return '🧿';
    }
  }

  String get mainStatName1 {
    switch (this) {
      case ItemType.weapon:
      case ItemType.ring:
      case ItemType.necklace:
        return '공격력';
      case ItemType.helmet:
      case ItemType.armor:
      case ItemType.boots:
        return '방어력';
    }
  }

  String? get mainStatName2 {
    switch (this) {
      case ItemType.armor:
      case ItemType.necklace:
        return '체력';
      default:
        return null;
    }
  }
}

enum ItemGrade {
  common(Color(0xFF9CA3AF), '일반'),
  uncommon(Color(0xFF22C55E), '고급'),
  rare(Color(0xFF3B82F6), '희귀'),
  epic(Color(0xFFA855F7), '영웅'),
  unique(Color(0xFFEAB308), '고유'),
  legendary(Color(0xFFEF4444), '전설'),
  mythic(Color(0xFFFF0000), '신화');

  final Color color;
  final String name;
  const ItemGrade(this.color, this.name);

  // [v0.4.0] 등급별 주능력치 보너스
  double get gradeBonus {
    switch (this) {
      case ItemGrade.common: return 1.0;
      case ItemGrade.uncommon: return 1.10;
      case ItemGrade.rare: return 1.25;
      case ItemGrade.epic: return 1.45;
      case ItemGrade.unique: return 1.55;
      case ItemGrade.legendary: return 1.70;
      case ItemGrade.mythic: return 2.0;
    }
  }

  // 배경 그라데이션: 중앙에서 밖으로 퍼지는 입체감
  Gradient get bgGradient {
    return RadialGradient(
      colors: [
        color.withOpacity(0.4), // 중앙 (밝음)
        Colors.black.withOpacity(0.8), // 외곽 (어두움)
      ],
      center: Alignment.center,
      radius: 0.8,
    );
  }

  // 외곽 발광(Glow) 색상
  Color get glowColor => color.withOpacity(0.6);

  // 등급에 따른 발광 강도 (Spread/Blur)
  double get glowIntensity {
    switch (this) {
      case ItemGrade.common: return 0.0;
      case ItemGrade.uncommon: return 2.0;
      case ItemGrade.rare: return 4.0;
      case ItemGrade.epic: return 8.0;
      case ItemGrade.unique: return 12.0;
      case ItemGrade.legendary: return 18.0;
      case ItemGrade.mythic: return 24.0;
    }
  }
}

class ItemOption {
  final String name;
  double value;
  final bool isPercentage;
  bool isLocked; // 잠금 상태 복구
  bool isSpecial; // 특별 옵션 (잠재능력 전용) 여부
  int stars; // 옵션 등급 (1~5)
  double maxValue; // 해당 티어의 최대값

  ItemOption({
    required this.name, 
    required this.value, 
    this.isPercentage = false,
    this.isLocked = false,
    this.isSpecial = false,
    this.stars = 1,
    this.maxValue = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'isPercentage': isPercentage,
        'isLocked': isLocked,
        'isSpecial': isSpecial,
        'stars': stars,
        'maxValue': maxValue,
      };

  factory ItemOption.fromJson(Map<String, dynamic> json) => ItemOption(
        name: json['name'],
        value: json['value'].toDouble(),
        isPercentage: json['isPercentage'],
        isLocked: json['isLocked'] ?? false,
        isSpecial: json['isSpecial'] ?? false,
        stars: json['stars'] ?? 1,
        maxValue: (json['maxValue'] ?? 0).toDouble(),
      );

  @override
  String toString() {
    final valStr = isPercentage 
        ? '${value.toStringAsFixed(1)}%' 
        : (name == '공격 속도' ? value.toStringAsFixed(1) : value.toInt().toString());
    
    String prefix = isSpecial ? '[특별] ' : '';
    return '$prefix$name +$valStr';
  }
}

class Item {
  final String id;
  final String name;
  final ItemType type;
  final ItemGrade grade;
  int tier; 
  int mainStat1; // 기존 mainStat
  int? mainStat2; // 추가 주능력치 (v0.0.58)
  final List<ItemOption> subOptions;
  int enhanceLevel;    // 강화 레벨 (+0, +1...)
  int durability;      // 현재 내구도
  int maxDurability;   // 최대 내구도
  bool isNew;          // 신규 획득 여부
  int rerollCount;     // 옵션 재설정 횟수 (Max 5)
  bool isLocked;       // 아이템 잠금 여부
  ItemOption? potential; // 잠재능력 (v0.0.50 추가)
  int failStreak;      // [v0.4.4] 연속 강화 실패 횟수
  
  bool get isBroken => durability <= 0; // 내구도 0 이하 시 파손 상태
  Item({
    required this.id,
    required this.name,
    required this.type,
    required this.grade,
    required this.tier,
    required this.mainStat1,
    this.mainStat2,
    required this.subOptions,
    this.enhanceLevel = 0,
    this.durability = 100,
    this.maxDurability = 100,
    this.isNew = true,
    this.rerollCount = 0,
    this.isLocked = false,
    this.potential,
    this.failStreak = 0,
  });

  Item copyWith({
    String? id,
    String? name,
    ItemType? type,
    ItemGrade? grade,
    int? tier,
    int? mainStat1,
    int? mainStat2,
    List<ItemOption>? subOptions,
    int? enhanceLevel,
    int? durability,
    int? maxDurability,
    bool? isNew,
    int? rerollCount,
    bool? isLocked,
    ItemOption? potential,
    int? failStreak,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      grade: grade ?? this.grade,
      tier: tier ?? this.tier,
      mainStat1: mainStat1 ?? this.mainStat1,
      mainStat2: mainStat2 ?? this.mainStat2,
      subOptions: subOptions ?? this.subOptions,
      enhanceLevel: enhanceLevel ?? this.enhanceLevel,
      durability: durability ?? this.durability,
      maxDurability: maxDurability ?? this.maxDurability,
      isNew: isNew ?? this.isNew,
      rerollCount: rerollCount ?? this.rerollCount,
      isLocked: isLocked ?? this.isLocked,
      potential: potential ?? this.potential,
      failStreak: failStreak ?? this.failStreak,
    );
  }

  // [v0.4.0] 강화 배율 테이블 (정확한 밸런스 유지용)
  static const List<double> enhanceFactorTable = [
    1.00, // +0
    1.05, // +1
    1.10, // +2
    1.16, // +3
    1.23, // +4
    1.31, // +5
    1.40, // +6
    1.50, // +7
    1.61, // +8
    1.73, // +9
    1.86, // +10
    2.00, // +11
    2.15, // +12
    2.31, // +13
    2.48, // +14
    2.66, // +15
    2.85, // +16
    3.05, // +17
    3.26, // +18
    3.48, // +19
    3.71, // +20
  ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'grade': grade.name,
        'tier': tier,
        'mainStat1': mainStat1,
        'mainStat2': mainStat2,
        'subOptions': subOptions.map((o) => o.toJson()).toList(),
        'enhanceLevel': enhanceLevel,
        'durability': durability,
        'maxDurability': maxDurability,
        'isNew': isNew,
        'rerollCount': rerollCount,
        'isLocked': isLocked,
        'potential': potential?.toJson(),
        'failStreak': failStreak,
      };

  factory Item.fromJson(Map<String, dynamic> json) {
    ItemType type = ItemType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ItemType.weapon,
    );
    ItemGrade grade = ItemGrade.values.firstWhere(
      (e) => e.name == json['grade'],
      orElse: () => ItemGrade.common,
    );

    int currentTier = json['tier'] ?? 1;
    int fixedMainStat1 = json['mainStat1'] ?? json['mainStat'] ?? 10;
    int? fixedMainStat2 = json['mainStat2'];
    List<ItemOption> fixedSubOptions = (json['subOptions'] as List).map((o) => ItemOption.fromJson(o)).toList();

    // 티어 1인 경우에만 새로운 수치로 강제 보정
    if (currentTier == 1) {
      switch (type) {
        case ItemType.weapon:
          fixedMainStat1 = 12;
          fixedMainStat2 = null;
          break;
        case ItemType.helmet:
          fixedMainStat1 = 10;
          fixedMainStat2 = null;
          break;
        case ItemType.armor:
          fixedMainStat1 = 15; // 방어력
          fixedMainStat2 = 80; // 체력
          break;
        case ItemType.boots:
          fixedMainStat1 = 8;
          fixedMainStat2 = null;
          break;
        case ItemType.necklace:
          fixedMainStat1 = 7;   // 공격력
          fixedMainStat2 = 100; // 체력
          break;
        case ItemType.ring:
          fixedMainStat1 = 10;
          fixedMainStat2 = null;
          break;
      }
    }

    return Item(
      id: json['id'],
      name: json['name'],
      type: type,
      grade: grade,
      tier: currentTier,
      mainStat1: fixedMainStat1,
      mainStat2: fixedMainStat2,
      subOptions: fixedSubOptions,
      enhanceLevel: json['enhanceLevel'],
      durability: json['durability'],
      maxDurability: json['maxDurability'],
      isNew: json['isNew'] ?? false,
      rerollCount: json['rerollCount'] ?? 0,
      isLocked: json['isLocked'] ?? false,
      potential: json['potential'] != null ? ItemOption.fromJson(json['potential']) : null,
      failStreak: json['failStreak'] ?? 0,
    );
  }


  // 실제 적용되는 주 능력치 (강화 계수 및 등급 보너스 반영, 파손 패널티)
  int get effectiveMainStat1 {
    double factor = getEnhanceFactor();
    double gradeMult = grade.gradeBonus;
    double brokenPenalty = isBroken ? 0.8 : 1.0; // 파손 시 80%로 감소
    return (mainStat1 * factor * gradeMult * brokenPenalty).toInt();
  }

  int get effectiveMainStat2 {
    if (mainStat2 == null) return 0;
    double factor = getEnhanceFactor();
    double gradeMult = grade.gradeBonus;
    double brokenPenalty = isBroken ? 0.8 : 1.0;
    return (mainStat2! * factor * gradeMult * brokenPenalty).toInt();
  }

  // 장비 리빌딩: 주 능력치 이름 규칙
  String get mainStatName1 => type.mainStatName1;
  String? get mainStatName2 => type.mainStatName2;

  // 아이템 전투력 계산 로직
  int get combatPower {
    double power = 0;

    // 1. 주 능력치 1 점수
    int mStat1 = effectiveMainStat1;
    String name1 = mainStatName1;
    if (name1 == '공격력') {
      power += mStat1 * 2.0;
    } else if (name1 == '체력') {
      power += mStat1 * 0.1;
    } else if (name1 == '방어력') {
      power += mStat1 * 1.5;
    }

    // 2. 주 능력치 2 점수 (있는 경우)
    if (mainStat2 != null) {
      int mStat2 = effectiveMainStat2;
      String? name2 = mainStatName2;
      if (name2 == '공격력') {
        power += mStat2 * 2.0;
      } else if (name2 == '체력') {
        power += mStat2 * 0.1;
      } else if (name2 == '방어력') {
        power += mStat2 * 1.5;
      }
    }

    // 3. 보조 옵션 점수
    for (var opt in subOptions) {
      switch (opt.name) {
        case '공격력': power += opt.value * 2.0; break;
        case '체력': power += opt.value * 0.1; break;
        case '방어력': 
          if (opt.isPercentage) {
            power += opt.value * 10;
          } else {
            power += opt.value * 1.5;
          }
          break;
        case '치명타 확률': power += opt.value * 50.0; break;
        case '치명타 피해': power += opt.value * 5.0; break;
        case '공격 속도': power += opt.value * 500.0; break;
        case 'HP 재생':
        case '골드 획득':
        case '경험치 획득':
        case '아이템 드롭':
          power += opt.value * 10.0;
          break;
      }
    }

    // 4. 잠재능력 점수 합산
    if (potential != null) {
      switch (potential!.name) {
        case '모든 스킬 레벨': power += 5000; break;
        case '최종 피해량 증폭': power += 3000; break;
        case '쿨타임 감소': power += 2000; break;
        default:
          // 일반 옵션과 동일 루틴
          if (potential!.name == '공격력') {
            power += potential!.value * 2.0;
          } else if (potential!.name == '체력') {
            power += potential!.value * 0.1;
          } else if (potential!.name == '방어력') {
            power += potential!.value * 1.5;
          } else if (potential!.name == '치명타 확률') {
            power += potential!.value * 50.0;
          } else if (potential!.name == '치명타 피해') {
            power += potential!.value * 5.0;
          } else if (potential!.name == '공격 속도') {
            power += potential!.value * 500.0;
          } else {
            power += potential!.value * 10.0;
          }
      }
    }

    // 5. 파손 패널티 적용
    if (isBroken) power *= 0.8;

    return power.toInt();
  }

  // 강화 계수 계산 (v0.4.0 테이블 참조 방식으로 변경)
  double getEnhanceFactor() {
    if (enhanceLevel <= 0) return 1.0;
    if (enhanceLevel >= enhanceFactorTable.length) {
      return enhanceFactorTable.last;
    }
    return enhanceFactorTable[enhanceLevel];
  }

  // 드랍 아이템 생성기 (v0.0.59: T1 고정 드랍 및 등급 분리 시스템)
  factory Item.generate(int playerLevel, {int tier = 1, ItemType? forcedType}) {
    final rand = Random();
    final id = DateTime.now().millisecondsSinceEpoch.toString() + rand.nextInt(1000).toString();
    
    // 1. 티어 결정
    int dropTier = tier;

    // 2. 등급 결정 (독립 확률) v0.4.2 개편
    // 일반: 82.0%, 고급: 14.0%, 희귀: 3.0%, 영웅: 0.8%, 고유: 0.15%, 전설: 0.04%, 신화: 0.01%
    ItemGrade grade;
    double gradeRoll = rand.nextDouble();
    if (gradeRoll < 0.0001) {
      grade = ItemGrade.mythic;        // 0.01%
    } else if (gradeRoll < 0.0005) {
      grade = ItemGrade.legendary;     // 0.04% (0.0001 + 0.0004)
    } else if (gradeRoll < 0.0020) {
      grade = ItemGrade.unique;        // 0.15% (0.0005 + 0.0015)
    } else if (gradeRoll < 0.0100) {
      grade = ItemGrade.epic;          // 0.8% (0.0020 + 0.0080)
    } else if (gradeRoll < 0.0400) {
      grade = ItemGrade.rare;          // 3.0% (0.0100 + 0.0300)
    } else if (gradeRoll < 0.1800) {
      grade = ItemGrade.uncommon;      // 14.0% (0.0400 + 0.1400)
    } else {
      grade = ItemGrade.common;        // 82.0%
    }

    ItemType type = forcedType ?? ItemType.values[rand.nextInt(ItemType.values.length)];

    // 3. 보조 옵션 개수 결정 (등급 기반: 1~6개)
    int optCount = grade.index + 1;

    int mStat1 = 0;
    int? mStat2;
    List<ItemOption> options = [];

    // ① 기본 능력치 설정 (T1 베이스 고정)
    double tierMult = pow(4, dropTier - 1).toDouble();

    switch (type) {
      case ItemType.weapon:
        mStat1 = (12 * tierMult).toInt(); 
        break;
      case ItemType.helmet:
        mStat1 = (10 * tierMult).toInt();
        break;
      case ItemType.armor:
        mStat1 = (15 * tierMult).toInt();
        mStat2 = (80 * tierMult).toInt();
        break;
      case ItemType.boots:
        mStat1 = (8 * tierMult).toInt();
        break;
      case ItemType.ring:
        mStat1 = (10 * tierMult).toInt();
        break;
      case ItemType.necklace:
        mStat1 = (7 * tierMult).toInt();
        mStat2 = (100 * tierMult).toInt();
        break;
    }

    // ② 랜덤 보조 옵션 생성 (중복 허용)
    for (int i = 0; i < optCount; i++) {
      ItemOption newOpt = _generateRandomOption(rand, dropTier, grade: grade);
      options.add(newOpt);
    }

    String prefix = getGradeName(grade);
    String typeName = type.nameKr;
    String name = '$prefix $typeName'; 

    return Item(
      id: id,
      name: name,
      type: type,
      grade: grade,
      tier: dropTier,
      mainStat1: mStat1,
      mainStat2: mStat2,
      subOptions: options,
      enhanceLevel: 0,
      durability: 100,
      maxDurability: 100,
      isNew: true,
    );
  }

  // 강화 성공 확률 (v0.4.3 개편)
  double get successChance {
    if (enhanceLevel < 6) return 1.0;     // +0~+5: 100%
    switch (enhanceLevel) {
      case 6: return 0.95;
      case 7: return 0.90;
      case 8: return 0.85;
      case 9: return 0.80;
      case 10: return 0.75;
      case 11: return 0.65;
      case 12: return 0.60;
      case 13: return 0.55;
      case 14: return 0.50;
      case 15: return 0.45;
      case 16: return 0.40;
      case 17: return 0.35;
      case 18: return 0.30;
      case 19: return 0.25;
      case 20: return 0.20;
      default: return 0.20;
    }
  }

  // 강화 비용 계산 (골드)
  int get enhanceCost {
    int base = 1000;
    return (base * pow(1.3, enhanceLevel)).toInt(); // 30%씩 복리 증가
  }

  // 강화석 소모량 계산
  int get stoneCost {
    if (enhanceLevel < 5) return 1;
    if (enhanceLevel < 10) return 3;
    if (enhanceLevel < 15) return 5;
    return 10;
  }

  // 강화 실패 시 내구도 감소량 (v0.4.3 개편)
  int get durabilityLoss {
    if (enhanceLevel <= 10) return 5;
    if (enhanceLevel <= 14) return 8;
    if (enhanceLevel <= 17) return 12;
    return 15;
  }

  // 강화 처리 로직 (v0.4.4 누적 보호 시스템 적용)
  String processEnhance(bool success) {
    if (isBroken) return "파손된 장비는 강화할 수 없습니다.";
    if (enhanceLevel >= 20) return "이미 최대 강화 단계(+20)에 도달했습니다.";

    if (success) {
      enhanceLevel++;
      failStreak = 0; // 성공 시 카운트 리셋
      return _applyLevelMilestone();
    } else {
      failStreak++;
      int loss = durabilityLoss;
      String protectionMsg = "";

      // [v0.4.4] 누적 보호 로직
      if (failStreak >= 6) {
        loss = 0; // 6회 이상 실패 시 내구도 감소 없음
        failStreak = 0; // 보호 발동 후 리셋
        protectionMsg = " (보호 발동: 내구도 보호!)";
      } else if (failStreak >= 3) {
        loss = (loss * 0.5).floor(); // 3회 이상 실패 시 감소량 50% 완화
        protectionMsg = " (완충 발동: 내구도 소모 50% 감소)";
      }

      // 내구도 감소 (단, 1 미만으로는 떨어지지 않음 - 파손 바로 직전까지만)
      int nextDurability = durability - loss;
      if (nextDurability < 1 && durability >= 1 && loss > 0) {
        durability = 1;
      } else {
        durability = nextDurability.clamp(0, maxDurability);
      }

      String msg = "강화 실패 (내구도 -$loss)$protectionMsg";
      
      if (isBroken) {
        msg = "강화 실패 및 장비 파손! (내구도 0)";
      }
      return msg;
    }
  }

  // 강화 계승 적용 (값만 직접 변경)
  void setEnhanceLevel(int level) {
    enhanceLevel = level;
  }

  // 레벨업 시 마일스톤 보너스 및 메시지 생성
  String _applyLevelMilestone() {
    /* 
    // 차후 재구현을 위해 마일스톤 로직 일시 중단
    final rand = Random();
    String message = "";

    // 1. 기존 마일스톤 (옵션 관련)
    if (enhanceLevel == 3 || enhanceLevel == 4 || enhanceLevel == 7) {
      if (subOptions.isNotEmpty) {
        int idx = rand.nextInt(subOptions.length);
        double growth = (enhanceLevel == 7) ? 0.3 : 0.15;
        subOptions[idx].value *= (1 + growth);
        message = "[성장] ${subOptions[idx].name} 수치가 대폭 상승했습니다!";
      }
    } else if (enhanceLevel == 5 || enhanceLevel == 8) {
      ItemOption newOpt = _generateRandomOption(rand, tier);
      subOptions.add(newOpt);
      message = "[개방] 새로운 옵션 '${newOpt.name}'이(가) 추가되었습니다!";
    } else if (enhanceLevel == 9 || enhanceLevel == 10) {
      for (var opt in subOptions) {
        opt.value *= 1.4;
      }
      message = "[폭주] 모든 부가 옵션의 잠재력이 폭발했습니다!";
    }
    
    if (message.isNotEmpty) return message;
    */
    
    return "강화 성공! (+$enhanceLevel)";
  }

  // --- [승급 시스템] (v0.1.14) ---
  bool get canPromote => enhanceLevel >= 20 && tier < 6;
  
  int get promotionGoldCost => tier * 50000;
  int get promotionCubeCost => tier * 10;

  void promote() {
    if (!canPromote) return;
    // 티어 상승, 강화 수치 +10으로 조정
    int nextTier = tier + 1;
    enhanceLevel = 10;
    durability = maxDurability;
    
    // 티어 상승에 따른 기본 스택 재계산 (간소화: 4배 지수 성장 모델 적용)
    double tierMult = pow(4, nextTier - 1).toDouble();
    double oldTierMult = pow(4, tier - 1).toDouble();
    
    mainStat1 = (mainStat1 / oldTierMult * tierMult).toInt();
    if (mainStat2 != null) {
      mainStat2 = (mainStat2! / oldTierMult * tierMult).toInt();
    }
    
    // (선택사항) 보조 옵션들의 maxValue 등도 재조정하면 좋지만, 
    // 여기서는 기본 스펙 진화에 초점을 맞춤.
    
    // 티어 필드 업데이트
    tier = nextTier;
  }

  static String getGradeName(ItemGrade grade) {
    switch (grade) {
      case ItemGrade.common: return '평범한';
      case ItemGrade.uncommon: return '고급';
      case ItemGrade.rare: return '희귀한';
      case ItemGrade.epic: return '영웅의';
      case ItemGrade.unique: return '고유한';
      case ItemGrade.legendary: return '전설의';
      case ItemGrade.mythic: return '신화의';
    }
  }


  static ItemOption _generateRandomOption(Random rand, int tier, {ItemGrade? grade}) {
    List<String> pool = ['공격력', '방어력', '체력', '치명타 확률', '치명타 피해', '공격 속도', 'HP 재생', '골드 획득', '경험치 획득', '아이템 드롭'];
    String name = pool[rand.nextInt(pool.length)];
    
    // 티어 스케일링: 4.0배 지수 성장 기반 최대치 설정
    double tierMult = pow(4, tier - 1).toDouble();
    double val = 0.0;
    double minVal = 0.0;
    double maxVal = 0.0;
    bool isPerc = false;

    // 등급 가중치 (고등급일수록 해당 티어의 천장에 가까운 수치가 뜰 확률 증가)
    double gradeWeight = (grade != null) ? (grade.index * 0.08) : 0.0;
    double roll = (rand.nextDouble() + gradeWeight).clamp(0.0, 1.0);

    switch (name) {
      case '공격력':
        minVal = 4.0 * tierMult;
        maxVal = 10.0 * tierMult;
        val = minVal + (maxVal - minVal) * roll;
        break;
      case '체력':
        minVal = 30.0 * tierMult;
        maxVal = 80.0 * tierMult;
        val = minVal + (maxVal - minVal) * roll;
        break;
      case '방어력':
        minVal = 2.0 * tierMult;
        maxVal = 6.0 * tierMult;
        val = minVal + (maxVal - minVal) * roll;
        break;
      case '치명타 확률':
        isPerc = true;
        minVal = 1.0 + (tier * 0.5);
        maxVal = 3.0 + (tier * 0.5);
        val = minVal + (maxVal - minVal) * roll;
        break;
      case '치명타 피해':
        isPerc = true;
        minVal = 5.0 + (tier * 5.0);
        maxVal = 15.0 + (tier * 5.0);
        val = minVal + (maxVal - minVal) * roll;
        break;
      case '공격 속도':
        minVal = 0.04 + (tier * 0.06); // 밸런스: 2배 상향 (0.02 → 0.04)
        maxVal = 0.16 + (tier * 0.08); // 밸런스: 2배 상향 (0.08 → 0.16)
        val = minVal + (maxVal - minVal) * roll;
        break;
      case 'HP 재생':
        isPerc = true;
        minVal = 0.3 + (tier * 0.2);
        maxVal = 0.8 + (tier * 0.2);
        val = minVal + (maxVal - minVal) * roll;
        break;
      case '골드 획득':
      case '경험치 획득':
      case '아이템 드롭':
        isPerc = true;
        minVal = 2.0 + (tier * 1.5);
        maxVal = 5.0 + (tier * 1.5);
        val = minVal + (maxVal - minVal) * roll;
        break;
    }
    
    int stars = ((val - minVal) / (maxVal - minVal) * 5).ceil().clamp(1, 5);
    
    return ItemOption(name: name, value: val, isPercentage: isPerc, stars: stars, maxValue: maxVal);
  }

  // 옵션 재설정 (리롤)
  void rerollSubOptions(Random rand) {
    if (rerollCount >= 5) return; // 횟수 제한

    for (int i = 0; i < subOptions.length; i++) {
      if (!subOptions[i].isLocked) {
        // 잠겨있지 않은 옵션만 새로 생성하여 교체
        subOptions[i] = _generateRandomOption(rand, tier);
      }
    }
    rerollCount++;
  }

  // 기존 gradeColor getter는 유지하거나 필요없으면 제거 가능
  Color get gradeColor => grade.color;


  // --- [잠재능력 개방] (v0.0.50) ---
  void awakenPotential(Random rand) {
    // 1. 특별 옵션 풀 (저확률 5%)
    if (rand.nextDouble() < 0.05) {
      List<String> specialPool = ['모든 스킬 레벨', '최종 피해량 증폭', '쿨타임 감소'];
      String name = specialPool[rand.nextInt(specialPool.length)];
      double val = (name == '모든 스킬 레벨') ? 1.0 : 5.0; // 스킬 +1, 나머지는 5%
      bool isPerc = (name != '모든 스킬 레벨');
      
      potential = ItemOption(name: name, value: val, isPercentage: isPerc, isSpecial: true, stars: 5, maxValue: val);
    } else {
      // 2. 일반 옵션 풀 (기존 generateRandomOption 활용, 티어 반영)
      potential = _generateRandomOption(rand, tier);
    }
  }
}
