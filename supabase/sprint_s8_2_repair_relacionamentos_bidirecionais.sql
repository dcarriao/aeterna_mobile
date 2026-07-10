-- ============================================================
-- Sprint S.8.2 — Reparo de Relacionamentos Bidirecionais
-- ============================================================
-- 1. Cria view grafo_pessoas_relacionamentos (usada pelo Mapa)
-- 2. Cria RPC listar_relacionamentos_pessoa (usada pelo detalhe)
-- 3. Completa inversas faltantes em pessoas_relacionamentos
-- ============================================================

BEGIN;

-- ============================================================
-- 1. VIEW grafo_pessoas_relacionamentos
--    Projeta cada linha com rótulos e nomes resolvidos,
--    normalizando A < B (pessoa_mais_antiga/nova).
-- ============================================================
DROP VIEW IF EXISTS public.grafo_pessoas_relacionamentos;
CREATE VIEW public.grafo_pessoas_relacionamentos
WITH (security_invoker = true) AS
SELECT
    pr.id AS relacionamento_id,
    pr.usuario_id,
    LEAST(pr.pessoa_a_id, pr.pessoa_b_id) AS pessoa_mais_antiga_id,
    GREATEST(pr.pessoa_a_id, pr.pessoa_b_id) AS pessoa_mais_nova_id,
    CASE
        WHEN pr.pessoa_a_id < pr.pessoa_b_id THEN pr.relacao_a_para_b
        ELSE pr.relacao_b_para_a
    END AS rotulo_a,
    CASE
        WHEN pr.pessoa_a_id < pr.pessoa_b_id THEN pr.relacao_b_para_a
        ELSE pr.relacao_a_para_b
    END AS rotulo_b,
    CASE
        WHEN pr.pessoa_a_id < pr.pessoa_b_id THEN p_a.nome
        ELSE p_b.nome
    END AS nome_a,
    CASE
        WHEN pr.pessoa_a_id < pr.pessoa_b_id THEN p_b.nome
        ELSE p_a.nome
    END AS nome_b,
    pr.tipo,
    pr.confirmado
FROM public.pessoas_relacionamentos pr
LEFT JOIN public.pessoas p_a ON p_a.id = pr.pessoa_a_id
LEFT JOIN public.pessoas p_b ON p_b.id = pr.pessoa_b_id
WHERE pr.confirmado = true
  AND pr.pessoa_a_id IS NOT NULL
  AND pr.pessoa_b_id IS NOT NULL;

GRANT SELECT ON public.grafo_pessoas_relacionamentos TO anon;
DO $$ BEGIN RAISE NOTICE '1. grafo_pessoas_relacionamentos criada'; END $$;

