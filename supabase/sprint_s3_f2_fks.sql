-- ============================================================
-- Sprint S.3 — Fase 2: Migração de FKs
-- Schema REAL auditado em 06/07/2026
-- ============================================================
-- ATENÇÃO: Requer downtime
-- ============================================================

BEGIN;

-- ============================================================
-- Função auxiliar com verificação de existência
-- ============================================================
CREATE OR REPLACE FUNCTION public._migrar_fk(
  p_tabela  TEXT,
  p_coluna  TEXT,
  p_origem  TEXT
)
RETURNS TEXT AS $$
DECLARE
  v_coluna_existe BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = p_tabela
      AND column_name = p_coluna
  ) INTO v_coluna_existe;

  IF NOT v_coluna_existe THEN
    RETURN format('⚠️ %I.%I não existe — pulando', p_tabela, p_coluna);
  END IF;

  EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS %I_novo BIGINT', p_tabela, p_coluna);

  EXECUTE format('
    UPDATE %I t
    SET %I_novo = m.nova_pessoa_id
    FROM migracao_pessoas_map m
    WHERE m.origem_tabela = %L
      AND m.origem_id = t.%I',
    p_tabela, p_coluna, p_origem, p_coluna);

  EXECUTE format('ALTER TABLE %I DROP COLUMN IF EXISTS %I CASCADE', p_tabela, p_coluna);
  EXECUTE format('ALTER TABLE %I RENAME COLUMN %I_novo TO %I', p_tabela, p_coluna, p_coluna);

  EXECUTE format('
    ALTER TABLE %I ADD CONSTRAINT fk_%I_%I_pessoas
    FOREIGN KEY (%I) REFERENCES pessoas(id)',
    p_tabela, p_tabela, p_coluna, p_coluna);

  RETURN format('✅ %I.%I → pessoas(id)', p_tabela, p_coluna);
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- MIGRAÇÕES (baseado no schema REAL)
-- ============================================================

-- 1. pessoas_relacionamentos: pessoa_a_id → contatos, pessoa_b_id → contatos, usuario_id → usuarios
SELECT _migrar_fk('pessoas_relacionamentos', 'pessoa_a_id', 'contatos');
SELECT _migrar_fk('pessoas_relacionamentos', 'pessoa_b_id', 'contatos');
SELECT _migrar_fk('pessoas_relacionamentos', 'usuario_id', 'usuarios');

-- 2. memorias: usuario_id → usuarios (com desabilitação de trigger recursivo)
ALTER TABLE memorias DISABLE TRIGGER USER;
SELECT _migrar_fk('memorias', 'usuario_id', 'usuarios');
ALTER TABLE memorias ENABLE TRIGGER USER;

-- 3. conteudo_permissoes: contato_id → contatos
SELECT _migrar_fk('conteudo_permissoes', 'contato_id', 'contatos');

-- 4. conteudo_colaboradores: usuario_id → usuarios, concedido_por → usuarios
SELECT _migrar_fk('conteudo_colaboradores', 'usuario_id', 'usuarios');
SELECT _migrar_fk('conteudo_colaboradores', 'concedido_por', 'usuarios');

-- 5. mensagens_futuro: usuario_id → usuarios, destinatario_id → contatos
SELECT _migrar_fk('mensagens_futuro', 'usuario_id', 'usuarios');
SELECT _migrar_fk('mensagens_futuro', 'destinatario_id', 'contatos');

-- 6. convites_familiares: usuario_origem_id → usuarios, contato_id → contatos, usuario_destino_id → usuarios
SELECT _migrar_fk('convites_familiares', 'usuario_origem_id', 'usuarios');
SELECT _migrar_fk('convites_familiares', 'contato_id', 'contatos');
SELECT _migrar_fk('convites_familiares', 'usuario_destino_id', 'usuarios');

-- 7. vinculos_familiares: usuario_id → usuarios, vinculado_usuario_id → usuarios
SELECT _migrar_fk('vinculos_familiares', 'usuario_id', 'usuarios');
SELECT _migrar_fk('vinculos_familiares', 'vinculado_usuario_id', 'usuarios');

-- 8. memoriais: usuario_id → usuarios (NÃO TEM contato_id — confirmado pelo schema real)
SELECT _migrar_fk('memoriais', 'usuario_id', 'usuarios');

