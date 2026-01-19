import 'package:flutter/material.dart';

enum ZoneId { grassland, forest, mine, dungeon, volcano, snowfield, abyss, tower }
enum ZoneType { general, special }

class HuntingZone {
  final ZoneId id;
  final String name;
  final String description;
  final Color color;
  final int minLevel;
  final List<String> monsterNames;
  final List<String> keyDrops; // UI 표시용
  final ZoneType type; // 일반/특별 구분
  final double difficultyMultiplier; // 맵 난이도 계수

  HuntingZone({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.minLevel,
    required this.monsterNames,
    required this.keyDrops,
    required this.type,
    this.difficultyMultiplier = 1.0,
  });
}

class HuntingZoneData {
  static final List<HuntingZone> list = [
    HuntingZone(
      id: ZoneId.grassland,
      name: '초원',
      description: '입문 단계. 빠른 레벨업과 기본 재화 수급',
      color: Colors.teal[700]!,
      minLevel: 1,
      monsterNames: ['슬라임', '뿔토끼', '들쥐'],
      keyDrops: ['마법 가루', '강화석', '초원의 파편'],
      type: ZoneType.general,
      difficultyMultiplier: 1.0,
    ),
    HuntingZone(
      id: ZoneId.forest,
      name: '숲',
      description: '첫 번째 벽. 물리 방어력이 조금씩 상승',
      color: Colors.green[900]!,
      minLevel: 21,
      monsterNames: ['고블린', '늑대', '식인식물'],
      keyDrops: ['강화석', '마법 가루', '초원의 파편'],
      type: ZoneType.general,
      difficultyMultiplier: 2.0,
    ),
    HuntingZone(
      id: ZoneId.mine,
      name: '광산',
      description: '본격적인 강화석 파밍 지역. 높은 체력의 적',
      color: Colors.blueGrey[800]!,
      minLevel: 51,
      monsterNames: ['골렘', '박쥐', '미믹'],
      keyDrops: ['재설정석', '강화석', '사막의 파편'],
      type: ZoneType.general,
      difficultyMultiplier: 4.0,
    ),
    HuntingZone(
      id: ZoneId.dungeon,
      name: '던전',
      description: '회피와 명중 스탯이 중요해지는 구간',
      color: Colors.deepPurple[900]!,
      minLevel: 91,
      monsterNames: ['스켈레톤', '유령', '해골궁수'],
      keyDrops: ['마법 가루', '재설정석', '사막의 파편'],
      type: ZoneType.general,
      difficultyMultiplier: 8.0,
    ),
    HuntingZone(
      id: ZoneId.volcano,
      name: '화산',
      description: '강력한 공격력. 체력 관리가 핵심인 하드코어 존',
      color: Colors.red[900]!,
      minLevel: 141,
      monsterNames: ['파이어드레이크', '라바스피릿', '불타는 골렘'],
      keyDrops: ['잠재의 큐브', '빛나는 강화석', '설원의 파편'],
      type: ZoneType.general,
      difficultyMultiplier: 16.0,
    ),
    HuntingZone(
      id: ZoneId.snowfield,
      name: '설원',
      description: '최상위 옵션이 붙은 신화 장비 드롭 구간',
      color: Colors.blue[900]!,
      minLevel: 201,
      monsterNames: ['아이스자이언트', '설인', '서리늑대'],
      keyDrops: ['빛나는 강화석', '잠재의 큐브', '설원의 파편'],
      type: ZoneType.general,
      difficultyMultiplier: 32.0,
    ),
    HuntingZone(
      id: ZoneId.abyss,
      name: '심연',
      description: '한계를 시험하는 엔드 콘텐츠 지역',
      color: Colors.black87,
      minLevel: 281,
      monsterNames: ['그림자 군단', '어둠의 화신', '공허의 수호자'],
      keyDrops: ['신화의 정수', '빛나는 강화석', '심연의 파편'],
      type: ZoneType.general,
      difficultyMultiplier: 64.0,
    ),
    // --- 특별 사냥터 ---
    HuntingZone(
      id: ZoneId.tower,
      name: '무한의탑',
      description: '매 층 강력한 수호자가 기다리는 도전형 콘텐츠',
      color: Colors.amber[900]!,
      minLevel: 1,
      monsterNames: ['탑의 수호자', '심판자', '고대 병기'],
      keyDrops: ['고급 잠재의 큐브', '전설 강화석', '영혼석'],
      type: ZoneType.special,
      difficultyMultiplier: 1.0,
    ),
  ];
}
