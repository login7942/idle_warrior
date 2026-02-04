import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/pvp_snapshot.dart';
import '../models/player.dart';
import '../models/skill.dart';
import '../models/item.dart';

class PvPManager {
  final _supabase = Supabase.instance.client;
  final _uuid = const Uuid();

  /// 유저의 현재 데이터를 PvP 스냅샷으로 저장
  Future<bool> uploadSnapshot(Player player) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final snapshot = PvPSnapshot(
        userId: user.id,
        username: player.name.isEmpty ? 'Warrior_${user.id.substring(0, 4)}' : player.name,
        level: player.level,
        combatPower: player.combatPower,
        maxHp: player.maxHp,
        attack: player.attack.toDouble(),
        defense: player.defense.toDouble(),
        critChance: player.critChance,
        critDamage: player.critDamage,
        attackSpeed: player.attackSpeed,
        cdr: player.cdr,
        equippedItems: player.equipment.values.where((i) => i != null).cast<Item>().toList(),
        activeSkills: player.skills.where((s) => s.type == SkillType.active).toList(),
        passiveSkills: player.skills.where((s) => s.type == SkillType.passive).toList(),
        reincarnation: player.reincarnation,
        updatedAt: DateTime.now(),
      );

      // snapshots 테이블 업데이트
      await _supabase.from('pvp_snapshots').upsert({
        'user_id': user.id,
        'username': snapshot.username,
        'combat_power': snapshot.combatPower,
        'level': snapshot.level,
        'snapshot_data': snapshot.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // rankings 테이블에 기본 데이터가 없으면 자동 생성
      await _supabase.rpc('ensure_pvp_rank_entry', params: {'p_user_id': user.id});

      return true;
    } catch (e) {
      print('PvP 스냅샷 업로드 실패: $e');
      return false;
    }
  }

