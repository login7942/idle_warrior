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
      case PetGrade.common: return const Color(0xFF2E2E2E);
      case PetGrade.uncommon: return const Color(0xFF2F6BFF);
      case PetGrade.rare: return const Color(0xFF8B5CF6);
      case PetGrade.epic: return const Color(0xFFF59E0B);
      case PetGrade.legendary: return const Color(0xFFEF4444);
      case PetGrade.mythic: return const Color(0xFFEC4899); // 신화/전설 펫은 핑크 계열로 포인트
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
      // 1등급 (일반)
      Pet(
        id: 'pet_01', 
        name: '길잃은 슬라임', 
        description: '말랑말랑하고 귀여운 파란 슬라임입니다.', 
        grade: PetGrade.common, 
        iconEmoji: '💧',
        ownAtkMultiplier: 1.0, 
        ownHpMultiplier: 2.0,
        companionSkillName: '끈적한 발걸음',
        companionSkillDesc: '드롭된 골드를 자동으로 끌어당깁니다.',
      ),
      // 2등급 (고급)
      Pet(
        id: 'pet_02', 
        name: '발빠른 토끼', 
        description: '항상 무언가에 쫓기는 듯 빠르게 움직입니다.', 
        grade: PetGrade.uncommon, 
        iconEmoji: '🐰',
        ownAtkMultiplier: 3.0, 
        ownGoldMultiplier: 5.0,
        companionSkillName: '가속 점프',
        companionSkillDesc: '이동 속도가 20% 증가합니다.',
        companionValue: 20.0,
      ),
      // 3등급 (희귀)
      Pet(
        id: 'pet_03', 
        name: '영리한 올빼미', 
        description: '지혜로운 눈으로 적의 약점을 파악합니다.', 
        grade: PetGrade.rare, 
        iconEmoji: '🦉',
        ownAtkMultiplier: 8.0, 
        ownHpMultiplier: 5.0,
        companionSkillName: '예리한 통찰',
        companionSkillDesc: '치명타 확률이 5% 증가합니다.',
        companionValue: 5.0,
      ),
      // 4등급 (고대)
      Pet(
        id: 'pet_04', 
        name: '화염 사막 여우', 
        description: '뜨거운 화염의 기운을 내뿜는 여우입니다.', 
        grade: PetGrade.epic, 
        iconEmoji: '🦊',
        ownAtkMultiplier: 20.0, 
        ownGoldMultiplier: 15.0,
        companionSkillName: '화염의 가호',
        companionSkillDesc: '모든 스킬 데미지가 15% 증가합니다.',
        companionValue: 15.0,
      ),
      // 5등급 (유물)
      Pet(
        id: 'pet_05', 
        name: '아기 드래곤', 
        description: '잠재력이 무궁무진한 드래곤의 새끼입니다.', 
        grade: PetGrade.legendary, 
        iconEmoji: '🐲',
        ownAtkMultiplier: 50.0, 
        ownHpMultiplier: 50.0,
        companionSkillName: '용의 분노',
        companionSkillDesc: '최종 데미지가 10% 증폭됩니다.',
        companionValue: 10.0,
      ),
      // 6등급 (전설)
      Pet(
        id: 'pet_06', 
        name: '파괴의 군주 티라노', 
        description: '존재만으로 모든 생명체를 압도하는 포식자입니다.', 
        grade: PetGrade.mythic, 
        iconEmoji: '🦖',
        ownAtkMultiplier: 150.0, 
        ownGoldMultiplier: 100.0,
        companionSkillName: '절대 위엄',
        companionSkillDesc: '비보스 몬스터를 3% 확률로 즉사시킵니다.',
        companionValue: 3.0,
      ),
    ];
  }
}
