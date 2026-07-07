-- ============================================================
-- Sprint S.5.1 — Memorial_Pessoas + Rename colunas legadas
-- ============================================================
-- Executar antes: sprint_s3_f3b_rls.sql
-- Executar depois: NADA (pode rodar a qualquer momento)
-- ============================================================

BEGIN;

-- ============================================================
-- 1. Tabela de ligação MEMORIAL_PESSOAS
-- ============================================================
CREATE TABLE IF NOT EXISTS memorial_pessoas (
  id          BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  memorial_id BIGINT NOT NULL REFERENCES memoriais(id) ON DELETE CASCADE,
  pessoa_id   BIGINT NOT NULL REFERENCES pessoas(id) ON DELETE CASCADE,
  papel       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (memorial_id, pessoa_id)
);

CREATE INDEX IF NOT EXISTS idx_mp_memorial ON memorial_pessoas(memorial_id);
CREATE INDEX IF NOT EXISTS idx_mp_pessoa   ON memorial_pessoas(pessoa_id);

-- Migrar dados existentes de contatos.memorial_id para memorial_pessoas
INSERT INTO memorial_pessoas (memorial_id, pessoa_id)
SELECT c.memorial_id, m.nova_pessoa_id
FROM contatos c
JOIN migracao_pessoas_map m ON m.origem_tabela = 'contatos' AND m.origem_id = c.id
WHERE c.memorial_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- ============================================================
-- 2. Renomear conteudo_permissoes.contato_id → pessoa_id (se ainda existir)
-- ============================================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'conteudo_permissoes'
      AND column_name = 'contato_id'
  ) THEN
    ALTER TABLE conteudo_permissoes DROP CONSTRAINT IF EXISTS fk_conteudo_permissoes_contato_id_pessoas;
    ALTER TABLE conteudo_permissoes RENAME COLUMN contato_id TO pessoa_id;
  END IF;
END $$;
ALTER TABLE conteudo_permissoes DROP CONSTRAINT IF EXISTS fk_conteudo_permissoes_pessoa_id_pessoas;
ALTER TABLE conteudo_permissoes ADD CONSTRAINT fk_conteudo_permissoes_pessoa_id_pessoas
  FOREIGN KEY (pessoa_id) REFERENCES pessoas(id);

-- ============================================================
-- 3. Renomear convites_familiares.contato_id → pessoa_id (se ainda existir)
-- ============================================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'convites_familiares'
      AND column_name = 'contato_id'
  ) THEN
    ALTER TABLE convites_familiares DROP CONSTRAINT IF EXISTS fk_convites_familiares_contato_id_pessoas;
    ALTER TABLE convites_familiares RENAME COLUMN contato_id TO pessoa_id;
  END IF;
END $$;
ALTER TABLE convites_familiares DROP CONSTRAINT IF EXISTS fk_convites_familiares_pessoa_id_pessoas;
ALTER TABLE convites_familiares ADD CONSTRAINT fk_convites_familiares_pessoa_id_pessoas
  FOREIGN KEY (pessoa_id) REFERENCES pessoas(id);

-- ============================================================
-- VALIDACAO
-- ============================================================
DO $$
DECLARE
  v_mp_exists    BOOLEAN;
  v_cp_col       TEXT;
  v_cf_col       TEXT;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'memorial_pessoas'
  ) INTO v_mp_exists;

  SELECT column_name INTO v_cp_col
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'conteudo_permissoes'
    AND column_name = 'pessoa_id';

  SELECT column_name INTO v_cf_col
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'convites_familiares'
    AND column_name = 'pessoa_id';

  IF NOT v_mp_exists THEN
    RAISE EXCEPTION 'Tabela memorial_pessoas nao criada';
  END IF;
  IF v_cp_col IS NULL THEN
    RAISE EXCEPTION 'coluna pessoa_id nao encontrada em conteudo_permissoes';
  END IF;
  IF v_cf_col IS NULL THEN
    RAISE EXCEPTION 'coluna pessoa_id nao encontrada em convites_familiares';
  END IF;

  RAISE NOTICE '✅ memorial_pessoas criada, colunas renomeadas para pessoa_id';
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK
-- ============================================================
-- DROP TABLE IF EXISTS memorial_pessoas CASCADE;
-- ALTER TABLE conteudo_permissoes RENAME COLUMN pessoa_id TO contato_id;
-- ALTER TABLE convites_familiares RENAME COLUMN pessoa_id TO contato_id;
