-- =============================================================
-- Sprint O — Menu Secundário e Paridade Discreta do Mobile
-- Funcionalidades: Mensagens para o Futuro, Cofre, Quem Sou Eu
-- =============================================================

-- 1. MENSAGENS PARA O FUTURO
CREATE TABLE IF NOT EXISTS mensagens_futuro (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  titulo TEXT NOT NULL,
  conteudo TEXT NOT NULL,
  data_agendamento TIMESTAMPTZ NOT NULL,
  entregue BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mensagens_futuro_usuario ON mensagens_futuro(usuario_id);
CREATE INDEX IF NOT EXISTS idx_mensagens_futuro_agendamento ON mensagens_futuro(data_agendamento);

ALTER TABLE mensagens_futuro ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mensagens_futuro_select" ON mensagens_futuro
  FOR SELECT USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "mensagens_futuro_insert" ON mensagens_futuro
  FOR INSERT WITH CHECK (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "mensagens_futuro_update" ON mensagens_futuro
  FOR UPDATE USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "mensagens_futuro_delete" ON mensagens_futuro
  FOR DELETE USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

-- 2. COFRE
CREATE TABLE IF NOT EXISTS cofre_itens (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  titulo TEXT NOT NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('texto', 'documento')),
  conteudo TEXT,
  url_arquivo TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cofre_itens_usuario ON cofre_itens(usuario_id);

ALTER TABLE cofre_itens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cofre_itens_select" ON cofre_itens
  FOR SELECT USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "cofre_itens_insert" ON cofre_itens
  FOR INSERT WITH CHECK (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "cofre_itens_update" ON cofre_itens
  FOR UPDATE USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "cofre_itens_delete" ON cofre_itens
  FOR DELETE USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

-- 3. QUEM SOU EU
CREATE TABLE IF NOT EXISTS quem_sou_eu (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  pergunta_chave TEXT NOT NULL,
  resposta TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_quem_sou_eu_usuario ON quem_sou_eu(usuario_id);

ALTER TABLE quem_sou_eu ENABLE ROW LEVEL SECURITY;

CREATE POLICY "quem_sou_eu_select" ON quem_sou_eu
  FOR SELECT USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "quem_sou_eu_insert" ON quem_sou_eu
  FOR INSERT WITH CHECK (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "quem_sou_eu_update" ON quem_sou_eu
  FOR UPDATE USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

CREATE POLICY "quem_sou_eu_delete" ON quem_sou_eu
  FOR DELETE USING (usuario_id = (SELECT id FROM usuarios WHERE auth_id = auth.uid()::text));

-- GRANTs (anon key)
GRANT ALL ON mensagens_futuro TO anon;
GRANT ALL ON cofre_itens TO anon;
GRANT ALL ON quem_sou_eu TO anon;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;
