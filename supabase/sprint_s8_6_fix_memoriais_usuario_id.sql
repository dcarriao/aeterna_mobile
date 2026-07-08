-- ============================================================================
-- S.8.6.6 — Fix memoriais.usuario_id
-- ============================================================================
-- Problema: memoriais legados têm usuario_id = NULL ou apontando para
--           o Test User (id=13) que não é o dono real.
--
-- Dono real: Darlan (pessoas.id=5, _legacy_usuario_id=2, situacao='ativo').
--            É a única pessoa com _legacy_usuario_id + situacao='ativo'
--            que é raiz da árvore (criado_por_id=null).
--
-- Não recria/apaga memorial. Não altera conversa_curador. Não perde fotos.
-- ============================================================================

-- 1. VALIDAÇÃO — estado atual
SELECT '=== 1. STATE: memoriais ===' AS info;
SELECT id, nome, parentesco, usuario_id, criado_em
FROM memoriais
ORDER BY id;

-- 2. VALIDAÇÃO — descobrir quem é o dono real
SELECT '=== 2. STATE: possiveis donos ===' AS info;
SELECT id, nome, sobrenome, situacao, _legacy_usuario_id, auth_user_id, criado_por_id
FROM pessoas
WHERE _legacy_usuario_id IS NOT NULL
   OR auth_user_id IS NOT NULL
ORDER BY id;

-- 3. Dono real (Darlan): _legacy_usuario_id IS NOT NULL, situacao='ativo',
--    criado_por_id IS NULL (raiz da árvore)
SELECT '=== 3. Dono real detectado ===' AS info;
SELECT id, nome, sobrenome
FROM pessoas
WHERE _legacy_usuario_id IS NOT NULL
  AND situacao = 'ativo'
  AND criado_por_id IS NULL
ORDER BY id
LIMIT 1;

-- ============================================================================
-- FIX
-- ============================================================================
DO $$
DECLARE
  dono_id BIGINT;
  linhas  INT;
BEGIN
  -- Encontra o dono real: _legacy_usuario_id preenchido, ativo,
  -- criado_por_id IS NULL (raiz da árvore familiar)
  SELECT id INTO dono_id FROM pessoas
  WHERE _legacy_usuario_id IS NOT NULL
    AND situacao = 'ativo'
    AND criado_por_id IS NULL
  ORDER BY id
  LIMIT 1;

  IF dono_id IS NOT NULL THEN
    -- Corrige memoriais SEM dono (usuario_id IS NULL)
    UPDATE memoriais
    SET usuario_id = dono_id
    WHERE usuario_id IS NULL;

    GET DIAGNOSTICS linhas = ROW_COUNT;
    RAISE NOTICE 'UPDATE NULL: % memoriais corrigidos para usuario_id = %', linhas, dono_id;

    -- Corrige memoriais com dono INVÁLIDO (apontando para pessoa
    -- que não tem _legacy_usuario_id, ex: Test User id=13)
    UPDATE memoriais m
    SET usuario_id = dono_id
    WHERE m.usuario_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM pessoas p
        WHERE p.id = m.usuario_id
          AND p._legacy_usuario_id IS NOT NULL
      );

    GET DIAGNOSTICS linhas = ROW_COUNT;
    RAISE NOTICE 'UPDATE INVALIDO: % memoriais corrigidos para usuario_id = %', linhas, dono_id;
  ELSE
    RAISE WARNING 'Nenhum dono encontrado';
  END IF;
END;
$$;

-- ============================================================================
-- PÓS-VALIDAÇÃO
-- ============================================================================
SELECT '=== 4. POS-FIX: memoriais ===' AS info;
SELECT id, nome, parentesco, usuario_id, criado_em
FROM memoriais
ORDER BY id;
