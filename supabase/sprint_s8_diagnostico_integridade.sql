-- ============================================================
-- Sprint S.8 — Diagnóstico de Integridade Pós-Migração
-- ============================================================
-- Executar no Supabase SQL Dashboard.
-- NÃO altera dados — apenas consulta.
-- ============================================================
-- Causa raiz provável:
--   sprint_s3_f2_fks.sql usa a function _migrar_fk() que:
--     1. Cria coluna _novo
--     2. Faz UPDATE via migracao_pessoas_map
--     3. DROP coluna antiga
--     4. RENAME _novo → nome original
--     5. ADD FK → pessoas(id)
--
--   Se alguma etapa falhou (FK existente impedindo DROP, trigger
--   bloqueando, conflito de constraint), a migração fica incompleta
--   e os valores de usuario_id em memorias, memoriais, fotos, etc.
--   continuam sendo o VELHO usuarios.id, não o novo pessoas.id.
--
--   Além disso, o backfill (S3.1) criou DUAS pessoas para a mesma
--   pessoa real: uma vinda de usuarios (com _legacy_usuario_id) e
--   outra vinda de contatos (com _legacy_contato_id).
-- ============================================================

-- ============================================================
-- A. MAPEAR usuarios → pessoas
-- ============================================================
SELECT 'A. usuarios → pessoas (via _legacy_usuario_id)' AS secao;
SELECT
    u.id              AS usuario_id,
    u.email           AS usuario_email,
    u.nome            AS usuario_nome,
    p.id              AS pessoa_id,
    p.nome            AS pessoa_nome,
    p.auth_user_id,
    p._legacy_usuario_id,
    p._legacy_contato_id,
    p.criado_por_id,
    p.merged_into_id,
    p.tipo,
    p.situacao
FROM usuarios u
LEFT JOIN pessoas p ON p._legacy_usuario_id = u.id
ORDER BY u.id;

-- ============================================================
-- B. MAPEAR contatos → pessoas (via _legacy_contato_id)
-- ============================================================
SELECT 'B. contatos → pessoas (via _legacy_contato_id)' AS secao;
SELECT
    c.id              AS contato_id,
    c.nome            AS contato_nome,
    c.usuario_id      AS contato_usuario_id,
    c.memorial_id     AS contato_memorial_id,
    p.id              AS pessoa_id,
    p.nome            AS pessoa_nome,
    p._legacy_contato_id,
    p._legacy_usuario_id,
    p.criado_por_id,
    p.merged_into_id,
    p.email
FROM contatos c
LEFT JOIN pessoas p ON p._legacy_contato_id = c.id
ORDER BY c.id;

-- ============================================================
-- C. DUPLICIDADES — mesmo email
-- ============================================================
SELECT 'C1. DUPLICADOS — mesmo email' AS secao;
SELECT
    p1.id AS id_a, p1.nome AS nome_a, p1._legacy_usuario_id, p1._legacy_contato_id,
    p2.id AS id_b, p2.nome AS nome_b, p2._legacy_usuario_id, p2._legacy_contato_id,
    p1.email
FROM pessoas p1
JOIN pessoas p2 ON p2.email = p1.email AND p2.id > p1.id
WHERE p1.email IS NOT NULL AND p1.email != ''
ORDER BY p1.email;

-- ============================================================
-- D. DUPLICIDADES — mesmo nome (normalizado)
-- ============================================================
SELECT 'D1. DUPLICADOS — mesmo nome' AS secao;
SELECT
    p1.id AS id_a, p1.nome, p1.sobrenome, p1._legacy_usuario_id, p1._legacy_contato_id,
    p2.id AS id_b, p2._legacy_usuario_id, p2._legacy_contato_id,
    p1.criado_por_id
FROM pessoas p1
JOIN pessoas p2 ON
    p2.nome = p1.nome
    AND COALESCE(p2.sobrenome, '') = COALESCE(p1.sobrenome, '')
    AND p2.id > p1.id
ORDER BY p1.nome;

-- ============================================================
-- E. VSÃO GERAL DE pessoas
-- ============================================================
SELECT 'E. TODAS as pessoas — visão geral' AS secao;
SELECT
    id, nome, sobrenome, email, tipo, situacao,
    auth_user_id, _legacy_usuario_id, _legacy_contato_id,
    criado_por_id, merged_into_id
FROM pessoas
ORDER BY id;

-- ============================================================
-- F. VERIFICAR conteudo_permissoes.pessoa_id
--    (se os valores são IDs de pessoas VÁLIDOS e quais)
-- ============================================================
SELECT 'F. conteudo_permissoes — pessoa_id vs pessoas.id real' AS secao;
SELECT
    cp.id AS cp_id,
    cp.pessoa_id,
    cp.tipo_conteudo,
    cp.conteudo_id,
    p.id AS pessoa_existe,
    p.nome AS pessoa_nome
