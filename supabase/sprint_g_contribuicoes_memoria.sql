-- ============================================================================
-- SPRINT G — Enriquecimento Colaborativo de Memórias
-- ============================================================================
-- Este script é ADITIVO e IDEMPOTENTE (pode ser rodado mais de uma vez sem
-- efeitos colaterais). Não remove nem altera dados existentes.
--
-- Ele:
--   1. Adiciona a coluna `aprovacao_obrigatoria` em `memorias` (default TRUE
--      para preservar o comportamento conservador atual — quem tem memória
--      existente sem essa coluna, por default, fica com aprovação obrigatória,
--      alinhado com a regra de "dono controla").
--   2. Adiciona a coluna `audio_url` em `contribuicoes` (a arquitetura da
--      tabela já está pronta para `tipo_conteudo='memoria'` e
--      `tipo_contribuicao IN ('texto','foto','video')` — preparamos o
--      campo áudio e o tipo_contribuicao='audio' para ativação futura,
--      sem quebrar nada existente).
--   3. Substitui as constraints CHECK para aceitar 'audio' como tipo de
--      contribuição (idempotente) e 'memoria' continua aceito (já era).
--   4. Adiciona índice composto `idx_contribuicoes_memoria_aprovadas`
--      otimizando a query "todas as contribuições aprovadas de uma memória"
--      (a tela de evolução da memória é chamada com frequência).
--   5. Adiciona índice composto `idx_contribuicoes_memoria_pendentes`
--      otimizando a query de moderação do dono.
--   6. Garante GRANT + policy RLS para a coluna nova (sem interferir nas
--      policies existentes).
--
-- Rode este arquivo INTEIRO no SQL Editor do Supabase.
-- ============================================================================


-- (1) Coluna `aprovacao_obrigatoria` em `memorias`
alter table public.memorias
    add column if not exists aprovacao_obrigatoria boolean not null default true;

comment on column public.memorias.aprovacao_obrigatoria is
    'Sprint G: quando true, contribuições ficam com status=pendente até aprovação do dono. Quando false, entram aprovadas diretamente.';


-- (2) Coluna `audio_url` em `contribuicoes` (preparação — ativada quando a
-- feature de áudio for habilitada no app).
alter table public.contribuicoes
    add column if not exists audio_url text;


-- (3) CHECKs expandidos (idempotente via DROP IF EXISTS + ADD).
alter table public.contribuicoes
    drop constraint if exists ck_contribuicoes_tipo_contribuicao;

alter table public.contribuicoes
    add constraint ck_contribuicoes_tipo_contribuicao
    check (tipo_contribuicao in ('texto', 'foto', 'video', 'audio'));


-- (4) Índice otimizado para "evolução da memória" (todas as contribuições
-- de uma memória, filtrando por tipo e status, ordenadas por data).
create index if not exists idx_contribuicoes_memoria_aprovadas
    on public.contribuicoes (tipo_conteudo, conteudo_id, status, criado_em desc);


-- (5) Índice otimizado para a aba "Moderar" do dono (contribuições pendentes
-- de uma memória).
create index if not exists idx_contribuicoes_memoria_pendentes
    on public.contribuicoes (tipo_conteudo, conteudo_id, status)
    where status = 'pendente';


-- (6) Verificação: GRANT/RLS já existem no `vinculos_familiares_e_permissoes.sql`
-- (PARTE 5, linhas 287-304). Nada novo a fazer. Este script apenas
-- confirma o estado esperado — rode o SELECT abaixo para auditar:
--
--   select grantee, string_agg(privilege_type, ', ')
--   from information_schema.role_table_grants
--   where table_name = 'contribuicoes'
--     and grantee = 'anon'
--   group by grantee;
--
-- Resultado esperado: select, insert, update, delete.

-- Fim.
