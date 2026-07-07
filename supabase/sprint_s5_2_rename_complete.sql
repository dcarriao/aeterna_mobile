-- ============================================================
-- Sprint S.5.2 — Eliminação Definitiva da Nomenclatura Legada
-- ============================================================
-- Executar APÓS: sprint_s5_1_memorial_pessoas.sql
--              (que renomeia conteudo_permissoes.contato_id → pessoa_id
--               e convites_familiares.contato_id → pessoa_id)
--
-- Corrige todas as views, funções, índices e RLS policies
-- que ainda referenciam contato_id (coluna renomeada).
-- ============================================================

BEGIN;

-- ============================================================
-- 1. ÍNDICE
-- ============================================================
DROP INDEX IF EXISTS public.idx_conteudo_permissoes_tipo_contato;
CREATE INDEX IF NOT EXISTS idx_conteudo_permissoes_tipo_pessoa
    ON public.conteudo_permissoes (tipo_conteudo, pessoa_id);

-- ============================================================
-- 2. VIEWS
-- ============================================================

-- 2a. pessoa_linha_tempo
DROP VIEW IF EXISTS public.pessoa_linha_tempo;
CREATE VIEW public.pessoa_linha_tempo
WITH (security_invoker = true) AS
WITH memorias_da_pessoa AS (
    SELECT DISTINCT cp.pessoa_id, cp.conteudo_id AS memoria_id
    FROM public.conteudo_permissoes cp
    WHERE cp.tipo_conteudo = 'memoria'
),
mem_eventos AS (
    SELECT
        mdp.pessoa_id, 'memoria'::TEXT AS tipo, m.id AS conteudo_id,
        m.titulo AS titulo,
        COALESCE(NULLIF(m.data_evento::TEXT, ''), m.data_criacao::TEXT) AS data_ordem,
        m.id AS memoria_origem_id, NULL::INT AS contribuicao_id, NULL::TEXT AS autor_contribuicao
    FROM memorias_da_pessoa mdp JOIN public.memorias m ON m.id = mdp.memoria_id
),
foto_eventos AS (
    SELECT
        mdp.pessoa_id, 'foto'::TEXT AS tipo, mf.foto_id AS conteudo_id,
        COALESCE(f.titulo, 'Foto') AS titulo, f.data_criacao::TEXT AS data_ordem,
        mf.memoria_id AS memoria_origem_id, NULL::INT AS contribuicao_id, NULL::TEXT AS autor_contribuicao
    FROM memorias_da_pessoa mdp
    JOIN public.memoria_fotos mf ON mf.memoria_id = mdp.memoria_id
    LEFT JOIN public.fotos f ON f.id = mf.foto_id
),
contrib_eventos AS (
    SELECT
        mdp.pessoa_id, 'contribuicao'::TEXT AS tipo, c.id AS conteudo_id,
        COALESCE(c.texto, c.arquivo_url, 'Contribuição') AS titulo, c.criado_em::TEXT AS data_ordem,
        c.conteudo_id AS memoria_origem_id, c.id AS contribuicao_id,
        c.usuario_contribuidor_nome AS autor_contribuicao
    FROM memorias_da_pessoa mdp
    JOIN public.contribuicoes c
      ON c.tipo_conteudo = 'memoria' AND c.conteudo_id = mdp.memoria_id AND c.status = 'aprovado'
)
SELECT * FROM mem_eventos
UNION ALL
SELECT * FROM foto_eventos
UNION ALL
SELECT * FROM contrib_eventos;

