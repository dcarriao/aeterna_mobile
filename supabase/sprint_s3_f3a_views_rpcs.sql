-- ============================================================
-- Sprint S.3 — Fase 3a: Views e RPCs
-- Atualiza objetos do banco para usar pessoas
-- ============================================================
-- Executar antes: sprint_s3_f2_fks.sql
-- Executar depois: sprint_s3_f3b_rls.sql
-- ============================================================

BEGIN;

-- ============================================================
-- S2.3.0: View GRAFO_PESSOAS_RELACIONAMENTOS
-- ============================================================
DROP VIEW IF EXISTS grafo_pessoas_relacionamentos CASCADE;
CREATE VIEW grafo_pessoas_relacionamentos AS
SELECT
  r.id AS relacao_id,
  r.pessoa_a_id,
  pa.nome AS pessoa_a_nome,
  pa.foto_perfil AS pessoa_a_foto,
  pa.falecido AS pessoa_a_falecido,
  pa.tipo AS pessoa_a_tipo,
  r.pessoa_b_id,
  pb.nome AS pessoa_b_nome,
  pb.foto_perfil AS pessoa_b_foto,
  pb.falecido AS pessoa_b_falecido,
  pb.tipo AS pessoa_b_tipo,
  r.tipo AS tipo_relacao_id,
  tr.rotulo_a_para_b,
  tr.rotulo_b_para_a,
  tr.categoria,
  r.confirmado,
  r.data_inicio,
  r.data_fim
FROM pessoas_relacionamentos r
JOIN pessoas pa ON pa.id = r.pessoa_a_id
JOIN pessoas pb ON pb.id = r.pessoa_b_id
LEFT JOIN tipos_relacionamento tr ON tr.id = r.tipo;

-- ============================================================
-- S2.3.1: RPC listar_relacionamentos_pessoa
-- ============================================================
DROP FUNCTION IF EXISTS listar_relacionamentos_pessoa(BIGINT);
CREATE FUNCTION listar_relacionamentos_pessoa(p_pessoa_id BIGINT)
RETURNS TABLE(
  relacao_id BIGINT,
  outra_pessoa_id BIGINT,
  outra_pessoa_nome TEXT,
  outra_pessoa_foto TEXT,
  outra_pessoa_falecido BOOLEAN,
  outra_pessoa_tipo TEXT,
  tipo_relacao_id TEXT,
  rotulo_pessoa TEXT,
  rotulo_outra TEXT,
  categoria TEXT,
  simetrico BOOLEAN,
  confirmado BOOLEAN,
  data_inicio DATE,
  data_fim DATE
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    r.id, r.pessoa_b_id, pb.nome, pb.foto_perfil, pb.falecido, pb.tipo,
    r.tipo, tr.rotulo_a_para_b, tr.rotulo_b_para_a,
    COALESCE(tr.categoria, 'outro'), COALESCE(tr.simetrico, false),
    r.confirmado, r.data_inicio, r.data_fim
  FROM pessoas_relacionamentos r
  JOIN pessoas pb ON pb.id = r.pessoa_b_id
  LEFT JOIN tipos_relacionamento tr ON tr.id = r.tipo
  WHERE r.pessoa_a_id = p_pessoa_id

  UNION ALL

  SELECT
    r.id, r.pessoa_a_id, pa.nome, pa.foto_perfil, pa.falecido, pa.tipo,
    r.tipo, tr.rotulo_b_para_a, tr.rotulo_a_para_b,
    COALESCE(tr.categoria, 'outro'), COALESCE(tr.simetrico, false),
    r.confirmado, r.data_inicio, r.data_fim
  FROM pessoas_relacionamentos r
  JOIN pessoas pa ON pa.id = r.pessoa_a_id
  LEFT JOIN tipos_relacionamento tr ON tr.id = r.tipo
  WHERE r.pessoa_b_id = p_pessoa_id
  ORDER BY categoria, rotulo_pessoa;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- S2.3.2: RPC listar_pessoas_com_mesma_relacao
-- ============================================================
DROP FUNCTION IF EXISTS listar_pessoas_com_mesma_relacao(BIGINT, TEXT);
CREATE FUNCTION listar_pessoas_com_mesma_relacao(
  p_pessoa_id BIGINT,
  p_tipo_relacao TEXT
)
RETURNS TABLE(
  pessoa_id BIGINT,
  nome TEXT,
  foto_perfil TEXT,
  falecido BOOLEAN,
  tipo TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT
    CASE WHEN r.pessoa_a_id = p_pessoa_id THEN r.pessoa_b_id ELSE r.pessoa_a_id END,
    p.nome, p.foto_perfil, p.falecido, p.tipo
  FROM pessoas_relacionamentos r
  JOIN pessoas p ON p.id = CASE WHEN r.pessoa_a_id = p_pessoa_id THEN r.pessoa_b_id ELSE r.pessoa_a_id END
  WHERE (r.pessoa_a_id = p_pessoa_id OR r.pessoa_b_id = p_pessoa_id)
    AND r.tipo = p_tipo_relacao
    AND p.id <> p_pessoa_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- S2.3.3: RPC upsert_device_token
-- ============================================================
DROP FUNCTION IF EXISTS upsert_device_token(TEXT, TEXT);
CREATE FUNCTION upsert_device_token(
  p_token TEXT,
  p_plataforma TEXT DEFAULT 'unknown'
)
RETURNS void AS $$
BEGIN
  INSERT INTO device_tokens (usuario_id, token, plataforma)
  VALUES (pessoa_autenticada_id(), p_token, p_plataforma)
  ON CONFLICT (usuario_id, token)
  DO UPDATE SET plataforma = EXCLUDED.plataforma, updated_at = now();
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- VALIDACAO
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE '✅ Fase 3a OK — views, RPCs, functions atualizadas';
END $$;

COMMIT;

-- ============================================================
-- ROLLBACK
-- ============================================================
-- DROP VIEW IF EXISTS grafo_pessoas_relacionamentos;
-- DROP FUNCTION IF EXISTS listar_relacionamentos_pessoa(BIGINT);
-- DROP FUNCTION IF EXISTS listar_pessoas_com_mesma_relacao(BIGINT, TEXT);
-- DROP FUNCTION IF EXISTS upsert_device_token(TEXT, TEXT);
