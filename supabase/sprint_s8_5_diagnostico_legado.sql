-- ============================================================
-- Sprint S.8.5 — Diagnóstico complementar: tabela legado
-- ============================================================
-- Verificar se a tabela usuarios antiga ainda existe e
-- se armazena senha/hash que não foi migrado.
-- ============================================================

-- 1. A tabela usuarios ainda existe? Tem dados?
SELECT '1. Tabela usuarios existe?' AS info;
SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'usuarios') AS existe;

-- 2. Se existe, quantas linhas?
SELECT '2. Quantos registros em usuarios?' AS info;
SELECT COUNT(*) AS total FROM public.usuarios;

-- 3. Estrutura da tabela usuarios (colunas)
SELECT '3. Colunas da tabela usuarios' AS info;
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'usuarios'
ORDER BY ordinal_position;

-- 4. Usuários com email que também estão em pessoas
SELECT '4. Usuarios com email correspondente em pessoas' AS info;
SELECT u.id AS usuario_id, u.nome, u.email, p.id AS pessoa_id, p.auth_user_id
FROM public.usuarios u
JOIN public.pessoas p ON LOWER(TRIM(u.email)) = LOWER(TRIM(p.email))
ORDER BY u.id;

-- 5. Pessoas SEM auth_user_id que tem correspondente em usuarios
SELECT '5. Pessoas sem auth_user_id com registro em usuarios' AS info;
SELECT p.id AS pessoa_id, p.nome, p.email, u.id AS usuario_id
FROM public.pessoas p
JOIN public.usuarios u ON LOWER(TRIM(u.email)) = LOWER(TRIM(p.email))
WHERE p.auth_user_id IS NULL
ORDER BY p.id;

-- 6. Pessoas que NÃO tem correspondente em usuarios nem auth_user_id
SELECT '6. Pessoas sem auth_user_id E sem usuario legado' AS info;
SELECT p.id, p.nome, p.email, p.created_at
FROM public.pessoas p
LEFT JOIN public.usuarios u ON LOWER(TRIM(u.email)) = LOWER(TRIM(p.email))
WHERE p.auth_user_id IS NULL AND u.id IS NULL
ORDER BY p.id;
