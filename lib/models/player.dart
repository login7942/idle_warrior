import 'dart:math';
import 'item.dart';
import 'skill.dart';
import 'pet.dart';

class Player {
  String name;
  int level;
  int exp;
  int maxExp;
  int gold;

  // 펫 시스템
  List<Pet> pets = [];
  Pet? activePet;
  
  // 펫 보유 효과 계산용 유틸리티
  double get petAtkBonus => pets.fold(0.0, (sum, p) => sum + p.currentAtkBonus);
  double get petHpBonus => pets.fold(0.0, (sum, p) => sum + p.currentHpBonus);
  double get petGoldBonus => pets.fold(0.0, (sum, p) => sum + p.currentGoldBonus);
  
  // [v0.0.68] 펫 보유 효과 요약 텍스트
  String get petSummaryText {
    String summary = "";
    if (petAtkBonus > 0) summary += "공격력 +${petAtkBonus.toStringAsFixed(1)}% ";
    if (petHpBonus > 0) summary += "HP +${petHpBonus.toStringAsFixed(1)}% ";
    if (petGoldBonus > 0) summary += "골드 +${petGoldBonus.toStringAsFixed(1)}% ";
    
    return summary.isEmpty ? "보유 중인 펫 효과 없음" : summary.trim();
  }
  
  // 동행 효과 값 가져오기용
  double getPetCompanionValue(String skillName) {
    if (activePet != null && activePet!.companionSkillName == skillName) {
      return activePet!.currentCompanionValue;
    }
    return 0.0;
  }

  // 5대 핵심 강화 재료
  int powder = 0;           // 가루
  int enhancementStone = 0; // 강화석
  int rerollStone = 0;      // 재설정
  int protectionStone = 0;   // 보호
  int cube = 0;             // 큐브

  // 누적 통계 (업적용)
  int totalKills = 0;
  int totalGoldEarned = 0;
  int totalItemsFound = 0;
  int totalSkillsUsed = 0;
  Map<String, int> achievementSteps = {}; // 각 업적별 현재 단계
  
