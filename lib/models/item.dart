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

  String get mainStatName {
    switch (this) {
      case ItemType.weapon:
      case ItemType.ring:
      case ItemType.necklace:
        return '공격력';
      case ItemType.helmet:
      case ItemType.armor:
      case ItemType.boots:
        return '체력';
      default:
        return '공격력';
    }
  }
}

enum ItemGrade { common, uncommon, rare, epic, legendary, mythic }

extension ItemGradeExtension on ItemGrade {
  Color get color {
    switch (this) {
      case ItemGrade.common: return const Color(0xFF9CA3AF);    // 일반: 회색
      case ItemGrade.uncommon: return const Color(0xFF22C55E);  // 고급: 녹색
      case ItemGrade.rare: return const Color(0xFF3B82F6);      // 희귀: 파란색
      case ItemGrade.epic: return const Color(0xFFA855F7);      // 에픽: 보라색
      case ItemGrade.legendary: return const Color(0xFFF59E0B); // 전설: 황금색 (Orange-Gold)
      case ItemGrade.mythic: return const Color(0xFFEF4444);    // 신화: 빨간색
    }
  }

  String get name {
    switch (this) {
      case ItemGrade.common: return '일반';
      case ItemGrade.uncommon: return '고급';
      case ItemGrade.rare: return '희귀';
      case ItemGrade.epic: return '에픽';
      case ItemGrade.legendary: return '전설';
      case ItemGrade.mythic: return '신화';
    }
  }

  // --- 프리미엄 UI 확장 데이터 ---
  
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
      case ItemGrade.legendary: return 12.0;
      case ItemGrade.mythic: return 18.0; // 최상위 등급은 강렬한 빛발산
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
    return '$prefix$name +$valStr${isLocked ? ' 🔒' : ''}';
  }
}

class Item {
  final String id;
  final String name;
  final ItemType type;
  final ItemGrade grade;
  final int tier; 
  int mainStat; // 가변으로 변경
  final List<ItemOption> subOptions;
  int enhanceLevel;    // 강화 레벨 (+0, +1...)
  int durability;      // 현재 내구도
  int maxDurability;   // 최대 내구도
  bool isNew;          // 신규 획득 여부
  int rerollCount;     // 옵션 재설정 횟수 (Max 5)
  bool isLocked;       // 아이템 잠금 여부
  ItemOption? potential; // 잠재능력 (v0.0.50 추가)

