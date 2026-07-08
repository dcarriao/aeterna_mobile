-- ============================================================================
-- S.8.7 — Remove duplicatas reais de pessoas (7=Darlan dup, 9=Alice dup)
-- ============================================================================
-- Duplicatas conhecidas:
--   Pessoa 7: Darlan, criado de contato legado (_legacy_contato_id=1),
--             merged_into_id=5, situacao=pendente, sem auth, sem memórias.
--   Pessoa 9: Alice, criada de contato legado (_legacy_contato_id=2),
--             merged_into_id=6, situacao=pendente, sem auth, sem memórias.
--
-- Antes de apagar: migrar TODAS as referências de 7→5 e 9→6.
-- Só apagar após zerar referências.
-- Não apaga: pessoa 5 (Darlan canônico), pessoa 6 (Alice canônica).
-- Não executa F4.
-- Não faz cleanup genérico.
-- ============================================================================
-- ORDEM DE EXECUÇÃO: rodar o arquivo INTEIRO (BEGIN … COMMIT).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. VALIDAÇÃO INICIAL — evidência das duplicatas
-- ============================================================================
SELECT '=== 1. EVIDENCIA: duplicatas ===' AS info;
SELECT id, nome, sobrenome, email, situacao, criado_por_id,
       merged_into_id, _legacy_usuario_id, _legacy_contato_id,
       auth_user_id, data_nascimento
FROM pessoas
WHERE id IN (7, 9)
ORDER BY id;

SELECT '=== 1b. EVIDENCIA: canonicas ===' AS info;
SELECT id, nome, sobrenome, email, situacao, criado_por_id,
       merged_into_id, _legacy_usuario_id, _legacy_contato_id,
       auth_user_id, data_nascimento
FROM pessoas
WHERE id IN (5, 6)
ORDER BY id;

-- ============================================================================
-- 2. VALIDAÇÃO — mapear TODAS as referências para 7 e 9
-- ============================================================================
SELECT '=== 2. REFS: pessoas.criado_por_id/merged_into_id ===' AS info;
SELECT id, nome, criado_por_id, merged_into_id
FROM pessoas
WHERE criado_por_id IN (7, 9) OR merged_into_id IN (7, 9);

SELECT '=== 2b. REFS: conteudo_permissoes ===' AS info;
SELECT id, tipo_conteudo, conteudo_id, pessoa_id
FROM conteudo_permissoes
WHERE pessoa_id IN (7, 9);

SELECT '=== 2c. REFS: memorial_pessoas ===' AS info;
SELECT id, memorial_id, pessoa_id
FROM memorial_pessoas
WHERE pessoa_id IN (7, 9);

SELECT '=== 2d. REFS: pessoas_relacionamentos (pessoa_a_id) ===' AS info;
SELECT id, pessoa_a_id, pessoa_b_id, tipo
FROM pessoas_relacionamentos
WHERE pessoa_a_id IN (7, 9);

SELECT '=== 2e. REFS: pessoas_relacionamentos (pessoa_b_id) ===' AS info;
SELECT id, pessoa_a_id, pessoa_b_id, tipo
FROM pessoas_relacionamentos
WHERE pessoa_b_id IN (7, 9);

SELECT '=== 2f. REFS: convites_familiares ===' AS info;
SELECT id, pessoa_id, email_destino, status
FROM convites_familiares
WHERE pessoa_id IN (7, 9);

SELECT '=== 2g. REFS: pessoa_identificadores ===' AS info;
SELECT * FROM pessoa_identificadores
WHERE pessoa_id IN (7, 9);

SELECT '=== 2h. REFS: migracao_pessoas_map ===' AS info;
SELECT * FROM migracao_pessoas_map
WHERE nova_pessoa_id IN (7, 9);

-- Tabelas com usuario_id migrado (7 e 9 podem ter sido usados como donos)
SELECT '=== 2i. REFS: memorias (usuario_id) ===' AS info;
SELECT id, titulo, usuario_id FROM memorias WHERE usuario_id IN (7, 9);

SELECT '=== 2j. REFS: memoriais (usuario_id) ===' AS info;
SELECT id, nome, usuario_id FROM memoriais WHERE usuario_id IN (7, 9);

SELECT '=== 2k. REFS: fotos (usuario_id) ===' AS info;
SELECT id, usuario_id FROM fotos WHERE usuario_id IN (7, 9);

SELECT '=== 2l. REFS: videos (usuario_id) ===' AS info;
SELECT id, usuario_id FROM videos WHERE usuario_id IN (7, 9);

SELECT '=== 2m. REFS: contribuicoes (usuario_dono_id) ===' AS info;
SELECT id, texto, usuario_dono_id FROM contribuicoes WHERE usuario_dono_id IN (7, 9);