FROM conteudo_permissoes cp
LEFT JOIN pessoas p ON p.id = cp.pessoa_id
ORDER BY cp.id;

-- ============================================================
-- G. MEMÓRIAS — qual usuario_id está armazenado
-- ============================================================
SELECT 'G1. memorias — usuario_id vs pessoas.id' AS secao;
SELECT
    m.id AS memoria_id,
    LEFT(m.titulo, 40) AS titulo,
    m.usuario_id AS memoria_usuario_id,
    p.id AS pessoa_id,
    p.nome AS pessoa_nome,
    p._legacy_usuario_id
FROM memorias m
LEFT JOIN pessoas p ON p.id = m.usuario_id
ORDER BY m.id;

-- Mostrar quantas memórias NÃO encontram pessoa correspondente
SELECT 'G2. memorias — SEM pessoa correspondente' AS secao;
SELECT COUNT(*) AS total_sem_pessoa
FROM memorias m
WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = m.usuario_id);

-- ============================================================
-- H. FOTOS — usuario_id
-- ============================================================
SELECT 'H. fotos — usuario_id vs pessoas.id' AS secao;
SELECT
    f.id AS foto_id, f.memorial_id, f.usuario_id AS foto_usuario_id,
    p.id AS pessoa_id, p.nome AS pessoa_nome
FROM fotos f
LEFT JOIN pessoas p ON p.id = f.usuario_id
ORDER BY f.id;

-- ============================================================
-- I. MEMORIAIS E MEMORIAL_PESSOAS
-- ============================================================
SELECT 'I1. memoriais — usuario_id e memorial_pessoas' AS secao;
SELECT
    ml.id AS memorial_id,
    ml.usuario_id AS memorial_usuario_id,
    ml.nome AS memorial_nome,
    mp.pessoa_id,
    p.nome AS pessoa_nome,
    mp.papel
FROM memoriais ml
LEFT JOIN memorial_pessoas mp ON mp.memorial_id = ml.id
LEFT JOIN pessoas p ON p.id = mp.pessoa_id
ORDER BY ml.id;

SELECT 'I2. memoriais SEM vinculo em memorial_pessoas' AS secao;
SELECT ml.id, ml.nome, ml.usuario_id
FROM memoriais ml
WHERE NOT EXISTS (SELECT 1 FROM memorial_pessoas mp WHERE mp.memorial_id = ml.id);

-- ============================================================
-- J. PESSOAS_RELACIONAMENTOS — nulos
-- ============================================================
SELECT 'J. pessoas_relacionamentos — nulos ou inválidos' AS secao;
SELECT *
FROM pessoas_relacionamentos
WHERE pessoa_a_id IS NULL
   OR pessoa_b_id IS NULL
   OR pessoa_a_id = 0
   OR pessoa_b_id = 0
   OR NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = pessoa_a_id)
   OR NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = pessoa_b_id)
ORDER BY id;

-- ============================================================
-- K. PESSOA_LINHA_TEMPO — amostra para ver o problema
-- ============================================================
SELECT 'K. pessoa_linha_tempo — amostra (primeiras 30)' AS secao;
SELECT *
FROM pessoa_linha_tempo
ORDER BY pessoa_id, data_ordem DESC
LIMIT 30;

SELECT 'K2. pessoa_linha_tempo — contagem por pessoa_id' AS secao;
SELECT pessoa_id, COUNT(*) AS total
FROM pessoa_linha_tempo
GROUP BY pessoa_id
ORDER BY total DESC;

-- ============================================================
-- L. PESSOAS_RECENTES — testar com cada ID candidato
-- ============================================================
SELECT 'L. pessoas_recentes(5) — Darlan pessoa.id=5' AS secao;
SELECT * FROM pessoas_recentes(5, 10);

SELECT 'L2. pessoas_recentes(2) — legacy usuario_id=2' AS secao;
SELECT * FROM pessoas_recentes(2, 10);

-- ============================================================
-- M. PESSOA_AUTENTICADA_ID — testar
-- ============================================================
SELECT 'M. pessoa_autenticada_id() — resultado atual' AS secao;
SELECT pessoa_autenticada_id() AS pessoa_id;

-- ============================================================
-- N. VIEWS — ainda referenciam contatos ou usuarios?
-- ============================================================
SELECT 'N1. VIEWS referenciando contatos' AS secao;
SELECT schemaname, viewname, LEFT(definition, 200) AS def_inicio
FROM pg_views
WHERE schemaname = 'public'
  AND (definition ILIKE '%contatos%' OR definition ILIKE '%contato_id%')
ORDER BY viewname;

SELECT 'N2. VIEWS referenciando usuarios (tabela)' AS secao;
SELECT schemaname, viewname, LEFT(definition, 200) AS def_inicio
FROM pg_views
WHERE schemaname = 'public'
  AND definition ILIKE '%from public.usuarios%'