-- 2b. memorias_evolucao_resumo
DROP VIEW IF EXISTS public.memorias_evolucao_resumo;
CREATE VIEW public.memorias_evolucao_resumo
WITH (security_invoker = true) AS
SELECT
    m.id AS memoria_id, m.usuario_id, m.titulo, m.categoria,
    m.data_evento, m.data_criacao AS criada_em, m.ultima_atualizacao_em,
    GREATEST(m.data_criacao, m.ultima_atualizacao_em) AS data_referencia,
    EXTRACT(EPOCH FROM (NOW() - GREATEST(m.data_criacao, m.ultima_atualizacao_em))) / 86400.0 AS dias_desde_ultima_atualizacao,
    (SELECT COUNT(DISTINCT cp.pessoa_id) FROM public.conteudo_permissoes cp
     WHERE cp.tipo_conteudo = 'memoria' AND cp.conteudo_id = m.id) AS total_pessoas,
    (SELECT COUNT(*) FROM public.contribuicoes c
     WHERE c.tipo_conteudo = 'memoria' AND c.conteudo_id = m.id AND c.status = 'aprovado') AS total_contribuicoes,
    (SELECT COUNT(*) FROM public.contribuicoes c
     WHERE c.tipo_conteudo = 'memoria' AND c.conteudo_id = m.id AND c.status = 'pendente') AS total_contribuicoes_pendentes,
    (SELECT COUNT(*) FROM public.memoria_fotos mf WHERE mf.memoria_id = m.id) AS total_fotos,
    (SELECT COUNT(*) FROM public.memoria_videos mv WHERE mv.memoria_id = m.id) AS total_videos,
    EXISTS (SELECT 1 FROM public.conteudo_colaboradores cc
            WHERE cc.tipo_conteudo = 'memoria' AND CC.conteudo_id = m.id
              AND cc.papel IN ('editor', 'colaborador')) AS tem_colaboradores,
    (SELECT COUNT(DISTINCT cc.usuario_id) FROM public.conteudo_colaboradores cc
     WHERE cc.tipo_conteudo = 'memoria' AND CC.conteudo_id = m.id
       AND cc.papel IN ('editor', 'colaborador')) AS total_colaboradores,
    (SELECT COUNT(DISTINCT LOWER(TRIM(C.usuario_contribuidor_email)))
     FROM public.contribuicoes c
     WHERE c.tipo_conteudo = 'memoria' AND c.conteudo_id = m.id
       AND c.status = 'aprovado' AND c.usuario_contribuidor_email IS NOT NULL) AS contribuidores_unicos
FROM public.memorias m;

-- ============================================================
-- 3. FUNCTIONS
-- ============================================================

-- 3a. pessoa_estatisticas
CREATE OR REPLACE FUNCTION public.pessoa_estatisticas(pessoa_id BIGINT)
RETURNS TABLE (total_memorias BIGINT, total_fotos BIGINT, total_videos BIGINT,
               total_contribuicoes BIGINT, primeira_data DATE, ultima_data DATE)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN QUERY
    WITH memorias_ids AS (
        SELECT CP.conteudo_id AS id FROM public.conteudo_permissoes cp
        WHERE cp.tipo_conteudo = 'memoria' AND cp.pessoa_id = pessoa_id
    ),
    contribs_ids AS (
        SELECT c.id FROM public.contribuicoes c
        JOIN memorias_ids mi ON mi.id = c.conteudo_id
        WHERE c.tipo_conteudo = 'memoria' AND c.status = 'aprovado'
    )
    SELECT
        (SELECT COUNT(*) FROM memorias_ids)::BIGINT,
        (SELECT COUNT(DISTINCT mf.foto_id) FROM public.memoria_fotos mf JOIN memorias_ids mi ON mi.id = mf.memoria_id)::BIGINT,
        (SELECT COUNT(DISTINCT mv.video_id) FROM public.memoria_videos mv JOIN memorias_ids mi ON mi.id = mv.memoria_id)::BIGINT,
        (SELECT COUNT(*) FROM contribs_ids)::BIGINT,
        (SELECT MIN(m.data_evento) FROM public.memorias m JOIN memorias_ids mi ON mi.id = m.id),
        (SELECT MAX(COALESCE(m.data_evento, m.data_criacao::DATE)) FROM public.memorias m JOIN memorias_ids mi ON mi.id = m.id);
END;
$$;

