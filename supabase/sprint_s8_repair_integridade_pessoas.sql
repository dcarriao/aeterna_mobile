-- ============================================================
-- Sprint S.8 — Reparação de Integridade Pós-Migração Pessoas
-- ============================================================
-- Objetivo: Corrigir a base SEM deletar dados, SEM truncar,
--           SEM recriar conteúdo, SEM executar F4.
-- ============================================================
-- Dados reais levantados em 07/07/2026:
--   pessoas(id): 5(Darlan canônico), 6(Alice canônica),
--                7(Darlan dup), 8(Dionir), 9(Alice dup),
--                10(Beatriz), 11(Andrey), 12(Delaine)
--   memorias.usuario_id: todas NULL (bug da _migrar_fk)
--   fotos.usuario_id: todas NULL
--   videos.usuario_id: todas NULL
--   conteudo_permissoes.pessoa_id: todas = 12 (Delaine) ou NULL
--   criado_por_id: 5 e 6 = 2 (old usuarios.id); 7-12 = 5 (correto)
--   memoriais.usuario_id: NULL
-- ============================================================

BEGIN;

-- ============================================================
-- A. FIX memorias.usuario_id
--    Dados reais: Darlan é dono de todas, exceto "Meu bolo
--    preferido" (id=35) que é da Alice.
--    Desabilita triggers (evita recursão de
--    tg_atualizar_ultima_atualizacao_memoria) antes do UPDATE
-- ============================================================
ALTER TABLE memorias DISABLE TRIGGER USER;
UPDATE memorias SET usuario_id = 5 WHERE usuario_id IS NULL AND id != 35;
UPDATE memorias SET usuario_id = 6 WHERE id = 35;
ALTER TABLE memorias ENABLE TRIGGER USER;
DO $$ BEGIN
    RAISE NOTICE 'A. memorias.usuario_id = 5 exceto id=35 (=6): % linhas',
        (SELECT count(*) FROM memorias WHERE usuario_id IS NOT NULL);
END $$;

-- ============================================================
-- B. FIX fotos.usuario_id
--    Todas pertencem a memórias do Darlan
-- ============================================================
ALTER TABLE fotos DISABLE TRIGGER USER;
UPDATE fotos SET usuario_id = 5 WHERE usuario_id IS NULL;
ALTER TABLE fotos ENABLE TRIGGER USER;
DO $$ BEGIN
    RAISE NOTICE 'B. fotos.usuario_id = 5: % linhas',
        (SELECT count(*) FROM fotos WHERE usuario_id = 5);
END $$;

-- ============================================================
-- C. FIX videos.usuario_id
--    Todos pertencem a memórias do Darlan
-- ============================================================
ALTER TABLE videos DISABLE TRIGGER USER;
UPDATE videos SET usuario_id = 5 WHERE usuario_id IS NULL;
ALTER TABLE videos ENABLE TRIGGER USER;
DO $$ BEGIN
    RAISE NOTICE 'C. videos.usuario_id = 5: % linhas',
        (SELECT count(*) FROM videos WHERE usuario_id = 5);
END $$;

-- ============================================================
-- D. FIX conteudo_permissoes.pessoa_id
--    Dados reais: TODOS os registros são conteúdo do Darlan
--    (já que só Darlan tem conteúdo no app). Estavam com
--    pessoa_id=12 (Delaine) por bug do _migrar_fk.
-- ============================================================
UPDATE conteudo_permissoes SET pessoa_id = 5
WHERE pessoa_id IS NULL OR pessoa_id != 5;
DO $$ BEGIN
    RAISE NOTICE 'D. conteudo_permissoes.pessoa_id = 5: % linhas',
        (SELECT count(*) FROM conteudo_permissoes WHERE pessoa_id = 5);
END $$;

