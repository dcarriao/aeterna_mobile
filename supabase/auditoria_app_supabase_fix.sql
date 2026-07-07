-- ============================================================================
-- auditoria_app_supabase_fix.sql
-- Consolidado idempotente — Sprints F a R.2
-- ============================================================================
-- GeraDO a partir da auditoria dos 13 scripts em supabase/ + referências do app.
--
-- O QUE FAZ:
--   Consolida em ORDEM SEGURA todos os objetos necessários (tabelas, views,
--   funções, triggers, índices, RLS, GRANTs), pulando scripts deprecados.
--
-- SCRIPTS PROibidos (NÃO executar separadamente):
--   - mvp_anon_policies.sql          → usa policies que serão sobrescritas
--   - vinculos_familiares_e_permissoes.sql  → tabelas não referenciadas pelo app
--   - vinculos_familiares_backfill.sql      → backfill de schema deprecado
--   - sprint_p_autenticacao.sql      → policies auth.uid() quebradas (fix aqui)
--   - sprint_o_menu_secundario.sql   → policies auth.uid() quebradas (fix aqui)
--   - sprint_r1_correcoes.sql        → já incorporado aqui
--
-- PODE executar este script inteiro quantas vezes quiser (idempotente).
-- ============================================================================
-- ORDEM DE EXECUÇÃO (dentro deste script):
--   1. Pré-requisitos (extensão, schema)
--   2. Tabelas Sprint O (quem_sou_eu, cofre_itens, mensagens_futuro)
--   3. Tabela configuracoes_curador (Sprint I)
--   4. Tabelas Curador Contextual (Sprint J)
--   5. Tabela memoria_relacionamentos (Sprint K)
--   6. Tabelas Grafo Pessoas (Sprint L)
--   7. ALTER TABLE — colunas faltantes (Sprints G, I, P, R.1)
--   8. Triggers functions + triggers
--   9. Views (Sprints H, I, J, K, L)
--  10. Functions/RPCs (Sprints H, I, J, K, L, M)
--  11. Índices
--  12. RLS — habilitar em todas as tabelas, policies USING(true)
--  13. GRANTs finais
-- ============================================================================


-- ============================================================================
-- 1. PRÉ-REQUISITOS
-- ============================================================================
create extension if not exists pg_trgm;

grant usage on schema public to anon;


-- ============================================================================
-- 2. TABELAS SPRINT O — Menu Secundário
-- ============================================================================

-- 2a. mensagens_futuro
create table if not exists public.mensagens_futuro (
    id bigint generated always as identity primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    titulo text not null,
    conteudo text not null,
    data_agendamento timestamptz not null,
    entregue boolean not null default false,
    destinatario_id bigint references public.contatos(id) on delete set null,
    created_at timestamptz not null default now()
);

-- 2b. cofre_itens
create table if not exists public.cofre_itens (
    id bigint generated always as identity primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    titulo text not null,
    tipo text not null check (tipo in ('texto', 'documento')),
    conteudo text,
    url_arquivo text,
    created_at timestamptz not null default now()
);

-- 2c. quem_sou_eu
create table if not exists public.quem_sou_eu (
    id bigint generated always as identity primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    pergunta_chave text not null,
    resposta text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);


-- ============================================================================
-- 3. TABELA configuracoes_curador (Sprint I)
-- ============================================================================
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


-- ============================================================================
-- 4. TABELAS CURADOR CONTEXTUAL (Sprint J)
-- ============================================================================

-- 4a. curador_sessoes
create table if not exists public.curador_sessoes (
    id bigserial primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    titulo text,
    contexto_inicial text not null default '',
    contexto_atual text not null default '',
    status text not null default 'em_andamento'
        check (status in ('em_andamento', 'concluida', 'cancelada')),
    etapa text not null default 'conversa',
    total_turnos integer not null default 0,
    memoria_id bigint references public.memorias(id) on delete set null,
    data_evento date,
    pessoas_json jsonb not null default '[]'::jsonb,
    criado_em timestamp without time zone not null default now(),
    atualizado_em timestamp without time zone not null default now()
);

-- 4b. curador_mensagens
create table if not exists public.curador_mensagens (
    id bigserial primary key,
    sessao_id bigint not null references public.curador_sessoes(id) on delete cascade,
    role text not null check (role in ('user', 'assistant', 'system')),
    conteudo text not null,
    ordem integer not null,
    tipo text,
    criado_em timestamp without time zone not null default now()
);


-- ============================================================================
-- 5. TABELA memoria_relacionamentos (Sprint K)
-- ============================================================================
create table if not exists public.memoria_relacionamentos (
    id bigserial primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    memoria_origem_id bigint not null references public.memorias(id) on delete cascade,
    memoria_destino_id bigint not null references public.memorias(id) on delete cascade,
    score integer not null check (score between 0 and 100),
    motivos jsonb not null default '{}'::jsonb,
    status text not null default 'pendente'
        check (status in ('pendente', 'confirmado', 'ignorado')),
    criado_em timestamp without time zone not null default now(),
    atualizado_em timestamp without time zone not null default now(),
    constraint ck_memoria_relacionamentos_distintas
        check (memoria_origem_id <> memoria_destino_id)
);


-- ============================================================================
-- 6. TABELAS GRAFO PESSOAS (Sprint L)
-- ============================================================================

-- 6a. tipos_relacionamento (catálogo + seed)
create table if not exists public.tipos_relacionamento (
    id text primary key,
    rotulo_a_para_b text not null,
    rotulo_b_para_a text not null,
    categoria text not null check (categoria in
        ('familia', 'afinidade', 'conjugue', 'amizade', 'outro')),
    ativo boolean not null default true,
    criado_em timestamp without time zone not null default now()
);

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria) values
    ('CONJUGE',       'Esposo(a)',     'Esposo(a)',     'conjugue'),
    ('COMPANHEIRO',   'Companheiro',  'Companheiro',   'conjugue'),
    ('PAI',           'Pai',           'Filho(a)',      'familia'),
    ('MAE',           'Mãe',           'Filho(a)',      'familia'),
    ('FILHO',         'Filho(a)',      'Pai',           'familia'),
    ('FILHA',         'Filho(a)',      'Mãe',           'familia'),
    ('AVO',           'Avô(ó)',        'Neto(a)',       'familia'),
    ('NETO',          'Neto(a)',       'Avô(ó)',        'familia'),
    ('BISAVO',        'Bisavô(ó)',     'Bisneto(a)',    'familia'),
    ('BISNETO',       'Bisneto(a)',    'Bisavô(ó)',     'familia'),
    ('IRMAO',         'Irmão(ã)',      'Irmão(ã)',      'familia'),
    ('TIO',           'Tio(a)',        'Sobrinho(a)',   'familia'),
    ('SOBRINHO',      'Sobrinho(a)',   'Tio(a)',        'familia'),
    ('PRIMO',         'Primo(a)',      'Primo(a)',      'familia'),
    ('PADRINHO',      'Padrinho',      'Afilhado(a)',   'afinidade'),
    ('MADRINHA',      'Madrinha',      'Afilhado(a)',   'afinidade'),
    ('AFILHADO',      'Afilhado(a)',   'Padrinho',      'afinidade'),
    ('GENRO',         'Genro',         'Sogro(a)',      'familia'),
    ('NORA',          'Nora',          'Sogro(a)',      'familia'),
    ('SOGRO',         'Sogro(a)',      'Genro/Nora',    'familia'),
    ('CUNHADO',       'Cunhado(a)',    'Cunhado(a)',    'familia'),
    ('AMIGO',         'Amigo(a)',      'Amigo(a)',      'amizade'),
    ('OUTRO',         'Conhecido(a)',  'Conhecido(a)',  'outro')
on conflict (id) do update set
    rotulo_a_para_b = excluded.rotulo_a_para_b,
    rotulo_b_para_a = excluded.rotulo_b_para_a,
    categoria = excluded.categoria,
    ativo = true;

-- 6b. pessoas_relacionamentos
create table if not exists public.pessoas_relacionamentos (
    id bigserial primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    pessoa_a_id bigint not null references public.contatos(id) on delete cascade,
    pessoa_b_id bigint not null references public.contatos(id) on delete cascade,
    tipo text not null references public.tipos_relacionamento(id),
    relacao_a_para_b text not null,
    relacao_b_para_a text not null,
    confirmado boolean not null default true,
    observacoes text,
    data_inicio date,
    data_fim date,
    criado_em timestamp without time zone not null default now(),
    atualizado_em timestamp without time zone not null default now(),
    constraint ck_pessoas_relacionamentos_distintas
        check (pessoa_a_id <> pessoa_b_id)
);


-- ============================================================================
-- 7. TABELAS VÍNCULOS FAMILIARES (vinculos_familiares_e_permissoes.sql)
-- ============================================================================
-- O app usa estas três tabelas (confirmado por grep em lib/). O script
-- original foi erroneamente classificado como "deprecado" na auditoria
-- inicial; estas tabelas são OBRIGATÓRIAS.

