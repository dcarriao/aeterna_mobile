-- ============================================================
-- Sprint S.8 — Correção de pessoas_relacionamentos
-- Base: contatos.parentesco de usuario_id=2 (Darlan)
-- ============================================================
-- Mapeamento Darlan(5) x pessoas via contatos:
--   contato 3 (Dionir, Pai)   → pessoa 8
--   contato 4 (Beatriz, Filha) → pessoa 10
--   contato 5 (Andrey, Irmão) → pessoa 11
--   contato 6 (Delaine, Irmã) → pessoa 12
--   contato 2 (Alice, Cônjuge) → pessoa 9→merged 6
-- ============================================================

BEGIN;

-- Zera tudo
DELETE FROM pessoas_relacionamentos;

-- Insere com base nos contatos do Darlan (usuario_id=2)
-- Cada contato gera DUAS linhas (A→B e B→A)

-- H1. Dionir(8) = Pai de Darlan → Darlan(5) FILHO DE Dionir(8)
--     Darlan(5) FILHO → Dionir(8) PAI
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5, 8, 'FILHO', 'Filho(a)', 'Pai', true),
    (5, 8, 5, 'PAI',   'Pai',      'Filho(a)', true);

-- H2. Beatriz(10) = Filha de Darlan → Darlan(5) PAI DE Beatriz(10)
--     Darlan(5) PAI → Beatriz(10) FILHA
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5,  10, 'PAI',   'Pai',      'Filho(a)', true),
    (5, 10, 5,  'FILHA', 'Filho(a)', 'Pai',      true);

-- H3. Andrey(11) = Irmão de Darlan → Darlan(5) IRMÃO DE Andrey(11)
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5,  11, 'IRMAO', 'Irmão(ã)', 'Irmão(ã)', true),
    (5, 11, 5,  'IRMAO', 'Irmão(ã)', 'Irmão(ã)', true);

-- H4. Delaine(12) = Irmã de Darlan → Darlan(5) IRMÃO DE Delaine(12)
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5,  12, 'IRMAO', 'Irmão(ã)', 'Irmão(ã)', true),
    (5, 12, 5,  'IRMAO', 'Irmão(ã)', 'Irmão(ã)', true);

-- H5. Alice(6) = Cônjuge de Darlan
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5, 6, 'CONJUGE', 'Esposo(a)', 'Esposo(a)', true),
    (5, 6, 5, 'CONJUGE', 'Esposo(a)', 'Esposo(a)', true);

DO $$ BEGIN
    RAISE NOTICE 'pessoas_relacionamentos recriados: % linhas',
        (SELECT count(*) FROM pessoas_relacionamentos);
END $$;

COMMIT;
