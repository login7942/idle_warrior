import 'package:flutter/material.dart';
import 'item.dart';

enum PetGrade { common, uncommon, rare, epic, legendary, mythic }

extension PetGradeExtension on PetGrade {
  String get name {
    switch (this) {
      case PetGrade.common: return '일반';
      case PetGrade.uncommon: return '고급';
      case PetGrade.rare: return '희귀';
      case PetGrade.epic: return '고대의';
      case PetGrade.legendary: return '유물의';
      case PetGrade.mythic: return '전설의';
    }
  }

  Color get color {
    switch (this) {
      case PetGrade.common: return const Color(0xFF9E9E9E);
      case PetGrade.uncommon: return const Color(0xFF4CAF50);
      case PetGrade.rare: return const Color(0xFF2196F3);
      case PetGrade.epic: return const Color(0xFF9C27B0);
      case PetGrade.legendary: return const Color(0xFFFF9800);
      case PetGrade.mythic: return const Color(0xFFE91E63);
    }
  }

  LinearGradient get bgGradient {
    switch (this) {
      case PetGrade.common:
        return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.grey.shade800, Colors.grey.shade900]);
      case PetGrade.uncommon:
        return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.green.shade700, Colors.green.shade900]);
      case PetGrade.rare:
        return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.blue.shade700, Colors.blue.shade900]);
      case PetGrade.epic:
        return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.purple.shade700, Colors.purple.shade900]);
      case PetGrade.legendary:
        return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.orange.shade700, Colors.deepOrange.shade900]);
      case PetGrade.mythic:
        return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFFE91E63), const Color(0xFF880E4F)]);
    }
  }
}

class Pet {
  final String id;
  final String name;
  final String description;
  final PetGrade grade;
  final String iconEmoji;

  // 보유 효과 (모든 보유 펫 합산 적용)
  final double ownAtkMultiplier; // 공격력 % (예: 1.0 = 1%)
  final double ownHpMultiplier;  // HP %
  final double ownGoldMultiplier; // 골드 %

  // 동행 효과 (장착 시에만 적용)
  final String companionSkillName;
  final String companionSkillDesc;
  final double companionValue; // 효과 수치

  int level;
  int star; // 진화 단계 (0~5성)

