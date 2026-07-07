-- ============================================================
-- Sprint S.8 — HOTFIX: schema pessoas não tem parentesco
-- ============================================================
-- Problema: sprint_s8_fix_rls.sql criou funções referenciando
-- p.parentesco, mas pessoas NÃO tem essa coluna (contatos tem).
-- Isso quebra pessoas_recentes() com erro 42703.
--
-- Correção:
--   1. Recria pessoas_recentes sem parentesco no SELECT
--   2. Remove trigger legado que depende de parentesco
--      (pessoas não tem a coluna, então trigger é no-op)
-- ============================================================
-- Executar ANTES de qualquer outro script no Supabase Dashboard
-- ============================================================

BEGIN;

-- ============================================================
-- 1. CORRIGE pessoas_recentes
--    Remove p.parentesco do SELECT (coluna não existe em pessoas)
--    Mantém parentesco na tabela de retorno como NULL
-- ============================================================
CREATE OR REPLACE FUNCTION public.pessoas_recentes(usuario bigint, limite int default 8)
RETURNS TABLE (id bigint, nome text, sobrenome text, parentesco text, email text,
               foto_perfil text, ultima_interacao timestamp, total_eventos bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN QUERY
    WITH ultimas AS (
        SELECT p.id AS pessoa_id,
            GREATEST(
                COALESCE((SELECT MAX(COALESCE(m.data_evento::TIMESTAMP, m.data_criacao))
                          FROM public.conteudo_permissoes cp JOIN public.memorias m ON m.id = cp.conteudo_id
                          WHERE cp.tipo_conteudo = 'memoria' AND cp.pessoa_id = p.id), '1970-01-01'::TIMESTAMP),
                COALESCE((SELECT MAX(c2.criado_em)
                          FROM public.contribuicoes c2
                          WHERE c2.tipo_conteudo = 'memoria' AND c2.conteudo_id IN (
                              SELECT cp.conteudo_id FROM public.conteudo_permissoes cp
                              WHERE cp.tipo_conteudo = 'memoria' AND cp.pessoa_id = p.id
                          ) AND c2.status = 'aprovado'), '1970-01-01'::TIMESTAMP)
            ) AS ultima
        FROM public.pessoas p WHERE p.criado_por_id = usuario
    )
    SELECT p.id, p.nome, p.sobrenome,
           NULL::TEXT AS parentesco,
           p.email, p.foto_perfil,
           u.ultima,
           (SELECT COUNT(*) FROM public.pessoa_linha_tempo plt WHERE plt.pessoa_id = p.id)::BIGINT
    FROM ultimas u JOIN public.pessoas p ON p.id = u.pessoa_id
    ORDER BY u.ultima DESC NULLS LAST LIMIT limite;
END;
$$;

GRANT EXECUTE ON FUNCTION public.pessoas_recentes(BIGINT, INT) TO anon;

-- ============================================================
-- 2. Corrige tg_pessoa_cria_relacionamento_legado
--    pessoas não tem parentesco, então trigger não pode
--    inferir tipo de relacionamento. Mantém como no-op seguro.
-- ============================================================
CREATE OR REPLACE FUNCTION public.tg_pessoa_cria_relacionamento_legado()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    -- pessoas não tem coluna parentesco
    -- relacionamentos devem ser criados manualmente pelo app
    RETURN new;
END;
$$;

DO $$ BEGIN
    RAISE NOTICE 'HOTFIX aplicado: pessoas_recentes OK, trigger no-op';
END $$;

COMMIT;
