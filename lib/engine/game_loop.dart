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
    final double rawDt = (elapsed.inMicroseconds - _lastElapsed.inMicroseconds) / 1000000.0;
    _lastElapsed = elapsed;

    // 🆕 [v2.5.1] 게임 루프 dt 보정: 극심한 프레임 드랍 시 로직 폭주 방지
    final double dt = rawDt > 0.1 ? 0.1 : rawDt;

    // 🆕 [최적화] 모든 계산 시작 전 알림 억제
    gameState.beginBatchUpdate();

    try {
      // 🆕 몬스터 소환 대기 처리 (isProcessingVictory와 무관하게 실행)
      final now = DateTime.now();
      
      // [v2.4.9] 타이머 시스템 업데이트 (애니메이션, 쿨타임 등)
      gameState.updateTimers(dt);

      if (gameState.pendingMonsterSpawn && gameState.monsterSpawnScheduledTime != null) {
        if (now.isAfter(gameState.monsterSpawnScheduledTime!)) {
          gameState.pendingMonsterSpawn = false;
          gameState.monsterSpawnScheduledTime = null;
          gameState.spawnMonster();
        }
      }

      if (gameState.currentMonster == null || gameState.isProcessingVictory) return;

      // 🆕 로직 누적 (전투 로직은 60FPS에 가깝게 처리하도록 임계치 하향)
      _logicAccumulator += dt;
      if (_logicAccumulator < 0.016) return;

      // 누적된 시간을 실제 전투 로직 처리 시간(tCombat)으로 사용
      double tCombat = _logicAccumulator;
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
        _attackAccumulator += tCombat;
      }

      double playerAttackInterval = 1.0 / gameState.player.attackSpeed;
      if (playerAttackInterval < 0.167) playerAttackInterval = 0.167; // 하드캡: 6.0 공속 (0.25 → 0.167)

      if (_attackAccumulator >= playerAttackInterval) {
        gameState.processCombatTurn();
        _attackAccumulator = 0;
      }

      // 2. 몬스터 공격 주기 처리 (기본 1.5초, 보스 광폭화 시 1.0초 등 가변 적용)
      _monsterAttackAccumulator += tCombat;
      if (_monsterAttackAccumulator >= gameState.monsterAttackInterval) {
        gameState.monsterPerformAttack();
        _monsterAttackAccumulator = 0;
      }

      // 3. 체력 재생 처리 (1틱 = 3초)
      _regenAccumulator += tCombat;
      if (_regenAccumulator >= 3.0) {
        gameState.applyRegen();
        _regenAccumulator = 0;
      }
    } finally {
      // 🆕 [최적화] 모든 계산이 끝난 후 단 한 번만 UI에 알림
      gameState.endBatchUpdate();
    }
  }

  void dispose() {
    _ticker.dispose();
  }
}