-- 7a. convites_familiares
create table if not exists public.convites_familiares (
    id bigserial primary key,
    usuario_origem_id bigint not null references public.usuarios(id) on delete cascade,
    pessoa_id bigint references public.pessoas(id) on delete set null,
    email_destino text not null,
    usuario_destino_id bigint references public.usuarios(id) on delete set null,
    status text not null default 'pendente',
    token text,
    papel_sugerido text,
    tipo_conteudo_alvo text,
    conteudo_id_alvo bigint,
    criado_em timestamp without time zone not null default now(),
    aceito_em timestamp without time zone
);

alter table public.convites_familiares drop constraint if exists ck_convites_familiares_status;
alter table public.convites_familiares add constraint ck_convites_familiares_status
    check (status in ('pendente', 'aceito', 'recusado', 'expirado'));

alter table public.convites_familiares drop constraint if exists ck_convites_familiares_papel;
alter table public.convites_familiares add constraint ck_convites_familiares_papel
    check (papel_sugerido is null or papel_sugerido in ('editor', 'colaborador', 'leitor'));

alter table public.convites_familiares drop constraint if exists ck_convites_familiares_tipo_alvo;
alter table public.convites_familiares add constraint ck_convites_familiares_tipo_alvo
    check (tipo_conteudo_alvo is null or tipo_conteudo_alvo in ('memoria', 'memorial', 'foto', 'video'));

alter table public.convites_familiares drop constraint if exists ck_convites_familiares_origem_destino;
alter table public.convites_familiares add constraint ck_convites_familiares_origem_destino
    check (usuario_destino_id is null or usuario_destino_id <> usuario_origem_id);

-- 7b. vinculos_familiares
create table if not exists public.vinculos_familiares (
    id bigserial primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    vinculado_usuario_id bigint not null references public.usuarios(id) on delete cascade,
    origem_convite_id bigint references public.convites_familiares(id) on delete set null,
    criado_em timestamp without time zone not null default now()
);

alter table public.vinculos_familiares drop constraint if exists ck_vinculos_familiares_distintos;
alter table public.vinculos_familiares add constraint ck_vinculos_familiares_distintos
    check (usuario_id <> vinculado_usuario_id);

alter table public.vinculos_familiares drop constraint if exists uq_vinculos_familiares;
alter table public.vinculos_familiares add constraint uq_vinculos_familiares
    unique (usuario_id, vinculado_usuario_id);

-- 7c. conteudo_colaboradores
create table if not exists public.conteudo_colaboradores (
    id bigserial primary key,
    tipo_conteudo text not null,
    conteudo_id bigint not null,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    papel text not null default 'leitor',
    convite_id bigint references public.convites_familiares(id) on delete set null,
    concedido_por bigint references public.usuarios(id) on delete set null,
    criado_em timestamp without time zone not null default now()
);

alter table public.conteudo_colaboradores drop constraint if exists ck_conteudo_colaboradores_tipo;
alter table public.conteudo_colaboradores add constraint ck_conteudo_colaboradores_tipo
    check (tipo_conteudo in ('memoria', 'memorial', 'foto', 'video'));

alter table public.conteudo_colaboradores drop constraint if exists ck_conteudo_colaboradores_papel;
alter table public.conteudo_colaboradores add constraint ck_conteudo_colaboradores_papel
    check (papel in ('editor', 'colaborador', 'leitor'));

alter table public.conteudo_colaboradores drop constraint if exists uq_conteudo_colaboradores;
alter table public.conteudo_colaboradores add constraint uq_conteudo_colaboradores
    unique (tipo_conteudo, conteudo_id, usuario_id);


-- ============================================================================
-- 8. ALTER TABLE — colunas faltantes em tabelas existentes
-- ============================================================================

-- 8a. Sprint G + vinculos_familiares_e_permissoes — colunas em memorias e contribuicoes
alter table public.memorias
    add column if not exists aprovacao_obrigatoria boolean not null default true;

alter table public.contribuicoes
    add column if not exists audio_url text;

-- Colunas do schema de contribuições (originadas em vinculos_familiares_e_permissoes.sql)
alter table public.contribuicoes add column if not exists usuario_dono_id bigint;
alter table public.contribuicoes add column if not exists usuario_contribuidor_email text;
alter table public.contribuicoes add column if not exists usuario_contribuidor_nome text;
alter table public.contribuicoes add column if not exists tipo_conteudo text;
alter table public.contribuicoes add column if not exists conteudo_id bigint;
alter table public.contribuicoes add column if not exists tipo_contribuicao text;
alter table public.contribuicoes add column if not exists texto text;
alter table public.contribuicoes add column if not exists arquivo_url text;
alter table public.contribuicoes add column if not exists arquivo_nome text;
alter table public.contribuicoes add column if not exists arquivo_tipo text;
alter table public.contribuicoes add column if not exists arquivo_tamanho bigint;
alter table public.contribuicoes add column if not exists status text default 'pendente';
alter table public.contribuicoes add column if not exists criado_em timestamp without time zone default now();
alter table public.contribuicoes add column if not exists avaliado_em timestamp without time zone;
alter table public.contribuicoes add column if not exists avaliado_por bigint;
alter table public.contribuicoes add column if not exists memorial_id bigint;

-- CHECK constraints para contribuicoes
alter table public.contribuicoes drop constraint if exists ck_contribuicoes_tipo_conteudo;
alter table public.contribuicoes add constraint ck_contribuicoes_tipo_conteudo
    check (tipo_conteudo in ('memoria', 'foto', 'video', 'memorial'));

alter table public.contribuicoes drop constraint if exists ck_contribuicoes_tipo_contribuicao;
alter table public.contribuicoes add constraint ck_contribuicoes_tipo_contribuicao
    check (tipo_contribuicao in ('texto', 'foto', 'video', 'audio'));

alter table public.contribuicoes drop constraint if exists ck_contribuicoes_status;
alter table public.contribuicoes add constraint ck_contribuicoes_status
    check (status in ('pendente', 'aprovado', 'rejeitado'));

-- 8b. Sprint I — coluna ultima_atualizacao_em em memorias
alter table public.memorias
    add column if not exists ultima_atualizacao_em timestamp without time zone;

do $$ begin
    update public.memorias
    set ultima_atualizacao_em = coalesce(data_evento::timestamp, data_criacao)
    where ultima_atualizacao_em is null;
end $$;

alter table public.memorias
    alter column ultima_atualizacao_em set not null;

alter table public.memorias
    alter column ultima_atualizacao_em set default now();

-- 8c. Sprint P — coluna auth_id em usuarios
alter table public.usuarios
    add column if not exists auth_id text unique;

-- 8d. Sprint R.1 — destinatario_id em mensagens_futuro
do $$ begin
    if exists (select from pg_tables where schemaname='public' and tablename='mensagens_futuro') then
        if not exists (
            select from information_schema.columns
            where table_schema='public' and table_name='mensagens_futuro' and column_name='destinatario_id'
        ) then
            alter table public.mensagens_futuro
                add column destinatario_id bigint references public.contatos(id) on delete set null;
        end if;
    end if;
end $$;


-- ============================================================================
-- 8. TRIGGERS (funções + triggers)
-- ============================================================================

-- 8a. Sprint I — ultima_atualizacao_em em memorias
create or replace function public.tg_atualizar_ultima_atualizacao_memoria()
returns trigger language plpgsql as $$
begin
    update public.memorias set ultima_atualizacao_em = now() where id = new.id;
    return new;
end;
$$;

drop trigger if exists trg_memorias_ultima_atualizacao on public.memorias;
create trigger trg_memorias_ultima_atualizacao
    after update on public.memorias
    for each row execute function public.tg_atualizar_ultima_atualizacao_memoria();

-- 8b. Sprint I — contribuicoes → ultima_atualizacao_em
create or replace function public.tg_atualizar_ultima_atualizacao_via_contribuicao()
returns trigger language plpgsql as $$
begin
    if new.tipo_conteudo = 'memoria' and new.conteudo_id is not null then
        update public.memorias set ultima_atualizacao_em = now() where id = new.conteudo_id;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_contribuicoes_atualiza_memoria on public.contribuicoes;
create trigger trg_contribuicoes_atualiza_memoria
    after insert or update on public.contribuicoes
    for each row execute function public.tg_atualizar_ultima_atualizacao_via_contribuicao();

-- 8c. Sprint J — curador_sessoes atualizado_em
create or replace function public.tg_curador_sessoes_updated()
returns trigger language plpgsql as $$
begin
    new.atualizado_em = now();
    return new;
end;
$$;

drop trigger if exists trg_curador_sessoes_updated on public.curador_sessoes;
create trigger trg_curador_sessoes_updated
    before update on public.curador_sessoes
    for each row execute function public.tg_curador_sessoes_updated();

-- 8d. Sprint K — memoria_relacionamentos atualizado_em
create or replace function public.tg_memoria_relacionamentos_updated()
returns trigger language plpgsql as $$
begin
    new.atualizado_em = now();
    return new;
end;
$$;

