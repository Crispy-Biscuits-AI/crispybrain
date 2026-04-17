CREATE TABLE IF NOT EXISTS openbrain_chat_turns (
  id BIGSERIAL PRIMARY KEY,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  message_text TEXT NOT NULL,
  project_slug TEXT,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_openbrain_chat_turns_session_created_at
ON openbrain_chat_turns (session_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_openbrain_chat_turns_project_slug
ON openbrain_chat_turns (project_slug);

CREATE INDEX IF NOT EXISTS idx_openbrain_chat_turns_metadata_json
ON openbrain_chat_turns
USING gin (metadata_json);
