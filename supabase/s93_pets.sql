-- =============================================================================
-- SPRINT S.9.3 — SEÇÃO DE PETS
-- Arquivo  : supabase/s93_pets.sql
-- Executar : SQL Editor do Supabase (projeto zfpvfljmnlgsqiqdxmka)
-- Downtime : Nenhum
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tipos de relação Tutor ↔ Pet
-- -----------------------------------------------------------------------------
INSERT INTO tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria, nivel, ativo)
VALUES
  ('TUTOR',  'Tutor',  'Pet de', 'pet', 80, true),
  ('PET_DE', 'Pet de', 'Tutor',  'pet', 80, true)
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. Constraint de integridade: pet nunca pode ter auth_user_id nem auth_id
-- -----------------------------------------------------------------------------
ALTER TABLE pessoas
  DROP CONSTRAINT IF EXISTS chk_pet_sem_auth;

ALTER TABLE pessoas
  ADD CONSTRAINT chk_pet_sem_auth
  CHECK (
    tipo <> 'pet'
    OR (auth_user_id IS NULL AND auth_id IS NULL)
  );

-- =============================================================================
-- QUERIES DE VALIDAÇÃO (executar separadamente para confirmar)
-- =============================================================================

-- 1. Pets cadastrados (deve listar sem auth_user_id/auth_id preenchidos)
SELECT id, nome, tipo, auth_user_id, auth_id
FROM pessoas
WHERE tipo = 'pet';

-- 2. Violações da constraint (deve retornar 0 linhas)
SELECT id, nome, tipo, auth_user_id, auth_id
FROM pessoas
WHERE tipo = 'pet'
  AND (auth_user_id IS NOT NULL OR auth_id IS NOT NULL);

-- 3. Confirmar tipos inseridos
SELECT id, rotulo_a_para_b, rotulo_b_para_a, categoria, nivel, ativo
FROM tipos_relacionamento
WHERE id IN ('TUTOR', 'PET_DE');
