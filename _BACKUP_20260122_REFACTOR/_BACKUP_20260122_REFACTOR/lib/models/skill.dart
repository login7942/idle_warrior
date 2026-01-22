import 'dart:math';

enum SkillType { active, passive }

class Skill {
  final String id;
  final String name;
  final String description;
  final SkillType type;
  final String iconEmoji;
  int level;
  final int maxLevel;
  final int unlockLevel;    // 해금 필요 레벨
  final int unlockCost;     // 최초 습득 비용 (골드)
  final int baseUpgradeCost; // 레벨업 기본 비용
  final double costMultiplier; // 비용 배율 (1.5 ~ 3.5)
  
  // 스킬 효과값 (레벨에 따라 증가)
  final double baseValue;
  final double valuePerLevel;
  
  // 활성 스킬 전용 속성
  final double baseCooldown; // 기본 쿨타임 (초)
  DateTime? lastUsed;

  Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.iconEmoji,
    this.level = 0,
    this.maxLevel = 100,
    required this.unlockLevel,
    required this.unlockCost,
    required this.baseUpgradeCost,
    required this.costMultiplier,
    required this.baseValue,
    required this.valuePerLevel,
    required this.baseCooldown,
    this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level,
        'lastUsed': lastUsed?.toIso8601String(),
      };

  // 기존 스킬 리스트에서 정보를 매칭하여 업데이트하기 위해 Named Constructor 대신 업데이트 메서드 사용
  void updateFromJson(Map<String, dynamic> json) {
    level = json['level'] ?? 0;
    if (json['lastUsed'] != null) {
      lastUsed = DateTime.parse(json['lastUsed']);
    }
  }

  // CDR(CoolDown Reduction)이 적용된 최종 쿨타임 계산
  double getFinalCooldown(double cdrPercent) {
    return baseCooldown * (1 - cdrPercent / 100);
  }

  // 현재 효과 수치 계산
  double get currentValue => baseValue + (level * valuePerLevel);

  // 레벨업 비용 계산: 기본 비용 * Math.pow(비용배율, 현재레벨)
  int get upgradeCost {
    if (level == 0) return unlockCost;
    return (baseUpgradeCost * pow(costMultiplier, level - 1)).toInt();
  }

  // 쿨타임 진행률 (cdrPercent 전달 받아서 계산)
  double getCooldownProgress(double cdrPercent) {
    if (type == SkillType.passive || lastUsed == null) return 1.0;
    final elapsedMs = DateTime.now().difference(lastUsed!).inMilliseconds;
    final totalMs = getFinalCooldown(cdrPercent) * 1000;
    return (elapsedMs / totalMs).clamp(0.0, 1.0);
  }

  // 남은 쿨타임 (초 단위)
  double getRemainingSeconds(double cdrPercent) {
    if (type == SkillType.passive || lastUsed == null || isReady(cdrPercent)) return 0.0;
    final elapsedMs = DateTime.now().difference(lastUsed!).inMilliseconds;
    final totalMs = getFinalCooldown(cdrPercent) * 1000;
    return max(0.0, (totalMs - elapsedMs) / 1000);
  }

  bool isReady(double cdrPercent) => getCooldownProgress(cdrPercent) >= 1.0;

  bool get isUnlocked => level > 0;
}
