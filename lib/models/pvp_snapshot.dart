import '../models/item.dart';
import '../models/skill.dart';
import '../models/reincarnation.dart';

class PvPSnapshot {
  final String userId;
  final String username;
  final int level;
  final int combatPower;
  final int maxHp;
  final double attack;
  final double defense;
  final double critChance;
  final double critDamage;
  final double attackSpeed;
  final double cdr;
  final List<Item> equippedItems;
  final List<Skill> activeSkills;
  final List<Skill> passiveSkills;
  final ReincarnationData reincarnation;
  final DateTime updatedAt;

  PvPSnapshot({
    required this.userId,
    required this.username,
    required this.level,
    required this.combatPower,
    required this.maxHp,
    required this.attack,
    required this.defense,
    required this.critChance,
    required this.critDamage,
    required this.attackSpeed,
    required this.cdr,
    required this.equippedItems,
    required this.activeSkills,
    required this.passiveSkills,
    required this.reincarnation,
    required this.updatedAt,
  });

  /// 🆕 공격 시 보호막 생성 확률 (%)
  double get gainShieldChance {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.gainShield) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.gainShield) total += item.potential!.value;
    }
    return total;
  }

  /// 🆕 공격 시 2연타 발동 확률 (%)
  double get doubleHitChance {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.doubleHit) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.doubleHit) total += item.potential!.value;
    }
    return total;
  }

  /// 🆕 흡혈 확률 (%)
  double get lifesteal {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.lifesteal) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.lifesteal) total += item.potential!.value;
    }
    return total;
  }

  /// 🆕 HP 재생 (%)
  double get hpRegen {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.addRegen) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addRegen) total += item.potential!.value;
    }
    return 1.0 + total; // 기본 1% + 아이템 보너스
  }

  /// 🆕 HP 재생 상한선 (%)
  double get hpRegenCap {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.addRegenCap) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addRegenCap) total += item.potential!.value;
    }
    return 5.0 + total; // 기본 5% + 아이템 보너스
  }

  /// 🆕 피격 시 데미지의 % 만큼 즉시 회복
  double get recoverOnDamagedPerc {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.recoverOnDamagedPerc) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.recoverOnDamagedPerc) total += item.potential!.value;
    }
    return total;
  }

  /// 🆕 스킬 사용 시 발동되는 피해 감소 확률 (%)
  double get dmgReductionOnSkill {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.dmgReductionOnSkill) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.dmgReductionOnSkill) total += item.potential!.value;
    }
    return total;
  }

  /// 🆕 스킬 사용 시 연속 발동(잔향) 확률 (%)
  double get skillEchoChance {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.skillEcho) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.skillEcho) total += item.potential!.value;
    }
    return total;
  }

  /// 🆕 치명타 시 (50% 확률로) 감소되는 쿨타임 (초)
  double get critCdrAmount {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.addCritCdr) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.addCritCdr) total += item.potential!.value;
    }
    return total;
  }

  /// 🆕 피격 시 피해 반사 확률 (%)
  double get reflectPerc {
    double total = 0.0;
    for (var item in equippedItems) {
      for (var opt in item.subOptions) {
        if (opt.effect == OptionEffect.reflect) total += opt.value;
      }
      if (item.potential?.effect == OptionEffect.reflect) total += item.potential!.value;
    }
    return total;
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'level': level,
      'combatPower': combatPower,
      'maxHp': maxHp,
      'attack': attack,
      'defense': defense,
      'critChance': critChance,
      'critDamage': critDamage,
      'attackSpeed': attackSpeed,
      'cdr': cdr,
      'equippedItems': equippedItems.map((i) => i.toJson()).toList(),
      'activeSkills': activeSkills.map((s) => s.toJson()).toList(),
      'passiveSkills': passiveSkills.map((s) => s.toJson()).toList(),
      'reincarnation': reincarnation.toJson(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PvPSnapshot.fromJson(Map<String, dynamic> json) {
    return PvPSnapshot(
      userId: json['userId'] ?? '',
      username: json['username'] ?? 'Unknown',
      level: json['level'] ?? 1,
      combatPower: json['combatPower'] ?? 0,
      maxHp: json['maxHp'] ?? 100,
      attack: (json['attack'] ?? 0).toDouble(),
      defense: (json['defense'] ?? 0).toDouble(),
      critChance: (json['critChance'] ?? 0).toDouble(),
      critDamage: (json['critDamage'] ?? 0).toDouble(),
      attackSpeed: (json['attackSpeed'] ?? 0).toDouble(),
      cdr: (json['cdr'] ?? 0).toDouble(),
      equippedItems: (json['equippedItems'] as List? ?? [])
          .map((i) => Item.fromJson(i))
          .toList(),
      activeSkills: (json['activeSkills'] as List? ?? [])
          .map((s) => Skill.fromJson(s as Map<String, dynamic>))
          .toList(),
      passiveSkills: (json['passiveSkills'] as List? ?? [])
          .map((s) => Skill.fromJson(s as Map<String, dynamic>))
          .toList(),
      reincarnation: ReincarnationData.fromJson(json['reincarnation'] ?? {}),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class PvPRankEntry {
  final String userId;
  final String username;
  final int score;
  final int wins;
  final int losses;
  final String rankTier;
  final int combatPower;

  PvPRankEntry({
    required this.userId,
    required this.username,
    required this.score,
    required this.wins,
    required this.losses,
    required this.rankTier,
    required this.combatPower,
  });

  factory PvPRankEntry.fromJson(Map<String, dynamic> json) {
    return PvPRankEntry(
      userId: json['user_id'] ?? '',
      username: json['username'] ?? 'Unknown', // snapshots 테이블과 join 시 필요
      score: json['score'] ?? 1000,
      wins: json['wins'] ?? 0,
      losses: json['losses'] ?? 0,
      rankTier: json['rank_tier'] ?? 'Bronze',
      combatPower: json['combat_power'] ?? 0,
    );
  }
}

class PvPBattleLog {
  final String attackerName;
  final String defenderName;
  final bool isVictory;
  final DateTime createdAt;

  PvPBattleLog({
    required this.attackerName,
    required this.defenderName,
    required this.isVictory,
    required this.createdAt,
  });

  factory PvPBattleLog.fromJson(Map<String, dynamic> json) {
    return PvPBattleLog(
      attackerName: json['attacker_name'] ?? 'Unknown',
      defenderName: json['defender_name'] ?? 'Unknown',
      isVictory: json['is_victory'] ?? false,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}
