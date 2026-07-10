-- ============================================================
-- Sprint S.7 — Auditoria Final Pré-Teste Real
-- ============================================================
-- Executar no Supabase SQL Dashboard (todo de uma vez).
-- Resultados esperados: 0 linhas em cada seção de "ERRO".
-- ============================================================

-- ============================================================
-- 1. SCHEMA FINAL — tabelas obrigatórias
-- ============================================================
SELECT '1. SCHEMA' AS secao;
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'pessoas', 'memorial_pessoas', 'pessoa_identificadores',
    'migracao_pessoas_map', 'contatos', 'usuarios'
  )
ORDER BY table_name;

-- ============================================================
-- 2. COLUNAS — pessoa_identificadores
-- ============================================================
SELECT '2. COLUNAS pessoa_identificadores' AS secao;
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'pessoa_identificadores'
ORDER BY ordinal_position;

-- ============================================================
-- 3. FKs QUEBRADAS — pessoas
-- ============================================================
SELECT '3. FKs QUEBRADAS — criado_por_id' AS secao;
SELECT p.id, p.nome, p.criado_por_id
FROM pessoas p
WHERE p.criado_por_id IS NOT NULL
  AND p.criado_por_id <> 0
  AND NOT EXISTS (
    SELECT 1 FROM pessoas ref WHERE ref.id = p.criado_por_id
  );

-- ============================================================
-- 4. FKs QUEBRADAS — memorial_pessoas
-- ============================================================
SELECT '4a. FKs QUEBRADAS — memorial_pessoas.pessoa_id' AS secao;
SELECT mp.*
FROM memorial_pessoas mp
WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = mp.pessoa_id);

SELECT '4b. FKs QUEBRADAS — memorial_pessoas.memorial_id' AS secao;
SELECT mp.*
FROM memorial_pessoas mp
WHERE NOT EXISTS (SELECT 1 FROM memoriais m WHERE m.id = mp.memorial_id);

-- ============================================================
-- 5. FKs QUEBRADAS — conteudo_permissoes
-- ============================================================
SELECT '5. FKs QUEBRADAS — conteudo_permissoes.pessoa_id' AS secao;
SELECT cp.*
FROM conteudo_permissoes cp
WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = cp.pessoa_id);

-- ============================================================
-- 6. FKs QUEBRADAS — convites_familiares
-- ============================================================
SELECT '6. FKs QUEBRADAS — convites_familiares.pessoa_id' AS secao;
SELECT cf.*
FROM convites_familiares cf
WHERE cf.pessoa_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = cf.pessoa_id);

-- ============================================================
-- 7. RELAÇÕES FAMILIARES sem pessoa correspondente
-- ============================================================
SELECT '7a. RELAÇÕES — pessoa_a_id sem pessoa' AS secao;
SELECT pr.*
FROM pessoas_relacionamentos pr
WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = pr.pessoa_a_id);

SELECT '7b. RELAÇÕES — pessoa_b_id sem pessoa' AS secao;
SELECT pr.*
FROM pessoas_relacionamentos pr
WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = pr.pessoa_b_id);

-- ============================================================
-- 8. MEMORIAIS sem pessoa correspondente
-- ============================================================
SELECT '8. MEMORIAIS sem pessoa em memorial_pessoas' AS secao;
SELECT m.*
FROM memoriais m
WHERE NOT EXISTS (
  SELECT 1 FROM memorial_pessoas mp WHERE mp.memorial_id = m.id
)
AND m.usuario_id IS NOT NULL;

-- ============================================================
-- 9. MENSAGENS FUTURAS sem destinatário válido
-- ============================================================
SELECT '9a. MENSAGENS — destinatario_id sem pessoa' AS secao;
SELECT mf.*
FROM mensagens_futuro mf
WHERE mf.destinatario_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = mf.destinatario_id);

SELECT '9b. MENSAGENS — usuario_id sem pessoa' AS secao;
SELECT mf.*
FROM mensagens_futuro mf
WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = mf.usuario_id);

-- ============================================================
-- 10. DUPLICIDADES PROVÁVEIS DE PESSOAS
-- ============================================================
SELECT '10a. DUPLICADOS — mesmo email' AS secao;
SELECT p1.id AS id_a, p1.nome AS nome_a, p1.email,
       p2.id AS id_b, p2.nome AS nome_b
FROM pessoas p1
JOIN pessoas p2 ON p2.email = p1.email AND p2.id > p1.id
WHERE p1.email IS NOT NULL AND p1.email <> '';

SELECT '10b. DUPLICADOS — mesmo nome + mesmo criado_por' AS secao;
SELECT p1.id AS id_a, p1.nome, p1.sobrenome, p1.criado_por_id,
       p2.id AS id_b
FROM pessoas p1
JOIN pessoas p2 ON p2.nome = p1.nome
  AND COALESCE(p2.sobrenome, '') = COALESCE(p1.sobrenome, '')
  AND p2.criado_por_id = p1.criado_por_id
  AND p2.id > p1.id;

