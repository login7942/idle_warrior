import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_state.dart';
import '../models/reincarnation.dart';
import '../main.dart'; // GlassContainer, PopBtn 등 사용

class ReincarnationPanel extends StatelessWidget {
  const ReincarnationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gs, child) {
        final player = gs.player;
        final re = player.reincarnation;
        final canReincarnate = player.level >= 200;
        final earnedPoints = gs.reincarnationPointsEarned;

        return Column(
          children: [
            const SizedBox(height: 16),
            _buildHeader(re),
            const SizedBox(height: 16),
            _buildReincarnateButton(context, gs, canReincarnate, earnedPoints),
            const SizedBox(height: 16),
            Expanded(
              child: _buildPerkList(gs, re),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(ReincarnationData re) {
    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildHeaderStat('💎 환생 횟수', '${re.reincarnationCount}회'),
          _buildHeaderStat('🔮 보유 포인트', '${re.points}pt'),
          _buildHeaderStat('✨ 누적 포인트', '${re.totalPointsEarned}pt'),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildReincarnateButton(BuildContext context, GameState gs, bool canRe, int points) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: PressableScale(
        onTap: canRe ? () => _showReincarnateConfirm(context, gs, points) : null,
        child: GlassContainer(
          padding: const EdgeInsets.all(20),
          borderRadius: 24,
          color: canRe ? Colors.deepPurpleAccent.withValues(alpha: 0.2) : Colors.white10,
          border: Border.all(color: canRe ? Colors.deepPurpleAccent.withValues(alpha: 0.4) : Colors.white12, width: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, color: canRe ? Colors.amberAccent : Colors.white24, size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    canRe ? '환생 가능!' : '환생 조건 미달 (Lv.200 필요)',
                    style: TextStyle(
                      color: canRe ? Colors.white : Colors.white24,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (canRe)
                    Text(
                      '환생 시 $points 포인트를 획득합니다.',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPerkList(GameState gs, ReincarnationData re) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: re.perks.length,
      itemBuilder: (context, index) {
        final perk = re.perks[index];
        return _buildPerkCard(gs, re, perk);
      },
    );
  }

  Widget _buildPerkCard(GameState gs, ReincarnationData re, ReincarnationPerk perk) {
    final canUpgrade = re.points > 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        padding: const EdgeInsets.all(12),
        borderRadius: 16,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(perk.icon, style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(perk.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 6),
                      Text('Lv.${perk.level}', style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(perk.description, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  const SizedBox(height: 4),
                  Text(
                    '현재 효과: +${perk.bonusValue.toStringAsFixed(perk.valuePerPoint < 0.1 ? 2 : 1)}${perk.unit}',
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PopBtn(
              '강화',
              canUpgrade ? Colors.blueAccent : Colors.white10,
              () => gs.upgradeReincarnationPerk(perk.id),
              isFull: false,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ],
        ),
      ),
    );
  }

  void _showReincarnateConfirm(BuildContext context, GameState gs, int points) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🌌 환생하시겠습니까?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '환생 시 다음 항목이 초기화됩니다:',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text('• 캐릭터 레벨 (→ 1)', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Text('• 현재 스테이지 (→ 1층)', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Text('• 보유 골드 (→ 0)', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 16),
            const Text(
              '장비, 강화, 펫, 스킬은 유지됩니다.',
              style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '획득 포인트: $points pt',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurpleAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(context);
              gs.executeReincarnation();
            },
            child: const Text('환생 실행', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
