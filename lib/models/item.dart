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

enum OptionTrigger {
  static,       // 상시 스탯
  onHit,        // 공격 적중 시
  onCrit,       // 치명타 발생 시
  onKill,       // 적 처치 시
  onDamaged,    // 피격 시
  onSkillUse,   // 스킬 사용 시
}
enum OptionEffect {
  // 기초 스탯 (static)
  addAtk, addAtkPerc,
  addHp, addHpPerc,
  addDef, addDefPerc,
  addAspd, addCritChance, addCritDamage,
  addRegen, addGoldGain, addExpGain, addItemDrop,
  addSkillLevel, addFinalDamagePerc, addCdr,
  
  // 특수 효과
  skillEcho,        // 스킬 추가 발동
  gainShield,       // 보호막 생성
  lifesteal,        // 흡혈
  doubleHit,        // 2연타 확률
  
  // 신규 회복/생존 옵션 (v2.0)
  addRegenCap,          // 회복 상한선(+)
  recoverOnDamagedPerc, // 피격 시 데미지 % 회복
  dmgReductionOnSkill,  // 스킬 사용 시 피해 감소
  addSpecificSkillCdr,  // 특정 스킬 쿨타임 감소
  addCritCdr,           // 치명타 시 쿨타임 감소 (50% 확률)
  execute,             // 치명타 시 즉사 확률
  atkBuffOnKill,      // 처치 시 공격력 버프
  defBuffOnKill,      // 처치 시 방어력 버프
  atkBuffOnZone,      // 지역 이동 시 공격력 버프
  defBuffOnZone,      // 지역 이동 시 방어력 버프
}

extension OptionEffectExtension on OptionEffect {
  String get label {
    switch (this) {
      case OptionEffect.addAtk: return '공격력';
      case OptionEffect.addAtkPerc: return '공격력(%)';
      case OptionEffect.addHp: return '체력';
      case OptionEffect.addHpPerc: return '체력(%)';
      case OptionEffect.addDef: return '방어력';
      case OptionEffect.addDefPerc: return '방어력(%)';
      case OptionEffect.addAspd: return '공격 속도';
      case OptionEffect.addCritChance: return '치명타 확률';
      case OptionEffect.addCritDamage: return '치명타 피해';
      case OptionEffect.addRegen: return 'HP 재생';
      case OptionEffect.addGoldGain: return '골드 획득';
      case OptionEffect.addExpGain: return '경험치 획득';
      case OptionEffect.addItemDrop: return '아이템 드롭';
      case OptionEffect.addSkillLevel: return '모든 스킬 레벨';
      case OptionEffect.addFinalDamagePerc: return '최종 피해량 증폭';
      case OptionEffect.addCdr: return '쿨타임 감소';
      case OptionEffect.skillEcho: return '스킬 추가 발동';
      case OptionEffect.gainShield: return '공격 시 보호막 생성';
      case OptionEffect.lifesteal: return '흡혈';
      case OptionEffect.doubleHit: return '2연타 확률';
      case OptionEffect.addRegenCap: return '회복 상한치';
      case OptionEffect.recoverOnDamagedPerc: return '피격 시 회복';
      case OptionEffect.dmgReductionOnSkill: return '스킬 사용시 피해감소 확률';
      case OptionEffect.addSpecificSkillCdr: return '특정 스킬 쿨감';
      case OptionEffect.addCritCdr: return '치명타 시 쿨감';
      case OptionEffect.execute: return '처형 확률';
      case OptionEffect.atkBuffOnKill: return '처치 시 공증';
      case OptionEffect.defBuffOnKill: return '처치 시 방증';
      case OptionEffect.atkBuffOnZone: return '지역 이동 시 공증';
      case OptionEffect.defBuffOnZone: return '지역 이동 시 방증';
    }
  }

