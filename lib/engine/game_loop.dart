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
  double _logicAccumulator = 0; // 🆕 로직 쓰로틀링용 누적기

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

    // 🆕 0-1. 몬스터 소환 대기 처리 (isProcessingVictory와 무관하게 실행)
    final now = DateTime.now();
    if (gameState.pendingMonsterSpawn && gameState.monsterSpawnScheduledTime != null) {
      if (now.isAfter(gameState.monsterSpawnScheduledTime!)) {
        gameState.pendingMonsterSpawn = false;
        gameState.monsterSpawnScheduledTime = null;
        gameState.spawnMonster();
      }
    }

    if (gameState.currentMonster == null || gameState.isProcessingVictory) return;

    // 🆕 30FPS 쓰로틀링: 33ms가 쌓일 때까지 로직 실행 연기
    _logicAccumulator += dt;
    if (_logicAccumulator < 0.033) return;

    // 누적된 시간을 실제 로직 처리 시간(t)으로 사용
    double t = _logicAccumulator;
    _logicAccumulator = 0;

    // 🆕 0. 연타 스킬 타격 처리 (예약된 시간이 된 타격 실행)
    while (gameState.pendingHits.isNotEmpty) {
      final hit = gameState.pendingHits.first;
      if (now.isBefore(hit.scheduledTime)) break; // 아직 시간이 안됨
      
      gameState.pendingHits.removeFirst();
      
      // 몬스터가 이미 죽었으면 스킵
      if (gameState.currentMonster == null || gameState.currentMonster!.isDead) continue;
      
      // 타격 실행
      gameState.damageMonster(
        hit.damage,
        false,
        hit.isSkill,
        ox: hit.offsetX,
        oy: hit.offsetY,
        shouldAnimate: hit.shouldAnimate,
        skillIcon: hit.skillIcon, // 🆕 아이콘 전달
        combo: hit.combo, // 🆕 콤보 정보 전달
      );
    }

    // 1. 플레이어 공격 주기 처리 (v0.1.x 직렬화 적용)
    // 연타 스킬(pendingHits)이 남아있는 동안에는 다음 공격 턴 게이지를 쌓지 않음
    if (gameState.pendingHits.isEmpty) {
      _attackAccumulator += t;
    }

    double playerAttackInterval = 1.0 / gameState.player.attackSpeed;
    if (playerAttackInterval < 0.167) playerAttackInterval = 0.167; // 하드캡: 6.0 공속 (0.25 → 0.167)

    if (_attackAccumulator >= playerAttackInterval) {
      gameState.processCombatTurn();
      _attackAccumulator = 0;
    }

    // 2. 몬스터 공격 주기 처리 (1.5초)
    _monsterAttackAccumulator += t;
    if (_monsterAttackAccumulator >= 1.5) {
      gameState.monsterPerformAttack();
      _monsterAttackAccumulator = 0;
    }

    // 3. 체력 재생 처리 (1초)
    _regenAccumulator += t;
    if (_regenAccumulator >= 1.0) {
      gameState.applyRegen();
      _regenAccumulator = 0;
    }
  }

  void dispose() {
    _ticker.dispose();
  }
}
