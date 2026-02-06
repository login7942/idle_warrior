import 'package:flutter/scheduler.dart';
import '../providers/game_state.dart';

class GameLoop {
  final GameState gameState;
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  
  // 공격 및 재생 주기를 위한 타이머 누적기
  double _attackAccumulator = 0;
  double _monsterAttackAccumulator = 0;
  double _defenderAttackAccumulator = 0; // 🆕 PvP 방어자 공격 누적기
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
    
    // 🆕 [최적화] 타겟 FPS에 도달하지 않았으면 업데이트 건너뛰기
    final double targetFrameTime = 1.0 / gameState.targetFps;
    if (rawDt < targetFrameTime && _lastElapsed != Duration.zero) {
      return; 
    }

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

      // [v2.7.5] PvP나 아레나 모드일 때는 몬스터가 없어도 로직이 진행되어야 함
      bool isTargetRequired = !gameState.isPvPMode && !gameState.isArenaMode;
      if ((isTargetRequired && gameState.currentMonster == null) || gameState.isProcessingVictory) return;

      // 🆕 로직 누적 (전투 로직은 최소 60FPS에 가깝게 처리하도록 임계치 하향하되, 타켓 FPS보다는 느리지 않게)
      _logicAccumulator += dt;
      if (_logicAccumulator < (targetFrameTime < 0.016 ? 0.016 : targetFrameTime)) return;

      // 누적된 시간을 실제 전투 로직 처리 시간(tCombat)으로 사용
      double tCombat = _logicAccumulator;
      _logicAccumulator = 0;

      // 🆕 0. 연타 스킬 타격 처리 (예약된 시간이 된 타격 실행)
      while (gameState.pendingHits.isNotEmpty) {
        final hit = gameState.pendingHits.first;
        if (now.isBefore(hit.scheduledTime)) break; // 아직 시간이 안됨
        
        gameState.pendingHits.removeFirst();
        
        if (gameState.isPvPMode) {
          // PvP 모드: 방어자 타격
          gameState.damageDefender(
            hit.damage,
            false,
            hit.isSkill,
            ox: hit.offsetX,
            oy: hit.offsetY,
            shouldAnimate: hit.shouldAnimate,
            skillIcon: hit.skillIcon,
            combo: hit.combo,
          );
        } else {
          // 일반 모드: 몬스터 타격
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
      }

      // 1. 플레이어 공격 주기 처리 (v0.1.x 직렬화 적용)
      // 연타 스킬(pendingHits)이 남아있는 동안에는 다음 공격 턴 게이지를 쌓지 않음
      // PvP 카운트다운 중에는 공격 불가
      if (gameState.pendingHits.isEmpty && (!gameState.isPvPMode || gameState.pvpCountdown <= 0)) {
        _attackAccumulator += tCombat;
      }

      double playerAttackInterval = 1.0 / gameState.player.attackSpeed;
      if (playerAttackInterval < 0.167) playerAttackInterval = 0.167; // 하드캡: 6.0 공속 (0.25 → 0.167)

      if (_attackAccumulator >= playerAttackInterval) {
        gameState.processCombatTurn();
        _attackAccumulator = 0;
      }

      // 2. 몬스터 또는 PvP 방어자 공격 주기 처리
      if (gameState.isPvPMode) {
        // PvP 모드: 방어자 공격 처리 (카운트다운 중엔 불가)
        if (gameState.pvpCountdown <= 0) {
          _defenderAttackAccumulator += tCombat;
          double defenderAttackInterval = 1.0 / (gameState.defenderSnapshot?.attackSpeed ?? 1.0);
          if (defenderAttackInterval < 0.167) defenderAttackInterval = 0.167;

          if (_defenderAttackAccumulator >= defenderAttackInterval) {
            gameState.processDefenderTurn();
            _defenderAttackAccumulator = 0;
          }
        }
      } else {
        // 일반 모드: 몬스터 공격 처리
        _monsterAttackAccumulator += tCombat;
        if (_monsterAttackAccumulator >= gameState.monsterAttackInterval) {
          gameState.monsterPerformAttack();
          _monsterAttackAccumulator = 0;
        }
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
