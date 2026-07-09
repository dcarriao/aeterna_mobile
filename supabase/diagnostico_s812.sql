-- ============================================================================
-- DIAGNÓSTICO S.8.12 — Jonathas + Beatriz duplicada
-- Executar no Supabase Dashboard > SQL Editor
-- ============================================================================

-- 1. JONATHAS — Todas as relações envolvendo Jonathas
SELECT '=== 1. RELACOES JONATHAS ===' AS info;
SELECT
    pr.id,
    pr.pessoa_a_id,
    pa.nome AS nome_a,
    pr.pessoa_b_id,
    pb.nome AS nome_b,
    pr.tipo,
    pr.relacao_a_para_b,
    pr.relacao_b_para_a
FROM pessoas_relacionamentos pr
JOIN pessoas pa ON pa.id = pr.pessoa_a_id
JOIN pessoas pb ON pb.id = pr.pessoa_b_id
WHERE pr.pessoa_a_id IN (
    SELECT id FROM pessoas WHERE lower(nome) LIKE '%jonathas%'
) OR pr.pessoa_b_id IN (
    SELECT id FROM pessoas WHERE lower(nome) LIKE '%jonathas%'
)
ORDER BY pr.pessoa_a_id, pr.pessoa_b_id;

-- 2. BEATRIZ — Todas as pessoas com nome Beatriz
SELECT '=== 2. PESSOAS BEATRIZ ===' AS info;
SELECT id, nome, sobrenome, email, telefone, data_nascimento, situacao, criado_por_id
FROM pessoas
WHERE lower(nome) LIKE '%beatriz%'
ORDER BY id;

-- 3. BEATRIZ — Relações de cada Beatriz
SELECT '=== 3. RELACOES BEATRIZ ===' AS info;
SELECT
    pr.id,
    pr.pessoa_a_id,
    pa.nome AS nome_a,
    pr.pessoa_b_id,
    pb.nome AS nome_b,
    pr.tipo,
    pr.relacao_a_para_b,
    pr.relacao_b_para_a
FROM pessoas_relacionamentos pr
JOIN pessoas pa ON pa.id = pr.pessoa_a_id
JOIN pessoas pb ON pb.id = pr.pessoa_b_id
WHERE pr.pessoa_a_id IN (
    SELECT id FROM pessoas WHERE lower(nome) LIKE '%beatriz%'
) OR pr.pessoa_b_id IN (
    SELECT id FROM pessoas WHERE lower(nome) LIKE '%beatriz%'
)
ORDER BY pr.pessoa_a_id, pr.pessoa_b_id;

-- 4. BEATRIZ — Vínculos em outras tabelas
SELECT '=== 4. VINCULOS BEATRIZ ===' AS info;
SELECT 'conteudo_permissoes' AS tabela, COUNT(*) AS total
FROM conteudo_permissoes
WHERE pessoa_id IN (SELECT id FROM pessoas WHERE lower(nome) LIKE '%beatriz%')
UNION ALL
SELECT 'memorial_pessoas', COUNT(*)
FROM memorial_pessoas
WHERE pessoa_id IN (SELECT id FROM pessoas WHERE lower(nome) LIKE '%beatriz%')
UNION ALL
SELECT 'pessoas_relacionamentos_a', COUNT(*)
FROM pessoas_relacionamentos
WHERE pessoa_a_id IN (SELECT id FROM pessoas WHERE lower(nome) LIKE '%beatriz%')
UNION ALL
SELECT 'pessoas_relacionamentos_b', COUNT(*)
FROM pessoas_relacionamentos
WHERE pessoa_b_id IN (SELECT id FROM pessoas WHERE lower(nome) LIKE '%beatriz%');

-- 5. ALICE — Relações da Alice (para entender Jonathas)
SELECT '=== 5. RELACOES ALICE ===' AS info;
SELECT
    pr.id,
    pr.pessoa_a_id,
    pa.nome AS nome_a,
    pr.pessoa_b_id,
    pb.nome AS nome_b,
    pr.tipo,
    pr.relacao_a_para_b,
    pr.relacao_b_para_a
FROM pessoas_relacionamentos pr
JOIN pessoas pa ON pa.id = pr.pessoa_a_id
JOIN pessoas pb ON pb.id = pr.pessoa_b_id
WHERE pr.pessoa_a_id IN (
    SELECT id FROM pessoas WHERE lower(nome) LIKE '%alice%'
) OR pr.pessoa_b_id IN (
    SELECT id FROM pessoas WHERE lower(nome) LIKE '%alice%'
)
ORDER BY pr.pessoa_a_id, pr.pessoa_b_id;
