-- ============================================================
-- Sprint S.8.4 — Diagnóstico de Autenticação
-- ============================================================
-- Antes de migrar, rode cada bloco abaixo no SQL Editor do
-- Supabase Dashboard (https://supabase.com/dashboard/project/zfpvfljmnlgsqiqdxmka/sql/new)
-- e cole os resultados aqui.
-- ============================================================

-- 1. Quantas pessoas existem na tabela `pessoas`?
SELECT COUNT(*) AS total_pessoas FROM public.pessoas;

-- 2. Quantas pessoas têm auth_user_id preenchido?
SELECT COUNT(*) AS com_auth FROM public.pessoas WHERE auth_user_id IS NOT NULL;

-- 3. Quantas pessoas NÃO têm auth_user_id (legado)?
SELECT id, nome, email, criado_em
FROM public.pessoas
WHERE auth_user_id IS NULL
ORDER BY id;

-- 4. Quantos auth users existem no schema auth?
SELECT COUNT(*) AS total_auth_users FROM auth.users;

-- 5. Listar auth users com email (para comparar com pessoas)
SELECT id, email, created_at, last_sign_in_at, confirmed_at
FROM auth.users
ORDER BY created_at DESC;

-- 6. Pessoas com auth_user_id que NÃO existem mais em auth.users
SELECT p.id, p.nome, p.email, p.auth_user_id
FROM public.pessoas p
LEFT JOIN auth.users u ON u.id = p.auth_user_id::uuid
WHERE u.id IS NULL AND p.auth_user_id IS NOT NULL;

-- 7. Auth users sem pessoa correspondente (órfãos)
SELECT u.id, u.email, u.created_at
FROM auth.users u
LEFT JOIN public.pessoas p ON p.auth_user_id = u.id::text
WHERE p.id IS NULL;

-- 8. Configuração SMTP (se tiver acesso)
-- Rode no SQL Editor:
SELECT * FROM supabase_settings WHERE name LIKE '%smtp%' OR name LIKE '%email%';
-- Se não tiver a view supabase_settings, verifique em:
-- https://supabase.com/dashboard/project/zfpvfljmnlgsqiqdxmka/auth/settings

-- ============================================================
-- Instruções:
-- 1. Cole cada bloco e Execute
-- 2. Copie os resultados
-- 3. Se o bloco 3 (pessoas sem auth) retornar linhas,
--    rode o script sprint_s8_4_migrar_auth.sql
-- ============================================================