SELECT '=== 2n. REFS: mensagens_futuro (destinatario_id) ===' AS info;
SELECT id, conteudo, destinatario_id FROM mensagens_futuro WHERE destinatario_id IN (7, 9);

SELECT '=== 2o. REFS: conteudo_colaboradores (usuario_id) ===' AS info;
SELECT id, conteudo_id, tipo_conteudo, usuario_id
FROM conteudo_colaboradores WHERE usuario_id IN (7, 9);

-- ============================================================================
-- 3. MIGRAÇÃO — atualizar referências de 7→5 e 9→6
-- ============================================================================
SELECT '=== 3. MIGRANDO REFERENCIAS ===' AS info;

-- 3a. Auto-referências na tabela pessoas
UPDATE pessoas SET criado_por_id = 5 WHERE criado_por_id = 7;
UPDATE pessoas SET criado_por_id = 6 WHERE criado_por_id = 9;
UPDATE pessoas SET merged_into_id = 5 WHERE merged_into_id = 7;
UPDATE pessoas SET merged_into_id = 6 WHERE merged_into_id = 9;

-- 3b. conteudo_permissoes
UPDATE conteudo_permissoes SET pessoa_id = 5 WHERE pessoa_id = 7;
UPDATE conteudo_permissoes SET pessoa_id = 6 WHERE pessoa_id = 9;

-- 3c. memorial_pessoas
UPDATE memorial_pessoas SET pessoa_id = 5 WHERE pessoa_id = 7;
UPDATE memorial_pessoas SET pessoa_id = 6 WHERE pessoa_id = 9;

-- 3d. pessoas_relacionamentos (pessoa_a_id e pessoa_b_id)
-- Evita conflito UNIQUE ao migrar 7→5 ou 9→6: deleta duplicatas resultantes
DELETE FROM pessoas_relacionamentos
WHERE id IN (
  SELECT pr1.id FROM pessoas_relacionamentos pr1
  JOIN pessoas_relacionamentos pr2 ON (
    pr2.pessoa_a_id = CASE
      WHEN pr1.pessoa_a_id = 7 THEN 5
      WHEN pr1.pessoa_a_id = 9 THEN 6
      ELSE pr1.pessoa_a_id
    END
    AND pr2.pessoa_b_id = CASE
      WHEN pr1.pessoa_b_id = 7 THEN 5
      WHEN pr1.pessoa_b_id = 9 THEN 6
      ELSE pr1.pessoa_b_id
    END
    AND pr2.id != pr1.id
  )
  WHERE pr1.pessoa_a_id IN (7, 9) OR pr1.pessoa_b_id IN (7, 9)
);
UPDATE pessoas_relacionamentos SET pessoa_a_id = 5 WHERE pessoa_a_id = 7;
UPDATE pessoas_relacionamentos SET pessoa_a_id = 6 WHERE pessoa_a_id = 9;
UPDATE pessoas_relacionamentos SET pessoa_b_id = 5 WHERE pessoa_b_id = 7;
UPDATE pessoas_relacionamentos SET pessoa_b_id = 6 WHERE pessoa_b_id = 9;

-- 3e. convites_familiares
UPDATE convites_familiares SET pessoa_id = 5 WHERE pessoa_id = 7;
UPDATE convites_familiares SET pessoa_id = 6 WHERE pessoa_id = 9;

-- 3f. pessoa_identificadores
UPDATE pessoa_identificadores SET pessoa_id = 5 WHERE pessoa_id = 7;
UPDATE pessoa_identificadores SET pessoa_id = 6 WHERE pessoa_id = 9;

-- 3g. migracao_pessoas_map
UPDATE migracao_pessoas_map SET nova_pessoa_id = 5 WHERE nova_pessoa_id = 7;
UPDATE migracao_pessoas_map SET nova_pessoa_id = 6 WHERE nova_pessoa_id = 9;

-- 3h. Tabelas com usuario_id migrado (verificacao segura)
UPDATE memorias SET usuario_id = 5 WHERE usuario_id = 7;
UPDATE memorias SET usuario_id = 6 WHERE usuario_id = 9;
UPDATE memoriais SET usuario_id = 5 WHERE usuario_id = 7;
UPDATE memoriais SET usuario_id = 6 WHERE usuario_id = 9;
UPDATE fotos SET usuario_id = 5 WHERE usuario_id = 7;
UPDATE fotos SET usuario_id = 6 WHERE usuario_id = 9;
UPDATE videos SET usuario_id = 5 WHERE usuario_id = 7;
UPDATE videos SET usuario_id = 6 WHERE usuario_id = 9;
UPDATE contribuicoes SET usuario_dono_id = 5 WHERE usuario_dono_id = 7;
UPDATE contribuicoes SET usuario_dono_id = 6 WHERE usuario_dono_id = 9;
UPDATE mensagens_futuro SET destinatario_id = 5 WHERE destinatario_id = 7;
UPDATE mensagens_futuro SET destinatario_id = 6 WHERE destinatario_id = 9;
UPDATE conteudo_colaboradores SET usuario_id = 5 WHERE usuario_id = 7;
UPDATE conteudo_colaboradores SET usuario_id = 6 WHERE usuario_id = 9;

