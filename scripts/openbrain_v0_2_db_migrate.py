#!/usr/bin/env python3
"""
CrispyBrain v0.2 database backup + migration script

What this script does:
1. Creates a timestamped PostgreSQL backup using pg_dump
2. Applies the canonical CrispyBrain v0.2 additive schema contract
3. Adds new nullable columns to the existing memories table
4. Creates new CrispyBrain v0.2 tables
5. Creates recommended indexes

How to use:
    export PGHOST=localhost
    export PGPORT=5432
    export PGDATABASE=n8n
    export PGUSER=n8n
    export PGPASSWORD=your_password

    python3 openbrain_v0_2_db_migrate.py

Optional:
    export BACKUP_DIR=./db_backups
    export PGDUMP_PATH=pg_dump
    export SKIP_BACKUP=1
"""

from __future__ import annotations

import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Iterable

try:
    import psycopg  # psycopg3
    DRIVER = "psycopg3"
except Exception:
    psycopg = None
    DRIVER = None

if psycopg is None:
    try:
        import psycopg2  # type: ignore
        from psycopg2.extensions import connection as PGConnection  # type: ignore
        DRIVER = "psycopg2"
    except Exception:
        psycopg2 = None
    else:
        psycopg2 = psycopg2
else:
    psycopg2 = None


def require_env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if value is None or value == "":
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def get_db_config() -> dict[str, str]:
    return {
        "host": require_env("PGHOST", "localhost"),
        "port": require_env("PGPORT", "5432"),
        "dbname": require_env("PGDATABASE"),
        "user": require_env("PGUSER"),
        "password": require_env("PGPASSWORD"),
    }