drop trigger if exists trg_memoria_relacionamentos_updated on public.memoria_relacionamentos;
create trigger trg_memoria_relacionamentos_updated
    before update on public.memoria_relacionamentos
    for each row execute function public.tg_memoria_relacionamentos_updated();

-- 8e. Sprint K — invalidar relacionamentos ao editar memória
create or replace function public.tg_memoria_invalida_relacionamentos()
returns trigger language plpgsql as $$
begin
    if tg_op = 'UPDATE' then
        update public.memoria_relacionamentos
        set atualizado_em = now() - interval '1 year'
        where (memoria_origem_id = new.id or memoria_destino_id = new.id)
          and status = 'pendente';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_memorias_invalida_relacionamentos on public.memorias;
create trigger trg_memorias_invalida_relacionamentos
    after update on public.memorias
    for each row execute function public.tg_memoria_invalida_relacionamentos();

-- 8f. Sprint L — criar relacionamento legado a partir de parentesco
create or replace function public.tg_pessoa_cria_relacionamento_legado()
returns trigger language plpgsql as $$
declare
    v_outra_pessoa_id bigint;
    v_tipo text;
    v_rotulo_a_para_b text;
    v_rotulo_b_para_a text;
    p_norm text;
begin
    if new.parentesco is null or new.parentesco = '' then
        return new;
    end if;

    p_norm := lower(trim(new.parentesco));
    case p_norm
        when 'pai' then v_tipo := 'PAI';
        when 'mãe', 'mae' then v_tipo := 'MAE';
        when 'filho' then v_tipo := 'FILHO';
        when 'filha' then v_tipo := 'FILHA';
        when 'irmão', 'irmao' then v_tipo := 'IRMAO';
        when 'irmã', 'irma' then v_tipo := 'IRMAO';
        when 'avô', 'avó', 'avo' then v_tipo := 'AVO';
        when 'neto' then v_tipo := 'NETO';
        when 'neta' then v_tipo := 'NETO';
        when 'tio' then v_tipo := 'TIO';
        when 'tia' then v_tipo := 'TIO';
        when 'primo' then v_tipo := 'PRIMO';
        when 'prima' then v_tipo := 'PRIMO';
        when 'amigo' then v_tipo := 'AMIGO';
        when 'amiga' then v_tipo := 'AMIGO';
        else v_tipo := null;
    end case;

    if v_tipo is null then
        return new;
    end if;

    select id into v_outra_pessoa_id
    from public.contatos c
    where c.usuario_id = new.usuario_id
      and c.id <> new.id
    limit 1;

    if v_outra_pessoa_id is null then
        return new;
    end if;

    if new.id < v_outra_pessoa_id then
        v_rotulo_a_para_b := (select rotulo_a_para_b from public.tipos_relacionamento where id = v_tipo);
        v_rotulo_b_para_a := (select rotulo_b_para_a from public.tipos_relacionamento where id = v_tipo);
    else
        v_rotulo_a_para_b := (select rotulo_b_para_a from public.tipos_relacionamento where id = v_tipo);
        v_rotulo_b_para_a := (select rotulo_a_para_b from public.tipos_relacionamento where id = v_tipo);
    end if;

    insert into public.pessoas_relacionamentos (
        usuario_id, pessoa_a_id, pessoa_b_id, tipo,
        relacao_a_para_b, relacao_b_para_a, confirmado
    ) values (
        new.usuario_id, new.id, v_outra_pessoa_id, v_tipo,
        v_rotulo_a_para_b, v_rotulo_b_para_a, true
    ) on conflict do nothing;

    return new;
end;
$$;

drop trigger if exists trg_pessoa_cria_relacionamento_legado on public.contatos;
create trigger trg_pessoa_cria_relacionamento_legado
    after insert on public.contatos
    for each row execute function public.tg_pessoa_cria_relacionamento_legado();

-- 8g. Sprint P — trigger sincronizar_auth_id
create or replace function public.sincronizar_auth_id()
returns trigger language plpgsql security definer as $$
begin
    update public.usuarios
    set auth_id = new.id::text
    where email = new.email and auth_id is null;
    return new;
end;
$$;

drop trigger if exists trg_sincronizar_auth_id on auth.users;
create trigger trg_sincronizar_auth_id
    after insert on auth.users
    for each row execute function public.sincronizar_auth_id();


-- ============================================================================
-- 9. VIEWS
-- ============================================================================

-- 9a. Sprint H — pessoa_linha_tempo
drop view if exists public.pessoa_linha_tempo;
create view public.pessoa_linha_tempo
with (security_invoker = true) as
with memorias_da_pessoa as (
    select distinct cp.pessoa_id, cp.conteudo_id as memoria_id
    from public.conteudo_permissoes cp
    where cp.tipo_conteudo = 'memoria'
),
mem_eventos as (
    select
        mdp.pessoa_id, 'memoria'::text as tipo, m.id as conteudo_id,
        m.titulo as titulo,
        coalesce(nullif(m.data_evento::text, ''), m.data_criacao::text) as data_ordem,
        m.id as memoria_origem_id, null::int as contribuicao_id, null::text as autor_contribuicao
    from memorias_da_pessoa mdp join public.memorias m on m.id = mdp.memoria_id
),
foto_eventos as (
    select
        mdp.pessoa_id, 'foto'::text as tipo, mf.foto_id as conteudo_id,
        coalesce(f.titulo, 'Foto') as titulo, f.data_criacao::text as data_ordem,
        mf.memoria_id as memoria_origem_id, null::int as contribuicao_id, null::text as autor_contribuicao
    from memorias_da_pessoa mdp
    join public.memoria_fotos mf on mf.memoria_id = mdp.memoria_id
    left join public.fotos f on f.id = mf.foto_id
),
contrib_eventos as (
    select
        mdp.pessoa_id, 'contribuicao'::text as tipo, c.id as conteudo_id,
        coalesce(c.texto, c.arquivo_url, 'Contribuição') as titulo, c.criado_em::text as data_ordem,
        c.conteudo_id as memoria_origem_id, c.id as contribuicao_id,
        c.usuario_contribuidor_nome as autor_contribuicao
    from memorias_da_pessoa mdp
    join public.contribuicoes c
      on c.tipo_conteudo = 'memoria' and c.conteudo_id = mdp.memoria_id and c.status = 'aprovado'
)
select * from mem_eventos
union all
select * from foto_eventos
union all
select * from contrib_eventos;

-- 9b. Sprint I — memorias_evolucao_resumo
drop view if exists public.memorias_evolucao_resumo;
create view public.memorias_evolucao_resumo
with (security_invoker = true) as
select
    m.id as memoria_id, m.usuario_id, m.titulo, m.categoria,
    m.data_evento, m.data_criacao as criada_em, m.ultima_atualizacao_em,
    greatest(m.data_criacao, m.ultima_atualizacao_em) as data_referencia,
    extract(epoch from (now() - greatest(m.data_criacao, m.ultima_atualizacao_em))) / 86400.0 as dias_desde_ultima_atualizacao,
    (select count(distinct cp.pessoa_id) from public.conteudo_permissoes cp
     where cp.tipo_conteudo = 'memoria' and cp.conteudo_id = m.id) as total_pessoas,
    (select count(*) from public.contribuicoes c
     where c.tipo_conteudo = 'memoria' and c.conteudo_id = m.id and c.status = 'aprovado') as total_contribuicoes,
    (select count(*) from public.contribuicoes c
     where c.tipo_conteudo = 'memoria' and c.conteudo_id = m.id and c.status = 'pendente') as total_contribuicoes_pendentes,
    (select count(*) from public.memoria_fotos mf where mf.memoria_id = m.id) as total_fotos,
    (select count(*) from public.memoria_videos mv where mv.memoria_id = m.id) as total_videos,
    exists (select 1 from public.conteudo_colaboradores cc
            where cc.tipo_conteudo = 'memoria' and cc.conteudo_id = m.id
              and cc.papel in ('editor', 'colaborador')) as tem_colaboradores,
    (select count(distinct cc.usuario_id) from public.conteudo_colaboradores cc
     where cc.tipo_conteudo = 'memoria' and cc.conteudo_id = m.id
       and cc.papel in ('editor', 'colaborador')) as total_colaboradores,
    (select count(distinct lower(trim(c.usuario_contribuidor_email)))
     from public.contribuicoes c
     where c.tipo_conteudo = 'memoria' and c.conteudo_id = m.id
       and c.status = 'aprovado' and c.usuario_contribuidor_email is not null) as contribuidores_unicos
from public.memorias m;

-- 9c. Sprint J — curador_sessao_ativa_por_usuario
drop view if exists public.curador_sessao_ativa_por_usuario;
create view public.curador_sessao_ativa_por_usuario
with (security_invoker = true) as
select s.id as sessao_id, s.usuario_id, s.titulo, s.contexto_inicial,
       s.contexto_atual, s.total_turnos, s.criado_em, s.atualizado_em,
       s.data_evento, s.pessoas_json, s.memoria_id
from public.curador_sessoes s
where s.status = 'em_andamento';

