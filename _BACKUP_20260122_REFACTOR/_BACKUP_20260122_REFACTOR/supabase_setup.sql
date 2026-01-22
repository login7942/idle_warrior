-- Supabase 데이터베이스 설정 SQL
-- Supabase SQL Editor에서 실행하세요

-- 1. player_saves 테이블 생성
CREATE TABLE IF NOT EXISTS player_saves (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  save_data JSONB NOT NULL,
  version TEXT DEFAULT '0.0.47',
  last_saved_at TIMESTAMP DEFAULT NOW(),
  device_info TEXT,
  
  UNIQUE(user_id)
);

-- 2. 인덱스 생성 (성능 최적화)
CREATE INDEX IF NOT EXISTS idx_player_saves_user_id ON player_saves(user_id);
CREATE INDEX IF NOT EXISTS idx_player_saves_last_saved ON player_saves(last_saved_at);

-- 3. Row Level Security (RLS) 활성화
ALTER TABLE player_saves ENABLE ROW LEVEL SECURITY;

-- 4. RLS 정책 생성

-- 사용자는 자신의 데이터만 조회 가능
CREATE POLICY "Users can view own save"
  ON player_saves FOR SELECT
  USING (auth.uid() = user_id);

-- 사용자는 자신의 데이터만 삽입 가능
CREATE POLICY "Users can insert own save"
  ON player_saves FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 사용자는 자신의 데이터만 업데이트 가능
CREATE POLICY "Users can update own save"
  ON player_saves FOR UPDATE
  USING (auth.uid() = user_id);

-- 사용자는 자신의 데이터만 삭제 가능
CREATE POLICY "Users can delete own save"
  ON player_saves FOR DELETE
  USING (auth.uid() = user_id);

-- 완료!
-- 이제 Flutter 앱에서 클라우드 세이브를 사용할 수 있습니다.