ORDER BY viewname;

-- ============================================================
-- O. FUNCTIONS — ainda referenciam contatos?
-- ============================================================
SELECT 'O. FUNCTIONS referenciando contatos' AS secao;
SELECT proname, LEFT(prosrc, 300) AS src_inicio
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND (prosrc ILIKE '%contatos%' OR prosrc ILIKE '%contato_id%')
ORDER BY proname;

-- ============================================================
-- P. PESSOAS SUGERIDAS — amostra
-- ============================================================
SELECT 'P. pessoas_sugeridas(5) — amostra' AS secao;
SELECT * FROM pessoas_sugeridas(5, 20);

-- ============================================================
-- Q. MEMORIAS_EVOLUCAO_RESUMO — amostra
-- ============================================================
SELECT 'Q. memorias_evolucao_resumo — amostra' AS secao;
SELECT *
FROM memorias_evolucao_resumo
ORDER BY memoria_id
LIMIT 20;

-- ============================================================
-- R. verificar se FKs foram migradas — amostra
--    (comparar valor vs. pessoas.id existente)
-- ============================================================
SELECT 'R1. memorias.usuario_id — valores únicos' AS secao;
SELECT usuario_id, COUNT(*) AS qtd
FROM memorias
GROUP BY usuario_id
ORDER BY usuario_id;

SELECT 'R2. memoriais.usuario_id — valores únicos' AS secao;
SELECT usuario_id, COUNT(*) AS qtd
FROM memoriais
GROUP BY usuario_id
ORDER BY usuario_id;

SELECT 'R3. fotos.usuario_id — valores únicos' AS secao;
SELECT usuario_id, COUNT(*) AS qtd
FROM fotos
GROUP BY usuario_id
ORDER BY usuario_id;

SELECT 'R4. videos.usuario_id — valores únicos' AS secao;
SELECT usuario_id, COUNT(*) AS qtd
FROM videos
GROUP BY usuario_id
ORDER BY usuario_id;

SELECT 'R5. cofre_itens.usuario_id — valores únicos' AS secao;
SELECT usuario_id, COUNT(*) AS qtd
FROM cofre_itens
GROUP BY usuario_id
ORDER BY usuario_id;

-- ============================================================
-- S. VERIFICAR auth.uid() — está null?
-- ============================================================
SELECT 'S. auth.uid() — valor atual' AS secao;
SELECT auth.uid() AS uid_atual;

-- ============================================================
-- T. PESSOAS COM auth_user_id vs auth.uid()
-- ============================================================
SELECT 'T. pessoas com auth_user_id' AS secao;
SELECT id, nome, auth_user_id, auth_id
FROM pessoas
WHERE auth_user_id IS NOT NULL OR auth_id IS NOT NULL;

-- ============================================================
-- U. MIGRACAO_PESSOAS_MAP — status
-- ============================================================
SELECT 'U. migracao_pessoas_map — resumo' AS secao;
SELECT origem_tabela, COUNT(*) AS total
FROM migracao_pessoas_map
GROUP BY origem_tabela;

-- ============================================================
-- V. RESUMO DE INCONSISTÊNCIAS
-- ============================================================
SELECT 'V. RESUMO — detectar problemas principais' AS secao;

-- V1. Pessoas sem mapping de origem
SELECT 'V1. pessoas SEM _legacy_usuario_id E SEM _legacy_contato_id' AS info;
SELECT id, nome, tipo, criado_por_id
FROM pessoas
WHERE _legacy_usuario_id IS NULL
  AND _legacy_contato_id IS NULL
  AND auth_user_id IS NULL
ORDER BY id;

-- V2. contatos com dados que não foram copiados para memorial_pessoas
SELECT 'V2. contatos com memorial_id SEM registro em memorial_pessoas' AS info;
SELECT c.id, c.nome, c.memorial_id
FROM contatos c
WHERE c.memorial_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM memorial_pessoas mp
    JOIN pessoas p ON p.id = mp.pessoa_id
    WHERE mp.memorial_id = c.memorial_id
      AND p._legacy_contato_id = c.id
  );

-- V3. pessoas com criado_por_id apontando para ID que não existe em pessoas
SELECT 'V3. criado_por_id SEM pessoa correspondente' AS info;
SELECT p.id, p.nome, p.criado_por_id
FROM pessoas p
WHERE p.criado_por_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM pessoas ref WHERE ref.id = p.criado_por_id);

-- V4. conteudo_permissoes.pessoa_id que não existe em pessoas
SELECT 'V4. conteudo_permissoes.pessoa_id SEM pessoa correspondente' AS info;
SELECT cp.id, cp.pessoa_id, cp.tipo_conteudo, cp.conteudo_id
FROM conteudo_permissoes cp
WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = cp.pessoa_id);

SELECT '=== FIM DO DIAGNÓSTICO ===' AS fim;
