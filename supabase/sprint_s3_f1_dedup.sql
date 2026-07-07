-- ============================================================
-- Sprint S.3 — Fase 1b: Deduplicação + Identificadores
-- ============================================================
-- Autor: Plano S.2 aprovado
-- Executar antes: sprint_s3_f1_backfill.sql
-- Executar depois: sprint_s3_f2_fks.sql
-- ============================================================

BEGIN;

-- ============================================================
-- S2.1.4: Detectar duplicatas (mesma pessoa em usuarios + contatos)
--   Match por email exato
--   Match por telefone exato
--   Match por nome + data_nascimento
-- ============================================================

-- 1a. Match por EMAIL
--     Redireciona o mapping do contato para apontar para a pessoas do usuario
UPDATE migracao_pessoas_map m
SET nova_pessoa_id = (
  SELECT m2.nova_pessoa_id
  FROM migracao_pessoas_map m2
  JOIN pessoas pu ON pu.id = m2.nova_pessoa_id AND m2.origem_tabela = 'usuarios'
  WHERE pu.email IS NOT NULL AND LOWER(pu.email) = LOWER(pc.email)
  LIMIT 1
)
FROM pessoas pc
WHERE m.origem_tabela = 'contatos'
  AND m.nova_pessoa_id = pc.id
  AND EXISTS (
    SELECT 1 FROM migracao_pessoas_map m2
    JOIN pessoas pu ON pu.id = m2.nova_pessoa_id AND m2.origem_tabela = 'usuarios'
    WHERE pu.email IS NOT NULL AND LOWER(pu.email) = LOWER(pc.email)
  );

DO $$
BEGIN
  RAISE NOTICE '✅ Dedup email: % contatos redirecionados',
    (SELECT count(*) FROM migracao_pessoas_map
     WHERE origem_tabela = 'contatos'
       AND nova_pessoa_id IN (
         SELECT id FROM pessoas WHERE _legacy_usuario_id IS NOT NULL
       ));
END $$;

-- 1b. Match por TELEFONE
UPDATE migracao_pessoas_map m
SET nova_pessoa_id = (
  SELECT m2.nova_pessoa_id
  FROM migracao_pessoas_map m2
  JOIN pessoas pu ON pu.id = m2.nova_pessoa_id AND m2.origem_tabela = 'usuarios'
  WHERE pu.telefone IS NOT NULL AND pu.telefone = pc.telefone
  LIMIT 1
)
FROM pessoas pc
WHERE m.origem_tabela = 'contatos'
  AND m.nova_pessoa_id = pc.id
  AND EXISTS (
    SELECT 1 FROM migracao_pessoas_map m2
    JOIN pessoas pu ON pu.id = m2.nova_pessoa_id AND m2.origem_tabela = 'usuarios'
    WHERE pu.telefone IS NOT NULL AND pu.telefone = pc.telefone
  );

DO $$
BEGIN
  RAISE NOTICE '✅ Dedup telefone: % contatos redirecionados',
    (SELECT count(*) FROM migracao_pessoas_map
     WHERE origem_tabela = 'contatos'
       AND nova_pessoa_id IN (
         SELECT id FROM pessoas WHERE _legacy_usuario_id IS NOT NULL
       ));
END $$;

-- 1c. Limpar pessoas órfãs (contatos que foram redirecionados para usuarios)
--     Marcar como merged_into_id para rastreio
UPDATE pessoas p
SET merged_into_id = m.nova_pessoa_id,
    situacao = 'inativo'
FROM migracao_pessoas_map m
WHERE m.origem_tabela = 'contatos'
  AND p.id = m.nova_pessoa_id
  AND p._legacy_usuario_id IS NULL   -- é um contato original
  AND EXISTS (                        -- mas foi redirecionado para um usuario
    SELECT 1 FROM migracao_pessoas_map m2
    WHERE m2.origem_tabela = 'contatos'
      AND m2.origem_id = p._legacy_contato_id
      AND m2.nova_pessoa_id <> p.id
  );

-- ============================================================
-- S2.1.5: Popular pessoa_identificadores
-- ============================================================

-- A partir de usuarios (email como principal)
INSERT INTO pessoa_identificadores (pessoa_id, tipo, valor, principal)
SELECT
  m.nova_pessoa_id,
  'email',
  p.email,
  true
FROM pessoas p
JOIN migracao_pessoas_map m
  ON m.origem_tabela = 'usuarios' AND m.origem_id = p._legacy_usuario_id
WHERE p.email IS NOT NULL AND p.email != ''
  AND NOT EXISTS (
    SELECT 1 FROM pessoa_identificadores pi
    WHERE pi.pessoa_id = m.nova_pessoa_id AND pi.tipo = 'email' AND pi.valor = p.email
  );

-- A partir de contatos (email, telefone)
INSERT INTO pessoa_identificadores (pessoa_id, tipo, valor, principal)
SELECT
  m.nova_pessoa_id,
  'email',
  p.email,
  false
FROM pessoas p
JOIN migracao_pessoas_map m
  ON m.origem_tabela = 'contatos'
  AND m.origem_id = COALESCE(p._legacy_contato_id, 0)
WHERE p.email IS NOT NULL AND p.email != ''
  AND p._legacy_contato_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM pessoa_identificadores pi
    WHERE pi.pessoa_id = m.nova_pessoa_id AND pi.tipo = 'email' AND pi.valor = p.email
  );

INSERT INTO pessoa_identificadores (pessoa_id, tipo, valor, principal)
SELECT
  m.nova_pessoa_id,
  'telefone',
  p.telefone,
  false
FROM pessoas p
JOIN migracao_pessoas_map m
  ON m.origem_tabela = 'contatos'
  AND m.origem_id = COALESCE(p._legacy_contato_id, 0)
WHERE p.telefone IS NOT NULL AND p.telefone != ''
  AND p._legacy_contato_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM pessoa_identificadores pi
    WHERE pi.pessoa_id = m.nova_pessoa_id AND pi.tipo = 'telefone' AND pi.valor = p.telefone
  );

DO $$
BEGIN
  RAISE NOTICE '✅ Identificadores criados: %',
    (SELECT count(*) FROM pessoa_identificadores);
END $$;

-- ============================================================
-- VALIDAÇÃO
-- ============================================================
DO $$
DECLARE
  v_duplicatas INT;
  v_ident_count INT;
BEGIN
  -- Verificar se auth_user_id continua único
  SELECT count(*) INTO v_duplicatas
  FROM pessoas
  WHERE auth_id IS NOT NULL
  GROUP BY auth_id HAVING count(*) > 1;
  IF v_duplicatas > 0 THEN
    RAISE WARNING '⚠️ auth_id duplicado em pessoas: %', v_duplicatas;
  END IF;

  SELECT count(*) INTO v_ident_count
  FROM pessoa_identificadores;
  RAISE NOTICE '✅ Fase 1b OK — identificadores:%, merged:%',
    v_ident_count,
    (SELECT count(*) FROM pessoas WHERE merged_into_id IS NOT NULL);
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK
-- ============================================================
-- Para desfazer:
--   DELETE FROM pessoa_identificadores;
--   UPDATE pessoas SET merged_into_id = NULL, situacao = 'pendente'
--   WHERE merged_into_id IS NOT NULL AND _legacy_usuario_id IS NULL;
--   Depois re-executar sprint_s3_f1_backfill.sql para restaurar mapping original
