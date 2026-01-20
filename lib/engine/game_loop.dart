import 'package:flutter/scheduler.dart';
import '../providers/game_state.dart';

class GameLoop {
  final GameState gameState;
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  
  // 공격 및 재생 주기를 위한 타이머 누적기
  double _attackAccumulator = 0;
  double _monsterAttackAccumulator = 0;
  double _regenAccumulator = 0;

  GameLoop(this.gameState) {
    _ticker = Ticker(_onTick);
  }

  void start() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void stop() {
    _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed.inMicroseconds - _lastElapsed.inMicroseconds) / 1000000.0;
    _lastElapsed = elapsed;

    if (gameState.currentMonster == null || gameState.isProcessingVictory) return;

    // 1. 플레이어 공격 주기 처리
    _attackAccumulator += dt;
    double playerAttackInterval = 1.0 / gameState.player.attackSpeed;
    if (playerAttackInterval < 0.25) playerAttackInterval = 0.25; // 하드캡

    if (_attackAccumulator >= playerAttackInterval) {
      gameState.processCombatTurn();
      _attackAccumulator = 0;
    }

    // 2. 몬스터 공격 주기 처리 (1.5초)
    _monsterAttackAccumulator += dt;
    if (_monsterAttackAccumulator >= 1.5) {
      gameState.monsterPerformAttack();
      _monsterAttackAccumulator = 0;
    }

    // 3. 체력 재생 처리 (1초)
    _regenAccumulator += dt;
    if (_regenAccumulator >= 1.0) {
      gameState.applyRegen();
      _regenAccumulator = 0;
    }
  }

  void dispose() {
    _ticker.dispose();
  }
}
