-- Remove Beatriz duplicata (id=17) e suas relações
BEGIN;

SELECT '=== Relacoes de Beatriz 17 ===' AS info;
SELECT id, pessoa_a_id, pessoa_b_id, tipo, relacao_a_para_b, relacao_b_para_a
FROM pessoas_relacionamentos
WHERE pessoa_a_id = 17 OR pessoa_b_id = 17;

DELETE FROM pessoas_relacionamentos
WHERE pessoa_a_id = 17 OR pessoa_b_id = 17;

SELECT '=== Removendo Beatriz 17 ===' AS info;
DELETE FROM pessoas WHERE id = 17;

SELECT '=== Verificacao: Beatriz restantes ===' AS info;
SELECT id, nome, sobrenome FROM pessoas WHERE nome ILIKE '%beatriz%' ORDER BY id;

COMMIT;