  Item({
    required this.id,
    required this.name,
    required this.type,
    required this.grade,
    required this.tier,
    required this.mainStat,
    required this.subOptions,
    this.enhanceLevel = 0,
    this.durability = 100,
    this.maxDurability = 100,
    this.isNew = true,
    this.rerollCount = 0,
    this.isLocked = false,
    this.potential,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'grade': grade.name,
        'tier': tier,
        'mainStat': mainStat,
        'subOptions': subOptions.map((o) => o.toJson()).toList(),
        'enhanceLevel': enhanceLevel,
        'durability': durability,
        'maxDurability': maxDurability,
        'isNew': isNew,
        'rerollCount': rerollCount,
        'isLocked': isLocked,
        'potential': potential?.toJson(),
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

    // --- [데이터 보정 로직] 1티어 아이템만 고정 수치 강제 적용 ---
    int fixedMainStat = json['mainStat'];
    List<ItemOption> fixedSubOptions = (json['subOptions'] as List).map((o) => ItemOption.fromJson(o)).toList();
    int currentTier = json['tier'] ?? 1;

    // 티어 1인 경우에만 구버전 데이터 보정 수행
    if (currentTier == 1) {
      switch (type) {
        case ItemType.weapon: fixedMainStat = 100; break;
        case ItemType.helmet: fixedMainStat = 300; break;
        case ItemType.armor: fixedMainStat = 500; break;
        case ItemType.boots: fixedMainStat = 200; break;
        case ItemType.ring:
          fixedMainStat = 20;
          _updateHpOption(fixedSubOptions, 100);
          break;
        case ItemType.necklace:
          fixedMainStat = 30;
          _updateHpOption(fixedSubOptions, 150);
          break;
      }
    }

    return Item(
      id: json['id'],
      name: json['name'],
      type: type,
      grade: grade,
      tier: currentTier,
      mainStat: fixedMainStat,
      subOptions: fixedSubOptions,
      enhanceLevel: json['enhanceLevel'],
      durability: json['durability'],
      maxDurability: json['maxDurability'],
      isNew: json['isNew'] ?? false,
      rerollCount: json['rerollCount'] ?? 0,
      isLocked: json['isLocked'] ?? false,
      potential: json['potential'] != null ? ItemOption.fromJson(json['potential']) : null,
    );
  }

  bool get isBroken => durability <= 0;

  // 장비 리빌딩: 강화 수식 적용 (기본수치 * (1 + level * 0.05))
  int get effectiveMainStat {
    double factor = 1 + (enhanceLevel * 0.05);
    double stat = mainStat * factor;

    if (isBroken) stat *= 0.8;
    return stat.toInt();
  }

  // 장비 리빌딩: 주 능력치 이름 규칙
  String get mainStatName => type.mainStatName;

  // 아이템 전투력 계산 로직
  int get combatPower {
    double power = 0;

    // 1. 주 능력치 점수
    int mStat = effectiveMainStat;
    if (mainStatName == '공격력') power += mStat * 2.0;
    else if (mainStatName == '체력') power += mStat * 0.1;
    else if (mainStatName == '방어력') power += mStat * 1.5;

    // 2. 반지/목걸이 고정 체력 보너스 반영 (강화 영향 포함)
    if (type == ItemType.ring || type == ItemType.necklace) {
      if (subOptions.isNotEmpty && subOptions[0].name == '체력') {
        power += (subOptions[0].value * getEnhanceFactor()) * 0.1;
      }
    }

    // 3. 보조 옵션 점수
    for (var opt in subOptions) {
      switch (opt.name) {
        case '공격력': power += opt.value * 2.0; break;
        case '체력': power += opt.value * 0.1; break;
        case '방어력': 
          if (opt.isPercentage) power += opt.value * 10; // 방어력 %는 임의 가중치
          else power += opt.value * 1.5;
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
          if (potential!.name == '공격력') power += potential!.value * 2.0;
          else if (potential!.name == '체력') power += potential!.value * 0.1;
          else if (potential!.name == '방어력') power += potential!.value * 1.5;
          else if (potential!.name == '치명타 확률') power += potential!.value * 50.0;
          else if (potential!.name == '치명타 피해') power += potential!.value * 5.0;
          else if (potential!.name == '공격 속도') power += potential!.value * 500.0;
          else power += potential!.value * 10.0;
      }
    }

    return power.toInt();
  }

  // 부가 옵션도 동일한 강화 계수 적용 여부 (반지/목걸이 HP 용)
  double getEnhanceFactor() => 1 + (enhanceLevel * 0.05);

  // 드롭 아이템 생성기 (점진적 티어 드롭 시스템)
  factory Item.generate(int playerLevel, {int stage = 1}) {
    final rand = Random();
    final id = DateTime.now().millisecondsSinceEpoch.toString() + rand.nextInt(1000).toString();
    
    // === 점진적 티어 드롭 시스템 ===
    // 현재 구간의 최대 티어 결정
    int maxTier = ((stage - 1) ~/ 100 + 1).clamp(1, 6);
    
    // 각 티어별 드롭 확률 계산
    Map<int, double> tierChances = {};
    
    if (maxTier == 1) {
      // T1 구간 (1-100): T1만 100%
      tierChances[1] = 1.0;
    } else {
      // T2 이상 구간: 점진적 확률 계산
      // 현재 구간 내 진행도 (0.0 ~ 1.0)
      int stageInTier = ((stage - 1) % 100) + 1; // 1~100
      double progress = stageInTier / 100.0; // 0.01 ~ 1.0
      
      // 현재 티어 확률: 5% → 20% (점진적 증가)
      double currentTierChance = 0.05 + (progress * 0.15);
      
      // 이전 티어들 확률 계산
      if (maxTier == 2) {
        // T2 구간 (101-200)
        tierChances[1] = 1.0 - currentTierChance; // 95% → 80%
        tierChances[2] = currentTierChance;        // 5% → 20%
      } else if (maxTier == 3) {
        // T3 구간 (201-300)
        // T1: 75% → 60% (점진적 감소)
        tierChances[1] = 0.75 - (progress * 0.15);
        tierChances[2] = 0.20; // T2 고정 20%
        tierChances[3] = currentTierChance; // T3: 5% → 20%
      } else if (maxTier == 4) {
        // T4 구간 (301-400)
        tierChances[1] = 0.55 - (progress * 0.15); // T1: 55% → 40%
        tierChances[2] = 0.20; // T2 고정 20%
        tierChances[3] = 0.20; // T3 고정 20%
        tierChances[4] = currentTierChance; // T4: 5% → 20%
      } else if (maxTier == 5) {
        // T5 구간 (401-500)
        tierChances[1] = 0.35 - (progress * 0.15); // T1: 35% → 20%
        tierChances[2] = 0.20; // T2 고정 20%
        tierChances[3] = 0.20; // T3 고정 20%
        tierChances[4] = 0.20; // T4 고정 20%
        tierChances[5] = currentTierChance; // T5: 5% → 20%
      } else { // maxTier >= 6
        // T6 구간 (501+)
        tierChances[1] = 0.20; // T1 고정 20%
        tierChances[2] = 0.20; // T2 고정 20%
        tierChances[3] = 0.20; // T3 고정 20%
        tierChances[4] = 0.20; // T4 고정 20%
        tierChances[5] = 0.15; // T5 고정 15%
        tierChances[6] = currentTierChance; // T6: 5% → 20%
      }
    }
    
    // 확률에 따라 티어 선택
    double roll = rand.nextDouble();
    double cumulative = 0.0;
    int dropTier = 1;
    
    for (int tier in tierChances.keys.toList()..sort()) {
      cumulative += tierChances[tier]!;
      if (roll < cumulative) {
        dropTier = tier;
        break;
      }
    }
    
    ItemGrade grade = ItemGrade.values[dropTier - 1];
    ItemType type = ItemType.values[rand.nextInt(ItemType.values.length)];

    // ② 보조 옵션 개수 결정 (티어별 차등)
    int minOpts = (dropTier <= 2) ? 1 : (dropTier == 3) ? 2 : (dropTier <= 5) ? 3 : 4;
    int maxOpts = (dropTier <= 2) ? 2 : (dropTier == 3) ? 3 : (dropTier <= 5) ? 4 : 5;
    int optCount = minOpts + rand.nextInt(maxOpts - minOpts + 1);

    int mStat = 0;
    List<ItemOption> options = [];

    // ① 기본 능력치 설정 (10배수 성장 모델)
    // T1: 1x, T2: 10x, T3: 100x ... T6: 100,000x
    double tierMult = pow(10, dropTier - 1).toDouble();

    switch (type) {
      case ItemType.weapon:
        mStat = (100 * tierMult).toInt(); 
        break;
      case ItemType.helmet:
        mStat = (300 * tierMult).toInt();
        break;
      case ItemType.armor:
        mStat = (500 * tierMult).toInt();
        break;
      case ItemType.boots:
        mStat = (200 * tierMult).toInt();
        break;
      case ItemType.ring:
        mStat = (20 * tierMult).toInt();
        // 장신구 전용 체력 옵션 (슬롯 0번에 우선 배치)
        options.add(ItemOption(name: '체력', value: 100 * tierMult, isPercentage: false));
        break;
      case ItemType.necklace:
        mStat = (30 * tierMult).toInt();
        options.add(ItemOption(name: '체력', value: 150 * tierMult, isPercentage: false));
        break;
    }

    // ② 랜덤 보조 옵션 생성 (중복 방지)
    Set<String> usedNames = options.map((e) => e.name).toSet();
    final int targetCount = options.length + optCount; // 고정 옵션 외에 추가로 optCount만큼 생성
    while (options.length < targetCount) {
      ItemOption newOpt = _generateRandomOption(rand, dropTier);
      if (!usedNames.contains(newOpt.name)) {
        options.add(newOpt);
        usedNames.add(newOpt.name);
      }
    }

    String prefix = _getGradeName(grade);
    String typeName = type.nameKr;
    String name = '$prefix $typeName'; // 이름 뒤의 티어 명시 제거

    return Item(
      id: id,
      name: name,
      type: type,
      grade: grade,
      tier: dropTier,
      mainStat: mStat,
      subOptions: options,
      enhanceLevel: 0,
      durability: 100,
      maxDurability: 100,
      isNew: true,
    );
  }

  // 강화 성공 확률 리빌딩
  double get successChance {
    if (enhanceLevel < 5) return 1.0;     // 1~5강: 100%
    if (enhanceLevel < 8) return 0.95;    // 6~8강: 95%
    if (enhanceLevel == 8) return 0.90;   // 9강(이전레벨 8): 90%
    if (enhanceLevel == 9) return 0.85;   // 10강(이전레벨 9): 85%
    return 0.30;                          // 11~20강: 30% 고정
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

  // 강화 실패 시 내구도 감소량
  int get durabilityLoss => 10;

  // 강화 처리 로직 (성공/실패 통합) - 리턴값은 결과 메시지
  String processEnhance(bool success) {
    if (success) {
      enhanceLevel++;
      return _applyLevelMilestone();
    } else {
      durability = (durability - durabilityLoss).clamp(0, maxDurability);
      String msg = "강화 실패 (내구도 -$durabilityLoss)";
      
      // 15강 이상에서 실패 시 30% 확률로 단계 하락
      if (enhanceLevel >= 15 && Random().nextDouble() < 0.3) {
        enhanceLevel = (enhanceLevel - 1).clamp(0, 99);
        msg += " & 단계 하락!";
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
    
    return "강화 성공! (+${enhanceLevel})";
  }

  static String _getGradeName(ItemGrade grade) {
    switch (grade) {
      case ItemGrade.common: return '평범한';
      case ItemGrade.uncommon: return '고급';
      case ItemGrade.rare: return '희귀한';
      case ItemGrade.epic: return '에픽';
      case ItemGrade.legendary: return '전설의';
      case ItemGrade.mythic: return '신화의';
    }
  }

  static String _getTypeName(ItemType type) => type.nameKr;

  static ItemOption _generateRandomOption(Random rand, int tier) {
    List<String> pool = ['공격력', '방어력', '체력', '치명타 확률', '치명타 피해', '공격 속도', 'HP 재생', '골드 획득', '경험치 획득', '아이템 드롭'];
    String name = pool[rand.nextInt(pool.length)];
    
    double tierMult = pow(10, tier - 1).toDouble();
    double val = 0.0;
    double minVal = 0.0;
    double maxVal = 0.0;
    bool isPerc = false;

    switch (name) {
      case '공격력':
        minVal = 5.0 * tierMult;
        maxVal = 15.0 * tierMult;
        val = (rand.nextInt(11) + 5).toDouble() * tierMult;
        break;
      case '체력':
        minVal = 50.0 * tierMult;
        maxVal = 150.0 * tierMult;
        val = (rand.nextInt(101) + 50).toDouble() * tierMult;
        break;
      case '방어력':
        minVal = 2.0 * tierMult;
        maxVal = 7.0 * tierMult;
        val = (rand.nextInt(6) + 2).toDouble() * tierMult;
        break;
      case '치명타 확률':
        isPerc = true;
        minVal = 1.0 + (tier * 0.5);
        maxVal = 3.0 + (tier * 0.5);
        val = (rand.nextDouble() * 2.0 + 1.0) + (tier * 0.5);
        break;
      case '치명타 피해':
        isPerc = true;
        minVal = 5.0 + (tier * 5.0);
        maxVal = 15.0 + (tier * 5.0);
        val = (rand.nextDouble() * 10.0 + 5.0) + (tier * 5.0);
        break;
      case '공격 속도':
        minVal = 0.5;
        maxVal = 1.5;
        val = (rand.nextDouble() * 1.0 + 0.5);
        break;
      case 'HP 재생':
        isPerc = true;
        minVal = 0.5;
        maxVal = 1.5;
        val = (rand.nextDouble() * 1.0 + 0.5);
        break;
      case '골드 획득':
      case '경험치 획득':
      case '아이템 드롭':
        isPerc = true;
        minVal = 2.0 + (tier * 1.0);
        maxVal = 5.0 + (tier * 1.0);
        val = (rand.nextDouble() * 3.0 + 2.0) + (tier * 1.0);
        break;
    }
    
    int stars = ((val - minVal) / (maxVal - minVal) * 5).ceil().clamp(1, 5);
    
    return ItemOption(name: name, value: val, isPercentage: isPerc, stars: stars, maxValue: maxVal);
  }

  // 옵션 재설정 (리롤)
  void rerollSubOptions(Random rand) {
    for (int i = 0; i < subOptions.length; i++) {
      if (!subOptions[i].isLocked) {
        // 잠겨있지 않은 옵션만 새로 생성하여 교체
        subOptions[i] = _generateRandomOption(rand, tier);
      }
    }
  }

  // 기존 gradeColor getter는 유지하거나 필요없으면 제거 가능
  Color get gradeColor => grade.color;

  // 헬퍼: 체력 옵션 업데이트/추가
  static void _updateHpOption(List<ItemOption> options, double value) {
    bool hasHp = options.any((o) => o.name == '체력');
    if (!hasHp) {
      options.add(ItemOption(name: '체력', value: value, isPercentage: false));
    } else {
      for (var o in options) {
        if (o.name == '체력') o.value = value;
      }
    }
  }

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