  /// [테스트용] 현재 플레이어의 클론을 생성하여 PvP 상대로 등록
  Future<bool> uploadClone(Player player, String cloneName) async {
    try {
      final String cloneUserId = _uuid.v4(); // 가상의 UUID 생성
      final user = _supabase.auth.currentUser;
      
      int currentScore = 1000;
      String currentTier = 'Bronze';

      // 1. 현재 내 랭킹 정보 조회
      if (user != null) {
        final rankData = await _supabase
            .from('pvp_rankings')
            .select('score, rank_tier')
            .eq('user_id', user.id)
            .maybeSingle();
        
        if (rankData != null) {
          currentScore = rankData['score'];
          currentTier = rankData['rank_tier'];
        }
      }

      final snapshot = PvPSnapshot(
        userId: cloneUserId,
        username: cloneName,
        level: player.level,
        combatPower: player.combatPower,
        maxHp: player.maxHp,
        attack: player.attack.toDouble(),
        defense: player.defense.toDouble(),
        critChance: player.critChance,
        critDamage: player.critDamage,
        attackSpeed: player.attackSpeed,
        cdr: player.cdr,
        equippedItems: player.equipment.values.where((i) => i != null).cast<Item>().toList(),
        activeSkills: player.skills.where((s) => s.type == SkillType.active).toList(),
        passiveSkills: player.skills.where((s) => s.type == SkillType.passive).toList(),
        reincarnation: player.reincarnation,
        updatedAt: DateTime.now(),
      );

      // snapshots 테이블에 삽입 (upsert 대신 insert)
      await _supabase.from('pvp_snapshots').insert({
        'user_id': cloneUserId,
        'username': snapshot.username,
        'combat_power': snapshot.combatPower,
        'level': snapshot.level,
        'snapshot_data': snapshot.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // rankings 테이블에도 강제 삽입 (RPC 대신 직접 insert)
      await _supabase.from('pvp_rankings').insert({
        'user_id': cloneUserId,
        'score': currentScore, // 복제 대상의 현재 점수 반영
        'wins': 0,
        'losses': 0,
        'rank_tier': currentTier, // 복제 대상의 현재 티어 반영
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('PvP 클론 생성 성공: $cloneName ($cloneUserId) - 점수: $currentScore');
      return true;
    } on PostgrestException catch (e) {
      print('PvP 클론 생성 DB 오류: [${e.code}] ${e.message}');
      return false;
    } catch (e) {
      print('PvP 클론 생성 예외 발생: $e');
      return false;
    }
  }

  /// 전역 Top 3 조회 (시상대용)
  Future<List<PvPRankEntry>> getTop3() async {
    return getTopRankings(limit: 3);
  }

  /// 특정 유저(나) 주변의 랭커 6명 조회 (상위 3명 + 나 + 하위 3명)
  Future<List<PvPRankEntry>> getNearMe(String userId) async {
    try {
      // 1. 내 점수 확인
      final meResponse = await _supabase
          .from('pvp_rankings')
          .select('score')
          .eq('user_id', userId)
          .maybeSingle(); // single() 대신 maybeSingle() 사용
      
      if (meResponse == null) {
        // 내가 랭킹에 없으면 Top 10 반환
        return getTopRankings(limit: 10);
      }
      
      final int myScore = meResponse['score'];

      // 2. 상위 3명
      final higher = await _supabase
          .from('pvp_rankings')
          .select('*, pvp_snapshots!inner(username, combat_power)')
          .gte('score', myScore)
          .neq('user_id', userId)
          .order('score', ascending: true)
          .limit(3);

      // 3. 하위 3명
      final lower = await _supabase
          .from('pvp_rankings')
          .select('*, pvp_snapshots!inner(username, combat_power)')
          .lt('score', myScore)
          .order('score', ascending: false)
          .limit(3);

      // 4. 나 자신 정보
      final mine = await _supabase
          .from('pvp_rankings')
          .select('*, pvp_snapshots!inner(username, combat_power)')
          .eq('user_id', userId)
          .maybeSingle();

      if (mine == null) {
        return getTopRankings(limit: 10);
      }

      // 결과 합치기 및 변환
      List<dynamic> combined = [];
      combined.addAll(higher);
      combined.add(mine);
      combined.addAll(lower);

      // 점수 내림차순 정렬
      combined.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      return combined.map((data) {
        final snapshot = data['pvp_snapshots'];
        return PvPRankEntry(
          userId: data['user_id'],
          username: snapshot['username'],
          score: data['score'],
          wins: data['wins'],
          losses: data['losses'],
          rankTier: data['rank_tier'],
          combatPower: snapshot['combat_power'],
        );
      }).toList();
    } catch (e) {
      print('주변 랭킹 조회 실패: $e');
      return [];
    }
  }

  /// 랭킹 리스트 조회 (범용)
  Future<List<PvPRankEntry>> getTopRankings({int limit = 50}) async {
    try {
      // rankings와 snapshots를 조인하여 유저 정보와 점수를 함께 가져옴
      final response = await _supabase
          .from('pvp_rankings')
          .select('*, pvp_snapshots!inner(username, combat_power)')
          .order('score', ascending: false)
          .limit(limit);

      return (response as List).map((data) {
        final snapshot = data['pvp_snapshots'];
        return PvPRankEntry(
          userId: data['user_id'],
          username: snapshot['username'],
          score: data['score'],
          wins: data['wins'],
          losses: data['losses'],
          rankTier: data['rank_tier'],
          combatPower: snapshot['combat_power'],
        );
      }).toList();
    } catch (e) {
      print('랭킹 조회 실패: $e');
      return [];
    }
  }

  /// 특정 유저의 스냅샷 조회 (대전 상대)
  Future<PvPSnapshot?> getSnapshot(String userId) async {
    try {
      final response = await _supabase
          .from('pvp_snapshots')
          .select()
          .eq('user_id', userId)
          .single();

      return PvPSnapshot.fromJson(response['snapshot_data']);
    } catch (e) {
      print('스냅샷 로드 실패: $e');
      return null;
    }
  }
  /// PvP 결과 반영 (점수 및 승패 업데이트)
  Future<Map<String, dynamic>?> updatePvPResult(String userId, bool isVictory) async {
    try {
      final int scoreChange = isVictory ? 20 : -10;
      
      // 현재 점수와 기록 가져오기
      final response = await _supabase
          .from('pvp_rankings')
          .select('score, wins, losses')
          .eq('user_id', userId)
          .single();
          
      int newScore = (response['score'] as int) + scoreChange;
      if (newScore < 0) newScore = 0; // 점수 음수 방지

      int newWins = (response['wins'] as int) + (isVictory ? 1 : 0);
      int newLosses = (response['losses'] as int) + (isVictory ? 0 : 1);

      await _supabase.from('pvp_rankings').update({
        'score': newScore,
        'wins': newWins,
        'losses': newLosses,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);

      return {
        'scoreChange': scoreChange,
        'newScore': newScore,
      };
    } catch (e) {
      print('PvP 결과 업데이트 실패: $e');
      return null;
    }
  }

  /// 전투 로그 저장
  Future<void> saveBattleLog(String attackerName, String defenderName, bool isVictory) async {
    try {
      await _supabase.from('pvp_battle_logs').insert({
        'attacker_name': attackerName,
        'defender_name': defenderName,
        'is_victory': isVictory,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      print('전투 로그 저장 실패: $e');
    }
  }

  /// 최근 전투 기록 조회
  Future<List<PvPBattleLog>> getRecentBattleLogs({int limit = 30}) async {
    try {
      final response = await _supabase
          .from('pvp_battle_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List).map((data) => PvPBattleLog.fromJson(data)).toList();
    } catch (e) {
      print('전투 기록 조회 실패: $e');
      return [];
    }
  }
  /// 시즌 초기화 (명예의 전당 및 랭킹 초기화)
  /// 시즌 초기화 (모든 데이터 완전 삭제)
  Future<bool> resetSeason() async {
    try {
      // 1. 모든 유저의 랭킹 정보 삭제
      await _supabase.from('pvp_rankings').delete().not('user_id', 'is', null);

      // 2. 모든 유저의 스냅샷 정보 삭제
      await _supabase.from('pvp_snapshots').delete().not('user_id', 'is', null);

      // 3. 전체 전투 로그 삭제
      await _supabase.from('pvp_battle_logs').delete().not('attacker_name', 'is', null);

      print('PvP 시즌 데이터 완전 초기화 완료');
      return true;
    } catch (e) {
      print('PvP 시즌 초기화 실패: $e');
      return false;
    }
  }
}
