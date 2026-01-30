import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_state.dart';
import '../models/npc.dart';
import 'common_widgets.dart';

class ArenaPanel extends StatelessWidget {
  const ArenaPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        if (gameState.isArenaMode) {
          return _buildBattleScene(gameState);
        }

        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShadowText('🏟️ 16강 무투회', fontSize: 28, fontWeight: FontWeight.bold),
              const SizedBox(height: 8),
              if (gameState.tournamentRound == 5)
                const Text('오늘의 대회가 종료되었습니다.', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))
              else
                const Text('가상의 강자들과 대결하여 우심을 차지하세요!', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              
              if (gameState.tournamentRound == 0)
                _buildEntryScreen(gameState)
              else if (gameState.tournamentRound == 5)
                _buildFinalResultScreen(gameState)
              else
                _buildTournamentBracket(gameState),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBattleScene(GameState gameState) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ShadowText('💥 결투 중 💥', fontSize: 24, color: Colors.redAccent),
          const SizedBox(height: 40),
          // 전투 현황 시각화
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildBattleUnit('나', gameState.playerCurrentHp, gameState.player.maxHp, true),
              const Text('VS', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white30)),
              _buildBattleUnit(gameState.currentOpponent?.name ?? '상대', gameState.monsterCurrentHp, gameState.currentOpponent?.maxHp ?? 100, false),
            ],
          ),
          const SizedBox(height: 60),
          const CircularProgressIndicator(color: Colors.redAccent),
          const SizedBox(height: 20),
          const Text('전투가 실시간으로 진행 중입니다...', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 10),
          const Text('(전투 탭의 엔진을 공유하여 진행됩니다)', style: TextStyle(color: Colors.white24, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildBattleUnit(String name, int hp, int maxHp, bool isPlayer) {
    double hpPerc = (hp / maxHp).clamp(0.0, 1.0);
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: isPlayer ? Colors.blue.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: isPlayer ? Colors.blueAccent : Colors.redAccent, width: 2),
            boxShadow: [
              BoxShadow(color: (isPlayer ? Colors.blue : Colors.red).withOpacity(0.3), blurRadius: 10),
            ],
          ),
          child: Center(
            child: Text(isPlayer ? '👤' : '👹', style: const TextStyle(fontSize: 40)),
          ),
        ),
        const SizedBox(height: 12),
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        // HP Bar
        Container(
          width: 100,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: hpPerc,
            child: Container(
              decoration: BoxDecoration(
                color: isPlayer ? Colors.greenAccent : Colors.redAccent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEntryScreen(GameState gameState) {
    return Expanded(
      child: Center(
        child: GlassContainer(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium, size: 80, color: Colors.amber),
              const SizedBox(height: 24),
              const Text('오늘의 무투회가 아직 시작되지 않았습니다.', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 32),
              PopBtn(
                '무투회 참여하기 (일 1회)', 
                Colors.amber.shade700, 
                () => gameState.generateTournament(),
                isFull: false,
                icon: Icons.play_arrow,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinalResultScreen(GameState gameState) {
    bool isWinner = gameState.tournamentResults.isNotEmpty && gameState.tournamentResults.last && gameState.tournamentResults.length >= 4;
    return Expanded(
      child: Center(
        child: GlassContainer(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isWinner ? Icons.emoji_events : Icons.sentiment_dissatisfied, 
                size: 80, 
                color: isWinner ? Colors.amber : Colors.grey
              ),
              const SizedBox(height: 24),
              Text(
                isWinner ? '무투회 최종 우승!' : '대회 탈락', 
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 12),
              Text(
                isWinner ? '당신은 오늘의 가장 강력한 전사입니다.' : '내일 다시 도전하세요.', 
                style: const TextStyle(color: Colors.white70)
              ),
              const SizedBox(height: 32),
              PopBtn(
                '기록 닫기', 
                Colors.blueGrey, 
                () => gameState.tournamentRound = 0,
                isFull: false,
                icon: Icons.refresh,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTournamentBracket(GameState gameState) {
    String roundName = '';
    switch (gameState.tournamentRound) {
      case 1: roundName = '16강전'; break;
      case 2: roundName = '8강전'; break;
      case 3: roundName = '4강전'; break;
      case 4: roundName = '결승전'; break;
    }

    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(roundName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueAccent)),
              ],
            ),
          ),
          const SizedBox(height: 40),
          _buildCurrentMatchCard(gameState),
          const Spacer(),
          const Text('남은 경쟁자들', style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: gameState.tournamentNPCs.length,
              itemBuilder: (context, idx) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.white10,
                  child: const Text('👹', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCurrentMatchCard(GameState gameState) {
    // 플레이어는 항상 index 0과 싸운다고 가정 (NPC 리스트가 줄어듦)
    final opponent = gameState.tournamentNPCs.isNotEmpty ? gameState.tournamentNPCs[0] : null;
    
    if (opponent == null) return const SizedBox.shrink();

    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildParticipant(gameState.player.name, '나', true),
              const ShadowText('VS', fontSize: 32, fontWeight: FontWeight.bold, color: Colors.redAccent),
              _buildParticipant(opponent.name, opponent.category.name, false, npc: opponent),
            ],
          ),
          const SizedBox(height: 32),
          PopBtn(
            '결투장에 입장하기', 
            Colors.redAccent, 
            () => gameState.startArenaMatch(0),
            isFull: true,
            icon: Icons.sports_martial_arts,
          ),
        ],
      ),
    );
  }

  Widget _buildParticipant(String name, String label, bool isPlayer, {TournamentNPC? npc}) {
    bool isChampion = npc != null && name.contains('👑');
    
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: isPlayer ? Colors.blue.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isChampion ? Colors.amber : (isPlayer ? Colors.blue : Colors.red), 
                  width: isChampion ? 3 : 2
                ),
                boxShadow: isChampion ? [BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 10)] : null,
              ),
              child: Center(
                child: Text(isPlayer ? '👤' : '👹', style: const TextStyle(fontSize: 36)),
              ),
            ),
            if (isChampion)
              Positioned(
                top: -10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('CHAMPION', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black)),
                ),
              ),
            // 특수 능력 아이콘 표시
            if (npc != null && !isPlayer)
              Positioned(
                bottom: -5,
                right: -5,
                child: Row(
                  children: [
                    if (npc.executeChance > 0) _buildTraitIcon('💀', Colors.red),
                    if (npc.lifestealPerc > 0) _buildTraitIcon('🩸', Colors.green),
                    if (npc.reflectPerc > 0) _buildTraitIcon('⚡', Colors.blue),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isChampion ? Colors.amber : Colors.white)),
        Text(
          label == 'offensive' ? '공격형' : 
          label == 'defensive' ? '방어형' : 
          label == 'skill' ? '기능형' : 
          label == 'balanced' ? '밸런스형' : label, 
          style: const TextStyle(fontSize: 11, color: Colors.white54)
        ),
      ],
    );
  }

  Widget _buildTraitIcon(String emoji, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black87,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 8)),
    );
  }
}