  // 강화 계승 시스템: 티어별 저장된 강화 레벨 (70% 계승용)
  Map<int, int> enhancementSuccession = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}; 

  // --- [신규 업데이트 v0.0.60] 제작 및 게이트 시스템 재료 ---
  // 티어 파편 (Disassembly Shards): 장비 분해 시 획득
  Map<int, int> tierShards = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};
  // 티어 코어 (Gate Cores): 스펙 조건 충족 시 몬스터 드랍 (심연의 구슬 등)
  Map<int, int> tierCores = {2: 0, 3: 0, 4: 0, 5: 0, 6: 0};

  // 장착 슬롯 강화 시스템 (v0.3.0)
  // +1 ~ +100레벨 시스템, 장비를 교체해도 유지됨
  Map<ItemType, int> slotEnhanceLevels = {
    ItemType.weapon: 0,
    ItemType.helmet: 0,
    ItemType.armor: 0,
    ItemType.boots: 0,
    ItemType.ring: 0,
    ItemType.necklace: 0,
  };

  // 장착 중인 모든 부위(6개)의 평균 강화 수치 (기존 아이템 강화 기준)
  double get averageEnhanceLevel {
    int total = 0;
    for (var item in equipment.values) {
      if (item != null) {
        total += item.enhanceLevel;
      }
    }
    return total / 6.0; // 6개 슬롯 기준 평균 (미장착 시 0강 취급)
  }

  // 장비 도감 시스템 (v0.0.35 추가)
  // encyclopediaProgress: "Tier_Type" -> Max Level reached (e.g., "T1_weapon" -> 15)
  Map<String, int> encyclopediaProgress = {};
  
  // [v0.0.78] 도감 업데이트 - 아이템 획득 및 강화 시 자동 호출
  void updateEncyclopedia(Item item) {
    String key = 'T${item.tier}_${item.type.name}';
    int currentMax = encyclopediaProgress[key] ?? -1;
    // 현재 도감 레벨보다 높은 등급/강화의 아이템이면 갱신 (-1인 경우 0강이라도 갱신)
    if (item.enhanceLevel > currentMax) {
      encyclopediaProgress[key] = item.enhanceLevel;
    }
  }

  // encyclopediaClaims: "Tier_Type" -> List of claimed levels (e.g., "T1_weapon" -> [0, 1, 2, 5])
  Map<String, List<int>> encyclopediaClaims = {};

  // 도감 보너스 계산 유틸리티
  double get encyclopediaAtkBonus {
    try {
      double total = 0;
      for (var entry in encyclopediaClaims.entries) {
        final key = entry.key;
        final levels = entry.value;
        String tierStr = key.split('_')[0].replaceAll('T', '');
        int tier = int.tryParse(tierStr) ?? 1;
        for (var _ in levels) {
          if (tier <= 4) {
            total += pow(2, tier - 1).toDouble(); 
          }
        }
      }
      return total;
    } catch (_) {
      return 0.0;
    }
  }

  double get encyclopediaAtkMultiplier {
    try {
      double multi = 0;
      encyclopediaClaims.forEach((key, levels) {
        String tierStr = key.split('_')[0].replaceAll('T', '');
        int tier = int.tryParse(tierStr) ?? 1;
        if (tier >= 5) {
          double step = (tier == 5) ? 0.01 : 0.05;
          multi += levels.length * step;
        }
      });
      return multi / 100;
    } catch (_) {
      return 0.0;
    }
  }

  double get encyclopediaHpBonus {
    try {
      double total = 0;
      for (var entry in encyclopediaClaims.entries) {
        final key = entry.key;
        final levels = entry.value;
        String tierStr = key.split('_')[0].replaceAll('T', '');
        int tier = int.tryParse(tierStr) ?? 1;
        for (var _ in levels) {
          if (tier <= 4) {
            total += pow(2, tier - 1).toDouble() * 10;
          }
        }
      }
      return total;
    } catch (_) {
      return 0.0;
    }
  }

  double get encyclopediaHpMultiplier {
    try {
      double multi = 0;
      encyclopediaClaims.forEach((key, levels) {
        String tierStr = key.split('_')[0].replaceAll('T', '');
        int tier = int.tryParse(tierStr) ?? 1;
        if (tier >= 5) {
          double step = (tier == 5) ? 0.01 : 0.05;
          multi += levels.length * step;
        }
      });
      return multi / 100;
    } catch (_) {
      return 0.0;
    }
  }

  // [v0.0.67] 도감 일괄 수령 로직
  int claimAllEncyclopediaRewards() {
    int totalClaimed = 0;
    encyclopediaProgress.forEach((key, maxLevel) {
      if (encyclopediaClaims[key] == null) {
        encyclopediaClaims[key] = [];
      }
      List<int> claimed = encyclopediaClaims[key]!;
      for (int lv = 0; lv <= maxLevel; lv++) {
        if (!claimed.contains(lv)) {
          claimed.add(lv);
          totalClaimed++;
        }
      }
    });
    return totalClaimed;
  }

  // [v0.0.67] 도감 보너스 요약 텍스트
  String get encyclopediaSummaryText {
    String summary = "";
    if (encyclopediaAtkBonus > 0) summary += "공격력 +${encyclopediaAtkBonus.toInt()} ";
    if (encyclopediaAtkMultiplier > 0) summary += "공격력 +${(encyclopediaAtkMultiplier * 100).toStringAsFixed(1)}% ";
    if (encyclopediaHpBonus > 0) summary += "HP +${encyclopediaHpBonus.toInt()} ";
    if (encyclopediaHpMultiplier > 0) summary += "HP +${(encyclopediaHpMultiplier * 100).toStringAsFixed(1)}% ";
    
    return summary.isEmpty ? "적용된 보너스 없음" : summary.trim();
  }

  // 기본 전투 스탯
  int baseHp;
  int baseAttack;
  int baseDefense;
  double baseAttackSpeed = 1.5; // 초반 밸런스 개선: 1.0 → 1.5 
  double baseCritChance = 5.0; 
  double baseCritDamage = 150.0; // 기본 치명타 피해 150%
  double baseHpRegen = 1.0;    
  double baseGoldBonus = 100.0;
  double baseDropBonus = 100.0;
  double baseOffEfficiency = 0.7; // 🆕 방치 효율 상향 (30% -> 70%)
  double baseCdr = 0.0; // 기본 쿨타임 감소 0%

  // 스킬 목록 (v0.0.62 밸런스 개편)
  List<Skill> skills = [
    Skill(id: 'act_1', name: '바람 베기', description: '초반 주력기 (3연타 공격)', type: SkillType.active, iconEmoji: '🌪️', unlockLevel: 5, unlockCost: 1000, baseUpgradeCost: 1000, costMultiplier: 1.5, baseValue: 80, valuePerLevel: 8, baseCooldown: 6),
    Skill(id: 'pas_1', name: '광폭화', description: '공격 속도가 영구적으로 증가합니다.', type: SkillType.passive, iconEmoji: '🔥', unlockLevel: 10, unlockCost: 5000, baseUpgradeCost: 5000, costMultiplier: 2.0, baseValue: 30, valuePerLevel: 2.0, baseCooldown: 0), // 밸런스: 10→30, 1.4→2.0
    Skill(id: 'act_2', name: '강격', description: '강력한 한방 데미지를 입힙니다.', type: SkillType.active, iconEmoji: '🔨', unlockLevel: 15, unlockCost: 2000, baseUpgradeCost: 2000, costMultiplier: 1.6, baseValue: 200, valuePerLevel: 20, baseCooldown: 12),
    Skill(id: 'pas_2', name: '철벽', description: '방어력이 % 비율로 증가합니다.', type: SkillType.passive, iconEmoji: '🛡️', unlockLevel: 20, unlockCost: 5000, baseUpgradeCost: 5000, costMultiplier: 2.0, baseValue: 10, valuePerLevel: 2, baseCooldown: 0),
    Skill(id: 'act_3', name: '얼음 화살', description: '고위력 공격 및 적을 빙결시킵니다.', type: SkillType.active, iconEmoji: '❄️', unlockLevel: 30, unlockCost: 5000, baseUpgradeCost: 5000, costMultiplier: 1.8, baseValue: 300, valuePerLevel: 40, baseCooldown: 15),
    Skill(id: 'pas_3', name: '탐욕의 시선', description: '골드 및 아이템 획득량이 증가합니다.', type: SkillType.passive, iconEmoji: '👁️', unlockLevel: 45, unlockCost: 8000, baseUpgradeCost: 8000, costMultiplier: 2.2, baseValue: 10, valuePerLevel: 2, baseCooldown: 0),
    Skill(id: 'act_4', name: '화염구', description: '강력한 마법형 광역 데미지.', type: SkillType.active, iconEmoji: '☄️', unlockLevel: 60, unlockCost: 8000, baseUpgradeCost: 8000, costMultiplier: 2.0, baseValue: 600, valuePerLevel: 80, baseCooldown: 20),
    Skill(id: 'pas_4', name: '약점 노출', description: '치명타 피해량이 대폭 증가합니다.', type: SkillType.passive, iconEmoji: '🎯', unlockLevel: 80, unlockCost: 10000, baseUpgradeCost: 10000, costMultiplier: 2.5, baseValue: 20, valuePerLevel: 5, baseCooldown: 0),
    Skill(id: 'act_5', name: '메테오', description: '최종 결전기 (초고화력 폭격)', type: SkillType.active, iconEmoji: '🌠', unlockLevel: 120, unlockCost: 50000, baseUpgradeCost: 50000, costMultiplier: 2.5, baseValue: 2000, valuePerLevel: 300, baseCooldown: 60),
    Skill(id: 'pas_5', name: '흡혈의 손길', description: '데미지 비례 체력을 흡수합니다.', type: SkillType.passive, iconEmoji: '🦇', unlockLevel: 160, unlockCost: 15000, baseUpgradeCost: 15000, costMultiplier: 3.0, baseValue: 1, valuePerLevel: 0.5, baseCooldown: 0),
    Skill(id: 'pas_6', name: '신속', description: '모든 스킬의 재사용 대기시간이 감소합니다.', type: SkillType.passive, iconEmoji: '⚡', unlockLevel: 200, unlockCost: 20000, baseUpgradeCost: 20000, costMultiplier: 3.5, baseValue: 5, valuePerLevel: 1, baseCooldown: 0),
  ];

  // 인벤토리 및 장비
  List<Item> inventory = [];
  final int maxInventory = 500; // 사용자 요청에 따라 500으로 수정
  Map<ItemType, Item?> equipment = {
    ItemType.weapon: null,
    ItemType.helmet: null,
    ItemType.armor: null,
    ItemType.boots: null,
    ItemType.ring: null,
    ItemType.necklace: null,
  };

  Player({
    this.name = '전웅',
    this.level = 1,
    this.exp = 0,
    this.maxExp = 100,
    this.gold = 5000, // 초반 밸런스: 1000 → 5000
    this.baseHp = 100,
    this.baseAttack = 10,
    this.baseDefense = 3,
  });

  int get combatPower {
    return (attack * 2) + (defense * 1.5).toInt() + (maxHp ~/ 10);
  }

  // --- [잠재능력 보너스 게터] ---
  int get potentialSkillBonus {
    int bonus = 0;
    equipment.values.where((i) => i != null).forEach((item) {
      if (item!.potential?.name == '모든 스킬 레벨') bonus += item.potential!.value.toInt();
    });
    return bonus;
  }

  double get potentialFinalDamageMult {
    double mult = 1.0;
    equipment.values.where((i) => i != null).forEach((item) {
      if (item!.potential?.name == '최종 피해량 증폭') mult += item.potential!.value / 100;
    });
    return mult;
  }

  double get potentialCdr {
    double cdr = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      if (item!.potential?.name == '쿨타임 감소') cdr += item.potential!.value;
    });
    return cdr;
  }

  double getSkillValue(String id) {
    try {
      final skill = skills.firstWhere((s) => s.id == id);
      if (!skill.isUnlocked) return 0.0;
      
      // 잠재능력 스킬 레벨 보너스 적용
      int effectiveLevel = skill.level + potentialSkillBonus;
      return skill.baseValue + (effectiveLevel * skill.valuePerLevel);
    } catch (_) {
      return 0.0;
    }
  }

  // --- [슬롯 강화 계수 계산] ---
  // 레벨당 2%씩 주 능력치 증폭 (100강 시 3배)
  double _getSlotMultiplier(ItemType type) {
    int level = slotEnhanceLevels[type] ?? 0;
    return 1.0 + (level * 0.02);
  }

  int get maxHp {
    double petBonus = 1.0 + (petHpBonus / 100);
    int flat = 0;

    for (var item in equipment.values) {
      if (item == null) {
        continue;
      }
      
      // 장비 주 능력치 체크
      double slotMult = _getSlotMultiplier(item.type);
      if (item.mainStatName1 == '체력') {
        flat += (item.effectiveMainStat1 * slotMult).toInt();
      }
      if (item.mainStatName2 == '체력') {
        flat += (item.effectiveMainStat2 * slotMult).toInt();
      }

      // 부가 옵션에 체력이 있는 경우
      for (var opt in item.subOptions) {
        if (opt.name == '체력') {
          // [수정] 장신구(반지/목걸이)의 고정 체력 보너스는 강화 계수를 적용 (0번 인덱스 가정)
          if ((item.type == ItemType.ring || item.type == ItemType.necklace) && item.subOptions.indexOf(opt) == 0) {
            flat += (opt.value * item.getEnhanceFactor()).toInt();
          } else {
            flat += opt.value.toInt();
          }
        }
      }

      // 잠재능력 체력 반영
      if (item.potential?.name == '체력') {
        flat += item.potential!.value.toInt();
      }
    }

    return (baseHp * petBonus * (1.0 + encyclopediaHpMultiplier)).toInt() + flat + encyclopediaHpBonus.toInt();
  }

  int get attack {
    double petBonus = 1.0 + (petAtkBonus / 100);
    int flat = getSkillValue('pas_1').toInt(); // 패시브 스킬 보너스
    double activePetMultiplier = 1.0 + (getPetCompanionValue('용의 분노') / 100);
    
    for (var item in equipment.values) {
      if (item == null) {
        continue;
      }

      // 장비 주 능력치 체크
      double slotMult = _getSlotMultiplier(item.type);
      if (item.mainStatName1 == '공격력') {
        flat += (item.effectiveMainStat1 * slotMult).toInt();
      }
      if (item.mainStatName2 == '공격력') {
        flat += (item.effectiveMainStat2 * slotMult).toInt();
      }

      // 부가 옵션에 공격력이 있는 경우 (강화 영향 안 받음)
      for (var opt in item.subOptions) {
        if (opt.name == '공격력') {
          flat += opt.value.toInt();
        }
      }

      // 잠재능력 공격력 반영
      if (item.potential?.name == '공격력') {
        flat += item.potential!.value.toInt();
      }
    }

    int totalAtk = (baseAttack * petBonus * (1.0 + encyclopediaAtkMultiplier)).toInt() + flat + encyclopediaAtkBonus.toInt();
    return (totalAtk * activePetMultiplier).toInt();
  }

  int get defense {
    double bonus = 1.0 + (getSkillValue('pas_2') / 100);
    int flat = 0;
    for (var item in equipment.values) {
      if (item == null) continue;
      
      double slotMult = _getSlotMultiplier(item.type);
      if (item.mainStatName1 == '방어력') {
        flat += (item.effectiveMainStat1 * slotMult).toInt();
      }
      if (item.mainStatName2 == '방어력') {
        flat += (item.effectiveMainStat2 * slotMult).toInt();
      }
      
      for (var opt in item.subOptions) {
        if (opt.name == '방어력') {
          if (opt.isPercentage) {
            bonus += opt.value / 100;
          } else {
            flat += opt.value.toInt();
          }
        }
      }
      // 잠재능력 방어력 반영
      if (item.potential?.name == '방어력') {
        if (item.potential!.isPercentage) {
          bonus += item.potential!.value / 100;
        } else {
          flat += item.potential!.value.toInt();
        }
      }
    }
    return (baseDefense * bonus).toInt() + flat;
  }

  double get attackSpeed {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '공격 속도') itemBonus += opt.value;
      }
      if (item.potential?.name == '공격 속도') itemBonus += item.potential!.value;
    });
    double total = baseAttackSpeed + (getSkillValue('pas_1') / 100) + (getPetCompanionValue('가속 점프') / 100) + (getPetCompanionValue('급강하 공격') / 100) + (getPetCompanionValue('화염 폭풍') / 100) + itemBonus;
    return total.clamp(0.1, 6.0); // 최대 공격 속도 6.0 (하드캡 상향: 4.0 → 6.0)
  }

  double get critChance {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '치명타 확률') itemBonus += opt.value;
      }
      if (item.potential?.name == '치명타 확률') itemBonus += item.potential!.value;
    });
    return baseCritChance + getPetCompanionValue('예리한 통찰') + itemBonus;
  }

  double get critDamage {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '치명타 피해') itemBonus += opt.value;
      }
      if (item.potential?.name == '치명타 피해') itemBonus += item.potential!.value;
    });
    return baseCritDamage + getSkillValue('pas_4') + itemBonus;
  }

  double get hpRegen {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == 'HP 재생') itemBonus += opt.value;
      }
      if (item.potential?.name == 'HP 재생') itemBonus += item.potential!.value;
    });
    return baseHpRegen + itemBonus;
  }

  double get goldBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '골드 획득') itemBonusPerc += opt.value;
      }
      if (item.potential?.name == '골드 획득') itemBonusPerc += item.potential!.value;
    });
    return goldBonusBase + getSkillValue('pas_3') + petGoldBonus + itemBonusPerc;
  }

  double get goldBonusBase => baseGoldBonus;

  double get expBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '경험치 획득') itemBonusPerc += opt.value;
      }
      if (item.potential?.name == '경험치 획득') itemBonusPerc += item.potential!.value;
    });
    return 100.0 + (getSkillValue('pas_4') / 100) + itemBonusPerc; // 기본 100% 기준
  }

  double get dropBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '아이템 드롭') itemBonusPerc += opt.value;
      }
      if (item.potential?.name == '아이템 드롭') itemBonusPerc += item.potential!.value;
    });
    return baseDropBonus + getSkillValue('pas_3') + itemBonusPerc;
  }
  double get offEfficiency => baseOffEfficiency;
  double get cdr => baseCdr + getSkillValue('pas_6') + potentialCdr;
  double get lifesteal => getSkillValue('pas_5');

  bool addItem(Item item) {
    if (inventory.length >= maxInventory) return false;
    
    // 계승 시스템: 같은 티어의 저장된 강화 수치가 있다면 주입 (파손 장비 보상)
    int savedLevel = enhancementSuccession[item.tier] ?? 0;
    if (savedLevel > 0 && item.enhanceLevel < savedLevel) {
      item.enhanceLevel = savedLevel;
      enhancementSuccession[item.tier] = 0; // 사용 후 해당 슬롯 초기화
    }
    
    inventory.add(item);
    return true;
  }

  void equipItem(Item item) {
    Item? current = equipment[item.type];
    if (current != null) inventory.add(current);
    equipment[item.type] = item;
    inventory.removeWhere((i) => i.id == item.id);
  }

  void unequipItem(ItemType type) {
    Item? current = equipment[type];
    if (current != null && inventory.length < maxInventory) {
      inventory.add(current);
      equipment[type] = null;
    }
  }

  void gainExp(int amount) {
    exp += amount;
    while (exp >= maxExp) {
      exp -= maxExp;
      level++;
      levelUp();
      
      // [v0.0.47] 레벨 1000 시스템: 선형 증가 방식
      // 기존: maxExp = (maxExp * 1.15).toInt() → 기하급수적 폭발
      // 신규: 레벨에 비례한 고정값 추가 → 레벨 1000까지 가능
      maxExp = maxExp + (level * 10);
    }
  }

  void levelUp() {
    // 레벨업 스탯 증가: HP +30, ATK +2, DEF +0.5 (2레벨당 1)
    baseHp += 30;
    baseAttack += 2;
    if (level % 2 == 0) {
      baseDefense += 1;
    }
  }

  String? checkAchievement(String id, int currentProgress, int target, int reward) {
    int currentStep = achievementSteps[id] ?? 0;
    if (currentProgress >= target) {
      achievementSteps[id] = currentStep + 1;
      enhancementStone += reward; 
      return '업적 달성! [$id ${currentStep + 1}단계] 보상: 강화석 $reward개';
    }
    return null;
  }

  Map<String, dynamic> calculateOfflineRewards(DateTime lastTime, double goldMin, double expMin, double killsMin) {
    int minutes = DateTime.now().difference(lastTime).inMinutes;
    if (minutes > 1440) minutes = 1440; // 최대 24시간
    if (minutes < 1) return {};
    
    double efficiency = baseOffEfficiency; 
    int totalGold = (minutes * goldMin * efficiency).toInt();
    int totalExp = (minutes * expMin * efficiency).toInt();
    int totalKills = (minutes * killsMin * efficiency).toInt();
    
    // [v0.0.61] 제작 재료 보상 추가 (균형형)
    int t1Shards = (totalKills * 0.5).toInt();      // T1 파편: 처치당 0.5개
    int powderReward = (totalKills * 0.3).toInt();  // 가루: 처치당 0.3개
    int stoneReward = (totalKills * 0.05).toInt();  // 강화석: 처치당 0.05개
    int rerollReward = (totalKills * 0.02).toInt(); // 재설정석: 처치당 0.02개
    int protectReward = (totalKills * 0.01).toInt();// 보호석: 처치당 0.01개
    int cubeReward = (totalKills * 0.005).toInt();  // 큐브: 처치당 0.005개
    
    // 티어별 파편 차등 지급 (평균 강화도 기반)
    Map<int, int> tierShardsReward = {1: t1Shards};
    if (averageEnhanceLevel >= 13.0) {
      // T2 파편: T1의 10%
      tierShardsReward[2] = (totalKills * 0.05).toInt();
    }
    if (averageEnhanceLevel >= 15.0) {
      // T3 파편: T1의 3%
      tierShardsReward[3] = (totalKills * 0.015).toInt();
    }
    
    return {
      'minutes': minutes,
      'gold': totalGold,
      'exp': totalExp,
      'kills': totalKills,
      'bonusStones': stoneReward, // 기존 bonusStones를 stoneReward로 통합
      'tierShards': tierShardsReward,
      'powder': powderReward,
      'rerollStone': rerollReward,
      'protectionStone': protectReward,
      'cube': cubeReward,
    };
  }

  void applyOfflineRewards(Map<String, dynamic> rewards) {
    if (rewards.isEmpty) return;
    
    // 기존 보상
    gold += rewards['gold'] as int;
    gainExp(rewards['exp'] as int);
    enhancementStone += rewards['bonusStones'] as int;
    totalKills += rewards['kills'] as int;
    totalGoldEarned += rewards['gold'] as int;
    
    // [v0.0.61] 신규 제작 재료 보상
    if (rewards.containsKey('tierShards')) {
      Map<int, int> tierShardsReward = Map<int, int>.from(rewards['tierShards']);
      tierShardsReward.forEach((tier, amount) {
        tierShards[tier] = (tierShards[tier] ?? 0) + amount;
      });
    }
    
    if (rewards.containsKey('powder')) {
      powder += rewards['powder'] as int;
    }
    if (rewards.containsKey('rerollStone')) {
      rerollStone += rewards['rerollStone'] as int;
    }
    if (rewards.containsKey('protectionStone')) {
      protectionStone += rewards['protectionStone'] as int;
    }
    if (rewards.containsKey('cube')) {
      cube += rewards['cube'] as int;
    }
  }

  // --- JSON 직렬화 및 역직렬화 ---

  Map<String, dynamic> toJson() => {
    'name': name, 'level': level, 'exp': exp, 'maxExp': maxExp, 'gold': gold,
    'powder': powder, 'enhancementStone': enhancementStone, 'rerollStone': rerollStone,
    'protectionStone': protectionStone, 'cube': cube,
    'totalKills': totalKills, 'totalGoldEarned': totalGoldEarned,
    'totalItemsFound': totalItemsFound, 'totalSkillsUsed': totalSkillsUsed,
    'achievementSteps': achievementSteps,
    'enhancementSuccession': enhancementSuccession.map((k, v) => MapEntry(k.toString(), v)),
    'baseHp': baseHp, 'baseAttack': baseAttack, 'baseDefense': baseDefense,
    'inventory': inventory.map((i) => i.toJson()).toList(),
    'equipment': equipment.map((k, v) => MapEntry(k.name, v?.toJson())),
    'skills': skills.map((s) => s.toJson()).toList(),
    'pets': pets.map((p) => p.toJson()).toList(),
    'activePetId': activePet?.id,
    'encyclopediaProgress': encyclopediaProgress,
    'encyclopediaClaims': encyclopediaClaims, 
    'tierShards': tierShards.map((k, v) => MapEntry(k.toString(), v)),
    'tierCores': tierCores.map((k, v) => MapEntry(k.toString(), v)),
    'slotEnhanceLevels': slotEnhanceLevels.map((k, v) => MapEntry(k.name, v)),
  };

  factory Player.fromJson(Map<String, dynamic> json) {
    var p = Player(
      name: json['name'] ?? '전웅',
      level: json['level'] ?? 1,
      exp: json['exp'] ?? 0,
      maxExp: json['maxExp'] ?? 100,
      gold: json['gold'] ?? 1000,
      baseHp: json['baseHp'] ?? 250,
      baseAttack: json['baseAttack'] ?? 30,
      baseDefense: json['baseDefense'] ?? 0,
    );

    // --- [데이터 보정] 기초 스탯 변경 반영 ---
    // 새로운 기초 스탯(100/10/3)과 레벨업 증가량(+30/+2)을 기준으로 보정
    int lvBonusHp = (p.level - 1) * 30;
    int lvBonusAtk = (p.level - 1) * 2;
    int lvBonusDef = (p.level - 1) ~/ 2;
    
    if (p.baseHp < 100 + lvBonusHp) p.baseHp = 100 + lvBonusHp;
    if (p.baseAttack < 10 + lvBonusAtk) p.baseAttack = 10 + lvBonusAtk;
    if (p.baseDefense < 3 + lvBonusDef) p.baseDefense = 3 + lvBonusDef;

    p.powder = json['powder'] ?? 0;
    p.enhancementStone = json['enhancementStone'] ?? 0;
    p.rerollStone = json['rerollStone'] ?? 0;
    p.protectionStone = json['protectionStone'] ?? 0;
    p.cube = json['cube'] ?? 0;
    p.totalKills = json['totalKills'] ?? 0;
    p.totalGoldEarned = json['totalGoldEarned'] ?? 0;
    p.totalItemsFound = json['totalItemsFound'] ?? 0;
    p.totalSkillsUsed = json['totalSkillsUsed'] ?? 0;
    
    if (json['achievementSteps'] != null) {
      p.achievementSteps = Map<String, int>.from(json['achievementSteps']);
    }
    
    if (json['enhancementSuccession'] != null) {
      var map = Map<String, dynamic>.from(json['enhancementSuccession']);
      p.enhancementSuccession = map.map((k, v) => MapEntry(int.tryParse(k) ?? 1, v as int));
    }

    if (json['inventory'] != null) {
      p.inventory = (json['inventory'] as List).map((i) => Item.fromJson(i)).toList();
    }

    if (json['equipment'] != null) {
      var equipMap = Map<String, dynamic>.from(json['equipment']);
      equipMap.forEach((k, v) {
        if (v != null) {
          p.equipment[ItemType.values.byName(k)] = Item.fromJson(v);
        }
      });
    }

    if (json['skills'] != null) {
      var savedSkills = json['skills'] as List;
      for (var sJson in savedSkills) {
        try {
          var skill = p.skills.firstWhere((s) => s.id == sJson['id']);
          skill.updateFromJson(sJson);
        } catch (_) {}
      }
    }

    if (json['pets'] != null) {
      var savedPets = json['pets'] as List;
      var initialPool = PetData.getInitialPets();
      p.pets = [];
      for (var pJson in savedPets) {
        try {
          var pet = initialPool.firstWhere((pt) => pt.id == pJson['id']);
          pet.updateFromJson(pJson);
          p.pets.add(pet);
        } catch (_) {}
      }
    }

    if (json['activePetId'] != null) {
      try {
        p.activePet = p.pets.firstWhere((pt) => pt.id == json['activePetId']);
      } catch (_) {}
    }

    if (json['encyclopediaProgress'] != null) {
      p.encyclopediaProgress = Map<String, int>.from(json['encyclopediaProgress']);
    }
    if (json['encyclopediaClaims'] != null) {
      var map = Map<String, dynamic>.from(json['encyclopediaClaims']);
      p.encyclopediaClaims = map.map((k, v) {
        try {
          return MapEntry(k, List<int>.from(v));
        } catch (e) {
          return MapEntry(k, <int>[]);
        }
      });
    }

    if (json['tierShards'] != null) {
      var map = Map<String, dynamic>.from(json['tierShards']);
      p.tierShards = map.map((k, v) => MapEntry(int.tryParse(k) ?? 1, v as int));
    }
    if (json['tierCores'] != null) {
      var map = Map<String, dynamic>.from(json['tierCores']);
      p.tierCores = map.map((k, v) => MapEntry(int.tryParse(k) ?? 2, v as int));
    }

    if (json['slotEnhanceLevels'] != null) {
      var map = Map<String, dynamic>.from(json['slotEnhanceLevels']);
      map.forEach((k, v) {
        try {
          p.slotEnhanceLevels[ItemType.values.byName(k)] = v as int;
        } catch (_) {}
      });
    }

    return p;
  }
}