-- 9d. Sprint K — memorias_resumo_leve
drop view if exists public.memorias_resumo_leve;
create view public.memorias_resumo_leve
with (security_invoker = true) as
select
    m.id, m.usuario_id, m.titulo, m.categoria,
    m.data_evento, m.data_criacao, m.ultima_atualizacao_em, m.aprovacao_obrigatoria,
    length(coalesce(m.conteudo, '')) as tamanho_conteudo,
    exists (select 1 from public.memoria_relacionamentos r
            where (r.memoria_origem_id = m.id or r.memoria_destino_id = m.id)
              and r.status = 'confirmado') as tem_relacionamentos_confirmados,
    (select count(*) from public.memoria_relacionamentos r
     where (r.memoria_origem_id = m.id or r.memoria_destino_id = m.id)
       and r.status = 'pendente') as total_relacionamentos_pendentes
from public.memorias m;

-- 9e. Sprint L — grafo_pessoas_relacionamentos
drop view if exists public.grafo_pessoas_relacionamentos;
create view public.grafo_pessoas_relacionamentos
with (security_invoker = true) as
select
    r.id as relacionamento_id, r.usuario_id,
    least(r.pessoa_a_id, r.pessoa_b_id) as pessoa_mais_antiga_id,
    greatest(r.pessoa_a_id, r.pessoa_b_id) as pessoa_mais_nova_id,
    r.tipo,
    case
        when r.pessoa_a_id = least(r.pessoa_a_id, r.pessoa_b_id) then r.relacao_a_para_b
        else r.relacao_b_para_a
    end as rotulo_a,
    case
        when r.pessoa_b_id = greatest(r.pessoa_a_id, r.pessoa_b_id) then r.relacao_b_para_a
        else r.relacao_a_para_b
    end as rotulo_b,
    (select nome from public.contatos where id =
        case when r.pessoa_a_id = least(r.pessoa_a_id, r.pessoa_b_id) then r.pessoa_a_id else r.pessoa_b_id end
    ) as nome_a,
    (select nome from public.contatos where id =
        case when r.pessoa_b_id = greatest(r.pessoa_a_id, r.pessoa_b_id) then r.pessoa_b_id else r.pessoa_a_id end
    ) as nome_b,
    r.confirmado, r.observacoes, r.data_inicio, r.data_fim, r.criado_em, r.atualizado_em
from public.pessoas_relacionamentos r;


-- ============================================================================
-- 10. FUNCTIONS / RPCs
-- ============================================================================

-- 10a. Sprint H — pessoa_estatisticas
create or replace function public.pessoa_estatisticas(pessoa_id bigint)
returns table (total_memorias bigint, total_fotos bigint, total_videos bigint,
               total_contribuicoes bigint, primeira_data date, ultima_data date)
language plpgsql security definer set search_path = public as $$
begin
    return query
    with memorias_ids as (
        select cp.conteudo_id as id from public.conteudo_permissoes cp
        where cp.tipo_conteudo = 'memoria' and cp.pessoa_id = pessoa_id
    ),
    contribs_ids as (
        select c.id from public.contribuicoes c
        join memorias_ids mi on mi.id = c.conteudo_id
        where c.tipo_conteudo = 'memoria' and c.status = 'aprovado'
    )
    select
        (select count(*) from memorias_ids)::bigint,
        (select count(distinct mf.foto_id) from public.memoria_fotos mf join memorias_ids mi on mi.id = mf.memoria_id)::bigint,
        (select count(distinct mv.video_id) from public.memoria_videos mv join memorias_ids mi on mi.id = mv.memoria_id)::bigint,
        (select count(*) from contribs_ids)::bigint,
        (select min(m.data_evento) from public.memorias m join memorias_ids mi on mi.id = m.id),
        (select max(coalesce(m.data_evento, m.data_criacao::date)) from public.memorias m join memorias_ids mi on mi.id = m.id);
end;
$$;

-- 10b. Sprint H — pessoas_recentes
create or replace function public.pessoas_recentes(usuario bigint, limite int default 8)
returns table (id bigint, nome text, sobrenome text, parentesco text, email text,
               foto_perfil text, ultima_interacao timestamp, total_eventos bigint)
language plpgsql security definer set search_path = public as $$
begin
    return query
    with ultimas as (
        select c.id as pessoa_id,
            greatest(
                coalesce((select max(coalesce(m.data_evento::timestamp, m.data_criacao))
                          from public.conteudo_permissoes cp join public.memorias m on m.id = cp.conteudo_id
                          where cp.tipo_conteudo = 'memoria' and cp.pessoa_id = c.id), '1970-01-01'::timestamp),
                coalesce((select max(c2.criado_em)
                          from public.contribuicoes c2
                          where c2.tipo_conteudo = 'memoria' and c2.conteudo_id in (
                              select cp.conteudo_id from public.conteudo_permissoes cp
                              where cp.tipo_conteudo = 'memoria' and cp.pessoa_id = c.id
                          ) and c2.status = 'aprovado'), '1970-01-01'::timestamp)
            ) as ultima
        from public.contatos c where c.usuario_id = usuario
    )
    select c.id, c.nome, c.sobrenome, c.parentesco, c.email, c.foto_perfil,
           u.ultima,
           (select count(*) from public.pessoa_linha_tempo plt where plt.pessoa_id = c.id)::bigint
    from ultimas u join public.contatos c on c.id = u.pessoa_id
    order by u.ultima desc nulls last limit limite;
end;
$$;

-- 10c. Sprint H — pessoas_sugeridas
create or replace function public.pessoas_sugeridas(usuario bigint, limite int default 5)
returns table (nome_sugerido text, ocorrencias bigint)
language plpgsql security definer set search_path = public as $$
begin
    return query
    with memorias_texto as (
        select m.conteudo as txt from public.memorias m
        where m.usuario_id = usuario and m.conteudo is not null
    ),
    palavras as (
        select distinct lower(word) as nome
        from memorias_texto,
        lateral regexp_matches(txt, '\y([A-ZÀ-Ú][a-zà-ú]{2,})\y', 'g') as word
    ),
    frequencia as (
        select p.nome, count(distinct m.id) as ocorrencias
        from palavras p
        join lateral (select m.id from public.memorias m
                      where m.usuario_id = usuario and m.conteudo ilike '%' || p.nome || '%') m on true
        group by p.nome
    ),
    ja_cadastrados as (
        select lower(c.nome) as nome from public.contatos c where c.usuario_id = usuario
    )
    select f.nome, f.ocorrencias
    from frequencia f
    where f.ocorrencias >= 2
      and not exists (select 1 from ja_cadastrados j where j.nome = f.nome)
    order by f.ocorrencias desc limit limite;
end;
$$;

-- 10d. Sprint H — memorial_da_pessoa
create or replace function public.memorial_da_pessoa(pessoa_id bigint)
returns table (memorial_id bigint, nome text)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select m.id, m.nome
    from public.contatos c join public.memoriais m on m.id = c.memorial_id
    where c.id = pessoa_id limit 1;
end;
$$;

-- 10e. Sprint I — memorias_que_podem_crescer
create or replace function public.memorias_que_podem_crescer(usuario bigint, limite int default 5)
returns table (memoria_id bigint, titulo text, categoria text, data_evento date,
               ultima_atualizacao_em timestamp without time zone,
               dias_desde_ultima_atualizacao double precision,
               total_pessoas bigint, total_contribuicoes bigint, total_fotos bigint,
               total_videos bigint, tem_colaboradores boolean,
               total_colaboradores bigint, contribuidores_unicos bigint)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select v.memoria_id, v.titulo, v.categoria, v.data_evento,
           v.ultima_atualizacao_em, v.dias_desde_ultima_atualizacao,
           v.total_pessoas, v.total_contribuicoes, v.total_fotos, v.total_videos,
           v.tem_colaboradores, v.total_colaboradores, v.contribuidores_unicos
    from public.memorias_evolucao_resumo v
    where v.usuario_id = usuario
    order by v.total_contribuicoes asc, v.ultima_atualizacao_em asc nulls last
    limit limite;
end;
$$;

-- 10f. Sprint J — curador_salvar_mensagem
create or replace function public.curador_salvar_mensagem(
    p_sessao_id bigint, p_role text, p_conteudo text, p_tipo text default null
)
returns bigint language plpgsql security definer set search_path = public as $$
declare
    v_ordem integer;
    v_id bigint;
begin
    select coalesce(max(ordem), 0) + 1 into v_ordem
    from public.curador_mensagens where sessao_id = p_sessao_id;

    insert into public.curador_mensagens (sessao_id, role, conteudo, ordem, tipo)
    values (p_sessao_id, p_role, p_conteudo, v_ordem, p_tipo)
    returning id into v_id;

    if p_role = 'user' then
        update public.curador_sessoes
        set contexto_atual = p_conteudo, total_turnos = total_turnos + 1
        where id = p_sessao_id;
    end if;

    return v_id;
end;
$$;

-- 10g. Sprint J — curador_finalizar_sessao
create or replace function public.curador_finalizar_sessao(
    p_sessao_id bigint, p_contexto_atual text, p_status text default 'concluida'
)
returns void language plpgsql security definer set search_path = public as $$
begin
    update public.curador_sessoes
    set status = p_status, contexto_atual = p_contexto_atual
    where id = p_sessao_id;