-- 3b. pessoas_recentes
CREATE OR REPLACE FUNCTION public.pessoas_recentes(usuario BIGINT, limite INT DEFAULT 8)
RETURNS TABLE (id BIGINT, nome TEXT, sobrenome TEXT, parentesco TEXT, email TEXT,
               foto_perfil TEXT, ultima_interacao TIMESTAMP, total_eventos BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN QUERY
    WITH ultimas AS (
        SELECT c.id AS pessoa_id,
            GREATEST(
                COALESCE((SELECT MAX(COALESCE(m.data_evento::TIMESTAMP, m.data_criacao))
                          FROM public.conteudo_permissoes cp JOIN public.memorias m ON m.id = cp.conteudo_id
                          WHERE cp.tipo_conteudo = 'memoria' AND cp.pessoa_id = c.id), '1970-01-01'::TIMESTAMP),
                COALESCE((SELECT MAX(c2.criado_em)
                          FROM public.contribuicoes c2
                          WHERE c2.tipo_conteudo = 'memoria' AND c2.conteudo_id IN (
                              SELECT cp.conteudo_id FROM public.conteudo_permissoes cp
                              WHERE cp.tipo_conteudo = 'memoria' AND cp.pessoa_id = c.id
                          ) AND c2.status = 'aprovado'), '1970-01-01'::TIMESTAMP)
            ) AS ultima
        FROM public.contatos c WHERE c.usuario_id = usuario
    )
    SELECT c.id, c.nome, c.sobrenome, c.parentesco, c.email, c.foto_perfil,
           u.ultima,
           (SELECT COUNT(*) FROM public.pessoa_linha_tempo plt WHERE plt.pessoa_id = c.id)::BIGINT
    FROM ultimas u JOIN public.contatos c ON c.id = u.pessoa_id
    ORDER BY u.ultima DESC NULLS LAST LIMIT limite;
END;
$$;

-- 3c. buscar_candidatas_relacionamento
CREATE OR REPLACE FUNCTION public.buscar_candidatas_relacionamento(
    p_memoria_id BIGINT, p_limite INT DEFAULT 30
)
RETURNS TABLE (id BIGINT, titulo TEXT, categoria TEXT, data_evento DATE,
               criada_em TIMESTAMP WITHOUT TIME ZONE, pessoas_em_comum INTEGER,
               dias_diferenca_evento INTEGER, mesmo_titulo BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_usuario_id BIGINT;
    v_titulo_norm TEXT;
    v_data_evento DATE;
BEGIN
    SELECT m.usuario_id, LOWER(TRIM(m.titulo)), m.data_evento
      INTO v_usuario_id, v_titulo_norm, v_data_evento
      FROM public.memorias m WHERE m.id = p_memoria_id;

    IF v_usuario_id IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT m.id, m.titulo, m.categoria, m.data_evento, m.data_criacao,
           COALESCE((SELECT COUNT(DISTINCT cp.pessoa_id)::INT
                      FROM public.conteudo_permissoes cp
                      WHERE cp.tipo_conteudo = 'memoria' AND cp.conteudo_id = m.id
                        AND cp.pessoa_id IN (
                            SELECT cp2.pessoa_id FROM public.conteudo_permissoes cp2
                            WHERE cp2.tipo_conteudo = 'memoria' AND cp2.conteudo_id = p_memoria_id
                        )), 0) AS pessoas_em_comum,
           CASE WHEN v_data_evento IS NULL OR m.data_evento IS NULL THEN NULL
                ELSE ABS((m.data_evento - v_data_evento)::INT)
           END AS dias_diferenca_evento,
           (v_titulo_norm IS NOT NULL AND v_titulo_norm <> ''
            AND LOWER(TRIM(m.titulo)) = v_titulo_norm) AS mesmo_titulo
    FROM public.memorias m
    WHERE m.usuario_id = v_usuario_id AND m.id <> p_memoria_id
    ORDER BY pessoas_em_comum DESC,
             CASE WHEN dias_diferenca_evento IS NULL THEN 1 ELSE 0 END,
             dias_diferenca_evento ASC NULLS LAST,
             m.data_criacao DESC
    LIMIT p_limite;
END;
$$;

-- 3d. memorias_do_dia
CREATE OR REPLACE FUNCTION public.memorias_do_dia(p_usuario_id BIGINT, p_limite INT DEFAULT 5)
RETURNS TABLE (id BIGINT, titulo TEXT, foto_principal TEXT, total_pessoas BIGINT,
               total_contribuicoes BIGINT, total_midias BIGINT,
               possui_relacionamentos BOOLEAN, anos_decorridos INTEGER, data_referencia DATE)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_hoje DATE := CURRENT_DATE;
    v_dia INTEGER := EXTRACT(DAY FROM v_hoje);
    v_mes INTEGER := EXTRACT(MONTH FROM v_hoje);
    v_ano_corrente INTEGER := EXTRACT(YEAR FROM v_hoje);
    v_limite INTEGER := GREATEST(p_limite, 1);
BEGIN
    RETURN QUERY
    WITH memorias_relevantes AS (
        SELECT m.id, m.titulo, m.data_evento AS data_ref,
            COALESCE(
                (SELECT caminho_arquivo FROM public.fotos f
                 JOIN public.memoria_fotos mf ON mf.foto_id = f.id
                 WHERE mf.memoria_id = m.id ORDER BY f.id ASC LIMIT 1),
                (SELECT caminho_arquivo FROM public.videos v
                 JOIN public.memoria_videos mv ON mv.video_id = v.id
                 WHERE mv.memoria_id = m.id ORDER BY v.id ASC LIMIT 1)
            ) AS foto_principal,
            (SELECT COUNT(DISTINCT cp.pessoa_id) FROM public.conteudo_permissoes cp
             WHERE cp.tipo_conteudo = 'memoria' AND cp.conteudo_id = m.id) AS total_pessoas,
            (SELECT COUNT(*) FROM public.contribuicoes c
             WHERE c.tipo_conteudo = 'memoria' AND c.conteudo_id = m.id AND c.status = 'aprovado') AS total_contribuicoes,
            ((SELECT COUNT(*) FROM public.memoria_fotos mf WHERE mf.memoria_id = m.id)
             + (SELECT COUNT(*) FROM public.memoria_videos mv WHERE mv.memoria_id = m.id)) AS total_midias,
            EXISTS (SELECT 1 FROM public.memoria_relacionamentos r
                    WHERE (r.memoria_origem_id = m.id OR r.memoria_destino_id = m.id)
                      AND r.status = 'confirmado') AS possui_relacionamentos,
            (v_ano_corrente - EXTRACT(YEAR FROM m.data_evento)::INT) AS anos_decorridos,
            'data_evento'::TEXT AS origem
        FROM public.memorias m
        WHERE m.usuario_id = p_usuario_id AND m.data_evento IS NOT NULL
          AND EXTRACT(DAY FROM m.data_evento)::INT = v_dia
          AND EXTRACT(MONTH FROM m.data_evento)::INT = v_mes
          AND EXTRACT(YEAR FROM m.data_evento)::INT <> v_ano_corrente

        UNION ALL

        SELECT m.id, m.titulo, m.data_criacao::DATE AS data_ref,
            COALESCE(
                (SELECT caminho_arquivo FROM public.fotos f
                 JOIN public.memoria_fotos mf ON mf.foto_id = f.id
                 WHERE mf.memoria_id = m.id ORDER BY f.id ASC LIMIT 1),
                (SELECT caminho_arquivo FROM public.videos v
                 JOIN public.memoria_videos mv ON mv.video_id = v.id
                 WHERE mv.memoria_id = m.id ORDER BY v.id ASC LIMIT 1)
            ) AS foto_principal,
            (SELECT COUNT(DISTINCT cp.pessoa_id) FROM public.conteudo_permissoes cp
             WHERE cp.tipo_conteudo = 'memoria' AND cp.conteudo_id = m.id) AS total_pessoas,
            (SELECT COUNT(*) FROM public.contribuicoes c
             WHERE c.tipo_conteudo = 'memoria' AND c.conteudo_id = m.id AND c.status = 'aprovado') AS total_contribuicoes,
            ((SELECT COUNT(*) FROM public.memoria_fotos mf WHERE mf.memoria_id = m.id)
             + (SELECT COUNT(*) FROM public.memoria_videos mv WHERE mv.memoria_id = m.id)) AS total_midias,
            EXISTS (SELECT 1 FROM public.memoria_relacionamentos r
                    WHERE (r.memoria_origem_id = m.id OR r.memoria_destino_id = m.id)
                      AND r.status = 'confirmado') AS possui_relacionamentos,
            (v_ano_corrente - EXTRACT(YEAR FROM m.data_criacao)::INT) AS anos_decorridos,
            'data_criacao'::TEXT AS origem
        FROM public.memorias m
        WHERE m.usuario_id = p_usuario_id AND m.data_evento IS NULL
          AND EXTRACT(DAY FROM m.data_criacao)::INT = v_dia
          AND EXTRACT(MONTH FROM m.data_criacao)::INT = v_mes
          AND m.data_criacao < (NOW() - INTERVAL '30 days')
    )
    SELECT mr.id, mr.titulo, mr.foto_principal, mr.total_pessoas,
           mr.total_contribuicoes, mr.total_midias,
           mr.possui_relacionamentos, mr.anos_decorridos, mr.data_ref
    FROM memorias_relevantes mr
    ORDER BY mr.anos_decorridos DESC NULLS LAST, mr.total_pessoas DESC NULLS LAST,
             mr.total_contribuicoes DESC NULLS LAST,
             CASE WHEN mr.possui_relacionamentos THEN 0 ELSE 1 END,
             mr.total_midias DESC NULLS LAST, mr.data_ref DESC NULLS LAST
    LIMIT v_limite;
END;
$$;

-- ============================================================
-- 4. RLS POLICIES
-- ============================================================
-- As policies abaixo foram criadas em sprint_s3_f3b_rls.sql.
-- Após S5.1 renomear conteudo_permissoes.contato_id → pessoa_id,
-- as policies originais (que referenciam contato_id) quebram.
-- Recriamos com pessoa_id.

-- 4a. RLS — memorias (policy memorias_select)
DROP POLICY IF EXISTS memorias_select ON public.memorias;
CREATE POLICY memorias_select ON public.memorias FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
  OR usuario_id IN (
    SELECT id FROM pessoas
    WHERE criado_por_id = pessoa_autenticada_id()
  )
  OR id IN (
    SELECT conteudo_id FROM conteudo_permissoes
    WHERE pessoa_id = pessoa_autenticada_id()
  )
);

-- 4b. RLS — conteudo_permissoes (cp_select, cp_insert, cp_update)
DROP POLICY IF EXISTS cp_select ON public.conteudo_permissoes;
CREATE POLICY cp_select ON public.conteudo_permissoes FOR SELECT USING (
  pessoa_id = pessoa_autenticada_id()
);

DROP POLICY IF EXISTS cp_insert ON public.conteudo_permissoes;
CREATE POLICY cp_insert ON public.conteudo_permissoes FOR INSERT WITH CHECK (
  pessoa_id = pessoa_autenticada_id()
  OR pessoa_id IN (
    SELECT id FROM pessoas WHERE criado_por_id = pessoa_autenticada_id()
  )
);

DROP POLICY IF EXISTS cp_update ON public.conteudo_permissoes;
CREATE POLICY cp_update ON public.conteudo_permissoes FOR UPDATE USING (
  pessoa_id = pessoa_autenticada_id()
  OR pessoa_id IN (
    SELECT id FROM pessoas WHERE criado_por_id = pessoa_autenticada_id()
  )
);

-- ============================================================
-- VALIDAÇÃO
-- ============================================================
DO $$
DECLARE
  v_index_exists       BOOLEAN;
  v_view_timeline      BOOLEAN;
  v_view_evolucao      BOOLEAN;
  v_func_estatisticas  BOOLEAN;
  v_func_recentes      BOOLEAN;
  v_func_candidatas    BOOLEAN;
  v_func_dodia         BOOLEAN;
  v_policy_cp_select   BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_conteudo_permissoes_tipo_pessoa') INTO v_index_exists;
  SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname = 'pessoa_linha_tempo' AND schemaname = 'public') INTO v_view_timeline;
  SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname = 'memorias_evolucao_resumo' AND schemaname = 'public') INTO v_view_evolucao;
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'pessoa_estatisticas') INTO v_func_estatisticas;
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'pessoas_recentes') INTO v_func_recentes;
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'buscar_candidatas_relacionamento') INTO v_func_candidatas;
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'memorias_do_dia') INTO v_func_dodia;
  SELECT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'cp_select' AND tablename = 'conteudo_permissoes') INTO v_policy_cp_select;

  IF NOT v_index_exists THEN RAISE WARNING '⚠ idx_conteudo_permissoes_tipo_pessoa nao encontrado'; END IF;
  IF NOT v_view_timeline THEN RAISE WARNING '⚠ view pessoa_linha_tempo nao encontrada'; END IF;
  IF NOT v_view_evolucao THEN RAISE WARNING '⚠ view memorias_evolucao_resumo nao encontrada'; END IF;
  IF NOT v_func_estatisticas THEN RAISE WARNING '⚠ funcao pessoa_estatisticas nao encontrada'; END IF;
  IF NOT v_func_recentes THEN RAISE WARNING '⚠ funcao pessoas_recentes nao encontrada'; END IF;
  IF NOT v_func_candidatas THEN RAISE WARNING '⚠ funcao buscar_candidatas_relacionamento nao encontrada'; END IF;
  IF NOT v_func_dodia THEN RAISE WARNING '⚠ funcao memorias_do_dia nao encontrada'; END IF;
  IF NOT v_policy_cp_select THEN RAISE WARNING '⚠ policy cp_select nao encontrada em conteudo_permissoes'; END IF;

  RAISE NOTICE '✅ S5.2 OK — index, views, funções, RLS recriados com pessoa_id';
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK
-- ============================================================
-- DROP INDEX IF EXISTS idx_conteudo_permissoes_tipo_pessoa;
-- CREATE INDEX IF NOT EXISTS idx_conteudo_permissoes_tipo_contato ON public.conteudo_permissoes (tipo_conteudo, contato_id);
-- ... (view/function droparia dados, não recomendado)
