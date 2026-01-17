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
  bool isLocked; // 잠금 상태 추가

  ItemOption({
    required this.name, 
    required this.value, 
    this.isPercentage = false,
    this.isLocked = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'isPercentage': isPercentage,
        'isLocked': isLocked,
      };

  factory ItemOption.fromJson(Map<String, dynamic> json) => ItemOption(
        name: json['name'],
        value: json['value'].toDouble(),
        isPercentage: json['isPercentage'],
        isLocked: json['isLocked'] ?? false,
      );

  @override
  String toString() => '$name +${isPercentage ? '${value.toStringAsFixed(1)}%' : value.toInt()}${isLocked ? ' 🔒' : ''}';
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

  // 부가 옵션도 동일한 강화 계수 적용 여부 (반지/목걸이 HP 용)
  double getEnhanceFactor() => 1 + (enhanceLevel * 0.05);

  // 드롭 아이템 생성기 (스테이지에 따라 티어 및 등급 결정)
  factory Item.generate(int playerLevel, {int stage = 1}) {
    final rand = Random();
    final id = DateTime.now().millisecondsSinceEpoch.toString() + rand.nextInt(1000).toString();
    
    // 티어 및 등급 결정 (100스테이지 단위로 도약)
    // 1-100: T1(Common), 101-200: T2(Uncommon), 201-300: T3(Rare) ...
    int dropTier = ((stage - 1) ~/ 100 + 1).clamp(1, 6);
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
    while (options.length < optCount) {
      ItemOption newOpt = _generateRandomOption(rand, dropTier);
      if (!usedNames.contains(newOpt.name)) {
        options.add(newOpt);
        usedNames.add(newOpt.name);
      }
    }

    String prefix = _getGradeName(grade);
    String typeName = type.nameKr;
    String name = '$prefix $typeName T$dropTier'; // 이름 뒤에 티어 명시

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
    
    return message.isEmpty ? "강화 성공! (+${enhanceLevel})" : message;
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
    bool isPerc = false;

    switch (name) {
      case '공격력':
        val = (rand.nextInt(11) + 5).toDouble() * tierMult; // 5~15
        break;
      case '체력':
        val = (rand.nextInt(101) + 50).toDouble() * tierMult; // 50~150
        break;
      case '방어력':
        val = (rand.nextInt(6) + 2).toDouble() * tierMult; // 2~7
        break;
      case '치명타 확률':
        isPerc = true;
        val = (rand.nextDouble() * 2.0 + 1.0) + (tier * 0.5); // 1~3% + 티어보너스
        break;
      case '치명타 피해':
        isPerc = true;
        val = (rand.nextDouble() * 10.0 + 5.0) + (tier * 5.0); // 5~15% + 티어보너스
        break;
      case '공격 속도':
        val = (rand.nextDouble() * 1.0 + 0.5); // 0.5~1.5 (대폭 상향)
        break;
      case 'HP 재생':
        isPerc = true;
        val = (rand.nextDouble() * 1.0 + 0.5); // 0.5~1.5%
        break;
      case '골드 획득':
      case '경험치 획득':
      case '아이템 드롭':
        isPerc = true;
        val = (rand.nextDouble() * 3.0 + 2.0) + (tier * 1.0); // 2~5% + 티어보너스
        break;
    }
    
    return ItemOption(name: name, value: val, isPercentage: isPerc);
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
}
