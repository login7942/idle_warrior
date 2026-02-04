import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../providers/game_state.dart';
import '../models/pvp_snapshot.dart';
import '../models/item.dart';
import '../models/skill.dart';
import '../models/player.dart';
import '../services/pvp_manager.dart';
import 'common_widgets.dart';

class RankingPanel extends StatefulWidget {
  final void Function(String, {bool isError}) onShowToast;
  final VoidCallback onNavigateToTab;

  const RankingPanel({super.key, required this.onShowToast, required this.onNavigateToTab});

  @override
  State<RankingPanel> createState() => _RankingPanelState();
}

class _RankingPanelState extends State<RankingPanel> {
  final PvPManager _pvpManager = PvPManager();
  List<PvPRankEntry>? _top3;
  List<PvPRankEntry>? _nearMe;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRankings();
  }

  Future<void> _loadRankings() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    
    final top3List = await _pvpManager.getTop3();
    List<PvPRankEntry>? nearMeList;
    
    if (userId != null) {
      nearMeList = await _pvpManager.getNearMe(userId);
    } else {
      nearMeList = await _pvpManager.getTopRankings(limit: 7);
    }

    setState(() {
      _top3 = top3List;
      _nearMe = nearMeList;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
              : (_top3 == null || _top3!.isEmpty)
                ? _buildEmptyState()
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildListSectionHeader('🏆 전설의 전당 (TOP 3)', isGold: true),
                        const SizedBox(height: 12),
                        _buildTop3Podium(),
                        const SizedBox(height: 24),
                        _buildListSectionHeader('⚔️ 실시간 라이벌 매칭 (내 주변)'),
                        const SizedBox(height: 12),
                        _buildNearMeList(),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 60), // 바텀 메뉴 여백
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.leaderboard, color: Colors.amber, size: 28),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('명예의 전당', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text('최강의 전사들이 이름을 올린 기록입니다.', 
                style: TextStyle(color: Colors.white38, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 🆕 내 정보 갱신 버튼 추가
        IconButton(
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tooltip: '내 정보 최신화',
          icon: const Icon(Icons.cloud_upload, color: Colors.blueAccent, size: 22),
          onPressed: () async {
            final gs = context.read<GameState>();
            final success = await _pvpManager.uploadSnapshot(gs.player);
            if (success) {
              widget.onShowToast('내 랭킹 정보가 최신으로 갱신되었습니다!', isError: false);
              _loadRankings(); 
            } else {
              widget.onShowToast('정보 갱신 실패. 로그인을 확인하세요.', isError: true);
            }
          },
        ),
        IconButton(
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tooltip: '랭킹 새로고침',
          icon: const Icon(Icons.refresh, color: Colors.white54, size: 22),
          onPressed: _loadRankings,
        ),
        // 🆕 최근 전투 기록 버튼 추가
        IconButton(
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tooltip: '최근 전투 기록',
          icon: const Icon(Icons.history, color: Colors.amberAccent, size: 22),
          onPressed: _showBattleLogs,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history_edu, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          const Text('랭킹 데이터가 없습니다.', style: TextStyle(color: Colors.white24)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () async {
              final gs = context.read<GameState>();
              final success = await _pvpManager.uploadSnapshot(gs.player);
              if (success) {
                widget.onShowToast('랭킹 등록이 완료되었습니다!', isError: false);
                _loadRankings(); // 등록 후 즉시 리스트 갱신
              } else {
                widget.onShowToast('랭킹 등록에 실패했습니다. 로그인을 확인하세요.', isError: true);
              }
            },
            child: const Text('내 랭킹 등록하기'),
          ),
        ],
      ),
    );
  }


  Widget _buildRankItem(int rank, PvPRankEntry entry) {
    final bool isMe = entry.userId == Supabase.instance.client.auth.currentUser?.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: PressableScale(
        onTap: () => _showOpponentDetail(entry),
        child: GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 15,
          border: Border.all(color: isMe ? Colors.blueAccent.withOpacity(0.3) : Colors.white.withValues(alpha: 0.05)),
          color: isMe ? Colors.blueAccent.withOpacity(0.05) : Colors.white.withValues(alpha: 0.02),
          child: Row(
            children: [
              _buildRankBadge(rank),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.username, style: TextStyle(color: isMe ? Colors.blueAccent : Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildMiniInfo('⚔️', entry.combatPower.toString()),
                        const SizedBox(width: 8),
                        _buildMiniInfo('⭐', '${entry.score} pts'),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isMe)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 정보 버튼 (상세 보기)
                    GestureDetector(
                      onTap: () => _showOpponentDetail(entry),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('정보', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 도전 버튼 (즉시 전투)
                    GestureDetector(
                      onTap: () async {
                        setState(() => _isLoading = true);
                        final snapshot = await _pvpManager.getSnapshot(entry.userId);
                        setState(() => _isLoading = false);
                        if (snapshot != null) {
                          _challengeWithSnapshot(snapshot);
                        } else {
                          widget.onShowToast('유저 데이터를 불러올 수 없습니다.', isError: true);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                        ),
                        child: const Text('도전', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListSectionHeader(String title, {bool isGold = false}) {
    return Row(
      children: [
        Container(
          width: 4, 
          height: 18, 
          decoration: BoxDecoration(
            color: isGold ? Colors.amber : Colors.blueAccent, 
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(color: (isGold ? Colors.amber : Colors.blueAccent).withOpacity(0.5), blurRadius: 4),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title, 
          style: TextStyle(
            color: isGold ? Colors.amber : Colors.white70, 
            fontSize: 14, 
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          )
        ),
      ],
    );
  }

  Widget _buildTop3Podium() {
    if (_top3 == null || _top3!.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (_top3!.length > 1) Expanded(child: _buildSimpleTopCard(_top3![1], 2)),
          const SizedBox(width: 8),
          if (_top3!.isNotEmpty) Expanded(child: _buildSimpleTopCard(_top3![0], 1)),
          const SizedBox(width: 8),
          if (_top3!.length > 2) Expanded(child: _buildSimpleTopCard(_top3![2], 3)),
        ],
      ),
    );
  }

  Widget _buildSimpleTopCard(PvPRankEntry entry, int rank) {
    Color medalColor = Colors.amber;
    String trophy = '🏆';
    if (rank == 2) { medalColor = const Color(0xFFC0C0C0); trophy = '🥈'; }
    if (rank == 3) { medalColor = const Color(0xFFCD7F32); trophy = '🥉'; }

    return PressableScale(
      onTap: () => _showOpponentDetail(entry),
      child: GlassContainer(
        padding: const EdgeInsets.all(12),
        borderRadius: 16,
        border: Border.all(color: medalColor.withValues(alpha: 0.3), width: 1.5),
        color: medalColor.withValues(alpha: 0.05),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(trophy, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              entry.username, 
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${entry.score} pts', 
              style: TextStyle(color: medalColor.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // 🆕 도전하기 버튼 추가
            GestureDetector(
              onTap: () async {
                setState(() => _isLoading = true);
                final snapshot = await _pvpManager.getSnapshot(entry.userId);
                setState(() => _isLoading = false);
                if (snapshot != null) {
                  _challengeWithSnapshot(snapshot);
                } else {
                  widget.onShowToast('유저 데이터를 불러올 수 없습니다.', isError: true);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: const Text('도전하기', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildNearMeList() {
    if (_nearMe == null || _nearMe!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.info_outline, color: Colors.white10, size: 40),
            const SizedBox(height: 12),
            const Text('주변에 대전 가능한 유저가 없습니다.', style: TextStyle(color: Colors.white24, fontSize: 13)),
          ],
        ),
      );
    }
    return Column(
      children: _nearMe!.asMap().entries.map((e) {
        final index = e.key;
        final entry = e.value;
        // 실제 랭킹 숫자를 알기 어려우므로 라이벌 아이콘 표시
        return _buildRankItem(0, entry); 
      }).toList(),
    );
  }

  Widget _buildRankBadge(int rank) {
    // 리스트 아이템의 배지 수정 (rank가 0이면 점수 아이콘 표시)
    if (rank == 0) {
      return Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
        child: const Icon(Icons.person_search, color: Colors.blueAccent, size: 16),
      );
    }
    
    Color color = Colors.white54;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Text('$rank', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildMiniInfo(String icon, String value) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 10)),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  Future<void> _showOpponentDetail(PvPRankEntry entry) async {
    setState(() => _isLoading = true);
    final snapshot = await _pvpManager.getSnapshot(entry.userId);
    setState(() => _isLoading = false);

    if (snapshot != null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => _OpponentDetailDialog(
          snapshot: snapshot,
          rankEntry: entry,
          onChallenge: () {
            Navigator.pop(context);
            _challengeWithSnapshot(snapshot);
          },
        ),
      );
    } else {
      widget.onShowToast('유저 데이터를 불러올 수 없습니다.', isError: true);
    }
  }

  Future<void> _challengeWithSnapshot(PvPSnapshot snapshot) async {
    final gs = context.read<GameState>();
    
    // 🆕 대전 시작 전 내 정보 자동 최신화
    await _pvpManager.uploadSnapshot(gs.player);
    
    // 화면 전환 후 상태 변경
    widget.onNavigateToTab();

    // 빌드 프레임 이후에 상태 업데이트 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gs.startPvPBattle(snapshot);
      widget.onShowToast('${snapshot.username} 유저와 대전을 시작합니다!');
    });
  }

  Future<void> _showBattleLogs() async {
    setState(() => _isLoading = true);
    final logs = await _pvpManager.getRecentBattleLogs();
    setState(() => _isLoading = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassContainer(
          borderRadius: 20,
          border: Border.all(color: Colors.white10),
          color: const Color(0xFF1A1D2E).withOpacity(0.95),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('⚔️ 최근 전투 기록', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                child: logs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text('기록된 전투가 없습니다.', style: TextStyle(color: Colors.white24)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: logs.length,
                        separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          final timeStr = "${log.createdAt.hour.toString().padLeft(2, '0')}:${log.createdAt.minute.toString().padLeft(2, '0')}";
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Text('[$timeStr]', style: const TextStyle(color: Colors.white24, fontSize: 11)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      children: [
                                        TextSpan(text: log.attackerName, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                        const TextSpan(text: ' 이(가) '),
                                        TextSpan(text: log.defenderName, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                        const TextSpan(text: ' 에게 '),
                                        TextSpan(
                                          text: log.isVictory ? '승리했습니다.' : '패배했습니다.',
                                          style: TextStyle(
                                            color: log.isVictory ? Colors.greenAccent : Colors.orangeAccent,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpponentDetailDialog extends StatelessWidget {
  final PvPSnapshot snapshot;
  final PvPRankEntry rankEntry;
  final VoidCallback onChallenge;

  const _OpponentDetailDialog({
    required this.snapshot, 
    required this.rankEntry,
    required this.onChallenge
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: GlassContainer(
          borderRadius: 20,
          border: Border.all(color: Colors.white10),
          color: const Color(0xFF1A1D2E).withOpacity(0.95),
          child: Column(
            children: [
              _buildHeader(context),
              const TabBar(
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.blueAccent,
                unselectedLabelColor: Colors.white38,
                tabs: [
                  Tab(text: '능력치'),
                  Tab(text: '장비'),
                  Tab(text: '스킬'),
                  Tab(text: '환생'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildStatsTab(),
                    _buildEquipmentTab(),
                    _buildSkillsTab(),
                    _buildReincarnationTab(),
                  ],
                ),
              ),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: const Center(child: Text('🛡️', style: TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(snapshot.username, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                      child: Text('Lv.${snapshot.level}', style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${rankEntry.rankTier} | ${rankEntry.score} pts', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildStatRow('전투력', BigNumberFormatter.format(snapshot.combatPower), color: Colors.amber),
        const Divider(color: Colors.white10),
        _buildStatRow('공격력', BigNumberFormatter.format(snapshot.attack)),
        _buildStatRow('방어력', BigNumberFormatter.format(snapshot.defense)),
        _buildStatRow('최대 체력', BigNumberFormatter.format(snapshot.maxHp)),
        const SizedBox(height: 10),
        _buildStatRow('치명타 확률', '${snapshot.critChance.toStringAsFixed(1)}%'),
        _buildStatRow('치명타 피해', '${snapshot.critDamage.toStringAsFixed(0)}%'),
        _buildStatRow('공격 속도', '${snapshot.attackSpeed.toStringAsFixed(2)}s'),
        _buildStatRow('쿨타임 감소', '${snapshot.cdr.toStringAsFixed(1)}%'),
        const SizedBox(height: 10),
        _buildStatRow('보호막 확률', '${snapshot.gainShieldChance.toStringAsFixed(1)}%', color: Colors.cyanAccent),
        _buildStatRow('2연타 확률', '${snapshot.doubleHitChance.toStringAsFixed(1)}%', color: Colors.orangeAccent),
        _buildStatRow('흡혈 확률', '${snapshot.lifesteal.toStringAsFixed(1)}%', color: Colors.greenAccent),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEquipmentTab() {
    if (snapshot.equippedItems.isEmpty) {
      return const Center(child: Text('장착된 장비가 없습니다.', style: TextStyle(color: Colors.white24)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: snapshot.equippedItems.length,
      itemBuilder: (context, index) {
        final item = snapshot.equippedItems[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: item.grade.color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Text(item.type.iconEmoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item.name} +${item.enhanceLevel}', style: TextStyle(color: item.grade.color, fontWeight: FontWeight.bold)),
                    Text('T${item.tier} ${item.type.nameKr}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(BigNumberFormatter.format(item.effectiveMainStat1.toDouble()), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(item.mainStatName1, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkillsTab() {
    final allSkills = [...snapshot.activeSkills, ...snapshot.passiveSkills];
    if (allSkills.isEmpty) {
      return const Center(child: Text('배운 스킬이 없습니다.', style: TextStyle(color: Colors.white24)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: allSkills.length,
      itemBuilder: (context, index) {
        final skill = allSkills[index];
        final bool isActive = snapshot.activeSkills.contains(skill);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? Colors.blueAccent.withOpacity(0.05) : Colors.amberAccent.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? Colors.blueAccent.withOpacity(0.2) : Colors.amberAccent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Text(skill.iconEmoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(skill.name, style: TextStyle(color: isActive ? Colors.blueAccent : Colors.amberAccent, fontWeight: FontWeight.bold)),
                    Text('Lv.${skill.level} | ${isActive ? '액티브' : '패시브'}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReincarnationTab() {
    final r = snapshot.reincarnation;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text('환생 단계', style: TextStyle(color: Colors.purpleAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${r.reincarnationCount}단계', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('영혼 포인트 ${r.totalPointsEarned}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('획득 특성', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
          ...r.perks.where((p) => p.level > 0).map((p) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${p.icon} ${p.name}', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                Text('+${p.bonusValue.toStringAsFixed(1)}${p.unit}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final bool isMe = snapshot.userId == Supabase.instance.client.auth.currentUser?.id;
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: PopBtn('닫기', Colors.grey, () => Navigator.pop(context), isFull: false),
          ),
          if (!isMe) ...[
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: PopBtn('도전하기', Colors.redAccent, onChallenge, isFull: false),
            ),
          ],
        ],
      ),
    );
  }
}
