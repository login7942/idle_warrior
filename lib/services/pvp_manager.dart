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
        'score': 5000, // 테스트용으로 상단에 노출되도록 높은 점수 부여
        'wins': 100,
        'losses': 0,
        'rank_tier': 'Diamond',
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('PvP 클론 생성 성공: $cloneName ($cloneUserId)');
      return true;
    } on PostgrestException catch (e) {
      print('PvP 클론 생성 DB 오류: [${e.code}] ${e.message}');
      return false;
    } catch (e) {
      print('PvP 클론 생성 예외 발생: $e');
      return false;
    }
  }

  /// 랭킹 리스트 조회
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
}