-- 9. curador_sessoes: usuario_id → usuarios
SELECT _migrar_fk('curador_sessoes', 'usuario_id', 'usuarios');

-- 10. cofre_itens: usuario_id → usuarios
SELECT _migrar_fk('cofre_itens', 'usuario_id', 'usuarios');

-- 11. quem_sou_eu: usuario_id → usuarios
SELECT _migrar_fk('quem_sou_eu', 'usuario_id', 'usuarios');

-- 12. device_tokens: usuario_id → usuarios
SELECT _migrar_fk('device_tokens', 'usuario_id', 'usuarios');

-- 13. configuracoes_curador: usuario_id → usuarios
SELECT _migrar_fk('configuracoes_curador', 'usuario_id', 'usuarios');

-- 14. contribuicoes: usuario_dono_id → usuarios, avaliado_por → usuarios
SELECT _migrar_fk('contribuicoes', 'usuario_dono_id', 'usuarios');
SELECT _migrar_fk('contribuicoes', 'avaliado_por', 'usuarios');

-- 15. fotos: usuario_id → usuarios
SELECT _migrar_fk('fotos', 'usuario_id', 'usuarios');

-- 16. videos: usuario_id → usuarios
SELECT _migrar_fk('videos', 'usuario_id', 'usuarios');

-- 17. memoria_relacionamentos: usuario_id → usuarios
SELECT _migrar_fk('memoria_relacionamentos', 'usuario_id', 'usuarios');

-- ============================================================
-- Limpeza
-- ============================================================
DROP FUNCTION IF EXISTS public._migrar_fk;

-- ============================================================
-- VALIDAÇÃO: testa APENAS colunas que existem
-- ============================================================
DO $$
DECLARE
  r RECORD;
  v_falhas INT := 0;
BEGIN
  FOR r IN (
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND (
        (table_name = 'pessoas_relacionamentos' AND column_name IN ('pessoa_a_id', 'pessoa_b_id', 'usuario_id'))
        OR (table_name = 'memorias' AND column_name = 'usuario_id')
        OR (table_name = 'conteudo_permissoes' AND column_name = 'contato_id')
        OR (table_name = 'conteudo_colaboradores' AND column_name IN ('usuario_id', 'concedido_por'))
        OR (table_name = 'mensagens_futuro' AND column_name IN ('usuario_id', 'destinatario_id'))
        OR (table_name = 'convites_familiares' AND column_name IN ('usuario_origem_id', 'contato_id', 'usuario_destino_id'))
        OR (table_name = 'vinculos_familiares' AND column_name IN ('usuario_id', 'vinculado_usuario_id'))
        OR (table_name = 'memoriais' AND column_name = 'usuario_id')
        OR (table_name = 'curador_sessoes' AND column_name = 'usuario_id')
        OR (table_name = 'cofre_itens' AND column_name = 'usuario_id')
        OR (table_name = 'quem_sou_eu' AND column_name = 'usuario_id')
        OR (table_name = 'device_tokens' AND column_name = 'usuario_id')
        OR (table_name = 'configuracoes_curador' AND column_name = 'usuario_id')
        OR (table_name = 'contribuicoes' AND column_name IN ('usuario_dono_id', 'avaliado_por'))
        OR (table_name = 'fotos' AND column_name = 'usuario_id')
        OR (table_name = 'videos' AND column_name = 'usuario_id')
        OR (table_name = 'memoria_relacionamentos' AND column_name = 'usuario_id')
      )
  ) LOOP
    EXECUTE format('
      SELECT count(*) FROM (
        SELECT 1 FROM %I x
        WHERE %I IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM pessoas WHERE id = x.%I)
        LIMIT 1
      ) t',
      r.table_name, r.column_name, r.column_name)
    INTO v_falhas;

    IF v_falhas > 0 THEN
      RAISE WARNING '⚠️ FK inválida em %I.%I → pessoas(id)', r.table_name, r.column_name;
    END IF;
  END LOOP;

  RAISE NOTICE '✅ Fase 2 OK — todas as colunas existentes foram migradas';
END $$;

COMMIT;

-- ROLLBACK: Requer pg_restore de backup
