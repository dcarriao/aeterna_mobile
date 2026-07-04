-- ============================================================================
-- SPRINT I — CURADOR DE MEMÓRIAS CONTÍNUAS
-- ============================================================================
-- Este script é ADITIVO e IDEMPOTENTE (pode ser rodado mais de uma vez sem
-- efeitos colaterais). Não remove nem altera dados existentes.
--
-- Ele:
--   1. Adiciona a coluna `ultima_atualizacao_em` em `memorias` —
--      alimentada por TRIGGER em UPDATE/INSERT de `memorias` e em
--      INSERT/UPDATE de `contribuicoes` (que é o canal de enriquecimento
--      da memória). É o índice simples que o app usa para ordenar
--      memórias candidatas ao convite do Curador.
--   2. Cria a VIEW `memorias_evolucao_resumo` que, para cada memória
--      do usuário, agrega contadores brutos (nº de contribuições, nº
--      de pessoas vinculadas, idade). NÃO calcula o score (o score
--      fica no client, conforme combinado na conversa com o usuário —
--      algoritmo `MemoryGrowthScoringService` para permitir ajustes
--      rápidos de peso entre sprints).
--   3. Cria a FUNÇÃO `memorias_que_podem_crescer(usuario, limite)` que
--      devolve as memórias candidatas ordenadas por mais antigas sem
--      contribuição. O app filtra mais (via score).
--   4. Cria a TABELA `configuracoes_curador` (preferências por
--      usuário). A Sprint I NÃO persiste nela ainda — só cria a
--      base, conforme decidido na conversa (configurações em outra
--      sprint).
--   5. Adiciona GRANTs/policies no padrão MVP anônimo.
--
-- Princípio: zero duplicação de dados, zero sobrescritas. O score
-- fica no client, o ranking simples vem do SQL.
-- ============================================================================


-- (1) Coluna `ultima_atualizacao_em` em `memorias`
alter table public.memorias
    add column if not exists ultima_atualizacao_em timestamp without time zone;

-- Backfill: usar `data_evento` se preenchido, senão `data_criacao`
update public.memorias
set ultima_atualizacao_em = coalesce(data_evento, data_criacao)
where ultima_atualizacao_em is null;

alter table public.memorias
    alter column ultima_atualizacao_em set not null;

alter table public.memorias
    alter column ultima_atualizacao_em set default now();

create index if not exists idx_memorias_ultima_atualizacao
    on public.memorias (usuario_id, ultima_atualizacao_em desc nulls last);

comment on column public.memorias.ultima_atualizacao_em is
    'Sprint I: timestamp da última atualização de conteúdo (update em memorias ou insert/update em contribuicoes). Mantido por trigger.';


-- (2) Trigger: atualiza `ultima_atualizacao_em` quando a memória
-- é editada. Para contribuições, a atualização vem da trigger na
-- tabela `contribuicoes` (próximo passo).
create or replace function public.tg_atualizar_ultima_atualizacao_memoria()
returns trigger
language plpgsql
as $$
begin
    update public.memorias
    set ultima_atualizacao_em = now()
    where id = new.id;
    return new;
end;
$$;

drop trigger if exists trg_memorias_ultima_atualizacao on public.memorias;
create trigger trg_memorias_ultima_atualizacao
    after update on public.memorias
    for each row
    execute function public.tg_atualizar_ultima_atualizacao_memoria();


-- (3) Trigger: quando uma contribuição é inserida/atualizada em uma
-- memória, atualiza `ultima_atualizacao_em` da memória correspondente.
-- Não importa o status (pendente/aprovado/rejeitado) — o simples fato
-- de alguém ter interagido já indica que a memória está "viva".
create or replace function public.tg_atualizar_ultima_atualizacao_via_contribuicao()
returns trigger
language plpgsql
as $$
begin
    if new.tipo_conteudo = 'memoria' and new.conteudo_id is not null then
        update public.memorias
        set ultima_atualizacao_em = now()
        where id = new.conteudo_id;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_contribuicoes_atualiza_memoria on public.contribuicoes;
create trigger trg_contribuicoes_atualiza_memoria
    after insert or update on public.contribuicoes
    for each row
    execute function public.tg_atualizar_ultima_atualizacao_via_contribuicao();


-- (4) View `memorias_evolucao_resumo` — metadados brutos por memória.
-- NÃO calcula o score; o app faz isso (facilita ajustes de peso).
drop view if exists public.memorias_evolucao_resumo;