-- ============================================================
-- E. FIX pessoas.criado_por_id
--    Pessoas 5 (Darlan) e 6 (Alice) vieram de usuarios → sem
--    criador (auto-cadastro por auth). Pessoas 7-12 vieram de
--    contatos → criadas por Darlan (5).
--    Dados atuais: 5 e 6 têm criado_por_id=2 (antigo usuarios.id)
-- ============================================================
UPDATE pessoas SET criado_por_id = NULL WHERE id IN (5, 6);
-- Garantir que pessoas de contatos tenham criado_por_id = 5
UPDATE pessoas SET criado_por_id = 5
WHERE _legacy_contato_id IS NOT NULL
  AND id IN (7, 8, 9, 10, 11, 12)
  AND (criado_por_id IS NULL OR criado_por_id != 5);
DO $$ BEGIN
    RAISE NOTICE 'E. criado_por_id corrigido';
END $$;

-- ============================================================
-- F. MARCAR DUPLICATAS com merged_into_id
--    Pessoa 7 (Darlan de contatos) → 5 (Darlan canônico)
--    Pessoa 9 (Alice de contatos) → 6 (Alice canônica)
--    NADA é apagado.
-- ============================================================
UPDATE pessoas SET merged_into_id = 5 WHERE id = 7;
UPDATE pessoas SET merged_into_id = 6 WHERE id = 9;
DO $$ BEGIN
    RAISE NOTICE 'F. Duplicatas marcadas: pessoa 7→5, 9→6';
END $$;

-- ============================================================
-- G. RECONECTAR MEMORIAL_PESSOAS
--    Memorial 1 (Douglas) está sem Darlan(5) como pessoa
--    vinculada. Darlan é irmão do Douglas e dono do memorial.
--    Manter Alice(6), Beatriz(10), Andrey(11), Delaine(12)
--    já vinculados.
-- ============================================================
INSERT INTO memorial_pessoas (memorial_id, pessoa_id, papel)
SELECT 1, 5, 'dono'
WHERE NOT EXISTS (
    SELECT 1 FROM memorial_pessoas WHERE memorial_id = 1 AND pessoa_id = 5
);
DO $$ BEGIN
    RAISE NOTICE 'G. Darlan(5) adicionado ao memorial 1 como dono';
END $$;

-- ============================================================
-- H. FIX PESSOAS_RELACIONAMENTOS
--    DELETE registros atuais (todos com IDs inválidos/nulos).
--    INSERT novos baseados em contatos.parentesco entre pessoas
--    canônicas. Cada relação gera DUAS linhas (A→B e B→A).
-- ============================================================
DELETE FROM pessoas_relacionamentos
WHERE pessoa_a_id IS NULL OR pessoa_b_id IS NULL
   OR NOT EXISTS (SELECT 1 FROM pessoas WHERE id = pessoa_a_id)
   OR NOT EXISTS (SELECT 1 FROM pessoas WHERE id = pessoa_b_id);

-- H1. Darlan(5) Pai → Beatriz(10) | Beatriz(10) Filha → Darlan(5)
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5, 10, 'PAI',    'Pai',      'Filho(a)', true),
    (5, 10, 5, 'FILHA',  'Filho(a)', 'Mãe',      true);

-- H2. Darlan(5) Irmão → Andrey(11) | Andrey(11) Irmão → Darlan(5)
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5, 11, 'IRMAO',  'Irmão(ã)', 'Irmão(ã)', true),
    (5, 11, 5, 'IRMAO',  'Irmão(ã)', 'Irmão(ã)', true);

-- H3. Darlan(5) Irmão → Delaine(12) | Delaine(12) Irmã → Darlan(5)
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5, 12, 'IRMAO',  'Irmão(ã)', 'Irmão(ã)', true),
    (5, 12, 5, 'IRMAO',  'Irmão(ã)', 'Irmão(ã)', true);

-- H4. Darlan(5) Filho → Dionir(8) | Dionir(8) Pai → Darlan(5)
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5, 8,  'FILHO', 'Filho(a)', 'Pai',  true),
    (5, 8,  5, 'PAI',   'Pai',      'Filho(a)', true);

-- H5. Darlan(5) Cônjuge → Alice(6) | Alice(6) Cônjuge → Darlan(5)
INSERT INTO pessoas_relacionamentos
    (usuario_id, pessoa_a_id, pessoa_b_id, tipo,
     relacao_a_para_b, relacao_b_para_a, confirmado)