def make_backup(db: dict[str, str]) -> Path:
    backup_dir = Path(os.getenv("BACKUP_DIR", "./db_backups")).resolve()
    backup_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    backup_file = backup_dir / f"openbrain_pre_v0_2_migration_{timestamp}.sql"

    pg_dump_path = os.getenv("PGDUMP_PATH", "pg_dump")

    env = os.environ.copy()
    env["PGPASSWORD"] = db["password"]

    cmd = [
        pg_dump_path,
        "-h", db["host"],
        "-p", db["port"],
        "-U", db["user"],
        "-d", db["dbname"],
        "-f", str(backup_file),
    ]

    print(f"[1/3] Creating backup: {backup_file}")
    try:
        result = subprocess.run(cmd, env=env, check=True, capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise RuntimeError(
            f"pg_dump was not found at '{pg_dump_path}'. "
            "Install PostgreSQL client tools or set PGDUMP_PATH."
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "pg_dump failed.\n"
            f"STDOUT:\n{exc.stdout}\n\nSTDERR:\n{exc.stderr}"
        ) from exc

    if result.stdout.strip():
        print(result.stdout.strip())
    if result.stderr.strip():
        print(result.stderr.strip())

    print("[ok] Backup complete")
    return backup_file


MIGRATIONS: list[str] = [
    # Extensions
    """
    CREATE EXTENSION IF NOT EXISTS vector;
    """,
    """
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    """,

    # Existing memories table: new nullable / safe columns
    """
    ALTER TABLE memories
    ADD COLUMN IF NOT EXISTS project_id UUID,
    ADD COLUMN IF NOT EXISTS memory_type TEXT DEFAULT 'raw_memory',
    ADD COLUMN IF NOT EXISTS importance_score NUMERIC DEFAULT 0.5,
    ADD COLUMN IF NOT EXISTS confidence_score NUMERIC DEFAULT 0.5,
    ADD COLUMN IF NOT EXISTS last_accessed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS access_count INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS summarized_into UUID,
    ADD COLUMN IF NOT EXISTS parent_memory_id BIGINT;
    """,

    # Projects
    """
    CREATE TABLE IF NOT EXISTS projects (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      slug TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      status TEXT DEFAULT 'active',
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    """,

    # Add foreign key from memories.project_id -> projects.id
    # Wrapped in DO block to avoid duplicate constraint errors on rerun.
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_memories_project_id'
      ) THEN
        ALTER TABLE memories
        ADD CONSTRAINT fk_memories_project_id
        FOREIGN KEY (project_id) REFERENCES projects(id)
        ON DELETE SET NULL;
      END IF;
    END $$;
    """,

    # Optional self-reference for parent_memory_id
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_memories_parent_memory_id'
      ) THEN
        ALTER TABLE memories
        ADD CONSTRAINT fk_memories_parent_memory_id
        FOREIGN KEY (parent_memory_id) REFERENCES memories(id)
        ON DELETE SET NULL;
      END IF;
    END $$;
    """,

    # Memory summaries
    """
    CREATE TABLE IF NOT EXISTS memory_summaries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
      summary_title TEXT NOT NULL,
      summary_text TEXT NOT NULL,
      source_memory_ids BIGINT[] NOT NULL,
      summary_embedding VECTOR(768),
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
    """,

    # Ingestion jobs
    """
    CREATE TABLE IF NOT EXISTS ingestion_jobs (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      filename TEXT,
      workflow_name TEXT,
      status TEXT NOT NULL,
      project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
      started_at TIMESTAMPTZ DEFAULT NOW(),
      completed_at TIMESTAMPTZ,
      chunk_count INTEGER DEFAULT 0,
      inserted_count INTEGER DEFAULT 0,
      error_message TEXT,
      metadata_json JSONB DEFAULT '{}'::jsonb
    );
    """,

    # Failed ingestion jobs
    """
    CREATE TABLE IF NOT EXISTS failed_ingestion_jobs (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      ingestion_job_id UUID REFERENCES ingestion_jobs(id) ON DELETE CASCADE,
      retry_count INTEGER DEFAULT 0,
      last_retry_at TIMESTAMPTZ,
      failure_stage TEXT,
      failure_payload JSONB,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
    """,

    # Retrieval history
    """
    CREATE TABLE IF NOT EXISTS retrieval_history (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      query_text TEXT NOT NULL,
      query_embedding VECTOR(768),
      project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
      retrieved_memory_ids BIGINT[],
      top_similarity NUMERIC,
      confidence_score NUMERIC,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
    """,

    # Answer history
    """
    CREATE TABLE IF NOT EXISTS answer_history (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      retrieval_id UUID REFERENCES retrieval_history(id) ON DELETE SET NULL,
      answer_text TEXT,
      sources JSONB,
      confidence_score NUMERIC,
      timing_ms INTEGER,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
    """,

    # Indexes
    """
    CREATE INDEX IF NOT EXISTS idx_memories_project_id
    ON memories(project_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_memories_type
    ON memories(memory_type);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_memories_access_count
    ON memories(access_count);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_memory_summaries_project_id
    ON memory_summaries(project_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_jobs_status
    ON ingestion_jobs(status);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_jobs_project_id
    ON ingestion_jobs(project_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_failed_retry
    ON failed_ingestion_jobs(retry_count);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_retrieval_history_project_id
    ON retrieval_history(project_id);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_answer_history_retrieval_id
    ON answer_history(retrieval_id);
    """,

    # Vector indexes
    """
    CREATE INDEX IF NOT EXISTS idx_memories_embedding
    ON memories
    USING ivfflat (embedding vector_cosine_ops);
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_summary_embedding
    ON memory_summaries
    USING ivfflat (summary_embedding vector_cosine_ops);
    """,
]


def _execute_with_psycopg3(db: dict[str, str], statements: Iterable[str]) -> None:
    conninfo = (
        f"host={db['host']} port={db['port']} dbname={db['dbname']} "
        f"user={db['user']} password={db['password']}"
    )
    with psycopg.connect(conninfo, autocommit=False) as conn:  # type: ignore[attr-defined]
        with conn.cursor() as cur:
            for i, sql in enumerate(statements, start=1):
                print(f"[2/3] Applying migration {i}/{len(MIGRATIONS)}")
                cur.execute(sql)
        conn.commit()


