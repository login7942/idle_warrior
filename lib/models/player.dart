import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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

  // 기본 전투 스탯
  int baseHp;
  int baseAttack;
  int baseDefense;
  double baseAttackSpeed = 1.0; 
  double baseCritChance = 5.0; 
  double baseCritDamage = 150.0; // 기본 치명타 피해 150%
  double baseHpRegen = 1.0;    
  double baseGoldBonus = 100.0;
  double baseDropBonus = 100.0;
  double baseOffEfficiency = 0.3;
  double baseCdr = 0.0; // 기본 쿨타임 감소 0%

  // 스킬 목록
  List<Skill> skills = [
    Skill(id: 'act_1', name: '바람 베기', description: '초반 주력기 (3연타 공격)', type: SkillType.active, iconEmoji: '🌪️', unlockLevel: 5, unlockCost: 5000, baseUpgradeCost: 1000, costMultiplier: 1.5, baseValue: 300, valuePerLevel: 30, baseCooldown: 6),
    Skill(id: 'pas_1', name: '광폭화', description: '공격 속도가 영구적으로 증가합니다.', type: SkillType.passive, iconEmoji: '🔥', unlockLevel: 10, unlockCost: 15000, baseUpgradeCost: 3000, costMultiplier: 1.8, baseValue: 5, valuePerLevel: 2, baseCooldown: 0),
    Skill(id: 'act_2', name: '강격', description: '강력한 한방 데미지를 입힙니다.', type: SkillType.active, iconEmoji: '🔨', unlockLevel: 15, unlockCost: 40000, baseUpgradeCost: 8000, costMultiplier: 2.1, baseValue: 800, valuePerLevel: 100, baseCooldown: 12),
    Skill(id: 'pas_2', name: '철벽', description: '방어력이 % 비율로 증가합니다.', type: SkillType.passive, iconEmoji: '🛡️', unlockLevel: 20, unlockCost: 100000, baseUpgradeCost: 20000, costMultiplier: 2.3, baseValue: 10, valuePerLevel: 3, baseCooldown: 0),
    Skill(id: 'act_3', name: '얼음 화살', description: '고위력 공격 및 적을 빙결시킵니다.', type: SkillType.active, iconEmoji: '❄️', unlockLevel: 30, unlockCost: 250000, baseUpgradeCost: 50000, costMultiplier: 2.5, baseValue: 1500, valuePerLevel: 200, baseCooldown: 15),
    Skill(id: 'pas_3', name: '탐욕의 시선', description: '골드 및 아이템 획득량이 증가합니다.', type: SkillType.passive, iconEmoji: '👁️', unlockLevel: 45, unlockCost: 600000, baseUpgradeCost: 120000, costMultiplier: 2.8, baseValue: 10, valuePerLevel: 5, baseCooldown: 0),
    Skill(id: 'act_4', name: '화염구', description: '강력한 마법형 광역 데미지.', type: SkillType.active, iconEmoji: '☄️', unlockLevel: 60, unlockCost: 1500000, baseUpgradeCost: 300000, costMultiplier: 3.0, baseValue: 3000, valuePerLevel: 500, baseCooldown: 20),
    Skill(id: 'pas_4', name: '약점 노출', description: '치명타 피해량이 대폭 증가합니다.', type: SkillType.passive, iconEmoji: '🎯', unlockLevel: 80, unlockCost: 4000000, baseUpgradeCost: 800000, costMultiplier: 3.2, baseValue: 50, valuePerLevel: 20, baseCooldown: 0),
    Skill(id: 'act_5', name: '메테오', description: '최종 결전기 (초고화력 폭격)', type: SkillType.active, iconEmoji: '🌠', unlockLevel: 120, unlockCost: 10000000, baseUpgradeCost: 2000000, costMultiplier: 3.4, baseValue: 10000, valuePerLevel: 2000, baseCooldown: 60),
    Skill(id: 'pas_5', name: '흡혈의 손길', description: '데미지 비례 체력을 흡수합니다.', type: SkillType.passive, iconEmoji: '🦇', unlockLevel: 160, unlockCost: 30000000, baseUpgradeCost: 5000000, costMultiplier: 3.5, baseValue: 1, valuePerLevel: 0.5, baseCooldown: 0),
    Skill(id: 'pas_6', name: '신속', description: '모든 스킬의 재사용 대기시간이 감소합니다.', type: SkillType.passive, iconEmoji: '⚡', unlockLevel: 200, unlockCost: 100000000, baseUpgradeCost: 20000000, costMultiplier: 3.5, baseValue: 5, valuePerLevel: 2, baseCooldown: 0),
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
    this.gold = 1000,
    this.baseHp = 250,
    this.baseAttack = 30,
    this.baseDefense = 0,
  });

  int get combatPower {
    return (attack * 2) + (defense * 1.5).toInt() + (maxHp ~/ 10);
  }

  double _getSkillValue(String id) {
    try {
      final skill = skills.firstWhere((s) => s.id == id);
      return skill.isUnlocked ? skill.currentValue : 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  int get maxHp {
    double petBonus = 1.0 + (petHpBonus / 100);
    int flat = 0;

    equipment.values.forEach((item) {
      if (item == null) return;
      
      // 장비 주 능력치가 체력인 경우 (강화 영향 받음)
      if (item.mainStatName == '체력') {
        flat += item.effectiveMainStat;
      }

      // 부가 옵션에 체력이 있는 경우 (강화 영향 안 받음)
      for (var opt in item.subOptions) {
        if (opt.name == '체력') {
          flat += opt.value.toInt();
        }
      }
    });

    return (baseHp * petBonus).toInt() + flat;
  }

  int get attack {
    double petBonus = 1.0 + (petAtkBonus / 100);
    int flat = _getSkillValue('pas_1').toInt(); // 패시브 스킬 보너스
    double activePetMultiplier = 1.0 + (getPetCompanionValue('용의 분노') / 100);
    
    equipment.values.forEach((item) {
      if (item == null) return;

      // 장비 주 능력치가 공격력인 경우 (강화 영향 받음)
      if (item.mainStatName == '공격력') {
        flat += item.effectiveMainStat;
      }

      // 부가 옵션에 공격력이 있는 경우 (강화 영향 안 받음)
      for (var opt in item.subOptions) {
        if (opt.name == '공격력') {
          flat += opt.value.toInt();
        }
      }
    });

    int totalAtk = (baseAttack * petBonus).toInt() + flat;
    return (totalAtk * activePetMultiplier).toInt();
  }

  int get defense {
    double bonus = 1.0 + (_getSkillValue('pas_2') / 100);
    int flat = 0;
    equipment.values.forEach((item) {
      if (item == null) return;
      int itemMainStat = item.effectiveMainStat;
      if (item.mainStatName == '방어력') flat += itemMainStat; // 현재 방어력이 주 능력치인 1티어 장비는 없으나 확장성 유지
      for (var opt in item.subOptions) {
        if (opt.name == '방어력') {
          if (opt.isPercentage) bonus += opt.value / 100;
          else flat += opt.value.toInt();
        }
      }
    });
    return (baseDefense * bonus).toInt() + flat;
  }

  double get attackSpeed {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '공격 속도') itemBonus += opt.value;
      }
    });
    double total = baseAttackSpeed + (_getSkillValue('pas_1') / 100) + (getPetCompanionValue('가속 점프') / 100) + itemBonus;
    return total.clamp(0.1, 10.0); // 최대 공격 속도를 10.0으로 캡 적용
  }

  double get critChance {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '치명타 확률') itemBonus += opt.value;
      }
    });
    return baseCritChance + getPetCompanionValue('예리한 통찰') + itemBonus;
  }

  double get critDamage {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '치명타 피해') itemBonus += opt.value;
      }
    });
    return baseCritDamage + _getSkillValue('pas_4') + itemBonus;
  }

  double get hpRegen {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == 'HP 재생') itemBonus += opt.value;
      }
    });
    return baseHpRegen + itemBonus;
  }

  double get goldBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '골드 획득') itemBonusPerc += opt.value;
      }
    });
    return goldBonusBase + _getSkillValue('pas_3') + petGoldBonus + itemBonusPerc;
  }

  double get goldBonusBase => baseGoldBonus;

  double get expBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '경험치 획득') itemBonusPerc += opt.value;
      }
    });
    return 100.0 + (_getSkillValue('pas_4') / 100) + itemBonusPerc; // 기본 100% 기준
  }

  double get dropBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.name == '아이템 드롭') itemBonusPerc += opt.value;
      }
    });
    return baseDropBonus + _getSkillValue('pas_3') + itemBonusPerc;
  }
  double get offEfficiency => baseOffEfficiency;
  double get cdr => baseCdr + _getSkillValue('pas_6');
  double get lifesteal => _getSkillValue('pas_5');

  bool addItem(Item item) {
    if (inventory.length >= maxInventory) return false;
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
      maxExp = (maxExp * 1.15).toInt();
    }
  }

  void levelUp() {
    baseHp += 30;
    baseAttack += 2;
    if (level % 2 == 0) baseDefense += 1;
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
    if (minutes > 1440) minutes = 1440;
    if (minutes < 1) return {};
    double efficiency = baseOffEfficiency; 
    int totalGold = (minutes * goldMin * efficiency).toInt();
    int totalExp = (minutes * expMin * efficiency).toInt();
    int totalKills = (minutes * killsMin * efficiency).toInt();
    int bonusStones = 0;
    for (int i = 0; i < totalKills; i++) {
      if (Random().nextDouble() < 0.05) bonusStones++;
    }
    return {
      'minutes': minutes, 'gold': totalGold, 'exp': totalExp,
      'kills': totalKills, 'bonusStones': bonusStones,
    };
  }

  void applyOfflineRewards(Map<String, dynamic> rewards) {
    if (rewards.isEmpty) return;
    gold += rewards['gold'] as int;
    gainExp(rewards['exp'] as int);
    enhancementStone += rewards['bonusStones'] as int;
    totalKills += rewards['kills'] as int;
    totalGoldEarned += rewards['gold'] as int;
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

    // --- [데이터 보정] 기존 플레이어 기초 스탯 상향 반영 ---
    // 기존 1레벨 기초(100/10)보다 낮은 경우 새로운 기초(250/30)로 보정
    int lvBonusHp = (p.level - 1) * 30;
    int lvBonusAtk = (p.level - 1) * 2;
    if (p.baseHp < 250 + lvBonusHp) p.baseHp = 250 + lvBonusHp;
    if (p.baseAttack < 30 + lvBonusAtk) p.baseAttack = 30 + lvBonusAtk;

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
      p.enhancementSuccession = map.map((k, v) => MapEntry(int.parse(k), v as int));
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

    return p;
  }
}