end;
$$;

-- 10h. Sprint J — curador_cancelar_sessao
create or replace function public.curador_cancelar_sessao(p_sessao_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
    update public.curador_sessoes set status = 'cancelada' where id = p_sessao_id;
end;
$$;

-- 10i. Sprint J — curador_listar_mensagens
create or replace function public.curador_listar_mensagens(p_sessao_id bigint)
returns table (id bigint, sessao_id bigint, role text, conteudo text,
               ordem integer, tipo text, criado_em timestamp without time zone)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select m.id, m.sessao_id, m.role, m.conteudo, m.ordem, m.tipo, m.criado_em
    from public.curador_mensagens m
    where m.sessao_id = p_sessao_id
    order by m.ordem;
end;
$$;

-- 10j. Sprint K — buscar_candidatas_relacionamento
create or replace function public.buscar_candidatas_relacionamento(
    p_memoria_id bigint, p_limite int default 30
)
returns table (id bigint, titulo text, categoria text, data_evento date,
               criada_em timestamp without time zone, pessoas_em_comum integer,
               dias_diferenca_evento integer, mesmo_titulo boolean)
language plpgsql security definer set search_path = public as $$
declare
    v_usuario_id bigint;
    v_titulo_norm text;
    v_data_evento date;
begin
    select m.usuario_id, lower(trim(m.titulo)), m.data_evento
      into v_usuario_id, v_titulo_norm, v_data_evento
      from public.memorias m where m.id = p_memoria_id;

    if v_usuario_id is null then return; end if;

    return query
    select m.id, m.titulo, m.categoria, m.data_evento, m.data_criacao,
           coalesce((select count(distinct cp.pessoa_id)::int
                      from public.conteudo_permissoes cp
                      where cp.tipo_conteudo = 'memoria' and cp.conteudo_id = m.id
                        and cp.pessoa_id in (
                            select cp2.pessoa_id from public.conteudo_permissoes cp2
                            where cp2.tipo_conteudo = 'memoria' and cp2.conteudo_id = p_memoria_id
                        )), 0) as pessoas_em_comum,
           case when v_data_evento is null or m.data_evento is null then null
                else abs((m.data_evento - v_data_evento)::int)
           end as dias_diferenca_evento,
           (v_titulo_norm is not null and v_titulo_norm <> ''
            and lower(trim(m.titulo)) = v_titulo_norm) as mesmo_titulo
    from public.memorias m
    where m.usuario_id = v_usuario_id and m.id <> p_memoria_id
    order by pessoas_em_comum desc,
             case when dias_diferenca_evento is null then 1 else 0 end,
             dias_diferenca_evento asc nulls last,
             m.data_criacao desc
    limit p_limite;
end;
$$;

-- 10k. Sprint L — listar_relacionamentos_pessoa
create or replace function public.listar_relacionamentos_pessoa(p_pessoa_id bigint)
returns table (relacionamento_id bigint, outra_pessoa_id bigint, outra_pessoa_nome text,
               tipo text, rotulo_da_outra_para_mim text, rotulo_de_mim_para_outra text,
               confirmado boolean, observacoes text, data_inicio date, data_fim date,
               criado_em timestamp without time zone)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select r.id as relacionamento_id,
           case when r.pessoa_a_id = p_pessoa_id then r.pessoa_b_id else r.pessoa_a_id end as outra_pessoa_id,
           (select nome from public.contatos where id =
               case when r.pessoa_a_id = p_pessoa_id then r.pessoa_b_id else r.pessoa_a_id end) as outra_pessoa_nome,
           r.tipo,
           case when r.pessoa_a_id = p_pessoa_id then r.relacao_b_para_a else r.relacao_a_para_b end as rotulo_da_outra_para_mim,
           case when r.pessoa_a_id = p_pessoa_id then r.relacao_a_para_b else r.relacao_b_para_a end as rotulo_de_mim_para_outra,
           r.confirmado, r.observacoes, r.data_inicio, r.data_fim, r.criado_em
    from public.pessoas_relacionamentos r
    where r.usuario_id = (select usuario_id from public.contatos where id = p_pessoa_id)
      and (r.pessoa_a_id = p_pessoa_id or r.pessoa_b_id = p_pessoa_id)
    order by r.tipo, r.criado_em desc;
end;
$$;

-- 10l. Sprint L — listar_pessoas_com_mesma_relacao
create or replace function public.listar_pessoas_com_mesma_relacao(
    p_usuario_id bigint, p_pessoa_referencia_id bigint, p_tipo text
)
returns table (pessoa_id bigint, nome text, tipo text, relacao_a_para_b text, relacao_b_para_a text)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select
        case when r.pessoa_a_id = p_pessoa_referencia_id then r.pessoa_b_id else r.pessoa_a_id end as pessoa_id,
        (select nome from public.contatos where id =
            case when r.pessoa_a_id = p_pessoa_referencia_id then r.pessoa_b_id else r.pessoa_a_id end) as nome,
        r.tipo, r.relacao_a_para_b, r.relacao_b_para_a
    from public.pessoas_relacionamentos r
    where r.usuario_id = p_usuario_id and r.tipo = p_tipo
      and (r.pessoa_a_id = p_pessoa_referencia_id or r.pessoa_b_id = p_pessoa_referencia_id);
end;
$$;

-- 10m. Sprint M — memorias_do_dia
create or replace function public.memorias_do_dia(p_usuario_id bigint, p_limite int default 5)
returns table (id bigint, titulo text, foto_principal text, total_pessoas bigint,
               total_contribuicoes bigint, total_midias bigint,
               possui_relacionamentos boolean, anos_decorridos integer, data_referencia date)
language plpgsql security definer set search_path = public as $$
declare
    v_hoje date := current_date;
    v_dia integer := extract(day from v_hoje);
    v_mes integer := extract(month from v_hoje);
    v_ano_corrente integer := extract(year from v_hoje);
    v_limite integer := greatest(p_limite, 1);
begin
    return query
    with memorias_relevantes as (
        select m.id, m.titulo, m.data_evento as data_ref,
            coalesce(
                (select caminho_arquivo from public.fotos f
                 join public.memoria_fotos mf on mf.foto_id = f.id
                 where mf.memoria_id = m.id order by f.id asc limit 1),
                (select caminho_arquivo from public.videos v
                 join public.memoria_videos mv on mv.video_id = v.id
                 where mv.memoria_id = m.id order by v.id asc limit 1)
            ) as foto_principal,
            (select count(distinct cp.pessoa_id) from public.conteudo_permissoes cp
             where cp.tipo_conteudo = 'memoria' and cp.conteudo_id = m.id) as total_pessoas,
            (select count(*) from public.contribuicoes c
             where c.tipo_conteudo = 'memoria' and c.conteudo_id = m.id and c.status = 'aprovado') as total_contribuicoes,
            ((select count(*) from public.memoria_fotos mf where mf.memoria_id = m.id)
             + (select count(*) from public.memoria_videos mv where mv.memoria_id = m.id)) as total_midias,
            exists (select 1 from public.memoria_relacionamentos r
                    where (r.memoria_origem_id = m.id or r.memoria_destino_id = m.id)
                      and r.status = 'confirmado') as possui_relacionamentos,
            (v_ano_corrente - extract(year from m.data_evento)::int) as anos_decorridos,
            'data_evento'::text as origem
        from public.memorias m
        where m.usuario_id = p_usuario_id and m.data_evento is not null
          and extract(day from m.data_evento)::int = v_dia
          and extract(month from m.data_evento)::int = v_mes
          and extract(year from m.data_evento)::int <> v_ano_corrente

        union all

        select m.id, m.titulo, m.data_criacao::date as data_ref,
            coalesce(
                (select caminho_arquivo from public.fotos f
                 join public.memoria_fotos mf on mf.foto_id = f.id
                 where mf.memoria_id = m.id order by f.id asc limit 1),
                (select caminho_arquivo from public.videos v
                 join public.memoria_videos mv on mv.video_id = v.id
                 where mv.memoria_id = m.id order by v.id asc limit 1)
            ) as foto_principal,
            (select count(distinct cp.pessoa_id) from public.conteudo_permissoes cp
             where cp.tipo_conteudo = 'memoria' and cp.conteudo_id = m.id) as total_pessoas,
            (select count(*) from public.contribuicoes c
             where c.tipo_conteudo = 'memoria' and c.conteudo_id = m.id and c.status = 'aprovado') as total_contribuicoes,
            ((select count(*) from public.memoria_fotos mf where mf.memoria_id = m.id)
             + (select count(*) from public.memoria_videos mv where mv.memoria_id = m.id)) as total_midias,
            exists (select 1 from public.memoria_relacionamentos r
                    where (r.memoria_origem_id = m.id or r.memoria_destino_id = m.id)
                      and r.status = 'confirmado') as possui_relacionamentos,
            (v_ano_corrente - extract(year from m.data_criacao)::int) as anos_decorridos,
            'data_criacao'::text as origem
        from public.memorias m
        where m.usuario_id = p_usuario_id and m.data_evento is null
          and extract(day from m.data_criacao)::int = v_dia
          and extract(month from m.data_criacao)::int = v_mes
          and m.data_criacao < (now() - interval '30 days')
    )
    select mr.id, mr.titulo, mr.foto_principal, mr.total_pessoas,
           mr.total_contribuicoes, mr.total_midias,
           mr.possui_relacionamentos, mr.anos_decorridos, mr.data_ref
    from memorias_relevantes mr
    order by mr.anos_decorridos desc nulls last, mr.total_pessoas desc nulls last,
             mr.total_contribuicoes desc nulls last,
             case when mr.possui_relacionamentos then 0 else 1 end,
             mr.total_midias desc nulls last, mr.data_ref desc nulls last
    limit v_limite;
end;
$$;


-- ============================================================================
-- 11. ÍNDICES
-- ============================================================================

-- Sprint O
create index if not exists idx_mensagens_futuro_usuario on public.mensagens_futuro(usuario_id);
create index if not exists idx_mensagens_futuro_agendamento on public.mensagens_futuro(data_agendamento);
create index if not exists idx_mensagens_futuro_destinatario on public.mensagens_futuro(destinatario_id);
create index if not exists idx_cofre_itens_usuario on public.cofre_itens(usuario_id);
create index if not exists idx_quem_sou_eu_usuario on public.quem_sou_eu(usuario_id);

-- Sprint P
create index if not exists idx_usuarios_auth_id on public.usuarios(auth_id);

-- Sprint H
create index if not exists idx_conteudo_permissoes_tipo_pessoa on public.conteudo_permissoes (tipo_conteudo, pessoa_id);
create index if not exists idx_memorias_data_evento_desc on public.memorias (data_evento desc nulls last);
create index if not exists idx_contribuicoes_tipo_conteudo_id_status on public.contribuicoes (tipo_conteudo, conteudo_id, status) where tipo_conteudo = 'memoria' and status = 'aprovado';
create index if not exists idx_memoria_fotos_memoria on public.memoria_fotos (memoria_id);
create index if not exists idx_memoria_videos_memoria on public.memoria_videos (memoria_id);

-- Sprint I
create index if not exists idx_memorias_ultima_atualizacao on public.memorias (usuario_id, ultima_atualizacao_em desc nulls last);

-- Sprint J
create unique index if not exists uq_curador_sessoes_em_andamento_por_usuario on public.curador_sessoes (usuario_id) where status = 'em_andamento';
create index if not exists idx_curador_sessoes_status on public.curador_sessoes (usuario_id, status, atualizado_em desc);
create unique index if not exists uq_curador_mensagens_sessao_ordem on public.curador_mensagens (sessao_id, ordem);
create index if not exists idx_curador_mensagens_sessao on public.curador_mensagens (sessao_id, ordem);

-- Sprint K
create unique index if not exists uq_memoria_relacionamentos_par on public.memoria_relacionamentos (memoria_origem_id, memoria_destino_id);
create index if not exists idx_memoria_relacionamentos_origem on public.memoria_relacionamentos (memoria_origem_id, status, score desc);
create index if not exists idx_memoria_relacionamentos_destino on public.memoria_relacionamentos (memoria_destino_id, status);
create index if not exists idx_memoria_relacionamentos_usuario_pendentes on public.memoria_relacionamentos (usuario_id, status, atualizado_em desc) where status = 'pendente';
create index if not exists idx_memorias_titulo_trgm on public.memorias using gin (lower(titulo) gin_trgm_ops);

-- Sprint L
create unique index if not exists uq_pessoas_relacionamentos_par_tipo on public.pessoas_relacionamentos (usuario_id, pessoa_a_id, pessoa_b_id, tipo);
create unique index if not exists uq_pessoas_relacionamentos_ordenado on public.pessoas_relacionamentos (usuario_id, least(pessoa_a_id, pessoa_b_id), greatest(pessoa_a_id, pessoa_b_id), tipo);
create index if not exists idx_pessoas_relacionamentos_a on public.pessoas_relacionamentos (pessoa_a_id);
create index if not exists idx_pessoas_relacionamentos_b on public.pessoas_relacionamentos (pessoa_b_id);
create index if not exists idx_pessoas_relacionamentos_usuario_tipo on public.pessoas_relacionamentos (usuario_id, tipo);

-- Sprint M
create index if not exists idx_memorias_data_evento_dia_mes on public.memorias (cast(extract(day from data_evento) as integer), cast(extract(month from data_evento) as integer)) where data_evento is not null;
create index if not exists idx_memorias_criada_em_dia_mes on public.memorias (cast(extract(day from data_criacao) as integer), cast(extract(month from data_criacao) as integer)) where data_evento is null;
create index if not exists idx_memorias_do_dia_usuario on public.memorias (usuario_id, data_evento, ultima_atualizacao_em) where data_evento is not null;

-- Vinculos familiares
create unique index if not exists uq_convites_familiares_pendente on public.convites_familiares (usuario_origem_id, lower(email_destino)) where status = 'pendente';
create index if not exists idx_convites_familiares_email on public.convites_familiares (lower(email_destino));
create index if not exists idx_convites_familiares_destino on public.convites_familiares (usuario_destino_id);
create index if not exists idx_convites_familiares_origem on public.convites_familiares (usuario_origem_id);
create unique index if not exists uq_convites_familiares_token on public.convites_familiares (token) where token is not null;
create index if not exists idx_vinculos_familiares_usuario on public.vinculos_familiares (usuario_id);
create index if not exists idx_conteudo_colaboradores_usuario on public.conteudo_colaboradores (usuario_id);
create index if not exists idx_conteudo_colaboradores_conteudo on public.conteudo_colaboradores (tipo_conteudo, conteudo_id);

-- Sprint G
create index if not exists idx_contribuicoes_memoria_aprovadas on public.contribuicoes (tipo_conteudo, conteudo_id, status, criado_em desc);
create index if not exists idx_contribuicoes_memoria_pendentes on public.contribuicoes (tipo_conteudo, conteudo_id, status) where status = 'pendente';
create index if not exists idx_contribuicoes_memorial on public.contribuicoes (memorial_id);
create index if not exists idx_contribuicoes_dono on public.contribuicoes (usuario_dono_id);
create index if not exists idx_contribuicoes_status on public.contribuicoes (status);


-- ============================================================================
-- 12. RLS — habilitar em todas as tabelas + policies USING(true)
-- ============================================================================
-- O app usa auth custom SHA-256 + salt (Sprint P), NÃO Supabase Auth.
-- auth.uid() retorna null, bloqueando queries que usam auth.uid() nas policies.
-- Solução consistente: todas as policies usam USING(true) / WITH CHECK(true).
-- A filtragem por usuario_id é feita exclusivamente no cliente Dart
-- via .eq('usuario_id', ...).

do $$ begin

-- Tabelas core (MVP)
alter table if exists public.memorias enable row level security;
alter table if exists public.fotos enable row level security;
alter table if exists public.memoria_fotos enable row level security;
alter table if exists public.contatos enable row level security;
alter table if exists public.usuarios enable row level security;
alter table if exists public.conteudo_permissoes enable row level security;
alter table if exists public.contribuicoes enable row level security;
alter table if exists public.memoriais enable row level security;

-- Sprint O
alter table if exists public.mensagens_futuro enable row level security;
alter table if exists public.cofre_itens enable row level security;
alter table if exists public.quem_sou_eu enable row level security;

-- Sprint I
alter table if exists public.configuracoes_curador enable row level security;

-- Sprint J
alter table if exists public.curador_sessoes enable row level security;
alter table if exists public.curador_mensagens enable row level security;

-- Sprint K
alter table if exists public.memoria_relacionamentos enable row level security;

-- Sprint L
alter table if exists public.pessoas_relacionamentos enable row level security;

-- Vinculos familiares
alter table if exists public.convites_familiares enable row level security;
alter table if exists public.vinculos_familiares enable row level security;
alter table if exists public.conteudo_colaboradores enable row level security;

end $$;

-- ========================================================================
-- POLICIES — memorias
-- ========================================================================
drop policy if exists "mvp anon select memorias" on public.memorias;
create policy "mvp anon select memorias" on public.memorias for select to anon using (true);

drop policy if exists "mvp anon insert memorias" on public.memorias;
create policy "mvp anon insert memorias" on public.memorias for insert to anon with check (origem = 'app_mobile');

drop policy if exists "mvp anon update memorias" on public.memorias;
create policy "mvp anon update memorias" on public.memorias for update to anon using (true);

drop policy if exists "mvp anon delete memorias" on public.memorias;
create policy "mvp anon delete memorias" on public.memorias for delete to anon using (origem = 'app_mobile');

-- ========================================================================
-- POLICIES — fotos
-- ========================================================================
drop policy if exists "mvp anon select fotos" on public.fotos;
create policy "mvp anon select fotos" on public.fotos for select to anon using (true);

drop policy if exists "mvp anon insert fotos" on public.fotos;
create policy "mvp anon insert fotos" on public.fotos for insert to anon with check (true);

drop policy if exists "mvp anon update fotos" on public.fotos;
create policy "mvp anon update fotos" on public.fotos for update to anon using (true);

drop policy if exists "mvp anon delete fotos" on public.fotos;
create policy "mvp anon delete fotos" on public.fotos for delete to anon using (true);

-- ========================================================================
-- POLICIES — memoria_fotos
-- ========================================================================
drop policy if exists "mvp anon select memoria fotos" on public.memoria_fotos;
create policy "mvp anon select memoria fotos" on public.memoria_fotos for select to anon using (true);

drop policy if exists "mvp anon insert memoria fotos" on public.memoria_fotos;
create policy "mvp anon insert memoria fotos" on public.memoria_fotos for insert to anon with check (true);

drop policy if exists "mvp anon update memoria fotos" on public.memoria_fotos;
create policy "mvp anon update memoria fotos" on public.memoria_fotos for update to anon using (true);

drop policy if exists "mvp anon delete memoria fotos" on public.memoria_fotos;
create policy "mvp anon delete memoria fotos" on public.memoria_fotos for delete to anon using (true);

-- ========================================================================
-- POLICIES — contatos
-- ========================================================================
drop policy if exists "mvp anon select contatos" on public.contatos;
create policy "mvp anon select contatos" on public.contatos for select to anon using (true);

drop policy if exists "mvp anon insert contatos" on public.contatos;
create policy "mvp anon insert contatos" on public.contatos for insert to anon with check (true);

drop policy if exists "mvp anon update contatos" on public.contatos;
create policy "mvp anon update contatos" on public.contatos for update to anon using (true);

drop policy if exists "mvp anon delete contatos" on public.contatos;
create policy "mvp anon delete contatos" on public.contatos for delete to anon using (true);

-- ========================================================================
-- POLICIES — usuarios (FIX: remove auth.uid() do Sprint P)
-- ========================================================================
drop policy if exists "mvp anon select usuarios" on public.usuarios;
drop policy if exists "usuarios_select" on public.usuarios;
create policy "usuarios_select" on public.usuarios for select to anon using (true);

drop policy if exists "mvp anon update usuarios" on public.usuarios;
drop policy if exists "usuarios_update" on public.usuarios;
create policy "usuarios_update" on public.usuarios for update to anon using (true);

-- ========================================================================
-- POLICIES — conteudo_permissoes
-- ========================================================================
drop policy if exists "mvp anon select conteudo_permissoes" on public.conteudo_permissoes;
create policy "mvp anon select conteudo_permissoes" on public.conteudo_permissoes for select to anon using (true);

drop policy if exists "mvp anon insert conteudo_permissoes" on public.conteudo_permissoes;
create policy "mvp anon insert conteudo_permissoes" on public.conteudo_permissoes for insert to anon with check (true);

drop policy if exists "mvp anon update conteudo_permissoes" on public.conteudo_permissoes;
create policy "mvp anon update conteudo_permissoes" on public.conteudo_permissoes for update to anon using (true);

drop policy if exists "mvp anon delete conteudo_permissoes" on public.conteudo_permissoes;
create policy "mvp anon delete conteudo_permissoes" on public.conteudo_permissoes for delete to anon using (true);

-- ========================================================================
-- POLICIES — contribuicoes
-- ========================================================================
drop policy if exists "mvp anon select contribuicoes" on public.contribuicoes;
create policy "mvp anon select contribuicoes" on public.contribuicoes for select to anon using (true);

drop policy if exists "mvp anon insert contribuicoes" on public.contribuicoes;
create policy "mvp anon insert contribuicoes" on public.contribuicoes for insert to anon with check (true);

drop policy if exists "mvp anon update contribuicoes" on public.contribuicoes;
create policy "mvp anon update contribuicoes" on public.contribuicoes for update to anon using (true);

drop policy if exists "mvp anon delete contribuicoes" on public.contribuicoes;
create policy "mvp anon delete contribuicoes" on public.contribuicoes for delete to anon using (true);

-- ========================================================================
-- POLICIES — memoriais
-- ========================================================================
drop policy if exists "mvp anon select memoriais" on public.memoriais;
create policy "mvp anon select memoriais" on public.memoriais for select to anon using (true);

drop policy if exists "mvp anon insert memoriais" on public.memoriais;
create policy "mvp anon insert memoriais" on public.memoriais for insert to anon with check (true);

drop policy if exists "mvp anon update memoriais" on public.memoriais;
create policy "mvp anon update memoriais" on public.memoriais for update to anon using (true);

drop policy if exists "mvp anon delete memoriais" on public.memoriais;
create policy "mvp anon delete memoriais" on public.memoriais for delete to anon using (true);

-- ========================================================================
-- POLICIES — mensagens_futuro (FIX: R.1 — remove auth.uid())
-- ========================================================================
drop policy if exists "mensagens_futuro_select" on public.mensagens_futuro;
create policy "mensagens_futuro_select" on public.mensagens_futuro for select to anon using (true);

drop policy if exists "mensagens_futuro_insert" on public.mensagens_futuro;
create policy "mensagens_futuro_insert" on public.mensagens_futuro for insert to anon with check (true);

drop policy if exists "mensagens_futuro_update" on public.mensagens_futuro;
create policy "mensagens_futuro_update" on public.mensagens_futuro for update to anon using (true);

drop policy if exists "mensagens_futuro_delete" on public.mensagens_futuro;
create policy "mensagens_futuro_delete" on public.mensagens_futuro for delete to anon using (true);

-- ========================================================================
-- POLICIES — cofre_itens (FIX: R.1 — remove auth.uid())
-- ========================================================================
drop policy if exists "cofre_itens_select" on public.cofre_itens;
create policy "cofre_itens_select" on public.cofre_itens for select to anon using (true);

drop policy if exists "cofre_itens_insert" on public.cofre_itens;
create policy "cofre_itens_insert" on public.cofre_itens for insert to anon with check (true);

drop policy if exists "cofre_itens_update" on public.cofre_itens;
create policy "cofre_itens_update" on public.cofre_itens for update to anon using (true);

drop policy if exists "cofre_itens_delete" on public.cofre_itens;
create policy "cofre_itens_delete" on public.cofre_itens for delete to anon using (true);

-- ========================================================================
-- POLICIES — quem_sou_eu (FIX: R.1 — remove auth.uid())
-- ========================================================================
drop policy if exists "quem_sou_eu_select" on public.quem_sou_eu;
create policy "quem_sou_eu_select" on public.quem_sou_eu for select to anon using (true);

drop policy if exists "quem_sou_eu_insert" on public.quem_sou_eu;
create policy "quem_sou_eu_insert" on public.quem_sou_eu for insert to anon with check (true);

drop policy if exists "quem_sou_eu_update" on public.quem_sou_eu;
create policy "quem_sou_eu_update" on public.quem_sou_eu for update to anon using (true);

drop policy if exists "quem_sou_eu_delete" on public.quem_sou_eu;
create policy "quem_sou_eu_delete" on public.quem_sou_eu for delete to anon using (true);

-- ========================================================================
-- POLICIES — configuracoes_curador
-- ========================================================================
drop policy if exists "mvp anon select configuracoes_curador" on public.configuracoes_curador;
create policy "mvp anon select configuracoes_curador" on public.configuracoes_curador for select to anon using (true);

drop policy if exists "mvp anon insert configuracoes_curador" on public.configuracoes_curador;
create policy "mvp anon insert configuracoes_curador" on public.configuracoes_curador for insert to anon with check (true);

drop policy if exists "mvp anon update configuracoes_curador" on public.configuracoes_curador;
create policy "mvp anon update configuracoes_curador" on public.configuracoes_curador for update to anon using (true);

drop policy if exists "mvp anon delete configuracoes_curador" on public.configuracoes_curador;
create policy "mvp anon delete configuracoes_curador" on public.configuracoes_curador for delete to anon using (true);

-- ========================================================================
-- POLICIES — curador_sessoes
-- ========================================================================
drop policy if exists "mvp anon select curador_sessoes" on public.curador_sessoes;
create policy "mvp anon select curador_sessoes" on public.curador_sessoes for select to anon using (true);

drop policy if exists "mvp anon insert curador_sessoes" on public.curador_sessoes;
create policy "mvp anon insert curador_sessoes" on public.curador_sessoes for insert to anon with check (true);

drop policy if exists "mvp anon update curador_sessoes" on public.curador_sessoes;
create policy "mvp anon update curador_sessoes" on public.curador_sessoes for update to anon using (true);

drop policy if exists "mvp anon delete curador_sessoes" on public.curador_sessoes;
create policy "mvp anon delete curador_sessoes" on public.curador_sessoes for delete to anon using (true);

-- ========================================================================
-- POLICIES — curador_mensagens
-- ========================================================================
drop policy if exists "mvp anon select curador_mensagens" on public.curador_mensagens;
create policy "mvp anon select curador_mensagens" on public.curador_mensagens for select to anon using (true);

drop policy if exists "mvp anon insert curador_mensagens" on public.curador_mensagens;
create policy "mvp anon insert curador_mensagens" on public.curador_mensagens for insert to anon with check (true);

drop policy if exists "mvp anon update curador_mensagens" on public.curador_mensagens;
create policy "mvp anon update curador_mensagens" on public.curador_mensagens for update to anon using (true);

drop policy if exists "mvp anon delete curador_mensagens" on public.curador_mensagens;
create policy "mvp anon delete curador_mensagens" on public.curador_mensagens for delete to anon using (true);

-- ========================================================================
-- POLICIES — memoria_relacionamentos
-- ========================================================================
drop policy if exists "mvp anon select memoria_relacionamentos" on public.memoria_relacionamentos;
create policy "mvp anon select memoria_relacionamentos" on public.memoria_relacionamentos for select to anon using (true);

drop policy if exists "mvp anon insert memoria_relacionamentos" on public.memoria_relacionamentos;
create policy "mvp anon insert memoria_relacionamentos" on public.memoria_relacionamentos for insert to anon with check (true);

drop policy if exists "mvp anon update memoria_relacionamentos" on public.memoria_relacionamentos;
create policy "mvp anon update memoria_relacionamentos" on public.memoria_relacionamentos for update to anon using (true);

drop policy if exists "mvp anon delete memoria_relacionamentos" on public.memoria_relacionamentos;
create policy "mvp anon delete memoria_relacionamentos" on public.memoria_relacionamentos for delete to anon using (true);

-- ========================================================================
-- POLICIES — pessoas_relacionamentos
-- ========================================================================
drop policy if exists "mvp anon select pessoas_relacionamentos" on public.pessoas_relacionamentos;
create policy "mvp anon select pessoas_relacionamentos" on public.pessoas_relacionamentos for select to anon using (true);

drop policy if exists "mvp anon insert pessoas_relacionamentos" on public.pessoas_relacionamentos;
create policy "mvp anon insert pessoas_relacionamentos" on public.pessoas_relacionamentos for insert to anon with check (true);

drop policy if exists "mvp anon update pessoas_relacionamentos" on public.pessoas_relacionamentos;
create policy "mvp anon update pessoas_relacionamentos" on public.pessoas_relacionamentos for update to anon using (true);

drop policy if exists "mvp anon delete pessoas_relacionamentos" on public.pessoas_relacionamentos;
create policy "mvp anon delete pessoas_relacionamentos" on public.pessoas_relacionamentos for delete to anon using (true);

-- ========================================================================
-- POLICIES — convites_familiares
-- ========================================================================
drop policy if exists "mvp anon select convites_familiares" on public.convites_familiares;
create policy "mvp anon select convites_familiares" on public.convites_familiares for select to anon using (true);

drop policy if exists "mvp anon insert convites_familiares" on public.convites_familiares;
create policy "mvp anon insert convites_familiares" on public.convites_familiares for insert to anon with check (true);

drop policy if exists "mvp anon update convites_familiares" on public.convites_familiares;
create policy "mvp anon update convites_familiares" on public.convites_familiares for update to anon using (true);

drop policy if exists "mvp anon delete convites_familiares" on public.convites_familiares;
create policy "mvp anon delete convites_familiares" on public.convites_familiares for delete to anon using (true);

-- ========================================================================
-- POLICIES — vinculos_familiares
-- ========================================================================
drop policy if exists "mvp anon select vinculos_familiares" on public.vinculos_familiares;
create policy "mvp anon select vinculos_familiares" on public.vinculos_familiares for select to anon using (true);

drop policy if exists "mvp anon insert vinculos_familiares" on public.vinculos_familiares;
create policy "mvp anon insert vinculos_familiares" on public.vinculos_familiares for insert to anon with check (true);

drop policy if exists "mvp anon update vinculos_familiares" on public.vinculos_familiares;
create policy "mvp anon update vinculos_familiares" on public.vinculos_familiares for update to anon using (true);

drop policy if exists "mvp anon delete vinculos_familiares" on public.vinculos_familiares;
create policy "mvp anon delete vinculos_familiares" on public.vinculos_familiares for delete to anon using (true);

-- ========================================================================
-- POLICIES — conteudo_colaboradores
-- ========================================================================
drop policy if exists "mvp anon select conteudo_colaboradores" on public.conteudo_colaboradores;
create policy "mvp anon select conteudo_colaboradores" on public.conteudo_colaboradores for select to anon using (true);

drop policy if exists "mvp anon insert conteudo_colaboradores" on public.conteudo_colaboradores;
create policy "mvp anon insert conteudo_colaboradores" on public.conteudo_colaboradores for insert to anon with check (true);

drop policy if exists "mvp anon update conteudo_colaboradores" on public.conteudo_colaboradores;
create policy "mvp anon update conteudo_colaboradores" on public.conteudo_colaboradores for update to anon using (true);

drop policy if exists "mvp anon delete conteudo_colaboradores" on public.conteudo_colaboradores;
create policy "mvp anon delete conteudo_colaboradores" on public.conteudo_colaboradores for delete to anon using (true);

-- ========================================================================
-- POLICIES — Storage (bucket fotos)
-- ========================================================================
drop policy if exists "mvp anon upload fotos" on storage.objects;
create policy "mvp anon upload fotos"
    on storage.objects for insert to anon
    with check (bucket_id = 'fotos' and name like 'usuario_%/app_mobile/%');

drop policy if exists "mvp anon select fotos" on storage.objects;
create policy "mvp anon select fotos"
    on storage.objects for select to anon
    using (bucket_id = 'fotos' and name like 'usuario_%/app_mobile/%');

drop policy if exists "mvp anon delete fotos" on storage.objects;
create policy "mvp anon delete fotos"
    on storage.objects for delete to anon
    using (bucket_id = 'fotos' and name like 'usuario_%/app_mobile/%');


-- ============================================================================
-- 13. GRANTs FINAIS
-- ============================================================================
grant usage on schema public to anon;

-- Tabelas core
grant select, insert, update, delete on public.memorias to anon;
grant select, insert, update, delete on public.fotos to anon;
grant select, insert, update, delete on public.memoria_fotos to anon;
grant select, insert, update, delete on public.contatos to anon;
grant select, update, insert on public.usuarios to anon;
grant select, insert, update, delete on public.conteudo_permissoes to anon;
grant select, insert, update, delete on public.contribuicoes to anon;
grant select, insert, update, delete on public.memoriais to anon;

-- Sprint O
grant all on public.mensagens_futuro to anon;
grant all on public.cofre_itens to anon;
grant all on public.quem_sou_eu to anon;

-- Sprint I
grant select, insert, update, delete on public.configuracoes_curador to anon;

-- Sprint J
grant select, insert, update, delete on public.curador_sessoes to anon;
grant select, insert, update, delete on public.curador_mensagens to anon;

-- Sprint K
grant select, insert, update, delete on public.memoria_relacionamentos to anon;

-- Sprint L
grant select on public.tipos_relacionamento to anon;
grant select, insert, update, delete on public.pessoas_relacionamentos to anon;

-- Vinculos familiares
grant select, insert, update, delete on public.convites_familiares to anon;
grant select, insert, update, delete on public.vinculos_familiares to anon;
grant select, insert, update, delete on public.conteudo_colaboradores to anon;

-- Views
grant select on public.pessoa_linha_tempo to anon;
grant select on public.memorias_evolucao_resumo to anon;
grant select on public.curador_sessao_ativa_por_usuario to anon;
grant select on public.memorias_resumo_leve to anon;
grant select on public.grafo_pessoas_relacionamentos to anon;

-- Funções (RPCs)
grant execute on function public.pessoa_estatisticas(bigint) to anon;
grant execute on function public.pessoas_recentes(bigint, int) to anon;
grant execute on function public.pessoas_sugeridas(bigint, int) to anon;
grant execute on function public.memorial_da_pessoa(bigint) to anon;
grant execute on function public.memorias_que_podem_crescer(bigint, int) to anon;
grant execute on function public.curador_salvar_mensagem(bigint, text, text, text) to anon;
grant execute on function public.curador_finalizar_sessao(bigint, text, text) to anon;
grant execute on function public.curador_cancelar_sessao(bigint) to anon;
grant execute on function public.curador_listar_mensagens(bigint) to anon;
grant execute on function public.buscar_candidatas_relacionamento(bigint, int) to anon;
grant execute on function public.listar_relacionamentos_pessoa(bigint) to anon;
grant execute on function public.listar_pessoas_com_mesma_relacao(bigint, bigint, text) to anon;
grant execute on function public.memorias_do_dia(bigint, int) to anon;

-- Sequences
grant usage, select on all sequences in schema public to anon;

-- ============================================================================
-- FIM — auditoria_app_supabase_fix.sql
-- ============================================================================
-- APÓS EXECUTAR, verifique:
--   1. SELECT count(*) FROM information_schema.tables WHERE table_schema='public';
--   2. SELECT * FROM memorias_do_dia(2, 5);
--   3. SELECT * FROM pessoa_linha_tempo LIMIT 5;
--   4. SELECT * FROM pessoas_recentes(2, 5);
-- ============================================================================