  Pet({
    required this.id,
    required this.name,
    required this.description,
    required this.grade,
    required this.iconEmoji,
    this.ownAtkMultiplier = 0,
    this.ownHpMultiplier = 0,
    this.ownGoldMultiplier = 0,
    this.companionSkillName = '',
    this.companionSkillDesc = '',
    this.companionValue = 0,
    this.level = 1,
    this.star = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level,
        'star': star,
      };

  void updateFromJson(Map<String, dynamic> json) {
    level = json['level'] ?? 1;
    star = json['star'] ?? 0;
  }

  // 실제 적용되는 보유 효과 (레벨 및 성급 반영)
  double get currentAtkBonus => ownAtkMultiplier * (1 + (level - 1) * 0.1) * (1 + star * 0.5);
  double get currentHpBonus => ownHpMultiplier * (1 + (level - 1) * 0.1) * (1 + star * 0.5);
  double get currentGoldBonus => ownGoldMultiplier * (1 + (level - 1) * 0.1) * (1 + star * 0.5);

  // 동행 효과 (성급에 따라 강화)
  double get currentCompanionValue => companionValue * (1 + star * 0.2);
}

class PetData {
  static List<Pet> getInitialPets() {
    return [
      // 1등급 (일반) - 5종
      Pet(id: 'pet_c1', name: '길잃은 슬라임', description: '말랑말랑하고 귀여운 파란 슬라임입니다.', grade: PetGrade.common, iconEmoji: '💧', ownAtkMultiplier: 1.0, ownHpMultiplier: 2.0, companionSkillName: '끈적한 발걸음', companionSkillDesc: '드롭된 골드를 자동으로 끌어당깁니다.'),
      Pet(id: 'pet_c2', name: '시골집 강아지', description: '주인을 잘 따르는 충직한 강아지입니다.', grade: PetGrade.common, iconEmoji: '🐕', ownAtkMultiplier: 1.5, ownGoldMultiplier: 1.0, companionSkillName: '꼬리 흔들기', companionSkillDesc: '골드 획득량이 2% 증가합니다.', companionValue: 2.0),
      Pet(id: 'pet_c3', name: '숲속 다람쥐', description: '도토리를 좋아하는 부지런한 다람쥐입니다.', grade: PetGrade.common, iconEmoji: '🐿️', ownAtkMultiplier: 1.2, ownHpMultiplier: 1.5, companionSkillName: '도토리 던지기', companionSkillDesc: '공격 속도가 1% 증가합니다.', companionValue: 1.0),
      Pet(id: 'pet_c4', name: '아기 병아리', description: '삐약삐약 울며 뒤를 졸졸 따라다닙니다.', grade: PetGrade.common, iconEmoji: '🐥', ownHpMultiplier: 3.0, companionSkillName: '치유의 울음', companionSkillDesc: '초당 HP 재생이 0.5% 증가합니다.', companionValue: 0.5),
      Pet(id: 'pet_c5', name: '낡은 상자 정령', description: '버려진 상자에 영혼이 깃들어 만들어졌습니다.', grade: PetGrade.common, iconEmoji: '📦', ownGoldMultiplier: 2.5, companionSkillName: '상자 수색', companionSkillDesc: '아이템 드롭률이 1% 증가합니다.', companionValue: 1.0),

      // 2등급 (고급) - 5종
      Pet(id: 'pet_u1', name: '발빠른 토끼', description: '항상 무언가에 쫓기는 듯 빠르게 움직입니다.', grade: PetGrade.uncommon, iconEmoji: '🐰', ownAtkMultiplier: 3.0, ownGoldMultiplier: 5.0, companionSkillName: '가속 점프', companionSkillDesc: '공격 속도가 3% 증가합니다.', companionValue: 3.0),
      Pet(id: 'pet_u2', name: '영리한 너구리', description: '재빠른 손놀림으로 소지품을 챙깁니다.', grade: PetGrade.uncommon, iconEmoji: '🦝', ownAtkMultiplier: 4.0, ownHpMultiplier: 3.0, companionSkillName: '물건 훔치기', companionSkillDesc: '아이템 드롭률이 3% 증가합니다.', companionValue: 3.0),
      Pet(id: 'pet_u3', name: '성난 멧돼지', description: '앞만 보고 돌진하는 저돌적인 멧돼지입니다.', grade: PetGrade.uncommon, iconEmoji: '🐗', ownAtkMultiplier: 6.0, companionSkillName: '돌격', companionSkillDesc: '깡 파워가 무엇인지 보여줍니다. 공격력 +5%.', companionValue: 5.0),
      Pet(id: 'pet_u4', name: '단단한 거북이', description: '웬만한 공격에도 끄떡없는 등껍질을 가졌습니다.', grade: PetGrade.uncommon, iconEmoji: '🐢', ownHpMultiplier: 10.0, companionSkillName: '껍질 숨기', companionSkillDesc: '방어력이 5% 증가합니다.', companionValue: 5.0),
      Pet(id: 'pet_u5', name: '촐랑거리는 원숭이', description: '나무 위를 자유롭게 누비는 개구쟁이입니다.', grade: PetGrade.uncommon, iconEmoji: '🐒', ownGoldMultiplier: 8.0, ownAtkMultiplier: 2.0, companionSkillName: '바나나 던지기', companionSkillDesc: '치명타 확률이 2% 증가합니다.', companionValue: 2.0),

      // 3등급 (희귀) - 5종
      Pet(id: 'pet_r1', name: '영리한 올빼미', description: '지혜로운 눈으로 적의 약점을 파악합니다.', grade: PetGrade.rare, iconEmoji: '🦉', ownAtkMultiplier: 10.0, ownHpMultiplier: 8.0, companionSkillName: '예리한 통찰', companionSkillDesc: '치명타 확률이 5% 증가합니다.', companionValue: 5.0),
      Pet(id: 'pet_r2', name: '용맹한 늑대', description: '달빛 아래에서 더 파괴적인 위력을 발휘합니다.', grade: PetGrade.rare, iconEmoji: '🐺', ownAtkMultiplier: 15.0, companionSkillName: '늑대의 울부짖음', companionSkillDesc: '치명타 피해가 15% 증가합니다.', companionValue: 15.0),
      Pet(id: 'pet_r3', name: '우아한 백조', description: '아름다운 몸짓으로 주인의 기운을 돋웁니다.', grade: PetGrade.rare, iconEmoji: '🦢', ownHpMultiplier: 20.0, companionSkillName: '호수의 안식', companionSkillDesc: '최대 HP가 10% 증가합니다.', companionValue: 10.0),
      Pet(id: 'pet_r4', name: '신비로운 사슴', description: '숲의 기운을 머금은 뿔에서 빛이 납니다.', grade: PetGrade.rare, iconEmoji: '🦌', ownGoldMultiplier: 20.0, ownAtkMultiplier: 5.0, companionSkillName: '대지의 은총', companionSkillDesc: '골드 획득량이 15% 증가합니다.', companionValue: 15.0),
      Pet(id: 'pet_r5', name: '날카로운 독수리', description: '하늘 높은 곳에서 적을 사냥합니다.', grade: PetGrade.rare, iconEmoji: '🦅', ownAtkMultiplier: 12.0, ownGoldMultiplier: 10.0, companionSkillName: '급강하 공격', companionSkillDesc: '공격 속도가 8% 증가합니다.', companionValue: 8.0),

      // 4등급 (고대의) - 5종
      Pet(id: 'pet_e1', name: '화염 사막 여우', description: '뜨거운 화염의 기운을 내뿜는 여우입니다.', grade: PetGrade.epic, iconEmoji: '🦊', ownAtkMultiplier: 30.0, ownGoldMultiplier: 25.0, companionSkillName: '화염의 가호', companionSkillDesc: '모든 스킬 데미지가 20% 증가합니다.', companionValue: 20.0),
      Pet(id: 'pet_e2', name: '서리 늑대왕', description: '북극의 냉기를 자유자재로 다스립니다.', grade: PetGrade.epic, iconEmoji: '❄️', ownAtkMultiplier: 40.0, ownHpMultiplier: 20.0, companionSkillName: '영구 동토', companionSkillDesc: '몬스터의 공격 속도를 15% 늦춥니다.', companionValue: 15.0),
      Pet(id: 'pet_e3', name: '고대 비석 골렘', description: '세월을 이겨낸 바위에 고대의 문자가 새겨졌습니다.', grade: PetGrade.epic, iconEmoji: '🗿', ownHpMultiplier: 60.0, companionSkillName: '석화 피부', companionSkillDesc: '받는 피해가 10% 감소합니다.', companionValue: 10.0),
      Pet(id: 'pet_e4', name: '벼락 천둥새', description: '구름 위에서 거대한 번개를 몰고 옵니다.', grade: PetGrade.epic, iconEmoji: '⚡', ownAtkMultiplier: 35.0, ownGoldMultiplier: 30.0, companionSkillName: '천둥의 심판', companionSkillDesc: '치명타 확률이 10% 증가합니다.', companionValue: 10.0),
      Pet(id: 'pet_e5', name: '폭풍 날개 페가수스', description: '바람을 가르며 날아오르는 전설의 영물입니다.', grade: PetGrade.epic, iconEmoji: '🦄', ownAtkMultiplier: 25.0, ownGoldMultiplier: 40.0, companionSkillName: '폭풍의 질주', companionSkillDesc: '스테이지 클리어 경험치가 25% 증가합니다.', companionValue: 25.0),

      // 5등급 (유물의) - 5종
      Pet(id: 'pet_l1', name: '아기 드래곤', description: '잠재력이 무궁무진한 드래곤의 새끼입니다.', grade: PetGrade.legendary, iconEmoji: '🐲', ownAtkMultiplier: 100.0, ownHpMultiplier: 100.0, companionSkillName: '용의 분노', companionSkillDesc: '최종 데미지가 15% 증폭됩니다.', companionValue: 15.0),
      Pet(id: 'pet_l2', name: '불사조 피닉스', description: '죽음에서 부활하는 영원한 생명의 상징입니다.', grade: PetGrade.legendary, iconEmoji: '🐦‍🔥', ownAtkMultiplier: 120.0, ownGoldMultiplier: 50.0, companionSkillName: '불사의 불꽃', companionSkillDesc: '사망 시 30% 체력으로 즉시 부활합니다 (쿨타임 60초).', companionValue: 30.0),
      Pet(id: 'pet_l3', name: '심해 지배자 레비아탄', description: '깊은 바닷속에서 모든 것을 삼키는 거수입니다.', grade: PetGrade.legendary, iconEmoji: '🐋', ownHpMultiplier: 200.0, ownAtkMultiplier: 50.0, companionSkillName: '심해의 공포', companionSkillDesc: '방어력 관통이 20% 증가합니다.', companionValue: 20.0),
      Pet(id: 'pet_l4', name: '대지 수호자 베히모스', description: '걸을 때마다 대지가 요동치는 거대한 맹수입니다.', grade: PetGrade.legendary, iconEmoji: '🐘', ownHpMultiplier: 150.0, ownGoldMultiplier: 100.0, companionSkillName: '대지의 울림', companionSkillDesc: '아이템 드롭률이 50% 증가합니다.', companionValue: 50.0),
      Pet(id: 'pet_l5', name: '태양의 사자 라', description: '찬란한 태양의 빛을 내뿜는 태양의 화신입니다.', grade: PetGrade.legendary, iconEmoji: '🦁', ownAtkMultiplier: 80.0, ownGoldMultiplier: 150.0, companionSkillName: '태양 광선', companionSkillDesc: '치명타 피해가 50% 증가합니다.', companionValue: 50.0),

      // 6등급 (전설의) - 5종
      Pet(id: 'pet_m1', name: '파괴 군주 티라노', description: '존재만으로 모든 생명체를 압도하는 포식자입니다.', grade: PetGrade.mythic, iconEmoji: '🦖', ownAtkMultiplier: 300.0, ownGoldMultiplier: 200.0, companionSkillName: '절대 위엄', companionSkillDesc: '몬스터를 5% 확률로 즉사시킵니다.', companionValue: 5.0),
      Pet(id: 'pet_m2', name: '창조 신룡 오리진', description: '세상의 시작과 함께 탄생한 근원의 드래곤입니다.', grade: PetGrade.mythic, iconEmoji: '🐉', ownAtkMultiplier: 500.0, ownHpMultiplier: 300.0, companionSkillName: '근원의 힘', companionSkillDesc: '모든 스탯이 25% 증가합니다.', companionValue: 25.0),
      Pet(id: 'pet_m3', name: '암흑 바실리스크', description: '그의 시선이 닿는 모든 고리가 죽음으로 변합니다.', grade: PetGrade.mythic, iconEmoji: '🐍', ownAtkMultiplier: 400.0, ownHpMultiplier: 400.0, companionSkillName: '죽음의 응시', companionSkillDesc: '몬스터 방어력을 50% 무시합니다.', companionValue: 50.0),
      Pet(id: 'pet_m4', name: '기원 불꽃 주작', description: '하늘을 뒤덮는 거대한 화염 날개를 가진 신수입니다.', grade: PetGrade.mythic, iconEmoji: '🔥', ownAtkMultiplier: 350.0, ownGoldMultiplier: 350.0, companionSkillName: '화염 폭풍', companionSkillDesc: '최종 공격 속도가 20% 증가합니다.', companionValue: 20.0),
      Pet(id: 'pet_m5', name: '겨울 구미호', description: '눈부시게 하얀 9개의 꼬리를 가진 환상의 여우입니다.', grade: PetGrade.mythic, iconEmoji: '🦊', ownAtkMultiplier: 250.0, ownGoldMultiplier: 500.0, companionSkillName: '환술', companionSkillDesc: '회피율이 30% 증가합니다.', companionValue: 30.0),
    ];
  }
}
