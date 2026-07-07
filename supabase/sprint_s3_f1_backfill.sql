-- ============================================================
-- Sprint S.3 — Fase 1: Backfill
-- Migra dados de usuarios e contatos para pessoas + mapping
-- ============================================================
-- Autor: Plano S.2 aprovado
-- Executar antes: sprint_s3_f0_preparacao.sql
-- Executar depois: sprint_s3_f1_dedup.sql
-- ============================================================

BEGIN;

-- ============================================================
-- S2.1.0 + S2.1.2: usuarios → pessoas + mapping
-- ============================================================
WITH inserted AS (
  INSERT INTO pessoas (auth_id, nome, sobrenome, email, telefone,
                       data_nascimento, foto_perfil, situacao,
                       _legacy_usuario_id, created_at, updated_at)
  SELECT
    u.auth_id,
    u.nome,
    u.sobrenome,
    u.email,
    u.telefone,
    CASE WHEN u.data_nascimento::text != '' THEN u.data_nascimento::date END,
    u.foto_perfil,
    'ativo' AS situacao,
    u.id    AS _legacy_usuario_id,
    u.data_criacao::timestamptz,
    u.data_criacao::timestamptz
  FROM usuarios u
  RETURNING id, _legacy_usuario_id
)
INSERT INTO migracao_pessoas_map (origem_tabela, origem_id, nova_pessoa_id)
SELECT 'usuarios', _legacy_usuario_id, id FROM inserted;

DO $$
BEGIN
  RAISE NOTICE '✅ usuarios → pessoas: % migrados',
    (SELECT count(*) FROM migracao_pessoas_map WHERE origem_tabela = 'usuarios');
END $$;

-- ============================================================
-- S2.1.1 + S2.1.3: contatos → pessoas + mapping
-- ============================================================
WITH inserted AS (
  INSERT INTO pessoas (nome, sobrenome, email, telefone,
                       data_nascimento, foto_perfil, situacao,
                       criado_por_id, falecido,
                       _legacy_contato_id, created_at)
  SELECT
    c.nome,
    c.sobrenome,
    c.email,
    c.telefone,
    CASE WHEN c.data_nascimento::text != '' THEN c.data_nascimento::date END,
    c.foto_perfil,
    'pendente' AS situacao,
    map.nova_pessoa_id AS criado_por_id,
    false AS falecido,  -- pode ser atualizado pelo app posteriormente
    c.id AS _legacy_contato_id,
    c.data_criacao::timestamptz
  FROM contatos c
  LEFT JOIN migracao_pessoas_map map
    ON map.origem_tabela = 'usuarios' AND map.origem_id = c.usuario_id
  RETURNING id, _legacy_contato_id
)
INSERT INTO migracao_pessoas_map (origem_tabela, origem_id, nova_pessoa_id)
SELECT 'contatos', _legacy_contato_id, id FROM inserted;

DO $$
BEGIN
  RAISE NOTICE '✅ contatos → pessoas: % migrados',
    (SELECT count(*) FROM migracao_pessoas_map WHERE origem_tabela = 'contatos');
END $$;

-- ============================================================
-- VALIDAÇÃO
-- ============================================================
DO $$
DECLARE
  v_usuarios INT;
  v_contatos INT;
  v_pessoas  INT;
  v_map_u    INT;
  v_map_c    INT;
BEGIN
  SELECT count(*) INTO v_usuarios FROM usuarios;
  SELECT count(*) INTO v_contatos FROM contatos;
  SELECT count(*) INTO v_pessoas  FROM pessoas;
  SELECT count(*) INTO v_map_u    FROM migracao_pessoas_map WHERE origem_tabela = 'usuarios';
  SELECT count(*) INTO v_map_c    FROM migracao_pessoas_map WHERE origem_tabela = 'contatos';

  IF v_map_u <> v_usuarios THEN
    RAISE EXCEPTION 'Mapping usuarios divergente: % usuarios vs % map', v_usuarios, v_map_u;
  END IF;

  IF v_map_c <> v_contatos THEN
    RAISE EXCEPTION 'Mapping contatos divergente: % contatos vs % map', v_contatos, v_map_c;
  END IF;

  RAISE NOTICE '✅ Fase 1 OK — usuarios:%, contatos:%, pessoas:%',
    v_usuarios, v_contatos, v_pessoas;
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK
-- ============================================================
-- Para desfazer esta fase ANTES de executar f2_fks.sql:
--   DELETE FROM migracao_pessoas_map;
--   DELETE FROM pessoas;
--   ALTER SEQUENCE pessoas_id_seq RESTART;
-- Para desfazer DEPOIS de f2_fks: ver rollback do script f2
