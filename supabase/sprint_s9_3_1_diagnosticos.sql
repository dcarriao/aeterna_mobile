-- =============================================================================
-- SPRINT S.9.3.1 — DIAGNÓSTICOS OBRIGATÓRIOS (Itens 3, 4, 6 e 10)
-- Arquivo  : supabase/sprint_s9_3_1_diagnosticos.sql
-- Executar : SQL Editor do Supabase — SOMENTE LEITURA (nenhum UPDATE/DELETE).
--            Rodar cada bloco separadamente e enviar os resultados ao chat
--            para que a correção de DADOS seja proposta com evidência.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- D1 (Item 10) — Erro 42703 "record new has no field tipo"
-- Lista TODOS os triggers do schema public. O erro acontece ao INSERIR em
-- conteudo_permissoes (participantes/compartilhamento da memória): algum
-- trigger dessa tabela referencia NEW.tipo, coluna que não existe nela.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    event_object_schema,
    event_object_table,
    trigger_name,
    action_timing,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- D1b — Foco: triggers da tabela envolvida no INSERT que falha
SELECT trigger_name, action_timing, event_manipulation, action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'conteudo_permissoes';

-- D1c — Corpo das funções que citam "tipo" e são usadas por triggers
--       (localiza a linha exata `NEW.tipo`)
SELECT p.proname, pg_get_functiondef(p.oid) AS definicao
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND pg_get_functiondef(p.oid) ILIKE '%NEW.tipo%';

-- D1d — Estrutura real de conteudo_permissoes (confirma que não há coluna tipo)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'conteudo_permissoes'
ORDER BY ordinal_position;

-- ─────────────────────────────────────────────────────────────────────────────
-- D2 (Item 6) — Relações invertidas no perfil (query oficial p/ Delaine)
-- Substituir :pessoa_perfil_id pelo id da Delaine (descobrir no D2a).
-- ─────────────────────────────────────────────────────────────────────────────
-- D2a — ids das pessoas citadas
SELECT id, nome, sobrenome, tipo
FROM pessoas
WHERE nome ILIKE ANY (ARRAY['%delaine%', '%andrey%', '%dionir%', '%alice%', '%jonathas%'])
ORDER BY nome;

-- D2b — Query oficial do perfil (o app exibe relacao_b_para_a)
--       Trocar 999 pelo id da Delaine.
SELECT
    r.id            AS relacionamento_id,
    r.pessoa_b_id,
    p.nome,
    p.sobrenome,
    r.tipo,
    r.relacao_a_para_b,
    r.relacao_b_para_a
FROM pessoas_relacionamentos r
INNER JOIN pessoas p ON p.id = r.pessoa_b_id
WHERE r.pessoa_a_id = 999   -- << id da Delaine
ORDER BY r.pessoa_b_id;

-- D2c — As DUAS direções de cada par envolvendo a Delaine (para ver se a
--       linha direta e a inversa estão contraditórias — efeito do bug de
--       gravação corrigido no app nesta sprint)
SELECT r.id, r.pessoa_a_id, pa.nome AS nome_a, r.pessoa_b_id, pb.nome AS nome_b,
       r.tipo, r.relacao_a_para_b, r.relacao_b_para_a
FROM pessoas_relacionamentos r
JOIN pessoas pa ON pa.id = r.pessoa_a_id
JOIN pessoas pb ON pb.id = r.pessoa_b_id
WHERE 999 IN (r.pessoa_a_id, r.pessoa_b_id)   -- << id da Delaine
ORDER BY LEAST(r.pessoa_a_id, r.pessoa_b_id),
         GREATEST(r.pessoa_a_id, r.pessoa_b_id), r.pessoa_a_id;

-- D2d — Pares sem linha inversa (o perfil agora lê apenas o lado A;
--       toda relação precisa existir nas duas direções)
SELECT r.id, r.pessoa_a_id, r.pessoa_b_id, r.tipo,
       r.relacao_a_para_b, r.relacao_b_para_a
FROM pessoas_relacionamentos r
WHERE NOT EXISTS (
    SELECT 1 FROM pessoas_relacionamentos i
    WHERE i.pessoa_a_id = r.pessoa_b_id
      AND i.pessoa_b_id = r.pessoa_a_id
)
ORDER BY r.id;

-- ─────────────────────────────────────────────────────────────────────────────
-- D3 (Item 4) — Relação Tutor/Pet: linhas reais e integridade de identidade
-- ─────────────────────────────────────────────────────────────────────────────
SELECT r.id, r.pessoa_a_id, pa.nome AS nome_a, pa.tipo AS tipo_a,
       r.pessoa_b_id, pb.nome AS nome_b, pb.tipo AS tipo_b,
       r.tipo AS tipo_relacao, r.relacao_a_para_b, r.relacao_b_para_a
FROM pessoas_relacionamentos r
JOIN pessoas pa ON pa.id = r.pessoa_a_id
JOIN pessoas pb ON pb.id = r.pessoa_b_id
WHERE r.tipo IN ('TUTOR', 'PET_DE')
   OR pa.tipo = 'pet' OR pb.tipo = 'pet'
ORDER BY r.id;

-- D3b — Pets que "viraram humano" (vítimas do bug de edição corrigido):
--       registros criados como pet cujo tipo hoje difere de 'pet'.
--       Evidência indireta: participam de relação TUTOR/PET_DE mas tipo <> 'pet'.
SELECT DISTINCT p.id, p.nome, p.tipo, p.especie, p.raca
FROM pessoas p
JOIN pessoas_relacionamentos r
  ON p.id IN (r.pessoa_a_id, r.pessoa_b_id)
WHERE r.tipo IN ('TUTOR', 'PET_DE')
  AND p.tipo <> 'pet'
  AND (
        (r.tipo = 'TUTOR'  AND r.pessoa_b_id = p.id)   -- lado esperado do pet
     OR (r.tipo = 'PET_DE' AND r.pessoa_a_id = p.id)
      );

-- ─────────────────────────────────────────────────────────────────────────────
-- D4 (Item 3) — Foto do usuário sobrescrita pela foto do pet
-- Trocar 111 pelo pessoas.id do usuário logado (Darlan) e 'Mili' se preciso.
-- ─────────────────────────────────────────────────────────────────────────────
-- D4a — Estado atual das fotos
SELECT id, nome, tipo, foto_perfil
FROM pessoas
WHERE id = 111                -- << id do usuário (Darlan)
   OR nome ILIKE '%mili%';

-- D4b — Histórico de arquivos no bucket 'fotos' do usuário
--       (objetos de perfil ficam em usuario_<id>/app_mobile/perfil_*)
--       A foto anterior do usuário provavelmente ainda existe no Storage:
SELECT name, created_at, updated_at
FROM storage.objects
WHERE bucket_id = 'fotos'
  AND name LIKE 'usuario_111/app_mobile/perfil_%'   -- << id do usuário
ORDER BY created_at DESC
LIMIT 20;

-- >>> COM o resultado de D4a/D4b em mãos, a foto correta é identificada por
-- >>> data/horário (a última 'perfil_*' ANTERIOR ao upload da foto da Mili)
-- >>> e só então será proposto o UPDATE de reparo — com evidência, sem chute.