def _execute_with_psycopg2(db: dict[str, str], statements: Iterable[str]) -> None:
    conn = psycopg2.connect(  # type: ignore[union-attr]
        host=db["host"],
        port=db["port"],
        dbname=db["dbname"],
        user=db["user"],
        password=db["password"],
    )
    try:
        conn.autocommit = False
        cur = conn.cursor()
        try:
            for i, sql in enumerate(statements, start=1):
                print(f"[2/3] Applying migration {i}/{len(MIGRATIONS)}")
                cur.execute(sql)
            conn.commit()
        finally:
            cur.close()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def run_migrations(db: dict[str, str]) -> None:
    if DRIVER == "psycopg3":
        _execute_with_psycopg3(db, MIGRATIONS)
    elif DRIVER == "psycopg2":
        _execute_with_psycopg2(db, MIGRATIONS)
    else:
        raise RuntimeError(
            "Neither psycopg (v3) nor psycopg2 is installed. "
            "Install one of them before running this script."
        )
    print("[ok] Migrations complete")


def verify(db: dict[str, str]) -> None:
    verification_sql = """
    SELECT
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'memories' AND column_name = 'project_id'
      ) AS has_project_id,
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'memories'
          AND column_name = 'parent_memory_id'
          AND data_type = 'bigint'
      ) AS has_parent_memory_id_bigint,
      EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'projects'
      ) AS has_projects_table,
      EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'memory_summaries'
      ) AS has_memory_summaries_table,
      EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'ingestion_jobs'
      ) AS has_ingestion_jobs_table,
      EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'failed_ingestion_jobs'
      ) AS has_failed_ingestion_jobs_table,
      EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'retrieval_history'
      ) AS has_retrieval_history_table,
      EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'answer_history'
      ) AS has_answer_history_table,
      EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'memories' AND indexname = 'idx_memories_project_id'
      ) AS has_memories_project_index,
      EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'memories' AND indexname = 'idx_memories_embedding'
      ) AS has_memories_embedding_index,
      EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'memory_summaries' AND indexname = 'idx_summary_embedding'
      ) AS has_summary_embedding_index;
    """

    print("[3/3] Verifying migration results")

    if DRIVER == "psycopg3":
        conninfo = (
            f"host={db['host']} port={db['port']} dbname={db['dbname']} "
            f"user={db['user']} password={db['password']}"
        )
        with psycopg.connect(conninfo, autocommit=True) as conn:  # type: ignore[attr-defined]
            with conn.cursor() as cur:
                cur.execute(verification_sql)
                row = cur.fetchone()
    else:
        conn = psycopg2.connect(  # type: ignore[union-attr]
            host=db["host"],
            port=db["port"],
            dbname=db["dbname"],
            user=db["user"],
            password=db["password"],
        )
        try:
            cur = conn.cursor()
            try:
                cur.execute(verification_sql)
                row = cur.fetchone()
            finally:
                cur.close()
        finally:
            conn.close()

    print("Verification:")
    print(f"  memories.project_id column: {row[0]}")
    print(f"  memories.parent_memory_id BIGINT: {row[1]}")
    print(f"  projects table:                  {row[2]}")
    print(f"  memory_summaries table:          {row[3]}")
    print(f"  ingestion_jobs table:            {row[4]}")
    print(f"  failed_ingestion_jobs table:     {row[5]}")
    print(f"  retrieval_history table:         {row[6]}")
    print(f"  answer_history table:            {row[7]}")
    print(f"  idx_memories_project_id:         {row[8]}")
    print(f"  idx_memories_embedding:          {row[9]}")
    print(f"  idx_summary_embedding:           {row[10]}")

    if not all(row):
        raise RuntimeError("Verification failed. One or more expected objects were not found.")

    print("[ok] Verification complete")


def main() -> int:
    try:
        db = get_db_config()

        backup_file = None
        if os.getenv("SKIP_BACKUP", "0") != "1":
            backup_file = make_backup(db)
        else:
            print("[1/3] Backup skipped because SKIP_BACKUP=1")

        run_migrations(db)
        verify(db)

        print("\nSuccess.")
        if backup_file is not None:
            print(f"Backup file: {backup_file}")
        return 0

    except Exception as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
