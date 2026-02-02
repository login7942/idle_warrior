import 'dart:math';

class ReincarnationPerk {
  final String id;
  final String name;
  final String icon;
  final String description;
  final double valuePerPoint;
  final String unit;
  int level;

  ReincarnationPerk({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.valuePerPoint,
    this.unit = '%',
    this.level = 0,
  });

  double get bonusValue => level * valuePerPoint;

  Map<String, dynamic> toJson() => {
    'id': id,
    'level': level,
  };

  void updateFromJson(Map<String, dynamic> json) {
    if (json['id'] == id) {
      level = json['level'] ?? 0;
    }
  }
}

class ReincarnationData {
  int reincarnationCount;
  int points; // 보유 포인트
  int totalPointsEarned; // 누적 포인트

  // 특성 데이터
  late List<ReincarnationPerk> perks;

  ReincarnationData({
    this.reincarnationCount = 0,
    this.points = 0,
    this.totalPointsEarned = 0,
    List<ReincarnationPerk>? initialPerks,
  }) {
    perks = initialPerks ?? _initializeDefaultPerks();
  }

  List<ReincarnationPerk> _initializeDefaultPerks() {
    return [
      // 전투 특성 (0.1% 계열)
      ReincarnationPerk(id: 'final_atk', name: '최종 공격력', icon: '⚔️', description: '영구적으로 최종 공격력이 상승합니다.', valuePerPoint: 0.1),
      ReincarnationPerk(id: 'final_hp', name: '최종 체력', icon: '❤️', description: '영구적으로 최종 체력이 상승합니다.', valuePerPoint: 0.1),
      ReincarnationPerk(id: 'crit_dmg', name: '치명타 피해량', icon: '💥', description: '치명타 피해량이 영구적으로 상승합니다.', valuePerPoint: 0.5),
      ReincarnationPerk(id: 'atk_spd', name: '공격 속도', icon: '⚡', description: '공격 속도가 영구적으로 상승합니다.', valuePerPoint: 0.1),
      
      // 유틸リティ (0.2% 계열)
      ReincarnationPerk(id: 'gold_bonus', name: '골드 획득량', icon: '💰', description: '전투 시 획득하는 골드가 상승합니다.', valuePerPoint: 0.2),
      ReincarnationPerk(id: 'exp_bonus', name: '경험치 획득량', icon: '📖', description: '전투 시 획득하는 경험치가 상승합니다.', valuePerPoint: 0.2),
      ReincarnationPerk(id: 'offline_eff', name: '오프라인 효율', icon: '💤', description: '오프라인 방치 효율이 상승합니다.', valuePerPoint: 0.1),
      
      // 특수 특성 (0.01% 계열)
      ReincarnationPerk(id: 'skill_proc', name: '스킬 효과 확률', icon: '🔮', description: '각 스킬의 부가효과 발동 확률이 상승합니다.', valuePerPoint: 0.01),
      ReincarnationPerk(id: 'boss_dmg', name: '보스 피해량', icon: '👑', description: '보스에게 입히는 피해량이 상승합니다.', valuePerPoint: 0.1),
      ReincarnationPerk(id: 'drop_rate', name: '고티어 드롭률', icon: '💎', description: '상위 등급 장비의 드롭 확률이 상승합니다.', valuePerPoint: 0.01),
    ];
  }

  // 특정 특성의 보너스 수치 가져오기
  double getBonus(String id) {
    try {
      return perks.firstWhere((p) => p.id == id).bonusValue;
    } catch (e) {
      return 0.0;
    }
  }

  Map<String, dynamic> toJson() => {
    'reincarnationCount': reincarnationCount,
    'points': points,
    'totalPointsEarned': totalPointsEarned,
    'perks': perks.map((p) => p.toJson()).toList(),
  };

  factory ReincarnationData.fromJson(Map<String, dynamic> json) {
    final data = ReincarnationData(
      reincarnationCount: json['reincarnationCount'] ?? 0,
      points: json['points'] ?? 0,
      totalPointsEarned: json['totalPointsEarned'] ?? 0,
    );
    
    if (json['perks'] != null) {
      final List<dynamic> perkList = json['perks'];
      for (var pJson in perkList) {
        String id = pJson['id'];
        try {
          data.perks.firstWhere((p) => p.id == id).updateFromJson(pJson);
        } catch (_) {}
      }
    }
    return data;
  }
}