  bool get isPercentage {
    switch (this) {
      case OptionEffect.addAtk:
      case OptionEffect.addHp:
      case OptionEffect.addDef:
      case OptionEffect.addAspd:
      case OptionEffect.addSkillLevel:
      case OptionEffect.addCritCdr: // 쿨감 초 단위
        return false;
      default:
        return true;
    }
  }
}

class ItemOption {
  OptionTrigger trigger;
  OptionEffect effect;
  List<double> values;
  bool isLocked;
  bool isSpecial;
  int stars;
  double maxValue;

  ItemOption({
    required this.trigger,
    required this.effect,
    required this.values,
    this.isLocked = false,
    this.isSpecial = false,
    this.stars = 1,
    this.maxValue = 0,
  });

  // 기존 코드와의 호환성을 위한 getter/setter
  double get value => values.isNotEmpty ? values[0] : 0.0;
  set value(double val) {
    if (values.isEmpty) {
      values = [val];
    } else {
      values[0] = val;
    }
  }

  Map<String, dynamic> toJson() => {
        'trigger': trigger.name,
        'effect': effect.name,
        'values': values,
        'isLocked': isLocked,
        'isSpecial': isSpecial,
        'stars': stars,
        'maxValue': maxValue,
      };

  factory ItemOption.fromJson(Map<String, dynamic> json) {
    // 🆕 구버전 마이그레이션 로직 (name 필드가 있는 경우)
    if (json.containsKey('name')) {
      String name = json['name'];
      bool isPerc = json['isPercentage'] ?? false;
      OptionTrigger trigger = OptionTrigger.static;
      OptionEffect effect = OptionEffect.addAtk;

      switch (name) {
        case '공격력': effect = isPerc ? OptionEffect.addAtkPerc : OptionEffect.addAtk; break;
        case '체력': effect = isPerc ? OptionEffect.addHpPerc : OptionEffect.addHp; break;
        case '방어력': effect = isPerc ? OptionEffect.addDefPerc : OptionEffect.addDef; break;
        case '치명타 확률': effect = OptionEffect.addCritChance; break;
        case '치명타 피해': effect = OptionEffect.addCritDamage; break;
        case '공격 속도': effect = OptionEffect.addAspd; break;
        case 'HP 재생': effect = OptionEffect.addRegen; break;
        case '골드 획득': effect = OptionEffect.addGoldGain; break;
        case '경험치 획득': effect = OptionEffect.addExpGain; break;
        case '아이템 드롭': effect = OptionEffect.addItemDrop; break;
        case '모든 스킬 레벨': effect = OptionEffect.addSkillLevel; break;
        case '최종 피해량 증폭': effect = OptionEffect.addFinalDamagePerc; break;
        case '쿨타임 감소': effect = OptionEffect.addCdr; break;
      }
      
      return ItemOption(
        trigger: trigger,
        effect: effect,
        values: [json['value'].toDouble()],
        isLocked: json['isLocked'] ?? false,
        isSpecial: json['isSpecial'] ?? false,
        stars: json['stars'] ?? 1,
        maxValue: (json['maxValue'] ?? 0).toDouble(),
      );
    }

    return ItemOption(
      trigger: OptionTrigger.values.firstWhere((e) => e.name == json['trigger']),
      effect: OptionEffect.values.firstWhere((e) => e.name == json['effect']),
      values: (json['values'] as List).map((v) => (v as num).toDouble()).toList(),
      isLocked: json['isLocked'] ?? false,
      isSpecial: json['isSpecial'] ?? false,
      stars: json['stars'] ?? 1,
      maxValue: (json['maxValue'] ?? 0).toDouble(),
    );
  }

