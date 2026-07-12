-- ============================================================================
-- S.8.13 — Popular relacao_b_para_a e relacao_a_para_b nulos
-- Executar no Supabase Dashboard > SQL Editor
-- ============================================================================

-- 1. EVIDÊNCIA: quantas linhas têm NULL
SELECT '=== ANTES ===' AS info;
SELECT
  COUNT(*) AS total,
  COUNT(relacao_b_para_a) AS com_rot_b,
  COUNT(relacao_a_para_b) AS com_rot_a,
  COUNT(*) - COUNT(relacao_b_para_a) AS sem_rot_b,
  COUNT(*) - COUNT(relacao_a_para_b) AS sem_rot_a
FROM pessoas_relacionamentos;

-- 2. Atualiza relacao_b_para_a nulo usando catálogo
UPDATE pessoas_relacionamentos pr
SET relacao_b_para_a = tr.rotulo_b_para_a
FROM tipos_relacionamento tr
WHERE pr.tipo = tr.id
  AND pr.relacao_b_para_a IS NULL;

-- 3. Atualiza relacao_a_para_b nulo usando catálogo
UPDATE pessoas_relacionamentos pr
SET relacao_a_para_b = tr.rotulo_a_para_b
FROM tipos_relacionamento tr
WHERE pr.tipo = tr.id
  AND pr.relacao_a_para_b IS NULL;

-- 4. VALIDAÇÃO: confirmar que não sobrou NULL
SELECT '=== DEPOIS ===' AS info;
SELECT
  COUNT(*) AS total,
  COUNT(relacao_b_para_a) AS com_rot_b,
  COUNT(relacao_a_para_b) AS com_rot_a,
  COUNT(*) - COUNT(relacao_b_para_a) AS sem_rot_b,
  COUNT(*) - COUNT(relacao_a_para_b) AS sem_rot_a
FROM pessoas_relacionamentos;

-- 5. Amostra de linhas atualizadas
SELECT '=== AMOSTRA ===' AS info;
SELECT
  pr.pessoa_a_id,
  pr.pessoa_b_id,
  pr.tipo,
  pr.relacao_a_para_b,
  pr.relacao_b_para_a
FROM pessoas_relacionamentos pr
ORDER BY pr.pessoa_a_id, pr.pessoa_b_id
LIMIT 20;
