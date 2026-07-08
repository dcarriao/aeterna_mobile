-- ============================================================================
-- S.8.7 — Correções no banco
-- ============================================================================
-- Itens:
--   2. Duplicata Darlan (id=7): já está merged_into_id=5 e situacao=pendente.
--      Apenas validar e confirmar.
--   3. Alice (id=6): auditar relação Darlan↔Alice em pessoa_relacionamentos.
--                    Se não existir relação CONJUGE, este SQL cria.
--   5. Memorial Douglas: corrigir usuario_id do memorial id=1.
-- ============================================================================

-- 1. VALIDAÇÃO — Duplicata Darlan (id=7)
SELECT '=== 1. Duplicata Darlan ===' AS info;
SELECT id, nome, sobrenome, situacao, merged_into_id, _legacy_usuario_id
FROM pessoas
WHERE id IN (5, 7)
ORDER BY id;

-- 2. VALIDAÇÃO — Relação Darlan ↔ Alice
SELECT '=== 2. Relacao Darlan (5) x Alice (6) ===' AS info;
SELECT pr.id, pr.pessoa_a_id, pr.pessoa_b_id, pr.tipo,
       pr.relacao_a_para_b, pr.relacao_b_para_a
FROM pessoas_relacionamentos pr
WHERE (pr.pessoa_a_id = 5 AND pr.pessoa_b_id = 6)
   OR (pr.pessoa_a_id = 6 AND pr.pessoa_b_id = 5);

-- 3. VALIDAÇÃO — Memorial Douglas (id=1)
SELECT '=== 3. Memorial Douglas ===' AS info;
SELECT id, nome, usuario_id, parentesco, criado_em
FROM memoriais
WHERE id = 1;

-- ============================================================================
-- FIX
-- ============================================================================

-- 3a. Corrigir usuario_id do Memorial Douglas para Darlan (pessoas.id=5)
--     (mesmo fix do sprint_s8_6_6, caso ainda não tenha sido executado)
UPDATE memoriais
SET usuario_id = 5
WHERE id = 1
  AND (usuario_id IS NULL OR usuario_id != 5);

-- 2a. Criar relação CONJUGE entre Darlan (5) e Alice (6) se não existir
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pessoas_relacionamentos
    WHERE (pessoa_a_id = 5 AND pessoa_b_id = 6)
       OR (pessoa_a_id = 6 AND pessoa_b_id = 5)
  ) THEN
    -- Linha direta: A=Darlan → B=Alice
    INSERT INTO pessoas_relacionamentos
      (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
       relacao_a_para_b, relacao_b_para_a, confirmado)
    VALUES
      (5, 5, 6, 'CONJUGE',
       'Esposo(a)', 'Esposo(a)', true);

    -- Linha inversa: A=Alice → B=Darlan
    INSERT INTO pessoas_relacionamentos
      (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
       relacao_a_para_b, relacao_b_para_a, confirmado)
    VALUES
      (5, 6, 5, 'CONJUGE',
       'Esposo(a)', 'Esposo(a)', true);

    RAISE NOTICE 'Relação CONJUGE criada entre Darlan(5) e Alice(6)';
  ELSE
    RAISE NOTICE 'Relação Darlan↔Alice já existe — nada alterado';
  END IF;
END;
$$;

-- ============================================================================
-- PÓS-VALIDAÇÃO
-- ============================================================================
SELECT '=== POS-FIX: Memorial Douglas ===' AS info;
SELECT id, nome, usuario_id, parentesco
FROM memoriais
WHERE id = 1;

SELECT '=== POS-FIX: Relacao Darlan x Alice ===' AS info;
SELECT pr.id, pr.pessoa_a_id, pr.pessoa_b_id, pr.tipo,
       pr.relacao_a_para_b, pr.relacao_b_para_a
FROM pessoas_relacionamentos pr
WHERE (pr.pessoa_a_id = 5 AND pr.pessoa_b_id = 6)
   OR (pr.pessoa_a_id = 6 AND pr.pessoa_b_id = 5);
