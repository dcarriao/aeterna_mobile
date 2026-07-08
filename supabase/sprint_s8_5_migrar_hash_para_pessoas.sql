-- ============================================================
-- Sprint S.8.5 — Migrar senha_hash + salt de usuarios para pessoas
-- ============================================================
-- Objetivo: unificar todos os dados do usuário em pessoas,
-- permitindo eliminar a dependência da tabela usuarios.
--
-- Regras:
--   ✅ Adiciona colunas senha_hash e salt em pessoas
--   ✅ Copia dados existentes de usuarios para pessoas
--   ✅ Mantém compatibilidade com site (site pode migrar depois)
--   ❌ NÃO apaga usuarios (site ainda usa)
--   ❌ NÃO apaga pessoas
--   ❌ NÃO altera IDs
-- ============================================================

-- 1. Adicionar colunas em pessoas
ALTER TABLE public.pessoas ADD COLUMN IF NOT EXISTS senha_hash TEXT;
ALTER TABLE public.pessoas ADD COLUMN IF NOT EXISTS salt TEXT;

-- 2. Copiar senha_hash e salt de usuarios para pessoas
--    Match por _legacy_usuario_id para precisão
UPDATE public.pessoas p
SET senha_hash = u.senha_hash,
    salt = u.salt
FROM public.usuarios u
WHERE p._legacy_usuario_id = u.id
  AND p.senha_hash IS NULL;

-- 3. Validar
SELECT 'Pessoas com senha_hash agora' AS info;
SELECT COUNT(*) AS total FROM public.pessoas WHERE senha_hash IS NOT NULL;

SELECT 'Pessoas AINDA sem senha_hash' AS info;
SELECT id, nome, email FROM public.pessoas WHERE senha_hash IS NULL;

SELECT 'Dados migrados' AS info;
SELECT p.id, p.nome, p.email,
       p.senha_hash IS NOT NULL AS tem_hash,
       p.salt IS NOT NULL AS tem_salt,
       p._legacy_usuario_id IS NOT NULL AS veio_de_usuario
FROM public.pessoas p
WHERE p.senha_hash IS NOT NULL
ORDER BY p.id;