  @override
  String toString() {
    String prefix = isSpecial ? '[특별] ' : '';

    if (effect == OptionEffect.addSpecificSkillCdr && values.length >= 2) {
      int skillIdx = values[0].toInt();
      double cdrVal = values[1];
      return '$prefix$skillIdx번 스킬 쿨타임 -${cdrVal.toStringAsFixed(1)}%';
    }

    if (effect == OptionEffect.addCritCdr) {
      return '$prefix${effect.label} -${value.toStringAsFixed(1)}s (50%)';
    }

    // [v2.0] 버프 및 특수 옵션 상세 설명 처리
    String suffix = '';
    if (effect == OptionEffect.atkBuffOnKill || effect == OptionEffect.defBuffOnKill || 
        effect == OptionEffect.atkBuffOnZone || effect == OptionEffect.defBuffOnZone) {
      suffix = ' (30초)';
    } else if (effect == OptionEffect.dmgReductionOnSkill) {
      suffix = ' (3초)';
    } else if (effect == OptionEffect.execute) {
      return '$prefix${effect.label} ${value.toStringAsFixed(1)}% (치명타 시 & HP 20% 이하)';
    } else if (effect == OptionEffect.skillEcho) {
      return '$prefix${effect.label} ${value.toStringAsFixed(1)}% (시전 시)';
    } else if (effect == OptionEffect.gainShield) {
      return '$prefix${effect.label} ${value.toStringAsFixed(1)}%';
    }

    final valStr = effect.isPercentage 
        ? '${value.toStringAsFixed(1)}%' 
        : (effect == OptionEffect.addAspd ? value.toStringAsFixed(2) : value.toInt().toString());
    
    return '$prefix${effect.label} +$valStr$suffix';
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
  String? setId;       // 🆕 [v0.7.0] 세트 아이템 ID (null이면 일반 아이템)
  
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
    this.setId,
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
    String? setId,
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
      setId: setId ?? this.setId,
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
        'setId': setId,
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
      setId: json['setId'],
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
      switch (opt.effect) {
        case OptionEffect.addAtk: power += opt.value * 2.0; break;
        case OptionEffect.addAtkPerc: power += opt.value * 10; break; // 임시 가점
        case OptionEffect.addHp: power += opt.value * 0.1; break;
        case OptionEffect.addHpPerc: power += opt.value * 5.0; break; // 임시 가점
        case OptionEffect.addDef: power += opt.value * 1.5; break;
        case OptionEffect.addDefPerc: power += opt.value * 10.0; break;
        case OptionEffect.addCritChance: power += opt.value * 50.0; break;
        case OptionEffect.addCritDamage: power += opt.value * 5.0; break;
        case OptionEffect.addAspd: power += opt.value * 500.0; break;
        case OptionEffect.addRegen:
        case OptionEffect.addGoldGain:
        case OptionEffect.addExpGain:
        case OptionEffect.addItemDrop:
          power += opt.value * 10.0;
          break;
        default:
          power += 500; // 특수 효과들 기본 점수
      }
    }

    // 4. 잠재능력 점수 합산
    if (potential != null) {
      switch (potential!.effect) {
        case OptionEffect.addSkillLevel: power += 5000; break;
        case OptionEffect.addFinalDamagePerc: power += 3000; break;
        case OptionEffect.addCdr: power += 2000; break;
        case OptionEffect.addAtk: power += potential!.value * 2.0; break;
        case OptionEffect.addHp: power += potential!.value * 0.1; break;
        case OptionEffect.addDef: power += potential!.value * 1.5; break;
        case OptionEffect.addCritChance: power += potential!.value * 50.0; break;
        case OptionEffect.addCritDamage: power += potential!.value * 5.0; break;
        case OptionEffect.addAspd: power += potential!.value * 500.0; break;
        default:
          power += potential!.value * 10.0;
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
  factory Item.generate(int playerLevel, {int tier = 1, ItemType? forcedType, String? setId}) {

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
      ItemOption newOpt = _generateRandomOption(rand, dropTier, type, grade: grade);
      options.add(newOpt);
    }

    String prefix = getGradeName(grade);
    String typeName = type.nameKr;
    String name = '$prefix $typeName'; 
    
    // [v0.7.0] 세트 명칭 반영
    if (setId != null) {
      String setName = getSetName(setId);
      name = '[$setName] $name';
    }

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
      setId: setId,
    );

  }