SELECT '10c. DUPLICADOS — mesmo auth_user_id' AS secao;
SELECT p1.id AS id_a, p1.nome, p1.auth_user_id,
       p2.id AS id_b, p2.nome
FROM pessoas p1
JOIN pessoas p2 ON p2.auth_user_id = p1.auth_user_id AND p2.id > p1.id
WHERE p1.auth_user_id IS NOT NULL;

-- ============================================================
-- 11. PETS com auth_user_id preenchido (NUNCA deve existir)
-- ============================================================
SELECT '11. ERRO — PETS com auth_user_id' AS secao;
SELECT id, nome, tipo, auth_user_id
FROM pessoas
WHERE tipo = 'pet' AND auth_user_id IS NOT NULL;

-- ============================================================
-- 12. HUMANOS ativos sem dados mínimos
-- ============================================================
SELECT '12a. HUMANOS sem nome' AS secao;
SELECT id, tipo, situacao
FROM pessoas
WHERE tipo IN ('humano', 'usuario') AND situacao = 'ativo'
  AND (nome IS NULL OR TRIM(nome) = '');

SELECT '12b. USUÁRIOS autenticáveis sem auth_user_id' AS secao;
SELECT id, nome, tipo, auth_user_id, email
FROM pessoas
WHERE tipo = 'usuario' AND auth_user_id IS NULL;

-- ============================================================
-- 13. PESSOAS sem tipo
-- ============================================================
SELECT '13. PESSOAS sem tipo' AS secao;
SELECT id, nome, tipo
FROM pessoas
WHERE tipo IS NULL OR TRIM(tipo) = '';

-- ============================================================
-- 14. PESSOAS com tipo inválido
-- ============================================================
SELECT '14. PESSOAS com tipo invalido' AS secao;
SELECT id, nome, tipo
FROM pessoas
WHERE tipo NOT IN ('humano', 'usuario', 'pet');

-- ============================================================
-- 15. REFERÊNCIAS LEGADAS EM VIEWS
-- ============================================================
SELECT '15a. VIEWS referenciando contatos' AS secao;
SELECT schemaname, viewname, definition
FROM pg_views
WHERE schemaname = 'public'
  AND (definition ILIKE '%contatos%' OR definition ILIKE '%contato_id%')
ORDER BY viewname;

SELECT '15b. VIEWS referenciando usuarios' AS secao;
SELECT schemaname, viewname, definition
FROM pg_views
WHERE schemaname = 'public'
  AND definition ILIKE '%usuarios%'
ORDER BY viewname;

-- ============================================================
-- 16. REFERÊNCIAS LEGADAS EM FUNCTIONS
-- ============================================================
SELECT '16a. FUNCTIONS referenciando contatos' AS secao;
SELECT proname, prosrc
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND (prosrc ILIKE '%contatos%' OR prosrc ILIKE '%contato_id%')
ORDER BY proname;

SELECT '16b. FUNCTIONS referenciando usuarios (tabela)' AS secao;
SELECT proname, prosrc
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND prosrc ILIKE '%usuarios%'
ORDER BY proname;

-- ============================================================
-- 17. REFERÊNCIAS LEGADAS EM POLICIES
-- ============================================================
SELECT '17a. POLICIES referenciando contato_id' AS secao;
SELECT schemaname, tablename, policyname, permissive, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual ILIKE '%contato_id%' OR with_check ILIKE '%contato_id%');

SELECT '17b. POLICIES referenciando usuarios' AS secao;
SELECT schemaname, tablename, policyname, permissive, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual ILIKE '%from public.usuarios%' OR with_check ILIKE '%from public.usuarios%');

-- ============================================================
-- 18. REFERÊNCIAS LEGADAS EM TRIGGERS
-- ============================================================
SELECT '18. TRIGGERS em tabelas legadas' AS secao;
SELECT tgname, relid::regclass
FROM pg_trigger
WHERE tgname NOT LIKE 'pg_%'
  AND pg_trigger.oid > 0
  AND EXISTS (
    SELECT 1 FROM pg_class c
    WHERE c.oid = pg_trigger.tgrelid
      AND c.relname IN ('contatos', 'usuarios')
  );

-- ============================================================
-- 19. TABELAS LEGADAS AINDA COM DADOS
-- ============================================================
SELECT '19a. contatos ainda com dados' AS secao;
SELECT COUNT(*) AS total FROM contatos;

SELECT '19b. usuarios ainda com dados' AS secao;
SELECT COUNT(*) AS total FROM usuarios;

SELECT '19c. migracao_pessoas_map ainda com dados' AS secao;
SELECT COUNT(*) AS total FROM migracao_pessoas_map;

-- ============================================================
-- 20. RESUMO
-- ============================================================
SELECT '20. RESUMO — linhas com erro' AS secao;
SELECT 'Revise cada secao acima. Se alguma retornar linhas, investigar. 0 linhas = OK.';
