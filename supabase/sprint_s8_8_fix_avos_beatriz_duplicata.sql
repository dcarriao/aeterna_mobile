-- ============================================================================
-- S.8.8 — Corrige avós invertidos da Beatriz + remove duplicata Beatriz 16
-- ============================================================================
-- Problemas:
--   A. Beatriz(10) vê Dionir como "Neto(a)" e Domair como "Neto(a)" —
--      o correto é "Avô" e "Avó". Dados invertidos em pessoas_relacionamentos.
--   B. Beatriz duplicata (id=16) precisa ser removida.
-- ============================================================================
-- ORDEM: rodar INTEIRO (BEGIN … COMMIT).
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- A. DIAGNÓSTICO — relações atuais da Beatriz (10)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT '=== A1. Relacoes de Beatriz(10) com labels ===' AS info;
SELECT pr.id, pr.pessoa_a_id, pr.pessoa_b_id,
       pr.relacao_a_para_b, pr.relacao_b_para_a,
       pa.nome AS nome_a, pb.nome AS nome_b
FROM pessoas_relacionamentos pr
JOIN pessoas pa ON pa.id = pr.pessoa_a_id
JOIN pessoas pb ON pb.id = pr.pessoa_b_id
WHERE pr.pessoa_a_id = 10 OR pr.pessoa_b_id = 10
ORDER BY pr.pessoa_a_id, pr.pessoa_b_id;

-- ═══════════════════════════════════════════════════════════════════════════
-- B. CORREÇÃO — avós invertidos
-- ═══════════════════════════════════════════════════════════════════════════
-- Lógica: Se Beatriz(10) → Dionir tem relacao_b_para_a = 'Neto(a)',
--         o label está trocado. O correto é Beatriz(10) → Dionir: relacao_b_para_a = 'Avô'.
--         E a inversa (Dionir → Beatriz) precisa ter relacao_a_para_b = 'Avô'.
--         Mesma lógica para Domair com 'Avó'.
-- ============================================================================

-- 1. Encontra as relações invertidas: Beatriz(10) como pessoa_a_id
--    onde relacao_b_para_a contém 'Neto' (indica que o avô está como neto)
SELECT '=== B1. Relacoes invertidas encontradas ===' AS info;
SELECT pr.id, pr.pessoa_a_id, pr.pessoa_b_id,
       pr.relacao_a_para_b, pr.relacao_b_para_a,
       pb.nome AS nome_avo
FROM pessoas_relacionamentos pr
JOIN pessoas pb ON pb.id = pr.pessoa_b_id
WHERE pr.pessoa_a_id = 10
  AND pr.relacao_b_para_a ILIKE '%neto%';

-- 2. Corrige: troca relacao_b_para_a de 'Neto(a)' para 'Avô'/'Avó'
--    Usa o nome para determinar gênero
UPDATE pessoas_relacionamentos
SET relacao_b_para_a = CASE
    WHEN pb.nome IN ('Dionir') THEN 'Avô'
    WHEN pb.nome IN ('Domair') THEN 'Avó'
    ELSE 'Avô/Avó'
  END,
  relacao_a_para_b = CASE
    WHEN pb.nome IN ('Dionir') THEN 'Neto(a)'
    WHEN pb.nome IN ('Domair') THEN 'Neto(a)'
    ELSE 'Neto(a)'
  END
FROM pessoas pb
WHERE pessoas_relacionamentos.pessoa_a_id = 10
  AND pessoas_relacionamentos.pessoa_b_id = pb.id
  AND pessoas_relacionamentos.relacao_b_para_a ILIKE '%neto%';

-- 3. Corrige a inversa: a linha onde o avô é pessoa_a_id e Beatriz é pessoa_b_id
--    Deve ter relacao_a_para_b = 'Avô'/'Avó' e relacao_b_para_a = 'Neto(a)'
UPDATE pessoas_relacionamentos
SET relacao_a_para_b = CASE
    WHEN pa.nome IN ('Dionir') THEN 'Avô'
    WHEN pa.nome IN ('Domair') THEN 'Avó'
    ELSE 'Avô/Avó'
  END,
  relacao_b_para_a = 'Neto(a)'
FROM pessoas pa
WHERE pessoas_relacionamentos.pessoa_b_id = 10
  AND pessoas_relacionamentos.pessoa_a_id = pa.id
  AND pessoas_relacionamentos.relacao_a_para_b ILIKE '%neto%';

-- ═══════════════════════════════════════════════════════════════════════════
-- C. VALIDAÇÃO PÓS-CORREÇÃO DOS AVÓS
-- ═══════════════════════════════════════════════════════════════════════════
SELECT '=== C1. Relacoes de Beatriz(10) apos correcao ===' AS info;
SELECT pr.id, pr.pessoa_a_id, pr.pessoa_b_id,
       pr.relacao_a_para_b, pr.relacao_b_para_a,
       pa.nome AS nome_a, pb.nome AS nome_b
FROM pessoas_relacionamentos pr
JOIN pessoas pa ON pa.id = pr.pessoa_a_id
JOIN pessoas pb ON pb.id = pr.pessoa_b_id
WHERE pr.pessoa_a_id = 10 OR pr.pessoa_b_id = 10
ORDER BY pr.pessoa_a_id, pr.pessoa_b_id;

-- ═══════════════════════════════════════════════════════════════════════════
-- D. REMOVER DUPLICATA BEATRIZ 16
-- ═══════════════════════════════════════════════════════════════════════════
SELECT '=== D1. Beatriz canonica(10) e duplicata(16) ===' AS info;
SELECT id, nome, sobrenome, email, situacao, criado_por_id,
       merged_into_id, _legacy_usuario_id, _legacy_contato_id