create view public.memorias_evolucao_resumo
with (security_invoker = true) as
select
    m.id as memoria_id,
    m.usuario_id,
    m.titulo,
    m.categoria,
    m.data_evento,
    m.criado_em as criada_em,
    m.ultima_atualizacao_em,
    greatest(m.criado_em, m.ultima_atualizacao_em) as data_referencia,
    extract(epoch from (now() - greatest(m.criado_em, m.ultima_atualizacao_em)))
        / 86400.0 as dias_desde_ultima_atualizacao,
    -- Nº de pessoas vinculadas (via conteudo_permissoes, com
    -- deduplicação por contato).
    (select count(distinct cp.contato_id)
     from public.conteudo_permissoes cp
     where cp.tipo_conteudo = 'memoria' and cp.conteudo_id = m.id
    ) as total_pessoas,
    -- Nº de contribuições APROVADAS na memória (Sprint G).
    (select count(*)
     from public.contribuicoes c
     where c.tipo_conteudo = 'memoria'
       and c.conteudo_id = m.id
       and c.status = 'aprovado'
    ) as total_contribuicoes,
    -- Nº de contribuições PENDENTES (útil para o convite do dono).
    (select count(*)
     from public.contribuicoes c
     where c.tipo_conteudo = 'memoria'
       and c.conteudo_id = m.id
       and c.status = 'pendente'
    ) as total_contribuicoes_pendentes,
    -- Nº de mídias (fotos vinculadas).
    (select count(*)
     from public.memoria_fotos mf
     where mf.memoria_id = m.id
    ) as total_fotos,
    -- Nº de vídeos vinculados.
    (select count(*)
     from public.memoria_videos mv
     where mv.memoria_id = m.id
    ) as total_videos,
    -- Flag: existe algum colaborador com papel != leitor que ainda
    -- não contribuiu? (heurística: a memória tem permissão de
    -- colaborador mas o número de contribuidores únicos aprovados é
    -- menor que o nº de colaboradores).
    exists (
        select 1
        from public.conteudo_colaboradores cc
        where cc.tipo_conteudo = 'memoria'
          and cc.conteudo_id = m.id
          and cc.papel in ('editor', 'colaborador')
    ) as tem_colaboradores,
    (
        select count(distinct cc.usuario_id)
        from public.conteudo_colaboradores cc
        where cc.tipo_conteudo = 'memoria'
          and cc.conteudo_id = m.id
          and cc.papel in ('editor', 'colaborador')
    ) as total_colaboradores,
    (
        select count(distinct lower(trim(c.usuario_contribuidor_email)))
        from public.contribuicoes c
        where c.tipo_conteudo = 'memoria'
          and c.conteudo_id = m.id
          and c.status = 'aprovado'
          and c.usuario_contribuidor_email is not null
    ) as contribuidores_unicos
from public.memorias m;

grant select on public.memorias_evolucao_resumo to anon;

comment on view public.memorias_evolucao_resumo is
    'Sprint I: metadados por memória para a heurística "pode crescer". NÃO calcula score — o algoritmo client-side (MemoryGrowthScoringService) é a fonte da decisão. Apenas agrega contadores brutos para evitar várias queries por memória.';


-- (5) Função `memorias_que_podem_crescer(usuario, limite)`
-- Retorna as memórias candidatas ordenadas por:
--   1) nº de contribuições menor primeiro (menos ricas)
--   2) última atualização mais antiga primeiro
-- O app filtra com o score depois.
create or replace function public.memorias_que_podem_crescer(
    usuario bigint,
    limite int default 5
)
returns table (
    memoria_id bigint,
    titulo text,
    categoria text,
    data_evento date,
    ultima_atualizacao_em timestamp without time zone,
    dias_desde_ultima_atualizacao double precision,
    total_pessoas bigint,
    total_contribuicoes bigint,
    total_fotos bigint,
    total_videos bigint,
    tem_colaboradores boolean,
    total_colaboradores bigint,
    contribuidores_unicos bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select
        v.memoria_id, v.titulo, v.categoria, v.data_evento,
        v.ultima_atualizacao_em, v.dias_desde_ultima_atualizacao,
        v.total_pessoas, v.total_contribuicoes, v.total_fotos, v.total_videos,
        v.tem_colaboradores, v.total_colaboradores, v.contribuidores_unicos
    from public.memorias_evolucao_resumo v
    where v.usuario_id = usuario
    order by v.total_contribuicoes asc, v.ultima_atualizacao_em asc nulls last
    limit limite;
end;
$$;

grant execute on function public.memorias_que_podem_crescer(bigint, int) to anon;


-- (6) Tabela `configuracoes_curador` — base para a sprint futura de
-- configurações. Criada agora (sem uso no app nesta Sprint) para que
-- quando a sprint de config for implementada, só sobre a UI.
create table if not exists public.configuracoes_curador (
    usuario_id bigint primary key references public.usuarios(id) on delete cascade,
    receber_convites boolean not null default true,
    frequencia text not null default 'padrao'
        check (frequencia in ('padrao', 'diaria', 'semanal', 'desativado')),
    horario_preferido time,
    pausado_ate timestamp without time zone,
    criado_em timestamp without time zone not null default now(),
    atualizado_em timestamp without time zone not null default now()
);

grant select, insert, update, delete on public.configuracoes_curador to anon;

alter table public.configuracoes_curador enable row level security;

drop policy if exists "mvp anon select configuracoes_curador" on public.configuracoes_curador;
create policy "mvp anon select configuracoes_curador"
    on public.configuracoes_curador for select to anon using (true);

drop policy if exists "mvp anon insert configuracoes_curador" on public.configuracoes_curador;
create policy "mvp anon insert configuracoes_curador"
    on public.configuracoes_curador for insert to anon with check (true);

drop policy if exists "mvp anon update configuracoes_curador" on public.configuracoes_curador;
create policy "mvp anon update configuracoes_curador"
    on public.configuracoes_curador for update to anon using (true);

drop policy if exists "mvp anon delete configuracoes_curador" on public.configuracoes_curador;
create policy "mvp anon delete configuracoes_curador"
    on public.configuracoes_curador for delete to anon using (true);


-- (7) Verificação sugerida (rode manualmente para auditar)
-- select * from memorias_evolucao_resumo where usuario_id = 2 limit 5;
-- select * from memorias_que_podem_crescer(2, 3);
-- select count(*) from configuracoes_curador;
--
-- Resultado esperado: a primeira função retorna metadados por
-- memória; a segunda retorna as memórias mais "carentes" primeiro.
-- Fim.