-- ============================================================================
-- 4. VALIDAÇÃO INTERMEDIÁRIA — confirmar que referências foram zeradas
-- ============================================================================
SELECT '=== 4. POS-MIGRACAO: refs restantes ===' AS info;
SELECT 'criado_por_id' AS tabela, COUNT(*) FROM pessoas WHERE criado_por_id IN (7,9)
UNION ALL
SELECT 'merged_into_id', COUNT(*) FROM pessoas WHERE merged_into_id IN (7,9)
UNION ALL
SELECT 'conteudo_permissoes', COUNT(*) FROM conteudo_permissoes WHERE pessoa_id IN (7,9)
UNION ALL
SELECT 'memorial_pessoas', COUNT(*) FROM memorial_pessoas WHERE pessoa_id IN (7,9)
UNION ALL
SELECT 'pessoas_rel_a', COUNT(*) FROM pessoas_relacionamentos WHERE pessoa_a_id IN (7,9)
UNION ALL
SELECT 'pessoas_rel_b', COUNT(*) FROM pessoas_relacionamentos WHERE pessoa_b_id IN (7,9)
UNION ALL
SELECT 'convites_familiares', COUNT(*) FROM convites_familiares WHERE pessoa_id IN (7,9)
UNION ALL
SELECT 'pessoa_identificadores', COUNT(*) FROM pessoa_identificadores WHERE pessoa_id IN (7,9)
UNION ALL
SELECT 'migracao_pessoas_map', COUNT(*) FROM migracao_pessoas_map WHERE nova_pessoa_id IN (7,9)
UNION ALL
SELECT 'memorias', COUNT(*) FROM memorias WHERE usuario_id IN (7,9)
UNION ALL
SELECT 'memoriais', COUNT(*) FROM memoriais WHERE usuario_id IN (7,9)
UNION ALL
SELECT 'fotos', COUNT(*) FROM fotos WHERE usuario_id IN (7,9)
UNION ALL
SELECT 'videos', COUNT(*) FROM videos WHERE usuario_id IN (7,9)
UNION ALL
SELECT 'contribuicoes', COUNT(*) FROM contribuicoes WHERE usuario_dono_id IN (7,9)
UNION ALL
SELECT 'mensagens_futuro', COUNT(*) FROM mensagens_futuro WHERE destinatario_id IN (7,9)
UNION ALL
SELECT 'conteudo_colaboradores', COUNT(*) FROM conteudo_colaboradores WHERE usuario_id IN (7,9);

-- ============================================================================
-- 5. REMOÇÃO — apagar duplicatas
-- ============================================================================
SELECT '=== 5. REMOVENDO DUPLICATAS ===' AS info;
DELETE FROM pessoas WHERE id = 7;
DELETE FROM pessoas WHERE id = 9;

-- ============================================================================
-- 6. VALIDAÇÃO FINAL
-- ============================================================================
SELECT '=== 6. POS-FIX: pessoa 7 existe? ===' AS info;
SELECT COUNT(*) = 0 AS removida FROM pessoas WHERE id = 7;

SELECT '=== 6b. POS-FIX: pessoa 9 existe? ===' AS info;
SELECT COUNT(*) = 0 AS removida FROM pessoas WHERE id = 9;

SELECT '=== 6c. POS-FIX: pessoa 5 existe? ===' AS info;
SELECT id, nome, sobrenome, email FROM pessoas WHERE id = 5;

SELECT '=== 6d. POS-FIX: pessoa 6 existe? ===' AS info;
SELECT id, nome, sobrenome, email FROM pessoas WHERE id = 6;

SELECT '=== 6e. POS-FIX: relacao Darlan/Alice preservada ===' AS info;
SELECT pr.id, pr.pessoa_a_id, pr.pessoa_b_id, pr.tipo,
       pr.relacao_a_para_b, pr.relacao_b_para_a
FROM pessoas_relacionamentos pr
WHERE (pr.pessoa_a_id = 5 AND pr.pessoa_b_id = 6)
   OR (pr.pessoa_a_id = 6 AND pr.pessoa_b_id = 5);

SELECT '=== 6f. POS-FIX: memorial/permissões preservados ===' AS info;
SELECT 'memoriais' AS tabela, COUNT(*) FROM memoriais
UNION ALL
SELECT 'memorial_pessoas', COUNT(*) FROM memorial_pessoas
UNION ALL
SELECT 'conteudo_permissoes', COUNT(*) FROM conteudo_permissoes;

COMMIT;
