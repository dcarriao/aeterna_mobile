-- ============================================================================
-- Remove duplicata Beatriz (16), canônica = Beatriz (10)
-- ============================================================================
-- Beatriz canônica: id=10, filha de Darlan, criada do contato legado 4
-- Beatriz duplicata: id=16
-- ============================================================================

BEGIN;

-- 1. EVIDÊNCIA
SELECT '=== 1. Beatriz canônica (10) e duplicata (16) ===' AS info;
SELECT id, nome, sobrenome, email, situacao, criado_por_id,
       merged_into_id, _legacy_usuario_id, _legacy_contato_id,
       auth_user_id, data_nascimento
FROM pessoas
WHERE id IN (10, 16)
ORDER BY id;

-- 2. AUDITAR REFERÊNCIAS A 16
SELECT '=== 2. REFS: pessoas.criado_por_id/merged_into_id ===' AS info;
SELECT id, nome, criado_por_id, merged_into_id
FROM pessoas
WHERE criado_por_id = 16 OR merged_into_id = 16;

SELECT '=== 2b. REFS: conteudo_permissoes ===' AS info;
SELECT id, tipo_conteudo, conteudo_id, pessoa_id
FROM conteudo_permissoes
WHERE pessoa_id = 16;

SELECT '=== 2c. REFS: memorial_pessoas ===' AS info;
SELECT id, memorial_id, pessoa_id
FROM memorial_pessoas
WHERE pessoa_id = 16;

SELECT '=== 2d. REFS: pessoas_relacionamentos (pessoa_a_id) ===' AS info;
SELECT id, pessoa_a_id, pessoa_b_id, tipo
FROM pessoas_relacionamentos
WHERE pessoa_a_id = 16;

SELECT '=== 2e. REFS: pessoas_relacionamentos (pessoa_b_id) ===' AS info;
SELECT id, pessoa_a_id, pessoa_b_id, tipo
FROM pessoas_relacionamentos
WHERE pessoa_b_id = 16;

SELECT '=== 2f. REFS: convites_familiares ===' AS info;
SELECT id, pessoa_id, email_destino, status
FROM convites_familiares
WHERE pessoa_id = 16;

SELECT '=== 2g. REFS: pessoa_identificadores ===' AS info;
SELECT * FROM pessoa_identificadores
WHERE pessoa_id = 16;

SELECT '=== 2h. REFS: migracao_pessoas_map ===' AS info;
SELECT * FROM migracao_pessoas_map
WHERE nova_pessoa_id = 16;

SELECT '=== 2i. REFS: memorias (usuario_id) ===' AS info;
SELECT id, titulo, usuario_id FROM memorias WHERE usuario_id = 16;

SELECT '=== 2j. REFS: memoriais (usuario_id) ===' AS info;
SELECT id, nome, usuario_id FROM memoriais WHERE usuario_id = 16;

SELECT '=== 2k. REFS: fotos (usuario_id) ===' AS info;
SELECT id, usuario_id FROM fotos WHERE usuario_id = 16;

SELECT '=== 2l. REFS: videos (usuario_id) ===' AS info;
SELECT id, usuario_id FROM videos WHERE usuario_id = 16;

SELECT '=== 2m. REFS: contribuicoes (usuario_dono_id) ===' AS info;
SELECT id, texto, usuario_dono_id FROM contribuicoes WHERE usuario_dono_id = 16;

SELECT '=== 2n. REFS: mensagens_futuro (destinatario_id) ===' AS info;
SELECT id, conteudo, destinatario_id FROM mensagens_futuro WHERE destinatario_id = 16;

SELECT '=== 2o. REFS: conteudo_colaboradores (usuario_id) ===' AS info;
SELECT id, conteudo_id, tipo_conteudo, usuario_id
FROM conteudo_colaboradores WHERE usuario_id = 16;

-- 3. MIGRAR REFERÊNCIAS 16 → 10
SELECT '=== 3. MIGRANDO REFERENCIAS 16 → 10 ===' AS info;

UPDATE pessoas SET criado_por_id = 10 WHERE criado_por_id = 16;
UPDATE pessoas SET merged_into_id = 10 WHERE merged_into_id = 16;

