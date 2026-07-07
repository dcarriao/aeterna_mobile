-- ============================================================
-- Sprint S.3 — Fase 0: Preparação
-- Cria as tabelas novas + índices + função RLS
-- ============================================================
-- Autor: Plano S.2 aprovado
-- Executar antes: Nada
-- Executar depois: sprint_s3_f1_backfill.sql
-- ============================================================

BEGIN;

-- ============================================================
-- S2.0.0: Tabela central PESSOAS
-- ============================================================
CREATE TABLE IF NOT EXISTS pessoas (
  id                BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  auth_user_id      UUID UNIQUE NULL,
  auth_id           TEXT UNIQUE NULL,
  nome              TEXT NOT NULL,
  sobrenome         TEXT NULL,
  email             TEXT NULL,
  telefone          TEXT NULL,
  data_nascimento   DATE NULL,
  foto_perfil       TEXT NULL,
  tipo              TEXT NOT NULL DEFAULT 'humano'
                    CHECK (tipo IN ('humano', 'pet')),
  situacao          TEXT NOT NULL DEFAULT 'pendente'
                    CHECK (situacao IN ('pendente', 'ativo', 'inativo')),
  falecido          BOOLEAN NOT NULL DEFAULT false,
  data_falecimento  DATE NULL,
  criado_por_id     BIGINT NULL,
  merged_into_id    BIGINT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- S2.0.1: Tabela de IDENTIFICADORES
-- ============================================================
CREATE TABLE IF NOT EXISTS pessoa_identificadores (
  id          BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  pessoa_id   BIGINT NOT NULL REFERENCES pessoas(id) ON DELETE CASCADE,
  tipo        TEXT NOT NULL
              CHECK (tipo IN ('email', 'telefone', 'whatsapp', 'cpf', 'instagram', 'outro')),
  valor       TEXT NOT NULL,
  principal   BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tipo, valor)
);

-- ============================================================
-- S2.0.2: Tabela de MAPPING (temporária)
-- ============================================================
CREATE TABLE IF NOT EXISTS migracao_pessoas_map (
  origem_tabela  TEXT NOT NULL CHECK (origem_tabela IN ('usuarios', 'contatos')),
  origem_id      BIGINT NOT NULL,
  nova_pessoa_id BIGINT NOT NULL REFERENCES pessoas(id),
  PRIMARY KEY (origem_tabela, origem_id)
);

-- ============================================================
-- S2.0.3: Colunas legado para rastrear IDs originais
-- ============================================================
ALTER TABLE pessoas ADD COLUMN IF NOT EXISTS _legacy_usuario_id BIGINT NULL;
ALTER TABLE pessoas ADD COLUMN IF NOT EXISTS _legacy_contato_id BIGINT NULL;

-- ============================================================
-- S2.0.4: Índices
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_pessoas_auth_user
  ON pessoas(auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pessoas_auth_id
  ON pessoas(auth_id) WHERE auth_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pessoas_nome_trgm
  ON pessoas USING gin (nome gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_pessoas_criado_por
  ON pessoas(criado_por_id);
CREATE INDEX IF NOT EXISTS idx_pessoas_merged_into
  ON pessoas(merged_into_id) WHERE merged_into_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pi_pessoa
  ON pessoa_identificadores(pessoa_id);
CREATE INDEX IF NOT EXISTS idx_migracao_nova
  ON migracao_pessoas_map(nova_pessoa_id);

-- ============================================================
-- S2.0.5: Função RLS — retorna o pessoas.id do usuário logado
-- ============================================================
CREATE OR REPLACE FUNCTION public.pessoa_autenticada_id()
RETURNS BIGINT
LANGUAGE SQL STABLE SECURITY DEFINER
AS $$
  SELECT id FROM pessoas
  WHERE auth_user_id = auth.uid()
     OR auth_id = auth.uid()::text
  LIMIT 1;
$$;

-- ============================================================
-- VALIDAÇÃO
-- ============================================================
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN ('pessoas', 'pessoa_identificadores', 'migracao_pessoas_map');
  IF v_count < 3 THEN
    RAISE EXCEPTION 'Tabelas criadas: % (esperado 3)', v_count;
  END IF;
  RAISE NOTICE '✅ Fase 0 OK — 3 tabelas criadas, índices OK, função OK';
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK
-- ============================================================
-- Para desfazer esta fase:
--   DROP TABLE IF EXISTS migracao_pessoas_map CASCADE;
--   DROP TABLE IF EXISTS pessoa_identificadores CASCADE;
--   DROP TABLE IF EXISTS pessoas CASCADE;
--   DROP FUNCTION IF EXISTS public.pessoa_autenticada_id();
