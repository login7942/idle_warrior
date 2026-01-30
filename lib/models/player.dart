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
  int enhancementStone = 0; // 강화석
  int rerollStone = 0;      // 재설정
  int protectionStone = 0;   // 보호
  int abyssalPowder = 0;    // 🆕 심연의 가루 (통합 재료)
  int cube = 0;             // 잠재력 큐브
  int soulStone = 0;        // 영혼석
  int goldDungeonTicket = 0;  // 🎫 황금의 방 입장권
  int trialDungeonTicket = 0; // 🎫 시련의 방 입장권


  // 누적 통계 (업적용)
  int totalKills = 0;
  int totalGoldEarned = 0;
  int totalItemsFound = 0;
  int totalSkillsUsed = 0;
  int totalEnhanceAttempts = 0; // 🆕 장비 강화 총 시도 횟수
  Map<String, int> achievementSteps = {}; // 각 업적별 현재 단계
  
  // 강화 계승 시스템: 티어별 저장된 강화 레벨 (70% 계승용)
  Map<int, int> enhancementSuccession = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}; 

  // 통합 파편 (Disassembly Shards): 장비 분해 및 사냥 시 획득
  int shards = 0;

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
  
  // [v0.3.5] 슬롯 강화 3.0 전용 데이터: 실패 횟수(천장용) 및 연속 성공 횟수(스트릭용)
  Map<ItemType, int> slotEnhanceFailCounts = {
    ItemType.weapon: 0,
    ItemType.helmet: 0,
    ItemType.armor: 0,
    ItemType.boots: 0,
    ItemType.ring: 0,
    ItemType.necklace: 0,
  };
  Map<ItemType, int> slotEnhanceStreakCounts = {
    ItemType.weapon: 0,
    ItemType.helmet: 0,
    ItemType.armor: 0,
    ItemType.boots: 0,
    ItemType.ring: 0,
    ItemType.necklace: 0,
  };

  // 🆕 [v0.5.40] 티어별 자동 제작 설정 (T2 ~ T6)
  Map<int, bool> autoCraftTiers = {2: false, 3: false, 4: false, 5: false, 6: false};

  // [v0.4.8] 기능 해금 알림 여부 (50, 300, 1000)
  List<int> notifiedMilestones = [];

  // 🆕 [v0.5.26] 승급 시스템 (Promotion Level 0~10)
  int promotionLevel = 0;
  
  // 🆕 [v0.8.14] 최고 도달 스테이지 (골드 가속 보너스용)
  int maxStageReached = 0;

  // 🆕 [v0.5.58] 길잡이 퀘스트 시스템
  int currentQuestIndex = 0;
  bool isQuestRewardClaimable = false;

  // 🆕 [v0.6.2] 펫 탐사 파견 시스템
  // ZoneId (name) -> List of 3 Pet IDs (nullable)
  Map<String, List<String?>> zoneExpeditions = {};
  // ZoneId (name) -> ISO-8601 Last Claimed Timestamp
  Map<String, String> zoneLastClaimedAt = {};
  
  // 🆕 [v0.7.0] 제작 숙련도 시스템
  int craftingMasteryLevel = 1;
  int craftingMasteryExp = 0;


  // 🆕 [v0.7.0] 세트 효과용 기간제 버프
  DateTime? desertBuffEndTime;

  // [v2.0] 신규 기간제 버프 종료 시각들
  DateTime? killAtkBuffEndTime;
  DateTime? killDefBuffEndTime;
  DateTime? zoneAtkBuffEndTime;
  DateTime? zoneDefBuffEndTime;

  
  // 숙련도 경험치 테이블 (레벨당 필요한 경험치 증가)
  int get craftingMasteryNextExp => craftingMasteryLevel * craftingMasteryLevel * 50;

  // 🆕 [v0.7.0] 세트 효과 계산
  Map<String, int> get activeSetCounts {
    Map<String, int> counts = {};
    equipment.values.forEach((item) {
      if (item != null && item.setId != null) {
        counts[item.setId!] = (counts[item.setId!] ?? 0) + 1;
      }
    });
    return counts;
  }

  // 특정 세트 효과 활성화 여부 체크
  bool isSetEffectActive(String setId, int reqCount) {
    return (activeSetCounts[setId] ?? 0) >= reqCount;
  }

  // 🆕 [v0.7.0] 세트 효과 배율 계산
  double get setFinalDamageMult {
    double mult = 1.0;
    // 드래곤 슬레이어 (T5) 4세트: 최종 피해량 증폭 +50%
    if (isSetEffectActive('dragon', 4)) mult += 0.5;
    return mult;
  }

  double get setSkillDamageMult {
    double mult = 1.0;
    // 차원 여행자 (T4) 2세트: 스킬 데미지 +25%
    if (isSetEffectActive('dimension', 2)) mult += 0.25;
    return mult;
  }






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

  // 🆕 [v0.3.6] 장착 슬롯 평균 강화 수치 (적정 사냥터 보너스 판정용)
  double get averageSlotEnhanceLevel {
    if (slotEnhanceLevels.isEmpty) return 0.0;
    int total = slotEnhanceLevels.values.fold(0, (sum, lv) => sum + lv);
    return total / 6.0;
  }

  // 🆕 [v0.3.8] 최고 슬롯 강화 수치
  int get maxSlotEnhanceLevel {
    if (slotEnhanceLevels.isEmpty) return 0;
    return slotEnhanceLevels.values.fold(0, (maxIv, lv) => lv > maxIv ? lv : maxIv);
  }

  // 🆕 [v0.5.57] 승급 정보 헬퍼 (조건 완화 적용)
  static const List<Map<String, dynamic>> promotionSteps = [
    {'lv': 0, 'req': 0, 'name': '수련생', 'bonus': '보너스 없음'},
    {'lv': 1, 'req': 300, 'name': '모험가', 'bonus': '골드 획득량 +5%'},
    {'lv': 2, 'req': 600, 'name': '신출내기', 'bonus': '경험치 획득량 +5%'},
    {'lv': 3, 'req': 1200, 'name': '용병', 'bonus': '공격 속도 +10%'},
    {'lv': 4, 'req': 2400, 'name': '정예 기사', 'bonus': '콤보 1,2타 피해 +10%'},
    {'lv': 5, 'req': 3600, 'name': '기사단장', 'bonus': '콤보 3타 피해 +10%'},
    {'lv': 6, 'req': 4800, 'name': '영웅', 'bonus': '콤보 최종타 피해 +10%'},
    {'lv': 7, 'req': 6000, 'name': '전설', 'bonus': '크리티컬 데미지 +15%'},
    {'lv': 8, 'req': 7800, 'name': '신화', 'bonus': '최종 피해량 +10%'},
    {'lv': 9, 'req': 10200, 'name': '초월자', 'bonus': '스킬 재사용 대기시간 -10%'},
    {'lv': 10, 'req': 13200, 'name': '무한의 경지', 'bonus': '모든 능력치 +10%'},
  ];

  String get promotionName => promotionLevel < promotionSteps.length 
      ? promotionSteps[promotionLevel]['name'] 
      : '초월';

  int get nextPromotionReq => (promotionLevel + 1 < promotionSteps.length)
      ? promotionSteps[promotionLevel + 1]['req']
      : 99999;

  // 🆕 [v0.3.9] 장착 슬롯 강화 레벨 총합 (티어 해금의 새로운 기준)
  int get totalSlotEnhanceLevel {
    if (slotEnhanceLevels.isEmpty) return 0;
    return slotEnhanceLevels.values.fold(0, (sum, lv) => sum + lv);
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
  // 🆕 [v0.8.14] 성장형 방치 효율: 레벨에 따라 0.5 ~ 0.8까지 상승
  double get baseOffEfficiency {
    double eff = 0.5 + (level / 1000) * 0.3;
    return eff.clamp(0.5, 0.8);
  }
  double baseCdr = 0.0; // 기본 쿨타임 감소 0%

  // 스킬 목록 (v0.0.62 밸런스 개편)
  List<Skill> skills = [
    Skill(id: 'act_1', name: '바람 베기', description: '초반 주력기 (3연타 공격)', type: SkillType.active, iconEmoji: '🌪️', unlockLevel: 5, unlockCost: 1000, baseUpgradeCost: 1000, costMultiplier: 1.5, baseValue: 70, valuePerLevel: 7, baseCooldown: 6), // 밸런스: 80→70
    Skill(id: 'act_2', name: '강격', description: '강력한 한방 데미지를 입힙니다.', type: SkillType.active, iconEmoji: '🔨', unlockLevel: 15, unlockCost: 2000, baseUpgradeCost: 2000, costMultiplier: 1.6, baseValue: 250, valuePerLevel: 25, baseCooldown: 12), // 밸런스: 200→250
    Skill(id: 'act_1_5', name: '쌍룡참', description: '매우 빠른 속도로 대상을 두 번 벱니다.', type: SkillType.active, iconEmoji: '⚔️', unlockLevel: 25, unlockCost: 4000, baseUpgradeCost: 4000, costMultiplier: 1.7, baseValue: 150, valuePerLevel: 15, baseCooldown: 10), // 🆕 신규 스킬
    Skill(id: 'pas_1', name: '광폭화', description: '공격 속도가 영구적으로 증가합니다.', type: SkillType.passive, iconEmoji: '🔥', unlockLevel: 10, unlockCost: 5000, baseUpgradeCost: 5000, costMultiplier: 2.0, baseValue: 30, valuePerLevel: 2.0, baseCooldown: 0), 
    Skill(id: 'pas_2', name: '철벽', description: '방어력이 일정 비율로 증가합니다.', type: SkillType.passive, iconEmoji: '🛡️', unlockLevel: 20, unlockCost: 5000, baseUpgradeCost: 5000, costMultiplier: 2.0, baseValue: 10, valuePerLevel: 2, baseCooldown: 0),
    Skill(id: 'act_3', name: '얼음 화살', description: '고위력 공격 및 적을 빙결시킵니다.', type: SkillType.active, iconEmoji: '❄️', unlockLevel: 30, unlockCost: 5000, baseUpgradeCost: 5000, costMultiplier: 1.8, baseValue: 300, valuePerLevel: 40, baseCooldown: 15),
    Skill(id: 'pas_atk', name: '근력 강화', description: '기본 공격력이 일정 비율로 증가합니다.', type: SkillType.passive, iconEmoji: '💪', unlockLevel: 35, unlockCost: 6000, baseUpgradeCost: 6000, costMultiplier: 2.1, baseValue: 10, valuePerLevel: 1.5, baseCooldown: 0), // 🆕 신규 패시브
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
      if (item!.potential?.effect == OptionEffect.addSkillLevel) bonus += item.potential!.value.toInt();
    });
    return bonus;
  }

  double get potentialFinalDamageMult {
    double mult = 1.0;
    equipment.values.where((i) => i != null).forEach((item) {
      if (item!.potential?.effect == OptionEffect.addFinalDamagePerc) mult += item.potential!.value / 100;
    });
    return mult;
  }

  double get potentialCdr {
    double cdr = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      if (item!.potential?.effect == OptionEffect.addCdr) cdr += item.potential!.value;
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
  // 기본: 레벨당 2%씩 주 능력치 증폭
  // 마일스톤 보너스: 1000 도달 시 강화 효과 +20%, 1500 도달 시 모든 슬롯 강화 효율 +15%
  double _getSlotMultiplier(ItemType type) {
    int level = slotEnhanceLevels[type] ?? 0;
    double efficiency = 0.02;

    // [마일스톤] 1500 도달 시 모든 슬롯 강화 효율 +15%
    bool globalBonus = slotEnhanceLevels.values.any((v) => v >= 1500);
    if (globalBonus) efficiency *= 1.15;

    double baseMulti = 1.0 + (level * efficiency);

    // [마일스톤] 1000 도달 시 해당 슬롯 강화 효과 +0.2 (20%) 추가
    if (level >= 1000) baseMulti += 0.2;

    return baseMulti;
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
        if (opt.effect == OptionEffect.addHp) {
          // [수정] 장신구(반지/목걸이)의 고정 체력 보너스는 강화 계수를 적용 (0번 인덱스 가정)
          if ((item.type == ItemType.ring || item.type == ItemType.necklace) && item.subOptions.indexOf(opt) == 0) {
            flat += (opt.value * item.getEnhanceFactor()).toInt();
          } else {
            flat += opt.value.toInt();
          }
        } else if (opt.effect == OptionEffect.addHpPerc) {
          // TODO: 체력 % 옵션 구현 시 여기에 추가
        }
      }

      // 잠재능력 체력 반영
      if (item.potential?.effect == OptionEffect.addHp) {
        flat += item.potential!.value.toInt();
      } else if (item.potential?.effect == OptionEffect.addHpPerc) {
        // TODO
      }
    }

    double finalMult = 1.0;
    if (promotionLevel >= 10) finalMult += 0.1; // 10단계 보너스: 모든능력치 +10%
    
    // [세트 효과] 태고의 신 (T6) 2세트: 모든 능력치 +20%
    if (isSetEffectActive('ancient', 2)) finalMult += 0.2;

    return (((baseHp * petBonus * (1.0 + encyclopediaHpMultiplier)).toInt() + flat + encyclopediaHpBonus.toInt()) * finalMult).toInt();

  }

  int get attack {
    double petBonus = 1.0 + (petAtkBonus / 100);
    int flat = 0; // [v0.4.0] 수식 오류 수정: pas_1(광폭화)은 공속 스킬이므로 제거
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
        if (opt.effect == OptionEffect.addAtk) {
          flat += opt.value.toInt();
        }
      }

      // 잠재능력 공격력 반영
      if (item.potential?.effect == OptionEffect.addAtk) {
        flat += item.potential!.value.toInt();
      }
    }

    int totalAtk = (baseAttack * petBonus * (1.0 + encyclopediaAtkMultiplier)).toInt() + flat + encyclopediaAtkBonus.toInt();
    
    double finalMult = activePetMultiplier + (getSkillValue('pas_atk') / 100);
    if (promotionLevel >= 10) finalMult += 0.1; // 10단계 보너스: 모든능력치 +10%
    if (promotionLevel >= 8) finalMult += 0.1;  // 8단계 보너스: 최종 피해량 +10%
    
    // [세트 효과] 드래곤 슬레이어 (T5) 2세트: 공격력 +30%
    if (isSetEffectActive('dragon', 2)) finalMult += 0.3;
    // [세트 효과] 태고의 신 (T6) 2세트: 모든 능력치 +20%
    if (isSetEffectActive('ancient', 2)) finalMult += 0.2;
    
    // [숙련도 보너스] 레벨당 공격력 +0.5%
    finalMult += (craftingMasteryLevel * 0.005);
    
    // [세트 효과] 사막의 약탈자 (T2) 4세트: 사냥터 이동 시 30초간 ATK +30%
    if (desertBuffEndTime != null && DateTime.now().isBefore(desertBuffEndTime!)) {
      finalMult += 0.3;
    }

    // [v2.0] 처치 시 공격력 버프 반영
    if (killAtkBuffEndTime != null && DateTime.now().isBefore(killAtkBuffEndTime!)) {
      finalMult += (killAtkBonus / 100);
    }
    // [v2.0] 지역 이동 시 공격력 버프 반영
    if (zoneAtkBuffEndTime != null && DateTime.now().isBefore(zoneAtkBuffEndTime!)) {
      finalMult += (zoneAtkBonus / 100);
    }


    return (totalAtk * finalMult).toInt();

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
        if (opt.effect == OptionEffect.addDef) {
          flat += opt.value.toInt();
        } else if (opt.effect == OptionEffect.addDefPerc) {
          bonus += opt.value / 100;
        }
      }
      // 잠재능력 방어력 반영
      if (item.potential?.effect == OptionEffect.addDef) {
        flat += item.potential!.value.toInt();
      } else if (item.potential?.effect == OptionEffect.addDefPerc) {
        bonus += item.potential!.value / 100;
      }
    }
    double finalMult = 1.0;
    if (promotionLevel >= 10) finalMult += 0.1; // 10단계 보너스: 모든능력치 +10%
    
    // [세트 효과] 광산의 수호자 (T3) 2세트: 방어력 +20%
    if (isSetEffectActive('mine', 2)) finalMult += 0.2;
    // [세트 효과] 태고의 신 (T6) 2세트: 모든 능력치 +20%
    if (isSetEffectActive('ancient', 2)) finalMult += 0.2;

    // [v2.0] 처치 시 방어력 버프 반영
    if (killDefBuffEndTime != null && DateTime.now().isBefore(killDefBuffEndTime!)) {
      finalMult += (killDefBonus / 100);
    }
    // [v2.0] 지역 이동 시 방어력 버프 반영
    if (zoneDefBuffEndTime != null && DateTime.now().isBefore(zoneDefBuffEndTime!)) {
      finalMult += (zoneDefBonus / 100);
    }

    return (((baseDefense * bonus).toInt() + flat) * finalMult).toInt();

  }

  double get attackSpeed {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addAspd) itemBonus += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addAspd) itemBonus += item.potential!.value;
    });
    double promotionBonus = (promotionLevel >= 3) ? 0.1 : 0.0; // 3단계 보너스: 공속 +10%
    double total = baseAttackSpeed + (getSkillValue('pas_1') / 100) + (getPetCompanionValue('가속 점프') / 100) + (getPetCompanionValue('급강하 공격') / 100) + (getPetCompanionValue('화염 폭풍') / 100) + itemBonus + promotionBonus;
    return total.clamp(0.1, 6.0); // 최대 공격 속도 6.0 (하드캡 상향: 4.0 → 6.0)
  }

  double get critChance {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addCritChance) itemBonus += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addCritChance) itemBonus += item.potential!.value;
    });
    return baseCritChance + getPetCompanionValue('예리한 통찰') + itemBonus;
  }

  double get critDamage {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addCritDamage) itemBonus += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addCritDamage) itemBonus += item.potential!.value;
    });
    double promotionBonus = (promotionLevel >= 7) ? 15.0 : 0.0; // 7단계 보너스: 크리티컬 데미지 +15%
    return baseCritDamage + getSkillValue('pas_4') + itemBonus + promotionBonus;
  }

  double get hpRegen {
    double itemBonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addRegen) itemBonus += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addRegen) itemBonus += item.potential!.value;
    });
    return baseHpRegen + itemBonus;
  }

  /// 틱당 최대 회복 상한선 (%)
  double get hpRegenCap {
    double bonus = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addRegenCap) bonus += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addRegenCap) bonus += item.potential!.value;
    });
    return 5.0 + bonus; // 기본 5% + 보너스
  }

  double get goldBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addGoldGain) itemBonusPerc += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addGoldGain) itemBonusPerc += item.potential!.value;
    });
    double promotionBonus = (promotionLevel >= 1) ? 5.0 : 0.0; // 1단계 보너스: 골드 +5%
    
    // [세트 효과] 사막의 개척자 (T2) 2세트: 골드 +20%
    double setBonus = isSetEffectActive('desert', 2) ? 20.0 : 0.0;

    // [v0.8.14] 스테이지 마일스톤 가속 보너스
    double stageMilestoneBonus = 0.0;
    if (maxStageReached >= 1000) {
      stageMilestoneBonus = 100.0; // 누적 +100%
    } else if (maxStageReached >= 500) {
      stageMilestoneBonus = 50.0;  // 누적 +50%
    } else if (maxStageReached >= 300) {
      stageMilestoneBonus = 20.0;  // +20%
    }

    return goldBonusBase + getSkillValue('pas_3') + petGoldBonus + itemBonusPerc + promotionBonus + setBonus + stageMilestoneBonus;
  }

  /// 피격 시 데미지의 % 만큼 즉시 회복하는 비율
  double get recoverOnDamagedPerc {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.recoverOnDamagedPerc) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.recoverOnDamagedPerc) total += item.potential!.value;
    });
    return total;
  }

  /// 스킬 사용 시 발동되는 피해 감소 수치 (%)
  double get dmgReductionOnSkill {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.dmgReductionOnSkill) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.dmgReductionOnSkill) total += item.potential!.value;
    });
    return total;
  }

  double get goldBonusBase => baseGoldBonus;

  double get expBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addExpGain) itemBonusPerc += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addExpGain) itemBonusPerc += item.potential!.value;
    });
    double promotionBonus = (promotionLevel >= 2) ? 5.0 : 0.0; // 2단계 보너스: 경험치 +5%
    
    // [세트 효과] 사막의 개척자 (T2) 2세트: EXP +20%
    double setBonus = isSetEffectActive('desert', 2) ? 20.0 : 0.0;

    return 100.0 + itemBonusPerc + promotionBonus + setBonus; // [v0.4.0] 수식 오류 수정: pas_4(약점 노출)는 치명타 피해 스킬이므로 제거

  }

  double get dropBonus {
    double itemBonusPerc = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addItemDrop) itemBonusPerc += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addItemDrop) itemBonusPerc += item.potential!.value;
    });
    return baseDropBonus + getSkillValue('pas_3') + itemBonusPerc;
  }
  double get offEfficiency => baseOffEfficiency;
  double get cdr {
    double promotionBonus = (promotionLevel >= 9) ? 10.0 : 0.0; // 9단계 보너스: 쿨감 +10%
    
    // [세트 효과] 차원 여행자 (T4) 4세트: 쿨감 +15%
    double setBonus = isSetEffectActive('dimension', 4) ? 15.0 : 0.0;
    
    return baseCdr + getSkillValue('pas_6') + potentialCdr + promotionBonus + setBonus;
  }

  /// 특정 스킬 번호(1~6)에 대한 추가 쿨타임 감소 (%)
  double getSpecificSkillCdr(int skillIdx) {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addSpecificSkillCdr && opt.values.length >= 2) {
          if (opt.values[0].toInt() == skillIdx) total += opt.values[1];
        }
      }
      if (item.potential?.effect == OptionEffect.addSpecificSkillCdr && item.potential!.values.length >= 2) {
        if (item.potential!.values[0].toInt() == skillIdx) total += item.potential!.values[1];
      }
    });
    return total;
  }

  /// 치명타 시 즉사(처형) 발동 확률 (%)
  double get executeChance {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.execute) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.execute) total += item.potential!.value;
    });
    return total;
  }

  /// 치명타 시 (50% 확률로) 감소되는 쿨타임 (초)
  double get critCdrAmount {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.addCritCdr) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addCritCdr) total += item.potential!.value;
    });
    return total;
  }

  /// 스킬 사용 시 연속 발동(잔향) 확률 (%)
  double get skillEchoChance {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.skillEcho) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.skillEcho) total += item.potential!.value;
    });
    return total;
  }

  /// 적 처치 시 보호막 생성 확률 (%)
  double get gainShieldChance {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.gainShield) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.gainShield) total += item.potential!.value;
    });
    return total;
  }

  /// 공격 적중 시 추가 타격 확률 (%)
  double get extraAttackChance {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.extraAttack) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.extraAttack) total += item.potential!.value;
    });
    return total;
  }

  /// 공격 시 2연타 발동 확률 (%)
  double get doubleHitChance {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.doubleHit) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.doubleHit) total += item.potential!.value;
    });
    return total;
  }

  /// 처치 시 공격력 버프 합계 (%)
  double get killAtkBonus {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.atkBuffOnKill) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.atkBuffOnKill) total += item.potential!.value;
    });
    return total;
  }

  /// 처치 시 방어력 버프 합계 (%)
  double get killDefBonus {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.defBuffOnKill) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.defBuffOnKill) total += item.potential!.value;
    });
    return total;
  }

  /// 지역 이동 시 공격력 버프 합계 (%)
  double get zoneAtkBonus {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.atkBuffOnZone) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.atkBuffOnZone) total += item.potential!.value;
    });
    return total;
  }

  /// 지역 이동 시 방어력 버프 합계 (%)
  double get zoneDefBonus {
    double total = 0.0;
    equipment.values.where((i) => i != null).forEach((item) {
      for (var opt in item!.subOptions) {
        if (opt.effect == OptionEffect.defBuffOnZone) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.defBuffOnZone) total += item.potential!.value;
    });
    return total;
  }

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
    // 레벨업 스탯 증가: HP +100, ATK +2, DEF +1
    baseHp += 100;
    baseAttack += 2;
    baseDefense += 1;
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

  Map<String, dynamic> calculateOfflineRewards(DateTime lastTime, double goldMin, double expMin, double killsMin, {int tier = 1}) {
    int minutes = DateTime.now().difference(lastTime).inMinutes;
    if (minutes > 1440) minutes = 1440; // 최대 24시간
    if (minutes < 1) return {};
    
    double efficiency = baseOffEfficiency; 
    int totalGold = (minutes * goldMin * efficiency).toInt();
    int totalExp = (minutes * expMin * efficiency).toInt();
    int totalKills = (minutes * killsMin * efficiency).toInt();
    
    // [v0.4.9] 통합 파편 보상 (슬롯 강화 총합 기반 효율 상승)
    int shardReward = (totalKills * 0.5).toInt();   // 기본: 처치당 0.5개
    if (totalSlotEnhanceLevel >= 1800) shardReward = (totalKills * 0.8).toInt();
    if (totalSlotEnhanceLevel >= 6000) shardReward = (totalKills * 1.5).toInt();
    
    int powderReward = (totalKills * 0.3).toInt();  // 가루: 처치당 0.3개
    int stoneReward = (totalKills * 0.05).toInt();  // 강화석: 처치당 0.05개
    int rerollReward = (totalKills * 0.02).toInt(); // 재설정석: 처치당 0.02개
    int protectReward = (totalKills * 0.01).toInt();// 보호석: 처치당 0.01개
    int cubeReward = (totalKills * 0.005).toInt();  // 큐브: 처치당 0.005개
    
    // 🆕 구슬 보상 -> 심연의 가루로 통합 (v0.8.16)
    int coreReward = (tier >= 2) ? (totalKills * 0.05).toInt() : 0;
    int abyssalReward = powderReward + coreReward;
    
    return {
      'minutes': minutes,
      'gold': totalGold,
      'exp': totalExp,
      'kills': totalKills,
      'bonusStones': stoneReward, 
      'shards': shardReward,
      'abyssalPowder': abyssalReward,
      'rerollStone': rerollReward,
      'protectionStone': protectReward,
      'cube': cubeReward,
      'maxStage': 0, 
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
    
    // [v0.4.9] 통합 파편 보상 적용
    if (rewards.containsKey('shards')) {
      shards += rewards['shards'] as int;
    }
    
    if (rewards.containsKey('abyssalPowder')) {
      abyssalPowder += rewards['abyssalPowder'] as int;
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

    // [v0.8.14] 스테이지 마일스톤 갱신 (오프라인 보전용)
    if (rewards.containsKey('maxStage')) {
      int s = rewards['maxStage'] as int;
      if (s > maxStageReached) maxStageReached = s;
    }
  }

  // --- JSON 직렬화 및 역직렬화 ---

  Map<String, dynamic> toJson() => {
    'name': name, 'level': level, 'exp': exp, 'maxExp': maxExp, 'gold': gold,
    'abyssalPowder': abyssalPowder, 'enhancementStone': enhancementStone, 'rerollStone': rerollStone,
    'protectionStone': protectionStone, 'cube': cube, 'soulStone': soulStone,
    'maxStageReached': maxStageReached,
    'totalKills': totalKills, 'totalGoldEarned': totalGoldEarned,
    'totalItemsFound': totalItemsFound, 'totalSkillsUsed': totalSkillsUsed,
    'totalEnhanceAttempts': totalEnhanceAttempts,
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
    'shards': shards,
    'goldDungeonTicket': goldDungeonTicket,
    'trialDungeonTicket': trialDungeonTicket,
    'slotEnhanceLevels': slotEnhanceLevels.map((k, v) => MapEntry(k.name, v)),
    'slotEnhanceFailCounts': slotEnhanceFailCounts.map((k, v) => MapEntry(k.name, v)),
    'slotEnhanceStreakCounts': slotEnhanceStreakCounts.map((k, v) => MapEntry(k.name, v)),
    'notifiedMilestones': notifiedMilestones,
    'promotionLevel': promotionLevel,
    'currentQuestIndex': currentQuestIndex,
    'isQuestRewardClaimable': isQuestRewardClaimable,
    'autoCraftTiers': autoCraftTiers.map((k, v) => MapEntry(k.toString(), v)),
    'zoneExpeditions': zoneExpeditions,
    'zoneLastClaimedAt': zoneLastClaimedAt,
    'craftingMasteryLevel': craftingMasteryLevel,
    'craftingMasteryExp': craftingMasteryExp,
    'desertBuffEndTime': desertBuffEndTime?.toIso8601String(),
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

    // 🆕 [v0.8.16] 심연의 가루 통합 마이그레이션
    int legacyPowder = json['powder'] ?? 0;
    int currentAbyssalPowder = json['abyssalPowder'] ?? 0;
    int coreSum = 0;
    if (json['tierCores'] != null) {
      try {
        Map<String, dynamic> cores = Map<String, dynamic>.from(json['tierCores']);
        cores.values.forEach((v) => coreSum += (v as int));
      } catch (_) {}
    }
    p.abyssalPowder = currentAbyssalPowder + legacyPowder + coreSum;

    p.goldDungeonTicket = json['goldDungeonTicket'] ?? 0;
    p.trialDungeonTicket = json['trialDungeonTicket'] ?? 0;

    p.enhancementStone = json['enhancementStone'] ?? 0;
    p.rerollStone = json['rerollStone'] ?? 0;
    p.protectionStone = json['protectionStone'] ?? 0;
    p.cube = json['cube'] ?? 0;
    p.maxStageReached = json['maxStageReached'] ?? 0;
    p.totalKills = json['totalKills'] ?? 0;
    p.totalGoldEarned = json['totalGoldEarned'] ?? 0;
    p.totalItemsFound = json['totalItemsFound'] ?? 0;
    p.totalSkillsUsed = json['totalSkillsUsed'] ?? 0;
    p.totalEnhanceAttempts = json['totalEnhanceAttempts'] ?? 0;
    p.currentQuestIndex = json['currentQuestIndex'] ?? 0;
    p.isQuestRewardClaimable = json['isQuestRewardClaimable'] ?? false;

    
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

    if (json['shards'] != null) {
      p.shards = json['shards'] as int;
    } else if (json['tierShards'] != null) {
      // 🆕 [v0.4.9] 마이그레이션: 기존 티어별 파편을 모두 합산하여 통합 파편으로 전환
      try {
        var oldMap = Map<String, dynamic>.from(json['tierShards']);
        int total = 0;
        oldMap.forEach((_, v) { total += (v as int); });
        p.shards = total;
      } catch (_) {}
    }

    if (json['slotEnhanceLevels'] != null) {
      var map = Map<String, dynamic>.from(json['slotEnhanceLevels']);
      map.forEach((k, v) {
        try {
          p.slotEnhanceLevels[ItemType.values.byName(k)] = v as int;
        } catch (_) {}
      });
    }

    if (json['slotEnhanceFailCounts'] != null) {
      var map = Map<String, dynamic>.from(json['slotEnhanceFailCounts']);
      map.forEach((k, v) {
        try {
          p.slotEnhanceFailCounts[ItemType.values.byName(k)] = v as int;
        } catch (_) {}
      });
    }

    if (json['slotEnhanceStreakCounts'] != null) {
      var map = Map<String, dynamic>.from(json['slotEnhanceStreakCounts']);
      map.forEach((k, v) {
        try {
          p.slotEnhanceStreakCounts[ItemType.values.byName(k)] = v as int;
        } catch (_) {}
      });
    }

    if (json['notifiedMilestones'] != null) {
      p.notifiedMilestones = List<int>.from(json['notifiedMilestones']);
    }

    if (json['promotionLevel'] != null) {
      p.promotionLevel = json['promotionLevel'] as int;
    }
    
    if (json['soulStone'] != null) {
      p.soulStone = json['soulStone'] as int;
    }

    if (json['autoCraftTiers'] != null) {
      var map = Map<String, dynamic>.from(json['autoCraftTiers']);
      p.autoCraftTiers = map.map((k, v) => MapEntry(int.tryParse(k) ?? 2, v as bool));
    }
    
    // 🆕 [v0.6.2] 펫 탐사 로드
    if (json.containsKey('zoneExpeditions')) {
      Map<String, dynamic> rawExp = json['zoneExpeditions'];
      p.zoneExpeditions = rawExp.map((k, v) => MapEntry(k, List<String?>.from(v)));
    }
    if (json.containsKey('zoneLastClaimedAt')) {
      p.zoneLastClaimedAt = Map<String, String>.from(json['zoneLastClaimedAt']);
    }
    
    // 🆕 [v0.7.0] 제작 숙련도 로드
    p.craftingMasteryLevel = json['craftingMasteryLevel'] ?? 1;
    p.craftingMasteryExp = json['craftingMasteryExp'] ?? 0;
    if (json['desertBuffEndTime'] != null) {
      p.desertBuffEndTime = DateTime.parse(json['desertBuffEndTime']);
    }



    return p;

  }
}