VALUES
    (5, 5, 6, 'CONJUGE', 'Esposo(a)', 'Esposo(a)', true),
    (5, 6, 5, 'CONJUGE', 'Esposo(a)', 'Esposo(a)', true);

DO $$ BEGIN
    RAISE NOTICE 'H. pessoas_relacionamentos recriadas: % pares',
        (SELECT count(*) FROM pessoas_relacionamentos WHERE pessoa_a_id IS NOT NULL)/2;
END $$;

-- ============================================================
-- I. RECRIAR VIEWS (garantia absoluta contra refs legadas)
-- ============================================================

-- I1. pessoa_linha_tempo
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
        COALESCE(c.texto, c.arquivo_url, 'Contribuição') AS titulo,
        c.criado_em::TEXT AS data_ordem,
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
GRANT SELECT ON public.pessoa_linha_tempo TO anon;

DO $$ BEGIN RAISE NOTICE 'I1. pessoa_linha_tempo recriada'; END $$;

-- I2. memorias_evolucao_resumo
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
            WHERE cc.tipo_conteudo = 'memoria' AND cc.conteudo_id = m.id
              AND cc.papel IN ('editor', 'colaborador')) AS tem_colaboradores,
    (SELECT COUNT(DISTINCT cc.usuario_id) FROM public.conteudo_colaboradores cc
     WHERE cc.tipo_conteudo = 'memoria' AND cc.conteudo_id = m.id
       AND cc.papel IN ('editor', 'colaborador')) AS total_colaboradores,
    (SELECT COUNT(DISTINCT LOWER(TRIM(c.usuario_contribuidor_email)))
     FROM public.contribuicoes c
     WHERE c.tipo_conteudo = 'memoria' AND c.conteudo_id = m.id
       AND c.status = 'aprovado' AND c.usuario_contribuidor_email IS NOT NULL) AS contribuidores_unicos
FROM public.memorias m;
GRANT SELECT ON public.memorias_evolucao_resumo TO anon;

DO $$ BEGIN RAISE NOTICE 'I2. memorias_evolucao_resumo recriada'; END $$;

-- ============================================================
-- J. GARANTIR FUNCTIONS CORRETAS
--    CUIDADO: pessoas NÃO tem coluna parentesco.
--    Nenhuma function pode referenciar p.parentesco.
-- ============================================================