  // 강화 성공 확률 (v0.8.4 티어별 페널티 적용)
  double get successChance {
    double base;
    if (enhanceLevel < 6) {
      base = 1.0; // +0~+5: 기본 100%
    } else {
      switch (enhanceLevel) {
        case 6: base = 0.95; break;
        case 7: base = 0.90; break;
        case 8: base = 0.85; break;
        case 9: base = 0.80; break;
        case 10: base = 0.75; break;
        case 11: base = 0.65; break;
        case 12: base = 0.60; break;
        case 13: base = 0.55; break;
        case 14: base = 0.50; break;
        case 15: base = 0.45; break;
        case 16: base = 0.40; break;
        case 17: base = 0.35; break;
        case 18: base = 0.30; break;
        case 19: base = 0.25; break;
        case 20: base = 0.20; break;
        default: base = 0.20;
      }
    }

    // [v0.8.4] 티어별 페널티 계수 적용
    double multiplier = 1.0;
    switch (tier) {
      case 1: multiplier = 1.0; break;
      case 2: multiplier = 0.7; break;
      case 3: multiplier = 0.5; break;
      case 4: multiplier = 0.4; break;
      case 5: multiplier = 0.3; break;
      case 6: multiplier = 0.25; break;
      default: multiplier = 0.25;
    }

    return base * multiplier;
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

  // 강화 처리 로직 (v0.8.5 보호석 지원 추가)
  String processEnhance(bool success, {bool useProtection = false}) {
    if (isBroken) return "파손된 장비는 강화할 수 없습니다.";
    if (enhanceLevel >= 20) return "이미 최대 강화 단계(+20)에 도달했습니다.";

    if (success) {
      enhanceLevel++;
      failStreak = 0; // 성공 시 카운트 리셋
      return _applyLevelMilestone();
    } else {
      failStreak++;
      int loss = useProtection ? 0 : durabilityLoss;
      String protectionMsg = useProtection ? " (보호석 효과: 내구도 보존)" : "";

      if (!useProtection) {
        // [v0.4.4] 누적 보호 로직 (보호석 미사용 시에만 체크)
        if (failStreak >= 6) {
          loss = 0; // 6회 이상 실패 시 내구도 감소 없음
          failStreak = 0; // 보호 발동 후 리셋
          protectionMsg = " (보호 발동: 내구도 보호!)";
        } else if (failStreak >= 3) {
          loss = (loss * 0.5).floor(); // 3회 이상 실패 시 감소량 50% 완화
          protectionMsg = " (완충 발동: 내구도 소모 50% 감소)";
        }
      }

      // [Last Chance 보호 로직] 
      // 현재 내구도가 1 초과라면, 어떤 감소량이 와도 일단 1에서 한 번 멈춰서 마지막 기회를 줌.
      // 이미 1인 상태에서 실패해야만 0(파손)이 됨. (단, loss가 0인 보호석 사용 시에는 발동 안함)
      if (loss > 0) {
        if (durability > 1) {
          durability = max(1, durability - loss);
        } else {
          durability = 0;
        }
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
  
  int get promotionGoldCost => tier * 500000;
  int get promotionStoneCost {
    switch (tier) {
      case 1: return 100;
      case 2: return 1000;
      case 3: return 10000;
      case 4: return 30000;
      case 5: return 50000;
      default: return 99999999;
    }
  }


  void promote() {
    if (!canPromote) return;
    // 티어 상승, 강화 수치 +10으로 조정
    int nextTier = tier + 1;
    enhanceLevel = 10;
    // durability = maxDurability; <- 제거 (GameState에서 확률적으로 처리)
    
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

  static String getSetName(String setId) {
    switch (setId) {
      case 'desert': return '사막의 개척자';
      case 'mine': return '광산의 수호자';
      case 'dimension': return '차원 여행자';
      case 'dragon': return '드래곤 슬레이어';
      case 'ancient': return '태고의 신';
      default: return '알 수 없는 세트';
    }
  }



  static ItemOption _generateRandomOption(Random rand, int tier, ItemType type, {ItemGrade? grade}) {
    List<OptionEffect> pool = [];
    
    // 모든 부위에서 공통적으로 모든 특수 옵션이 등장하도록 통합
    pool.addAll([
      OptionEffect.addCritChance, 
      OptionEffect.addCritDamage, 
      OptionEffect.addCritCdr,
      OptionEffect.execute,
      OptionEffect.doubleHit,
      OptionEffect.skillEcho,
      OptionEffect.gainShield,
      OptionEffect.addRegen,
      OptionEffect.addRegenCap,
      OptionEffect.recoverOnDamagedPerc,
      OptionEffect.dmgReductionOnSkill,
    ]);
    
    // 공통 유틸리티 풀 추가
    pool.addAll([OptionEffect.addGoldGain, OptionEffect.addExpGain, OptionEffect.addItemDrop]);
    
    OptionEffect effect = pool[rand.nextInt(pool.length)];
    OptionTrigger trigger = OptionTrigger.static;
    
    // 티어 스케일링: 4.0배 지수 성장 기반 최대치 설정
    double tierMult = pow(4, tier - 1).toDouble();
    double val = 0.0;
    double minVal = 0.0;
    double maxVal = 0.0;
    bool isPerc = false;

    // 등급 가중치 (고등급일수록 해당 티어의 천장에 가까운 수치가 뜰 확률 증가)
    double gradeWeight = (grade != null) ? (grade.index * 0.08) : 0.0;
    double roll = (rand.nextDouble() + gradeWeight).clamp(0.0, 1.0);

    switch (effect) {
      case OptionEffect.addAtk:
        minVal = 4.0 * tierMult;
        maxVal = 10.0 * tierMult;
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.addHp:
        minVal = 30.0 * tierMult;
        maxVal = 80.0 * tierMult;
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.addDef:
        minVal = 2.0 * tierMult;
        maxVal = 6.0 * tierMult;
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.addCritChance:
        minVal = 1.0 + (tier * 0.5);
        maxVal = 3.0 + (tier * 0.5);
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.addCritDamage:
        minVal = 5.0 + (tier * 5.0);
        maxVal = 15.0 + (tier * 5.0);
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.addAspd:
        minVal = 0.04 + (tier * 0.06); // 밸런스: 2배 상향 (0.02 → 0.04)
        maxVal = 0.16 + (tier * 0.08); // 밸런스: 2배 상향 (0.08 → 0.16)
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.addRegen:
        minVal = 0.3 + (tier * 0.2);
        maxVal = 0.8 + (tier * 0.2);
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.addRegenCap:
        minVal = 0.5 + (tier * 0.5);
        maxVal = 1.5 + (tier * 0.5);
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.recoverOnDamagedPerc:
        minVal = 1.0 + (tier * 0.5);
        maxVal = 3.0 + (tier * 0.5);
        val = minVal + (maxVal - minVal) * roll;
        break;
      case OptionEffect.dmgReductionOnSkill:
      minVal = 1.0 + (tier * 0.75);
      maxVal = 2.5 + (tier * 0.75);
      val = minVal + (maxVal - minVal) * roll;
      break;
    case OptionEffect.addSpecificSkillCdr:
      minVal = 5.0 + (tier * 5.0);
      maxVal = 15.0 + (tier * 5.0);
      val = minVal + (maxVal - minVal) * roll;
      int skillIdx = rand.nextInt(6) + 1;
      int starsIdx = ((val - minVal) / (maxVal - minVal) * 5).ceil().clamp(1, 5);
      return ItemOption(trigger: trigger, effect: effect, values: [skillIdx.toDouble(), val], stars: starsIdx, maxValue: maxVal);
    case OptionEffect.addCritCdr:
      minVal = 0.1 + (tier * 0.1);
      maxVal = 0.3 + (tier * 0.1);
      val = minVal + (maxVal - minVal) * roll;
      break;
    case OptionEffect.execute:
      minVal = 1.0 + (tier * 1.0);
      maxVal = 3.0 + (tier * 1.0);
      val = minVal + (maxVal - minVal) * roll;
      break;
    case OptionEffect.skillEcho:
      minVal = 2.0 + (tier * 1.0);
      maxVal = 4.0 + (tier * 1.0);
      val = minVal + (maxVal - minVal) * roll;
      break;
      case OptionEffect.gainShield:
        minVal = 1.0 + (tier * 1.0); // 🆕 확률 절반 하향 (2.0+2.0T -> 1.0+1.0T)
        maxVal = 2.5 + (tier * 1.0); // 🆕 확률 절반 하향 (5.0+2.0T -> 2.5+1.0T)
        val = minVal + (maxVal - minVal) * roll;
        break;
    case OptionEffect.doubleHit:
      minVal = 2.0 + (tier * 1.0);
      maxVal = 4.0 + (tier * 1.0);
      val = minVal + (maxVal - minVal) * roll;
      break;
    case OptionEffect.atkBuffOnKill:
    case OptionEffect.defBuffOnKill:
    case OptionEffect.atkBuffOnZone:
    case OptionEffect.defBuffOnZone:
      minVal = 5.0 + (tier * 5.0);
      maxVal = 15.0 + (tier * 5.0);
      val = minVal + (maxVal - minVal) * roll;
      break;
    default:
      // 골드, 경험치, 아이템 드랍 등 공통 퍼센트 옵션
      minVal = 2.0 + (tier * 1.5);
      maxVal = 5.0 + (tier * 1.5);
      val = minVal + (maxVal - minVal) * roll;
      break;
  }
  
  int stars = ((val - minVal) / (maxVal - minVal) * 5).ceil().clamp(1, 5);
  
  return ItemOption(trigger: trigger, effect: effect, values: [val], stars: stars, maxValue: maxVal);
}

  // 옵션 재설정 (리롤)
  void rerollSubOptions(Random rand) {
    if (rerollCount >= 5) return; // 횟수 제한

    for (int i = 0; i < subOptions.length; i++) {
      if (!subOptions[i].isLocked) {
        // 잠겨있지 않은 옵션만 새로 생성하여 교체
        subOptions[i] = _generateRandomOption(rand, tier, type);
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
      List<OptionEffect> specialPool = [
        OptionEffect.addSkillLevel, 
        OptionEffect.addFinalDamagePerc, 
        OptionEffect.addCdr,
        OptionEffect.addRegenCap,
        OptionEffect.dmgReductionOnSkill,
        OptionEffect.execute, // [v2.0] 처형은 특별 잠재에만 추가 저확률
      ];
      OptionEffect effect = specialPool[rand.nextInt(specialPool.length)];
      
      // 특별 옵션 수치 설정
      double val = 1.0;
      switch (effect) {
        case OptionEffect.addSkillLevel: val = 1.0; break;
        case OptionEffect.addRegenCap: val = 3.0; break; // 잠재 특별: 상한 +3%
        case OptionEffect.dmgReductionOnSkill: val = 7.5; break; // 잠재 특별: 감댐 15% -> 7.5%로 하향
        case OptionEffect.execute: val = 1.0; break; // 잠재 특별: 처형 1%
        default: val = 10.0; // FinalDmg, CDR 등
      }
      
      potential = ItemOption(
        trigger: OptionTrigger.static, 
        effect: effect, 
        values: [val], 
        isSpecial: true, 
        stars: 5, 
        maxValue: val
      );
    } else {
      // 2. 일반 옵션 풀 (기존 generateRandomOption 활용, 티어 반영)
      potential = _generateRandomOption(rand, tier, type);
    }
  }
}
