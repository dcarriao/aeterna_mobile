-- ============================================================
-- Sprint S.3 — Fase 3b: RLS Policies
-- Substitui auth.uid() por pessoa_autenticada_id() nas policies
-- ============================================================
-- Executar antes: sprint_s3_f3a_views_rpcs.sql
-- Executar depois: sprint_s3_f4_cleanup.sql
-- ============================================================

BEGIN;

-- ============================================================
-- Função auxiliar: pessoa_autenticada_id (recriada)
-- ============================================================
CREATE OR REPLACE FUNCTION public.pessoa_autenticada_id()
RETURNS BIGINT
LANGUAGE SQL STABLE SECURITY DEFINER
AS $$
  SELECT id FROM pessoas
  WHERE auth_user_id = auth.uid()
     OR auth_id = auth.uid()::text
  LIMIT 1;
$$;

-- ============================================================
-- S2.3.4: RLS — PESSOAS
-- ============================================================
ALTER TABLE pessoas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pessoas_select ON pessoas;
DROP POLICY IF EXISTS pessoas_insert ON pessoas;
DROP POLICY IF EXISTS pessoas_update ON pessoas;

CREATE POLICY pessoas_select ON pessoas FOR SELECT USING (
  id = pessoa_autenticada_id()
  OR criado_por_id = pessoa_autenticada_id()
  OR id IN (
    SELECT pessoa_a_id FROM pessoas_relacionamentos
    WHERE pessoa_b_id = pessoa_autenticada_id()
    UNION
    SELECT pessoa_b_id FROM pessoas_relacionamentos
    WHERE pessoa_a_id = pessoa_autenticada_id()
  )
  OR (
    tipo = 'pet'
    AND criado_por_id = pessoa_autenticada_id()
  )
);

CREATE POLICY pessoas_insert ON pessoas FOR INSERT WITH CHECK (
  true  -- qualquer usuario logado pode criar (controle via app)
);

CREATE POLICY pessoas_update ON pessoas FOR UPDATE USING (
  id = pessoa_autenticada_id()  -- so a propria pessoa
  OR criado_por_id = pessoa_autenticada_id()  -- ou quem criou
);

-- ============================================================
-- RLS — PESSOA_IDENTIFICADORES
-- ============================================================
ALTER TABLE pessoa_identificadores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pi_select ON pessoa_identificadores;
DROP POLICY IF EXISTS pi_insert ON pessoa_identificadores;
DROP POLICY IF EXISTS pi_update ON pessoa_identificadores;
DROP POLICY IF EXISTS pi_delete ON pessoa_identificadores;

CREATE POLICY pi_select ON pessoa_identificadores FOR SELECT USING (
  pessoa_id = pessoa_autenticada_id()
);

CREATE POLICY pi_insert ON pessoa_identificadores FOR INSERT WITH CHECK (
  pessoa_id = pessoa_autenticada_id()
);

CREATE POLICY pi_update ON pessoa_identificadores FOR UPDATE USING (
  pessoa_id = pessoa_autenticada_id()
);

CREATE POLICY pi_delete ON pessoa_identificadores FOR DELETE USING (
  pessoa_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — MEMORIAS (exemplo: atualizar de auth.uid() para pessoa_autenticada_id())
-- ============================================================
DROP POLICY IF EXISTS memorias_select ON memorias;
DROP POLICY IF EXISTS memorias_insert ON memorias;
DROP POLICY IF EXISTS memorias_update ON memorias;

CREATE POLICY memorias_select ON memorias FOR SELECT USING (
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

CREATE POLICY memorias_insert ON memorias FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);

CREATE POLICY memorias_update ON memorias FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — PESSOAS_RELACIONAMENTOS
-- ============================================================
DROP POLICY IF EXISTS pr_select ON pessoas_relacionamentos;
DROP POLICY IF EXISTS pr_insert ON pessoas_relacionamentos;
DROP POLICY IF EXISTS pr_update ON pessoas_relacionamentos;

CREATE POLICY pr_select ON pessoas_relacionamentos FOR SELECT USING (
  pessoa_a_id = pessoa_autenticada_id()
  OR pessoa_b_id = pessoa_autenticada_id()
  OR usuario_id = pessoa_autenticada_id()
);

CREATE POLICY pr_insert ON pessoas_relacionamentos FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);

CREATE POLICY pr_update ON pessoas_relacionamentos FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — CONTEUDO_PERMISSOES
-- ============================================================
DROP POLICY IF EXISTS cp_select ON conteudo_permissoes;
DROP POLICY IF EXISTS cp_insert ON conteudo_permissoes;
DROP POLICY IF EXISTS cp_update ON conteudo_permissoes;

CREATE POLICY cp_select ON conteudo_permissoes FOR SELECT USING (
  pessoa_id = pessoa_autenticada_id()
);

CREATE POLICY cp_insert ON conteudo_permissoes FOR INSERT WITH CHECK (
  pessoa_id = pessoa_autenticada_id()
  OR pessoa_id IN (
    SELECT id FROM pessoas WHERE criado_por_id = pessoa_autenticada_id()
  )
);

CREATE POLICY cp_update ON conteudo_permissoes FOR UPDATE USING (
  pessoa_id = pessoa_autenticada_id()
  OR pessoa_id IN (
    SELECT id FROM pessoas WHERE criado_por_id = pessoa_autenticada_id()
  )
);