UPDATE conteudo_permissoes SET pessoa_id = 10 WHERE pessoa_id = 16;

UPDATE memorial_pessoas SET pessoa_id = 10 WHERE pessoa_id = 16;

-- Evitar UNIQUE conflict em pessoas_relacionamentos
DELETE FROM pessoas_relacionamentos
WHERE id IN (
  SELECT pr1.id FROM pessoas_relacionamentos pr1
  JOIN pessoas_relacionamentos pr2 ON (
    pr2.pessoa_a_id = CASE
      WHEN pr1.pessoa_a_id = 16 THEN 10
      ELSE pr1.pessoa_a_id
    END
    AND pr2.pessoa_b_id = CASE
      WHEN pr1.pessoa_b_id = 16 THEN 10
      ELSE pr1.pessoa_b_id
    END
    AND pr2.id != pr1.id
  )
  WHERE pr1.pessoa_a_id = 16 OR pr1.pessoa_b_id = 16
);
UPDATE pessoas_relacionamentos SET pessoa_a_id = 10 WHERE pessoa_a_id = 16;
UPDATE pessoas_relacionamentos SET pessoa_b_id = 10 WHERE pessoa_b_id = 16;

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

-- 4. VALIDAÇÃO INTERMEDIÁRIA
SELECT '=== 4. POS-MIGRACAO: refs restantes p/ 16 ===' AS info;
SELECT 'criado_por_id' AS tabela, COUNT(*) FROM pessoas WHERE criado_por_id = 16
UNION ALL
SELECT 'merged_into_id', COUNT(*) FROM pessoas WHERE merged_into_id = 16
UNION ALL
SELECT 'conteudo_permissoes', COUNT(*) FROM conteudo_permissoes WHERE pessoa_id = 16
UNION ALL
SELECT 'memorial_pessoas', COUNT(*) FROM memorial_pessoas WHERE pessoa_id = 16
UNION ALL
SELECT 'pessoas_rel_a', COUNT(*) FROM pessoas_relacionamentos WHERE pessoa_a_id = 16
UNION ALL
SELECT 'pessoas_rel_b', COUNT(*) FROM pessoas_relacionamentos WHERE pessoa_b_id = 16
UNION ALL
SELECT 'convites_familiares', COUNT(*) FROM convites_familiares WHERE pessoa_id = 16
UNION ALL
SELECT 'pessoa_identificadores', COUNT(*) FROM pessoa_identificadores WHERE pessoa_id = 16
UNION ALL
SELECT 'migracao_pessoas_map', COUNT(*) FROM migracao_pessoas_map WHERE nova_pessoa_id = 16
UNION ALL
SELECT 'memorias', COUNT(*) FROM memorias WHERE usuario_id = 16
UNION ALL
SELECT 'memoriais', COUNT(*) FROM memoriais WHERE usuario_id = 16
UNION ALL
SELECT 'fotos', COUNT(*) FROM fotos WHERE usuario_id = 16
UNION ALL
SELECT 'videos', COUNT(*) FROM videos WHERE usuario_id = 16
UNION ALL
SELECT 'contribuicoes', COUNT(*) FROM contribuicoes WHERE usuario_dono_id = 16
UNION ALL
SELECT 'mensagens_futuro', COUNT(*) FROM mensagens_futuro WHERE destinatario_id = 16
UNION ALL
SELECT 'conteudo_colaboradores', COUNT(*) FROM conteudo_colaboradores WHERE usuario_id = 16;

-- 5. REMOVER
SELECT '=== 5. REMOVENDO Beatriz 16 ===' AS info;
DELETE FROM pessoas WHERE id = 16;

-- 6. VALIDAÇÃO FINAL
SELECT '=== 6. POS-FIX: Beatriz 16 removida? ===' AS info;
SELECT COUNT(*) = 0 AS removida FROM pessoas WHERE id = 16;

SELECT '=== 6b. Beatriz canônica 10 preservada ===' AS info;
SELECT id, nome, sobrenome, email FROM pessoas WHERE id = 10;

COMMIT;