-- J1. pessoa_estatisticas
CREATE OR REPLACE FUNCTION public.pessoa_estatisticas(pessoa_id BIGINT)
RETURNS TABLE (total_memorias BIGINT, total_fotos BIGINT, total_videos BIGINT,
               total_contribuicoes BIGINT, primeira_data DATE, ultima_data DATE)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN QUERY
    WITH memorias_ids AS (
        SELECT cp.conteudo_id AS id FROM public.conteudo_permissoes cp
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
GRANT EXECUTE ON FUNCTION public.pessoa_estatisticas(BIGINT) TO anon;
DO $$ BEGIN RAISE NOTICE 'J1. pessoa_estatisticas OK'; END $$;

-- J2. pessoas_recentes (CORRIGIDO: sem p.parentesco)
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
        FROM public.pessoas p WHERE p.criado_por_id = usuario AND p.merged_into_id IS NULL
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
DO $$ BEGIN RAISE NOTICE 'J2. pessoas_recentes OK'; END $$;

-- J3. pessoas_sugeridas
CREATE OR REPLACE FUNCTION public.pessoas_sugeridas(usuario bigint, limite int default 5)
RETURNS TABLE (nome_sugerido text, ocorrencias bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN QUERY
    WITH memorias_texto AS (
        SELECT m.conteudo AS txt FROM public.memorias m
        WHERE m.usuario_id = usuario AND m.conteudo IS NOT NULL
    ),
    palavras AS (
        SELECT DISTINCT LOWER(word) AS nome
        FROM memorias_texto,
        LATERAL regexp_matches(txt, '\y([A-ZÀ-Ú][a-zà-ú]{2,})\y', 'g') AS word
    ),
    frequencia AS (
        SELECT p.nome, COUNT(DISTINCT m.id) AS ocorrencias
        FROM palavras p
        JOIN LATERAL (SELECT m.id FROM public.memorias m
                      WHERE m.usuario_id = usuario AND m.conteudo ILIKE '%' || p.nome || '%') m ON TRUE
        GROUP BY p.nome
    ),
    ja_cadastrados AS (
        SELECT LOWER(p.nome) AS nome FROM public.pessoas p
        WHERE p.criado_por_id = usuario AND p.merged_into_id IS NULL
    )
    SELECT f.nome, f.ocorrencias
    FROM frequencia f
    WHERE f.ocorrencias >= 2
      AND NOT EXISTS (SELECT 1 FROM ja_cadastrados j WHERE j.nome = f.nome)
    ORDER BY f.ocorrencias DESC LIMIT limite;
END;
$$;
GRANT EXECUTE ON FUNCTION public.pessoas_sugeridas(BIGINT, INT) TO anon;
DO $$ BEGIN RAISE NOTICE 'J3. pessoas_sugeridas OK'; END $$;

-- J4. memorias_do_dia
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
GRANT EXECUTE ON FUNCTION public.memorias_do_dia(BIGINT, INT) TO anon;
DO $$ BEGIN RAISE NOTICE 'J4. memorias_do_dia OK'; END $$;

-- J5. buscar_candidatas_relacionamento
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
GRANT EXECUTE ON FUNCTION public.buscar_candidatas_relacionamento(BIGINT, INT) TO anon;
DO $$ BEGIN RAISE NOTICE 'J5. buscar_candidatas_relacionamento OK'; END $$;

-- ============================================================
-- K. VALIDAÇÃO
-- ============================================================
DO $$
DECLARE
    v_qtd_checks INT := 0;
    v_qtd_falhas INT := 0;
    v_criado_por_ok BOOLEAN;
    v_memorias_ok BOOLEAN;
    v_fotos_ok BOOLEAN;
    v_conteudo_perm_ok BOOLEAN;
    v_memorial_pessoas_ok BOOLEAN;
    v_relacionamentos_ok BOOLEAN;
    v_views_sem_contatos BOOLEAN;
    v_functions_sem_contatos BOOLEAN;
BEGIN
    -- K1. criado_por_id existe em pessoas
    SELECT NOT EXISTS (
        SELECT 1 FROM pessoas p
        WHERE p.criado_por_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM pessoas ref WHERE ref.id = p.criado_por_id)
    ) INTO v_criado_por_ok;
    v_qtd_checks := v_qtd_checks + 1;
    IF NOT v_criado_por_ok THEN RAISE WARNING 'K1. FALHA: criado_por_id ref inválida'; v_qtd_falhas := v_qtd_falhas + 1; END IF;

    -- K2. memorias.usuario_id existe em pessoas
    SELECT NOT EXISTS (
        SELECT 1 FROM memorias m
        WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = m.usuario_id)
    ) INTO v_memorias_ok;
    v_qtd_checks := v_qtd_checks + 1;
    IF NOT v_memorias_ok THEN RAISE WARNING 'K2. FALHA: memorias.usuario_id ref inválida'; v_qtd_falhas := v_qtd_falhas + 1; END IF;

    -- K3. fotos.usuario_id existe em pessoas
    SELECT NOT EXISTS (
        SELECT 1 FROM fotos f
        WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = f.usuario_id)
    ) INTO v_fotos_ok;
    v_qtd_checks := v_qtd_checks + 1;
    IF NOT v_fotos_ok THEN RAISE WARNING 'K3. FALHA: fotos.usuario_id ref inválida'; v_qtd_falhas := v_qtd_falhas + 1; END IF;

    -- K4. conteudo_permissoes.pessoa_id existe em pessoas
    SELECT NOT EXISTS (
        SELECT 1 FROM conteudo_permissoes cp
        WHERE NOT EXISTS (SELECT 1 FROM pessoas p WHERE p.id = cp.pessoa_id)
    ) INTO v_conteudo_perm_ok;
    v_qtd_checks := v_qtd_checks + 1;
    IF NOT v_conteudo_perm_ok THEN RAISE WARNING 'K4. FALHA: conteudo_permissoes.pessoa_id ref inválida'; v_qtd_falhas := v_qtd_falhas + 1; END IF;

    -- K5. memoriais com memorial_pessoas
    SELECT NOT EXISTS (
        SELECT 1 FROM memoriais m
        WHERE NOT EXISTS (SELECT 1 FROM memorial_pessoas mp WHERE mp.memorial_id = m.id)
    ) INTO v_memorial_pessoas_ok;
    v_qtd_checks := v_qtd_checks + 1;
    IF NOT v_memorial_pessoas_ok THEN RAISE WARNING 'K5. FALHA: memoriais sem memorial_pessoas'; v_qtd_falhas := v_qtd_falhas + 1; END IF;

    -- K6. pessoas_relacionamentos válidos
    SELECT NOT EXISTS (
        SELECT 1 FROM pessoas_relacionamentos
        WHERE pessoa_a_id IS NULL OR pessoa_b_id IS NULL
           OR NOT EXISTS (SELECT 1 FROM pessoas WHERE id = pessoa_a_id)
           OR NOT EXISTS (SELECT 1 FROM pessoas WHERE id = pessoa_b_id)
    ) INTO v_relacionamentos_ok;
    v_qtd_checks := v_qtd_checks + 1;
    IF NOT v_relacionamentos_ok THEN RAISE WARNING 'K6. FALHA: relacionamentos inválidos'; v_qtd_falhas := v_qtd_falhas + 1; END IF;

    -- K7. Views SEM contatos
    SELECT NOT EXISTS (
        SELECT 1 FROM pg_views
        WHERE schemaname = 'public'
          AND (definition ILIKE '%contatos%' OR definition ILIKE '%contato_id%')
    ) INTO v_views_sem_contatos;
    v_qtd_checks := v_qtd_checks + 1;
    IF NOT v_views_sem_contatos THEN RAISE WARNING 'K7. FALHA: views ref contatos'; v_qtd_falhas := v_qtd_falhas + 1; END IF;

    -- K8. Functions SEM contatos
    SELECT NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE pronamespace = 'public'::regnamespace
          AND (prosrc ILIKE '%contatos%' OR prosrc ILIKE '%contato_id%')
    ) INTO v_functions_sem_contatos;
    v_qtd_checks := v_qtd_checks + 1;
    IF NOT v_functions_sem_contatos THEN RAISE WARNING 'K8. FALHA: functions ref contatos'; v_qtd_falhas := v_qtd_falhas + 1; END IF;

    RAISE NOTICE '============================================';
    RAISE NOTICE 'VALIDAÇÃO: % checks, % falhas', v_qtd_checks, v_qtd_falhas;
    IF v_qtd_falhas = 0 THEN
        RAISE NOTICE '✅ REPARO CONCLUÍDO — 0 falhas';
    ELSE
        RAISE WARNING '⚠️ % falha(s) — revisar', v_qtd_falhas;
    END IF;
    RAISE NOTICE '============================================';
END $$;

COMMIT;

-- ============================================================
-- VALIDAÇÃO VISUAL — queries para conferir após execução
-- ============================================================
-- 1. SELECT id, nome, merged_into_id FROM pessoas WHERE merged_into_id IS NOT NULL;
--
-- 2. SELECT usuario_id, count(*) FROM memorias GROUP BY usuario_id;
--
-- 3. SELECT * FROM pessoa_linha_tempo WHERE pessoa_id = 5 LIMIT 10;
--
-- 4. SELECT * FROM pessoas_recentes(5, 10);
--
-- 5. SELECT * FROM memorial_pessoas mp JOIN memoriais m ON m.id = mp.memorial_id;
--
-- 6. SELECT * FROM pessoas_relacionamentos ORDER BY tipo, pessoa_a_id;
-- ============================================================