-- ============================================================
-- RLS — MENSAGENS_FUTURO
-- ============================================================
DROP POLICY IF EXISTS mf_select ON mensagens_futuro;
DROP POLICY IF EXISTS mf_insert ON mensagens_futuro;
DROP POLICY IF EXISTS mf_update ON mensagens_futuro;

CREATE POLICY mf_select ON mensagens_futuro FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
  OR destinatario_id = pessoa_autenticada_id()
);

CREATE POLICY mf_insert ON mensagens_futuro FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);

CREATE POLICY mf_update ON mensagens_futuro FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — CONVITES_FAMILIARES
-- ============================================================
DROP POLICY IF EXISTS cf_select ON convites_familiares;
DROP POLICY IF EXISTS cf_insert ON convites_familiares;
DROP POLICY IF EXISTS cf_update ON convites_familiares;

CREATE POLICY cf_select ON convites_familiares FOR SELECT USING (
  usuario_origem_id = pessoa_autenticada_id()
  OR usuario_destino_id = pessoa_autenticada_id()
);

CREATE POLICY cf_insert ON convites_familiares FOR INSERT WITH CHECK (
  usuario_origem_id = pessoa_autenticada_id()
);

CREATE POLICY cf_update ON convites_familiares FOR UPDATE USING (
  usuario_origem_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — device_tokens
-- ============================================================
DROP POLICY IF EXISTS dt_select ON device_tokens;
DROP POLICY IF EXISTS dt_insert ON device_tokens;
DROP POLICY IF EXISTS dt_update ON device_tokens;
DROP POLICY IF EXISTS dt_delete ON device_tokens;

CREATE POLICY dt_select ON device_tokens FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY dt_insert ON device_tokens FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY dt_update ON device_tokens FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY dt_delete ON device_tokens FOR DELETE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — curador_sessoes
-- ============================================================
DROP POLICY IF EXISTS cs_select ON curador_sessoes;
DROP POLICY IF EXISTS cs_insert ON curador_sessoes;
DROP POLICY IF EXISTS cs_update ON curador_sessoes;

CREATE POLICY cs_select ON curador_sessoes FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY cs_insert ON curador_sessoes FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY cs_update ON curador_sessoes FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — cofre_itens
-- ============================================================
DROP POLICY IF EXISTS ci_select ON cofre_itens;
DROP POLICY IF EXISTS ci_insert ON cofre_itens;
DROP POLICY IF EXISTS ci_update ON cofre_itens;

CREATE POLICY ci_select ON cofre_itens FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY ci_insert ON cofre_itens FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY ci_update ON cofre_itens FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — quem_sou_eu
-- ============================================================
DROP POLICY IF EXISTS qse_select ON quem_sou_eu;
DROP POLICY IF EXISTS qse_insert ON quem_sou_eu;
DROP POLICY IF EXISTS qse_update ON quem_sou_eu;

CREATE POLICY qse_select ON quem_sou_eu FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY qse_insert ON quem_sou_eu FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY qse_update ON quem_sou_eu FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — configuracoes_curador
-- ============================================================
DROP POLICY IF EXISTS cc_select ON configuracoes_curador;
DROP POLICY IF EXISTS cc_insert ON configuracoes_curador;
DROP POLICY IF EXISTS cc_update ON configuracoes_curador;

CREATE POLICY cc_select ON configuracoes_curador FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY cc_insert ON configuracoes_curador FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);
CREATE POLICY cc_update ON configuracoes_curador FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — contribuicoes (leitura para dono do memorial e quem criou)
-- ============================================================
DROP POLICY IF EXISTS contrib_select ON contribuicoes;
DROP POLICY IF EXISTS contrib_insert ON contribuicoes;

CREATE POLICY contrib_select ON contribuicoes FOR SELECT USING (
  usuario_dono_id = pessoa_autenticada_id()
  OR avaliado_por = pessoa_autenticada_id()
);

CREATE POLICY contrib_insert ON contribuicoes FOR INSERT WITH CHECK (
  true  -- qualquer um pode contribuir; aprovacao via status
);

-- ============================================================
-- RLS — memoriais
-- ============================================================
DROP POLICY IF EXISTS mem_select ON memoriais;
DROP POLICY IF EXISTS mem_insert ON memoriais;
DROP POLICY IF EXISTS mem_update ON memoriais;

CREATE POLICY mem_select ON memoriais FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
);

CREATE POLICY mem_insert ON memoriais FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);

CREATE POLICY mem_update ON memoriais FOR UPDATE USING (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- RLS — vinculos_familiares
-- ============================================================
DROP POLICY IF EXISTS vf_select ON vinculos_familiares;
DROP POLICY IF EXISTS vf_insert ON vinculos_familiares;

CREATE POLICY vf_select ON vinculos_familiares FOR SELECT USING (
  usuario_id = pessoa_autenticada_id()
  OR vinculado_usuario_id = pessoa_autenticada_id()
);
CREATE POLICY vf_insert ON vinculos_familiares FOR INSERT WITH CHECK (
  usuario_id = pessoa_autenticada_id()
);

-- ============================================================
-- VALIDACAO
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE '✅ Fase 3b OK — RLS policies atualizadas para pessoa_autenticada_id()';
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK
-- ============================================================
-- Remover RLS policies:
--   DROP POLICY IF EXISTS pessoas_select ON pessoas;
--   ... (para cada policy criada acima)
-- Restaurar funcao original (se existia):
--   CREATE OR REPLACE FUNCTION public.pessoa_autenticada_id() ...;
