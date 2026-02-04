import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_state.dart';
import '../models/guide_data.dart';
import '../models/item.dart';
import 'package:flutter/services.dart';
import 'common_widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:intl/intl.dart';

class QuickMenuPanel extends StatefulWidget {
  const QuickMenuPanel({super.key});

  @override
  State<QuickMenuPanel> createState() => _QuickMenuPanelState();
}

class _QuickMenuPanelState extends State<QuickMenuPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: GlassContainer(
        borderRadius: 32,
        color: const Color(0xFF10121D).withOpacity(0.95),
        border: Border.all(color: Colors.white10),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAutomationTab(),
                  _buildGuideTab(),
                  _buildSystemTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.widgets_outlined, color: Colors.blueAccent, size: 24),
              SizedBox(width: 12),
              Text(
                '통합 관제 센터',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.blueAccent.withOpacity(0.15),
          border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.blueAccent,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: const [
          Tab(text: '자동화'),
          Tab(text: '가이드'),
          Tab(text: '시스템'),
        ],
      ),
    );
  }

  // --- [1. 자동화 탭] ---
  Widget _buildAutomationTab() {
    return Consumer<GameState>(
      builder: (context, gs, child) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildSectionTitle('전투 및 진행'),
            _buildToggleCard(
              title: '자동 스테이지 진행',
              subtitle: '처치 수 달성 시 자동으로 다음 스테이지로 이동',
              value: gs.autoAdvance,
              onChanged: (val) {
                gs.autoAdvance = val;
                gs.saveGameData();
              },
              icon: Icons.auto_mode,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('장비 분해 (계층 구조)'),
            _buildDismantleSettings(gs),
          ],
        );
      },
    );
  }

  Widget _buildDismantleSettings(GameState gs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          _buildSliderSelection(
            label: "기준 등급 이하",
            value: gs.autoDismantleGrade.toDouble() + 1,
            labels: ["OFF", "일반", "고급", "희귀", "영웅", "고유", "전설", "신화"],
            activeColor: gs.autoDismantleGrade == -1 
                ? Colors.grey 
                : ItemGrade.values[gs.autoDismantleGrade].color,
            onChanged: (v) {
              gs.autoDismantleGrade = v.toInt() - 1;
              gs.saveGameData();
            },
          ),
          const SizedBox(height: 20),
          _buildSliderSelection(
            label: "기준 티어 이하",
            value: gs.autoDismantleTier == -1 ? 0 : gs.autoDismantleTier.toDouble(),
            labels: ["OFF", "T1", "T2", "T3", "T4", "T5", "T6"],
            activeColor: Colors.blueAccent,
            onChanged: (v) {
              gs.autoDismantleTier = v == 0 ? -1 : v.toInt();
              gs.saveGameData();
            },
          ),
          if (gs.autoDismantleGrade != -1 && gs.autoDismantleTier != -1)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'T${gs.autoDismantleTier} ${ItemGrade.values[gs.autoDismantleGrade].name} 등급 계층 분해 활성화 중',
                style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  // --- [2. 가이드 탭] ---
  Widget _buildGuideTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildSectionTitle('시스템 가이드'),
        ...GameGuideData.automationGuides.map((g) => _buildGuideCard(g)),
        const SizedBox(height: 24),
        _buildSectionTitle('성장 공식'),
        ...GameGuideData.growthGuides.map((g) => _buildGuideCard(g)),
        const SizedBox(height: 24),
        _buildSectionTitle('자주 묻는 질문'),
        ...GameGuideData.faq.map((f) => _buildFaqCard(f['q']!, f['a']!)),
      ],
    );
  }

  // --- [3. 시스템 탭] ---
  Widget _buildSystemTab() {
    return Consumer<GameState>(
      builder: (context, gs, child) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildSectionTitle('계정 및 데이터'),
            _buildActionCard(
              title: gs.isCloudLoadFailed ? '⚠️ 클라우드 동기화 오류' : '클라우드 저장',
              subtitle: gs.isCloudLoadFailed 
                ? '서버 데이터를 불러오지 못했습니다. 현재 상태를 저장하려면 [강제 동기화]를 누르세요. (자동 저장 중지됨)'
                : '데이터를 서버에 강제 동기화합니다. (최근 저장: ${gs.lastCloudSaveTime != null ? DateFormat('HH:mm:ss').format(gs.lastCloudSaveTime!) : '기록 없음'})',
              icon: gs.isCloudLoadFailed ? Icons.cloud_off : Icons.cloud_upload_outlined,
              color: gs.isCloudLoadFailed ? Colors.redAccent : Colors.deepPurpleAccent,
              onTap: () async {
                if (gs.isCloudLoadFailed) {
                  // 동기화 재시도
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('서버 데이터를 다시 불러오는 중...'))
                  );
                  await gs.loadGameData();
                  if (!gs.isCloudLoadFailed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('동기화 성공! 최신 데이터를 불러왔습니다.'))
                    );
                  } else {
                    // 여전히 로드 실패 시 강제 저장 여부 묻기 (또는 그냥 로드 시도 안내)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('여전히 서버에 연결할 수 없습니다. 네트워크를 확인해주세요.'))
                    );
                  }
                } else {
                  gs.saveGameData(forceCloud: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('클라우드 저장이 완료되었습니다.'))
                  );
                }
              },
              trailing: gs.isCloudLoadFailed ? ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2)),
                onPressed: () {
                  // 강제로 현재 1레벨(혹은 로컬 데이터)을 클라우드에 덮어씌움
                  gs.saveGameData(forceCloud: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('현재 상태를 서버에 강제 저장(덮어쓰기)했습니다.'))
                  );
                },
                child: const Text('강제 덮어쓰기', style: TextStyle(color: Colors.orangeAccent, fontSize: 10)),
              ) : null,
            ),
            const SizedBox(height: 12),
            // 구글 로그인 연동 버튼 추가
            if (gs.authService.isAnonymous)
              _buildActionCard(
                title: '구글 계정 연동',
                subtitle: '현재 익명 계정을 구글 계정에 연결하여 데이터를 보호합니다.',
                icon: Icons.account_circle_outlined,
                onTap: () async {
                  final success = await gs.authService.signInWithGoogle();
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('구글 계정 연동 성공! 데이터를 안전하게 보관합니다.'))
                    );
                    gs.saveGameData(forceCloud: true);
                  }
                },
              )
            else
              _buildInfoCard('로그인 계정', gs.authService.userEmail ?? '알 수 없는 계정', Icons.email_outlined),
            
            const SizedBox(height: 12),
            _buildActionCard(
              title: '로그아웃',
              subtitle: '다른 계정으로 로그인하거나 게임을 종료합니다.',
              icon: Icons.logout_rounded,
              onTap: () {
                gs.authService.signOut();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('고객 지원 정보 (인식표)'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('유저 고유 ID (User ID)', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          gs.authService.userId ?? '미인증 상태',
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16, color: Colors.white24),
                        onPressed: () {
                          if (gs.authService.userId != null) {
                            Clipboard.setData(ClipboardData(text: gs.authService.userId!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('User ID가 클립보드에 복사되었습니다.'))
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('게임 환경'),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.hasData 
                    ? 'v${snapshot.data!.version}+${snapshot.data!.buildNumber}' 
                    : '로딩 중...';
                return _buildInfoCard('앱 버전', version, Icons.info_outline);
              },
            ),
            _buildInfoCard('빌드 환경', 'Stable Production', Icons.terminal_outlined),
          ],
        );
      },
    );
  }

  // --- [UI Helper Methods] ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.blueAccent, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blueAccent,
            activeTrackColor: Colors.blueAccent.withOpacity(0.3),
            inactiveThumbColor: Colors.white12,
            inactiveTrackColor: Colors.white.withOpacity(0.05),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.blueAccent, // 기본값
    Widget? trailing, // 🆕 추가
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color.withOpacity(0.7), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ] else 
              const Icon(Icons.chevron_right, color: Colors.white12, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideCard(GuideEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(entry.icon, color: Colors.amberAccent.withOpacity(0.5), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(entry.content, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqCard(String q, String a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Q. $q', style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(a, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white24),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white24, fontSize: 13)),
            ],
          ),
          Text(value, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSliderSelection({
    required String label,
    required double value,
    required List<String> labels,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
            Text(
              labels[value.toInt()],
              style: TextStyle(color: activeColor, fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: activeColor.withOpacity(0.5),
            inactiveTrackColor: Colors.white.withOpacity(0.05),
            thumbColor: activeColor,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
            activeTickMarkColor: activeColor,
            inactiveTickMarkColor: Colors.white12,
          ),
          child: Slider(
            value: value,
            min: 0,
            max: (labels.length - 1).toDouble(),
            divisions: labels.length - 1,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