-- ============================================================
-- 2. RPC listar_relacionamentos_pessoa
--    Retorna todas as relações de uma pessoa, com nome e rótulo
--    já resolvidos pela perspectiva da pessoa.
-- ============================================================
DROP FUNCTION IF EXISTS public.listar_relacionamentos_pessoa(BIGINT);
CREATE OR REPLACE FUNCTION public.listar_relacionamentos_pessoa(
    p_pessoa_id BIGINT
)
RETURNS TABLE (
    relacionamento_id BIGINT,
    outra_pessoa_id BIGINT,
    outra_pessoa_nome TEXT,
    tipo TEXT,
    rotulo_da_outra_para_mim TEXT,
    rotulo_de_mim_para_outra TEXT,
    observacoes TEXT,
    data_inicio DATE,
    data_fim DATE
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN QUERY
    SELECT
        pr.id,
        CASE WHEN pr.pessoa_a_id = p_pessoa_id THEN pr.pessoa_b_id ELSE pr.pessoa_a_id END,
        CASE WHEN pr.pessoa_a_id = p_pessoa_id THEN COALESCE(p_b.nome, 'Pessoa #' || pr.pessoa_b_id)
             ELSE COALESCE(p_a.nome, 'Pessoa #' || pr.pessoa_a_id)
        END,
        pr.tipo,
        CASE WHEN pr.pessoa_a_id = p_pessoa_id THEN pr.relacao_b_para_a ELSE pr.relacao_a_para_b END,
        CASE WHEN pr.pessoa_a_id = p_pessoa_id THEN pr.relacao_a_para_b ELSE pr.relacao_b_para_a END,
        pr.observacoes,
        pr.data_inicio,
        pr.data_fim
    FROM public.pessoas_relacionamentos pr
    LEFT JOIN public.pessoas p_a ON p_a.id = pr.pessoa_a_id
    LEFT JOIN public.pessoas p_b ON p_b.id = pr.pessoa_b_id
    WHERE (pr.pessoa_a_id = p_pessoa_id OR pr.pessoa_b_id = p_pessoa_id)
      AND pr.confirmado = true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.listar_relacionamentos_pessoa(BIGINT) TO anon;
DO $$ BEGIN RAISE NOTICE '2. listar_relacionamentos_pessoa criada'; END $$;

-- ============================================================
-- 3. COMPLETAR INVERSAS FALTANTES
--    Para cada linha que NÃO tem sua inversa, cria a inversa.
--    Regra: se existe (A, B, tipoX), deve existir (B, A, tipoY)
--    onde tipoY é o inverso de tipoX.
--    Usa um mapping de inversos para trocar o tipo corretamente.
-- ============================================================
DO $$
DECLARE
    v_count INT := 0;
    r RECORD;
    v_inverse_tipo TEXT;
BEGIN
    -- Mapeamento de tipos para seus inversos
    -- Usamos WHEN/THEN para cada par conhecido
    FOR r IN
        SELECT pr.*
        FROM public.pessoas_relacionamentos pr
        WHERE NOT EXISTS (
            SELECT 1 FROM public.pessoas_relacionamentos pr2
            WHERE pr2.pessoa_a_id = pr.pessoa_b_id
              AND pr2.pessoa_b_id = pr.pessoa_a_id
              AND pr2.usuario_id = pr.usuario_id
        )
    LOOP
        -- Determina o tipo inverso
        v_inverse_tipo := CASE r.tipo
            WHEN 'PAI' THEN 'FILHO'
            WHEN 'MAE' THEN 'FILHO'
            WHEN 'FILHO' THEN
                CASE WHEN r.relacao_b_para_a = 'Mãe' THEN 'MAE' ELSE 'PAI' END
            WHEN 'FILHA' THEN 'PAI'
            WHEN 'AVO' THEN 'NETO'
            WHEN 'NETO' THEN 'AVO'
            WHEN 'BISAVO' THEN 'BISNETO'
            WHEN 'BISNETO' THEN 'BISAVO'
            WHEN 'TIO' THEN 'SOBRINHO'
            WHEN 'SOBRINHO' THEN 'TIO'
            WHEN 'PADRINHO' THEN 'AFILHADO'
            WHEN 'MADRINHA' THEN 'AFILHADO'
            WHEN 'AFILHADO' THEN
                CASE WHEN r.relacao_b_para_a = 'Madrinha' THEN 'MADRINHA' ELSE 'PADRINHO' END
            WHEN 'GENRO' THEN 'SOGRO'
            WHEN 'NORA' THEN 'SOGRO'
            WHEN 'SOGRO' THEN
                CASE WHEN r.relacao_b_para_a = 'Genro' THEN 'GENRO' ELSE 'NORA' END
            ELSE r.tipo  -- simétricos: IRMAO, CONJUGE, PRIMO, CUNHADO, AMIGO, OUTRO, COMPANHEIRO
        END;

        INSERT INTO public.pessoas_relacionamentos
            (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
             relacao_a_para_b, relacao_b_para_a, confirmado,
             observacoes, data_inicio, data_fim)
        VALUES
            (r.usuario_id, r.pessoa_b_id, r.pessoa_a_id, v_inverse_tipo,
             r.relacao_b_para_a, r.relacao_a_para_b, r.confirmado,
             r.observacoes, r.data_inicio, r.data_fim);
        v_count := v_count + 1;
    END LOOP;

    RAISE NOTICE '3. Inversas criadas: %', v_count;
END $$;

-- ============================================================
-- 4. VALIDAÇÃO
-- ============================================================

-- 4.1 Relações sem inversa
DO $$
DECLARE
    v_sem_inversa INT;
    v_duplicatas INT;
BEGIN
    SELECT count(*) INTO v_sem_inversa
    FROM pessoas_relacionamentos pr
    WHERE NOT EXISTS (
        SELECT 1 FROM pessoas_relacionamentos pr2
        WHERE pr2.pessoa_a_id = pr.pessoa_b_id
          AND pr2.pessoa_b_id = pr.pessoa_a_id
          AND pr2.usuario_id = pr.usuario_id
    );
    RAISE NOTICE '4.1 Relações SEM inversa: %', v_sem_inversa;

    -- 4.2 Duplicatas exatas
    SELECT count(*) INTO v_duplicatas
    FROM (
        SELECT pessoa_a_id, pessoa_b_id, usuario_id, tipo, count(*)
        FROM pessoas_relacionamentos
        GROUP BY pessoa_a_id, pessoa_b_id, usuario_id, tipo
        HAVING count(*) > 1
    ) dup;
    RAISE NOTICE '4.2 Duplicatas exatas: %', v_duplicatas;

    -- 4.3 Relações da Beatriz (pessoa 10)
    RAISE NOTICE '4.3 Relações da Beatriz (10):';
END $$;

-- Queries para executar manualmente:
--
-- 5. SELECT pr.*, p.nome AS nome_a
--    FROM pessoas_relacionamentos pr
--    JOIN pessoas p ON p.id = pr.pessoa_a_id
--    WHERE pr.pessoa_b_id = 10 OR pr.pessoa_a_id = 10;
--
-- 6. SELECT pr.*, p.nome AS nome_b
--    FROM pessoas_relacionamentos pr
--    JOIN pessoas p ON p.id = pr.pessoa_b_id
--    WHERE pr.pessoa_b_id = 8 OR pr.pessoa_a_id = 8;
--
-- 7. SELECT * FROM grafo_pessoas_relacionamentos ORDER BY relacionamento_id;

COMMIT;
