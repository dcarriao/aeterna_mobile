-- =============================================================================
-- SPRINT S.9.3.1 — ESPÉCIE E RAÇA DO PET (Item 2)
-- Arquivo  : supabase/sprint_s9_3_1_pet_especie_raca.sql
-- Executar : SQL Editor do Supabase — ANTES de distribuir o build S.9.3.1
--            (o app passa a selecionar as colunas especie/raca).
-- Downtime : Nenhum (ALTER TABLE aditivo, colunas nullable, sem rewrite)
-- Rollback : ALTER TABLE pessoas DROP COLUMN IF EXISTS especie;
--            ALTER TABLE pessoas DROP COLUMN IF EXISTS raca;
-- =============================================================================

-- 0. AUDITORIA PRÉVIA — os campos já existem?
--    (Se retornar linhas, as colunas já existem e o passo 1 é no-op.)
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'pessoas'
  AND column_name IN ('especie', 'raca');

-- 1. MIGRATION ADITIVA (idempotente)
ALTER TABLE pessoas ADD COLUMN IF NOT EXISTS especie text NULL;
ALTER TABLE pessoas ADD COLUMN IF NOT EXISTS raca    text NULL;

COMMENT ON COLUMN pessoas.especie IS
  'S.9.3.1 — Espécie do pet (Cachorro, Gato, ... ou texto livre). NULL para humanos.';
COMMENT ON COLUMN pessoas.raca IS
  'S.9.3.1 — Raça do pet (texto livre, opcional). NULL para humanos.';

-- 2. GARANTIA: humanos nunca carregam espécie/raça
--    (o app já não grava; a constraint blinda contra regressão)
ALTER TABLE pessoas DROP CONSTRAINT IF EXISTS chk_especie_raca_apenas_pet;
ALTER TABLE pessoas
  ADD CONSTRAINT chk_especie_raca_apenas_pet
  CHECK (
    tipo = 'pet'
    OR (especie IS NULL AND raca IS NULL)
  );

-- =============================================================================
-- QUERIES DE VALIDAÇÃO (executar separadamente)
-- =============================================================================

-- V1. Colunas criadas (deve retornar 2 linhas, ambas is_nullable = YES)
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'pessoas'
  AND column_name IN ('especie', 'raca');

-- V2. Nenhum humano com espécie/raça (deve retornar 0 linhas)
SELECT id, nome, tipo, especie, raca
FROM pessoas
WHERE tipo <> 'pet'
  AND (especie IS NOT NULL OR raca IS NOT NULL);

-- V3. Pets existentes intactos (nenhum apagado; especie/raca começam NULL)
SELECT id, nome, tipo, especie, raca, situacao
FROM pessoas
WHERE tipo = 'pet'
ORDER BY id;
