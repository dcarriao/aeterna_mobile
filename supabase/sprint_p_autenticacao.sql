-- =============================================================
-- Sprint P — Autenticação e Cadastro
-- Melhorias no modelo de autenticação existente (SHA-256 + salt)
-- + trigger para popular auth_id (compatibilidade futura com Auth)
-- =============================================================

-- 1. Garantir que a coluna auth_id existe na tabela usuarios
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS auth_id TEXT UNIQUE;

-- 2. Índice para busca rápida por auth_id
CREATE INDEX IF NOT EXISTS idx_usuarios_auth_id ON public.usuarios(auth_id);

-- 3. Trigger: quando um usuário fizer login via Supabase Auth no futuro,
--    popula auth_id automaticamente se o email coincidir.
CREATE OR REPLACE FUNCTION public.sincronizar_auth_id()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.usuarios
  SET auth_id = NEW.id::text
  WHERE email = NEW.email
    AND auth_id IS NULL;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sincronizar_auth_id ON auth.users;
CREATE TRIGGER trg_sincronizar_auth_id
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.sincronizar_auth_id();

-- 4. RLS — usuários: cada usuário vê apenas o próprio registro
--    (mantendo compatibilidade com o SELECT/UPDATE existentes)
DROP POLICY IF EXISTS "mvp anon select usuarios" ON public.usuarios;
DROP POLICY IF EXISTS "mvp anon update usuarios" ON public.usuarios;

-- SELECT: qualquer um pode ver (necessário para login por email)
CREATE POLICY "usuarios_select" ON public.usuarios
  FOR SELECT TO anon USING (true);

-- UPDATE: cada um atualiza apenas o próprio registro
CREATE POLICY "usuarios_update" ON public.usuarios
  FOR UPDATE TO anon
  USING (id = (SELECT id FROM public.usuarios WHERE auth_id = auth.uid()::text))
  WITH CHECK (id = (SELECT id FROM public.usuarios WHERE auth_id = auth.uid()::text));

-- INSERT: qualquer um pode inserir (cadastro)
GRANT INSERT ON TABLE public.usuarios TO anon;

-- 5. Garantir GRANTs existentes
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;