FROM pessoas
WHERE id IN (10, 16)
ORDER BY id;

-- D2. Auditar refs a 16
SELECT '=== D2. REFS: pessoas_relacionamentos p/ 16 ===' AS info;
SELECT id, pessoa_a_id, pessoa_b_id, tipo, relacao_a_para_b, relacao_b_para_a
FROM pessoas_relacionamentos
WHERE pessoa_a_id = 16 OR pessoa_b_id = 16;

-- D3. Migrar refs 16→10 (com proteção UNIQUE)
DELETE FROM pessoas_relacionamentos
WHERE id IN (
  SELECT pr1.id FROM pessoas_relacionamentos pr1
  JOIN pessoas_relacionamentos pr2 ON (
    pr2.pessoa_a_id = CASE
      WHEN pr1.pessoa_a_id = 16 THEN 10 ELSE pr1.pessoa_a_id
    END
    AND pr2.pessoa_b_id = CASE
      WHEN pr1.pessoa_b_id = 16 THEN 10 ELSE pr1.pessoa_b_id
    END
    AND pr2.id != pr1.id
  )
  WHERE pr1.pessoa_a_id = 16 OR pr1.pessoa_b_id = 16
);
UPDATE pessoas_relacionamentos SET pessoa_a_id = 10 WHERE pessoa_a_id = 16;
UPDATE pessoas_relacionamentos SET pessoa_b_id = 10 WHERE pessoa_b_id = 16;

-- D4. Migrar demais tabelas
UPDATE pessoas SET criado_por_id = 10 WHERE criado_por_id = 16;
UPDATE pessoas SET merged_into_id = 10 WHERE merged_into_id = 16;
UPDATE conteudo_permissoes SET pessoa_id = 10 WHERE pessoa_id = 16;
UPDATE memorial_pessoas SET pessoa_id = 10 WHERE pessoa_id = 16;
UPDATE convites_familiares SET pessoa_id = 10 WHERE pessoa_id = 16;
UPDATE pessoa_identificadores SET pessoa_id = 10 WHERE pessoa_id = 16;
UPDATE migracao_pessoas_map SET nova_pessoa_id = 10 WHERE nova_pessoa_id = 16;
UPDATE memorias SET usuario_id = 10 WHERE usuario_id = 16;
UPDATE memoriais SET usuario_id = 10 WHERE usuario_id = 16;
UPDATE fotos SET usuario_id = 10 WHERE usuario_id = 16;
UPDATE videos SET usuario_id = 10 WHERE usuario_id = 16;
UPDATE contribuicoes SET usuario_dono_id = 10 WHERE usuario_dono_id = 16;
UPDATE mensagens_futuro SET destinatario_id = 10 WHERE destinatario_id = 16;
UPDATE conteudo_colaboradores SET usuario_id = 10 WHERE usuario_id = 16;

-- D5. Verificar se todas as refs foram zeradas
SELECT '=== D5. POS-MIGRACAO: refs restantes p/ 16 ===' AS info;
SELECT 'criado_por_id', COUNT(*) FROM pessoas WHERE criado_por_id = 16
UNION ALL SELECT 'merged_into_id', COUNT(*) FROM pessoas WHERE merged_into_id = 16
UNION ALL SELECT 'conteudo_permissoes', COUNT(*) FROM conteudo_permissoes WHERE pessoa_id = 16
UNION ALL SELECT 'memorial_pessoas', COUNT(*) FROM memorial_pessoas WHERE pessoa_id = 16
UNION ALL SELECT 'pessoas_rel_a', COUNT(*) FROM pessoas_relacionamentos WHERE pessoa_a_id = 16
UNION ALL SELECT 'pessoas_rel_b', COUNT(*) FROM pessoas_relacionamentos WHERE pessoa_b_id = 16
UNION ALL SELECT 'convites_familiares', COUNT(*) FROM convites_familiares WHERE pessoa_id = 16
UNION ALL SELECT 'pessoa_identificadores', COUNT(*) FROM pessoa_identificadores WHERE pessoa_id = 16
UNION ALL SELECT 'migracao_pessoas_map', COUNT(*) FROM migracao_pessoas_map WHERE nova_pessoa_id = 16
UNION ALL SELECT 'memorias', COUNT(*) FROM memorias WHERE usuario_id = 16
UNION ALL SELECT 'memoriais', COUNT(*) FROM memoriais WHERE usuario_id = 16
UNION ALL SELECT 'fotos', COUNT(*) FROM fotos WHERE usuario_id = 16
UNION ALL SELECT 'videos', COUNT(*) FROM videos WHERE usuario_id = 16
UNION ALL SELECT 'contribuicoes', COUNT(*) FROM contribuicoes WHERE usuario_dono_id = 16
UNION ALL SELECT 'mensagens_futuro', COUNT(*) FROM mensagens_futuro WHERE destinatario_id = 16
UNION ALL SELECT 'conteudo_colaboradores', COUNT(*) FROM conteudo_colaboradores WHERE usuario_id = 16;

-- D6. Remover
SELECT '=== D6. Removendo Beatriz 16 ===' AS info;
DELETE FROM pessoas WHERE id = 16;

-- D7. Validar remocao
SELECT '=== D7. Beatriz 16 removida? ===' AS info;
SELECT COUNT(*) = 0 AS removida FROM pessoas WHERE id = 16;
SELECT 'Beatriz 10 preservada:' AS info;
SELECT id, nome, sobrenome, email FROM pessoas WHERE id = 10;

COMMIT;
