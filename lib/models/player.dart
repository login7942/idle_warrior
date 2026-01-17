import 'dart:math';
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
  double baseAttackSpeed = 2.0; 
  double baseCritChance = 5.0; 
  double baseCritDamage = 150.0; // 기본 치명타 피해 150%
  double baseHpRegen = 1.0;    
  double baseGoldBonus = 100.0;
  double baseDropBonus = 100.0;
  double baseOffEfficiency = 0.3;
  double baseCdr = 0.0; // 기본 쿨타임 감소 0%

  // 스킬 목록 (사용자 요청 기반 재구성)
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
  final int maxInventory = 100;
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
    this.gold = 1000, // 초기 골드 약간 지급
    this.baseHp = 100,
    this.baseAttack = 10,
    this.baseDefense = 5,
  }) {
    // 초기 스킬 미오픈 (레벨 5부터 오픈)
  }

  int get combatPower {
    return (attack * 2) + (defense * 1.5).toInt() + (maxHp ~/ 10);
  }

  // 패시브 스킬 보너스 합산용 헬퍼
  double _getSkillValue(String id) {
    try {
      return skills.firstWhere((s) => s.id == id).currentValue;
    } catch (_) {
      return 0.0;
    }
  }

  int get maxHp {
    double bonus = 1.0 + (petHpBonus / 100); // 펫 보유 효과 반영
    int flat = 0;
    equipment.values.forEach((item) {
      if (item == null) return;
      int itemMainStat = item.effectiveMainStat;
      if (item.type == ItemType.armor) flat += itemMainStat;
      for (var opt in item.subOptions) {
        if (opt.name == '생명력') {
          if (opt.isPercentage) bonus += opt.value / 100;
          else flat += opt.value.toInt();
        }
      }
    });
    return (baseHp * bonus).toInt() + flat;
  }

  int get attack {
    double bonus = 1.0 + (petAtkBonus / 100); // 펫 보유 효과 반영
    int flat = _getSkillValue('pas_1').toInt(); // 패시브 공격력
    
    // 펫 동행 효과: 최종 데미지 증폭 (용의 분노 등)
    double finalMultiplier = 1.0 + (getPetCompanionValue('용의 분노') / 100);
    
    equipment.values.forEach((item) {
      if (item == null) return;
      int itemMainStat = item.effectiveMainStat;
      if (item.type == ItemType.weapon) flat += itemMainStat;
      for (var opt in item.subOptions) {
        if (opt.name == '공격력') {
          if (opt.isPercentage) bonus += opt.value / 100;
          else flat += opt.value.toInt();
        }
      }
    });
    
    int total = (baseAttack * bonus).toInt() + flat;
    return (total * finalMultiplier).toInt();
  }

  int get defense {
    double bonus = 1.0 + (_getSkillValue('pas_2') / 100); // 철벽 (DEF %)
    int flat = 0;
    equipment.values.forEach((item) {
      if (item == null) return;
      int itemMainStat = item.effectiveMainStat;
      if (item.type == ItemType.helmet || item.type == ItemType.boots) flat += itemMainStat;
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
    double total = baseAttackSpeed + (_getSkillValue('pas_1') / 100); 
    total += getPetCompanionValue('가속 점프') / 100; // 펫 토끼 동행 효과
    equipment.values.forEach((item) {
      if (item == null) return;
      for (var opt in item.subOptions) {
        if (opt.name == '공격 속도') total += opt.value / 100;
      }
    });
    return total;
  }

  double get critChance {
    double total = baseCritChance + getPetCompanionValue('예리한 통찰'); // 펫 올빼미 동행 효과
    equipment.values.forEach((item) {
      if (item == null) return;
      for (var opt in item.subOptions) {
        if (opt.name == '치명타 확률') total += opt.value;
      }
    });
    return total;
  }

  double get critDamage {
    double total = baseCritDamage + _getSkillValue('pas_4'); // 약점 노출 (CritDamage)
    equipment.values.forEach((item) {
      if (item == null) return;
      for (var opt in item.subOptions) {
        if (opt.name == '치명타 피해') total += opt.value;
      }
    });
    return total;
  }

  double get hpRegen {
    double total = baseHpRegen;
    equipment.values.forEach((item) {
      if (item == null) return;
      for (var opt in item.subOptions) {
        if (opt.name == 'HP 재생') total += opt.value;
      }
    });
    return total;
  }

  double get goldBonus {
    double total = baseGoldBonus + _getSkillValue('pas_3') + petGoldBonus; // 펫 보유 효과 반영
    equipment.values.forEach((item) {
      if (item == null) return;
      for (var opt in item.subOptions) {
        if (opt.name == '골드 획득') total += opt.value;
      }
    });
    return total;
  }

  double get expBonus {
    double bonus = 1.0 + (_getSkillValue('pas_4') / 100);
    equipment.values.forEach((item) {
      if (item == null) return;
      for (var opt in item.subOptions) {
        if (opt.name == '경험치 획득') bonus += opt.value / 100;
      }
    });
    return bonus;
  }

  double get dropBonus {
    double total = baseDropBonus + _getSkillValue('pas_3'); // 탐욕의 시선 (Item)
    equipment.values.forEach((item) {
      if (item == null) return;
      for (var opt in item.subOptions) {
        if (opt.name == '아이템 드롭') total += opt.value;
      }
    });
    return total;
  }

  double get offEfficiency => baseOffEfficiency;

  double get cdr => baseCdr + _getSkillValue('pas_6'); // 신속 (CDR)
  double get lifesteal => _getSkillValue('pas_5'); // 흡혈의 손길

  // 인벤토리 관리
  bool addItem(Item item) {
    if (inventory.length >= maxInventory) return false;
    inventory.add(item);
    return true;
  }

  void equipItem(Item item) {
    Item? current = equipment[item.type];
    if (current != null) {
      inventory.add(current);
    }
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
      levelUp(); // 레벨업 시 스탯 증가 호출
      maxExp = (maxExp * 1.15).toInt(); // 1.2 -> 1.15 (15% 복리 증가)
    }
  }

  // 업적 보상 수령 로직
  String? checkAchievement(String id, int currentProgress, int target, int reward) {
    int currentStep = achievementSteps[id] ?? 0;
    if (currentProgress >= target) {
      achievementSteps[id] = currentStep + 1;
      // 보상 지급 (예: 다이아몬드 대신 모든 자원을 골고루 지급하거나 특정 자원 지급)
      // 여기서는 예시로 강화석을 지급하도록 설정 (Achievement 모델에 따라 가변 가능)
      enhancementStone += reward; 
      return '업적 달성! [$id ${currentStep + 1}단계] 보상: 강화석 $reward개';
    }
    return null;
  }

  // 오프라인 보상 계산 (최대 24시간)
  Map<String, dynamic> calculateOfflineRewards(DateTime lastTime, double goldMin, double expMin, double killsMin) {
    int minutes = DateTime.now().difference(lastTime).inMinutes;
    if (minutes > 1440) minutes = 1440; // 최대 24시간 제한
    if (minutes < 1) return {};

    double efficiency = baseOffEfficiency; // 기본 30%
    
    int totalGold = (minutes * goldMin * efficiency).toInt();
    int totalExp = (minutes * expMin * efficiency).toInt();
    int totalKills = (minutes * killsMin * efficiency).toInt();
    
    // 보너스 아이템 (강화석) - 킬당 5% 확률로 1개
    int bonusStones = 0;
    for (int i = 0; i < totalKills; i++) {
      if (Random().nextDouble() < 0.05) bonusStones++;
    }

    return {
      'minutes': minutes,
      'gold': totalGold,
      'exp': totalExp,
      'kills': totalKills,
      'bonusStones': bonusStones,
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
  void levelUp() {
    // DOC_GAME_DESIGN.md 3.3 기준
    // 공격력(ATK): +2
    // 체력(HP): +30
    // 방어력(DEF): +0.5
    baseHp += 30;
    baseAttack += 2;
    // baseDefense는 int이므로 2레벨마다 1씩 증가하도록 처리하거나 double로 관리 필요
    // 여기서는 간단하게 level이 짝수일 때 1씩 증가시키는 방식으로 0.5 구현
    if (level % 2 == 0) {
      baseDefense += 1;
    }
  }
}
