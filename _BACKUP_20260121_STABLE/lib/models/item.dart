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
  epic(Color(0xFFA855F7), '에픽'),
  legendary(Color(0xFFF59E0B), '전설'),
  mythic(Color(0xFFEF4444), '신화');

  final Color color;
  final String name;
  const ItemGrade(this.color, this.name);
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
      case ItemGrade.mythic: return 18.0;
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
    );
  }

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
    );
  }

  bool get isBroken => durability <= 0;

  // 장비 리빌딩: 강화 수식 적용 (복리 성장 모델)
  int get effectiveMainStat1 {
    double factor = getEnhanceFactor();
    double stat = mainStat1 * factor;

    if (isBroken) stat *= 0.8;
    return stat.toInt();
  }

  int get effectiveMainStat2 {
    if (mainStat2 == null) return 0;
    double factor = getEnhanceFactor();
    double stat = mainStat2! * factor;

    if (isBroken) stat *= 0.8;
    return stat.toInt();
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

    return power.toInt();
  }

  // 부가 옵션도 동일한 강화 계수 적용 여부 (반지/목걸이 HP 용)
  // 강화 계수 계산 (복리 모델: 1~17강 12%, 18강~ 6%)
  double getEnhanceFactor() {
    if (enhanceLevel <= 0) return 1.0;
    
    if (enhanceLevel <= 17) {
      return pow(1.12, enhanceLevel).toDouble();
    } else {
      // 17강까지는 12%, 그 이후는 6% 복리
      double baseFactor = pow(1.12, 17).toDouble();
      return baseFactor * pow(1.06, enhanceLevel - 17).toDouble();
    }
  }

  // 드랍 아이템 생성기 (v0.0.59: T1 고정 드랍 및 등급 분리 시스템)
  factory Item.generate(int playerLevel, {int tier = 1, ItemType? forcedType}) {
    final rand = Random();
    final id = DateTime.now().millisecondsSinceEpoch.toString() + rand.nextInt(1000).toString();
    
    // 1. 티어 결정
    int dropTier = tier;

    // 2. 등급 결정 (독립 확률)
    // 일반: 80%, 고급: 12%, 희귀: 5%, 에픽: 2%, 전설: 0.8%, 신화: 0.2%
    ItemGrade grade;
    double gradeRoll = rand.nextDouble();
    if (gradeRoll < 0.002) {
      grade = ItemGrade.mythic;        // 0.2%
    } else if (gradeRoll < 0.010) {
      grade = ItemGrade.legendary;     // 0.8%
    } else if (gradeRoll < 0.030) {
      grade = ItemGrade.epic;          // 2%
    } else if (gradeRoll < 0.080) {
      grade = ItemGrade.rare;          // 5%
    } else if (gradeRoll < 0.200) {
      grade = ItemGrade.uncommon;      // 12%
    } else {
      grade = ItemGrade.common;        // 80%
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

    // ② 랜덤 보조 옵션 생성 (중복 방지)
    Set<String> usedNames = options.map((e) => e.name).toSet();
    while (options.length < optCount) {
      ItemOption newOpt = _generateRandomOption(rand, dropTier, grade: grade);
      if (!usedNames.contains(newOpt.name)) {
        options.add(newOpt);
        usedNames.add(newOpt.name);
      }
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
    
    return "강화 성공! (+$enhanceLevel)";
  }

  static String getGradeName(ItemGrade grade) {
    switch (grade) {
      case ItemGrade.common: return '평범한';
      case ItemGrade.uncommon: return '고급';
      case ItemGrade.rare: return '희귀한';
      case ItemGrade.epic: return '에픽';
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
    for (int i = 0; i < subOptions.length; i++) {
      if (!subOptions[i].isLocked) {
        // 잠겨있지 않은 옵션만 새로 생성하여 교체
        subOptions[i] = _generateRandomOption(rand, tier);
      }
    }
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
