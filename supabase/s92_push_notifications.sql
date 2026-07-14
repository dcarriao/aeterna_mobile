-- ============================================================================
-- S.9.2 — Push Notifications Transacionais
-- ============================================================================
-- Sprint : S.9.2
-- Data   : 2026-07-10
--
-- ARQUITETURA: Database Webhook (sem pg_net, sem ALTER DATABASE)
--   1. Triggers fazem INSERT em `notificacoes` (fila/auditoria)
--   2. Supabase Database Webhook detecta o INSERT e chama a Edge Function send-push
--   3. Edge Function lê o registro, busca tokens em push_dispositivos e envia FCM
--
-- O QUE ESTE ARQUIVO FAZ (em ordem):
--   1. Cria tabela `push_dispositivos`     — tokens FCM por pessoa (FK: pessoas.id)
--   2. Cria tabela `notificacoes`          — fila de envio + auditoria + idempotência
--   3. Função  `upsert_push_dispositivo`   — Flutter chama ao logar / token refresh
--   4. Função  `desativar_dispositivo`     — Flutter chama ao fazer logout
--   5. Função  `desativar_token_invalido`  — Edge Function chama quando FCM rejeita token
--   6. Função  `marcar_notificacao_lida`   — Flutter chama quando usuário toca na notificação
--   7. Triggers para 5 dos 6 eventos autorizados (apenas INSERT em notificacoes):
--        a) convite_familiar_recebido   → AFTER INSERT em convites_familiares
--        b) memoria_compartilhada       → AFTER INSERT em conteudo_permissoes
--        c) nova_contribuicao           → AFTER INSERT em contribuicoes
--        d) convite_memorial            → AFTER INSERT em memorial_pessoas
--        e) atualizacao_conteudo        → AFTER UPDATE em memorias
--        (f) mensagem_futura_liberada   → requer pg_cron — implementar separadamente
--   8. RLS e GRANTs padrão MVP anônimo
--   9. Migração best-effort de device_tokens → push_dispositivos
--
-- PRÉ-REQUISITOS:
--   a) Segredo FIREBASE_SERVICE_ACCOUNT_JSON em Supabase → Edge Functions → Secrets
--   b) Edge Function send-push deployada
--   c) Database Webhook configurado no dashboard (instruções no final do arquivo)
--
-- IDEMPOTENTE: pode ser executado múltiplas vezes sem efeitos colaterais.
-- ============================================================================


-- ============================================================================
-- 1. TABELA push_dispositivos
-- ============================================================================
-- Substitui device_tokens (que tinha FK errada → usuarios.id).
-- A identidade do destinatário é sempre pessoas.id (desde Sprint S.3).

create table if not exists public.push_dispositivos (
    id           bigint generated always as identity primary key,
    pessoa_id    bigint not null references public.pessoas(id) on delete cascade,
    token        text   not null,
    plataforma   text   not null default 'unknown'
        check (plataforma in ('ios', 'android', 'web', 'unknown')),
    device_id    text,
    app_version  text,
    ativo        boolean not null default true,
    last_seen_at timestamptz not null default now(),
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

comment on table public.push_dispositivos is
    'S.9.2: tokens FCM por dispositivo/pessoa. FK correta: pessoas.id (não usuarios.id).';
comment on column public.push_dispositivos.ativo is
    'false após logout explícito ou quando FCM retorna token inválido/não-registrado.';

create unique index if not exists uq_push_dispositivos_pessoa_token
    on public.push_dispositivos (pessoa_id, token);

create index if not exists idx_push_dispositivos_pessoa_ativo
    on public.push_dispositivos (pessoa_id) where ativo = true;


-- ============================================================================
-- 2. TABELA notificacoes
-- ============================================================================
-- Fila de envio: o trigger insere aqui; o Webhook chama a Edge Function;
-- a Edge Function atualiza enviada/erro_envio ao terminar.

create table if not exists public.notificacoes (
    id             bigint generated always as identity primary key,
    pessoa_id      bigint not null references public.pessoas(id) on delete cascade,
    tipo           text   not null,
    titulo         text   not null,
    corpo          text   not null,
    dados          jsonb,
    conteudo_id    bigint,
    conteudo_tipo  text,
    lida           boolean not null default false,
    enviada        boolean not null default false,
    tentativas     int     not null default 0,
    erro_envio     text,
    created_at     timestamptz not null default now(),
    enviada_at     timestamptz,
    lida_at        timestamptz
);

comment on table public.notificacoes is
    'S.9.2: fila de push + auditoria. INSERT feito pelos triggers; '
    'envio feito pela Edge Function send-push via Database Webhook.';

-- Índice de idempotência: mesmo evento para a mesma pessoa não gera duplicatas
create unique index if not exists uq_notificacoes_evento_pessoa
    on public.notificacoes (pessoa_id, tipo, conteudo_id, conteudo_tipo)
    where conteudo_id is not null and conteudo_tipo is not null;

create index if not exists idx_notificacoes_pessoa_lida
    on public.notificacoes (pessoa_id, lida) where lida = false;


-- ============================================================================
-- 3. RPC upsert_push_dispositivo
-- ============================================================================
-- Chamada pelo Flutter ao logar, ao restaurar sessão e ao renovar token FCM.
--   p_pessoa_id  — PessoaRepository.usuarioId (pessoas.id desde S.3)
--   p_token      — token FCM do dispositivo
--   p_plataforma — 'ios' | 'android'
--   p_device_id  — opcional, identificador do hardware
--   p_app_version — opcional

create or replace function public.upsert_push_dispositivo(
    p_pessoa_id  bigint,
    p_token      text,
    p_plataforma text    default 'unknown',
    p_device_id  text    default null,
    p_app_version text   default null
)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
    v_id bigint;
begin
    insert into public.push_dispositivos
        (pessoa_id, token, plataforma, device_id, app_version, ativo, last_seen_at, updated_at)
    values
        (p_pessoa_id, p_token, p_plataforma, p_device_id, p_app_version, true, now(), now())
    on conflict (pessoa_id, token) do update
        set plataforma   = excluded.plataforma,
            device_id    = coalesce(excluded.device_id,    push_dispositivos.device_id),
            app_version  = coalesce(excluded.app_version,  push_dispositivos.app_version),
            ativo        = true,
            last_seen_at = now(),
            updated_at   = now()
    returning id into v_id;

    return v_id;
end;
$$;

comment on function public.upsert_push_dispositivo is
    'S.9.2: registra/atualiza token FCM. Chamado pelo Flutter no login e token refresh.';


-- ============================================================================
-- 4. RPC desativar_dispositivo
-- ============================================================================
-- Chamado pelo Flutter no logout. Marca ativo=false para não receber pushes
-- de outra conta no mesmo dispositivo.

create or replace function public.desativar_dispositivo(
    p_pessoa_id bigint,
    p_token     text
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    update public.push_dispositivos
    set    ativo      = false,
           updated_at = now()
    where  pessoa_id = p_pessoa_id
      and  token     = p_token;
end;
$$;

comment on function public.desativar_dispositivo is
    'S.9.2: desativa token no logout. Evita push para conta errada no mesmo aparelho.';


-- ============================================================================
-- 5. RPC desativar_token_invalido
-- ============================================================================
-- Chamado pela Edge Function quando FCM retorna NOT_REGISTERED ou INVALID_ARGUMENT.
-- Não recebe pessoa_id (o token identifica o dispositivo unicamente).

create or replace function public.desativar_token_invalido(
    p_token text
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    update public.push_dispositivos
    set    ativo      = false,
           updated_at = now()
    where  token = p_token;
end;
$$;

comment on function public.desativar_token_invalido is
    'S.9.2: chamado pela Edge Function quando FCM rejeita o token (NOT_REGISTERED).';


-- ============================================================================
-- 6. RPC marcar_notificacao_lida
-- ============================================================================
-- Chamado pelo Flutter quando o usuário toca na notificação.

create or replace function public.marcar_notificacao_lida(
    p_notificacao_id bigint
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    update public.notificacoes
    set    lida    = true,
           lida_at = now()
    where  id = p_notificacao_id
      and  lida = false;
end;
$$;

comment on function public.marcar_notificacao_lida is
    'S.9.2: chamado pelo Flutter ao tocar na notificação push.';


-- ============================================================================
-- 7a. TRIGGER — convite_familiar_recebido
-- ============================================================================
-- Evento : AFTER INSERT em convites_familiares
-- Destino: usuario_destino_id (já é pessoas.id desde Sprint S.3)
-- Guard  : usuario_destino_id NOT NULL (sem conta = sem push)

create or replace function public.tg_push_convite_familiar()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_nome_origem text;
begin
    -- Só notifica se o destinatário já tem conta
    if NEW.usuario_destino_id is null then
        return NEW;
    end if;

    -- Busca nome do remetente
    select coalesce(nome, 'Alguém') into v_nome_origem
    from public.pessoas
    where id = NEW.usuario_origem_id
    limit 1;

    insert into public.notificacoes
        (pessoa_id, tipo, titulo, corpo, dados, conteudo_id, conteudo_tipo)
    values (
        NEW.usuario_destino_id,
        'convite_familiar_recebido',
        'Convite familiar recebido',
        coalesce(v_nome_origem, 'Alguém') || ' convidou você para se conectar.',
        jsonb_build_object('route', 'familia', 'convite_id', NEW.id),
        NEW.id,
        'convite_familiar'
    )
    on conflict (pessoa_id, tipo, conteudo_id, conteudo_tipo)
        where conteudo_id is not null and conteudo_tipo is not null
    do nothing;

    return NEW;
end;
$$;

drop trigger if exists trg_push_convite_familiar on public.convites_familiares;
create trigger trg_push_convite_familiar
    after insert on public.convites_familiares
    for each row
    execute function public.tg_push_convite_familiar();


-- ============================================================================
-- 7b. TRIGGER — memoria_compartilhada
-- ============================================================================
-- Evento : AFTER INSERT em conteudo_permissoes
-- Destino: NEW.pessoa_id (já é pessoas.id desde Sprint S.5.1)
-- Guard  : NEW.papel = 'compartilhado'  (NÃO existe coluna `tipo` nesta tabela;
--          valor errado antigo era 'compartilhamento' — corrigido em S.9.3.2)

create or replace function public.tg_push_memoria_compartilhada()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_titulo_conteudo text;
begin
    -- Participante aparece na memória; só 'compartilhado' recebe push.
    if NEW.papel is distinct from 'compartilhado' then
        return NEW;
    end if;

    if NEW.pessoa_id is null then
        return NEW;
    end if;

    -- Pet nunca recebe notificação/push.
    if exists (
        select 1 from public.pessoas p
        where p.id = NEW.pessoa_id and p.tipo = 'pet'
    ) then
        return NEW;
    end if;

    if NEW.tipo_conteudo = 'memoria' then
        select coalesce(titulo, 'uma memória') into v_titulo_conteudo
        from public.memorias where id = NEW.conteudo_id limit 1;
    elsif NEW.tipo_conteudo = 'memorial' then
        select coalesce(nome, 'um memorial') into v_titulo_conteudo
        from public.memoriais where id = NEW.conteudo_id limit 1;
    else
        v_titulo_conteudo := 'um conteúdo';
    end if;

    insert into public.notificacoes
        (pessoa_id, tipo, titulo, corpo, dados, conteudo_id, conteudo_tipo)
    values (
        NEW.pessoa_id,
        'memoria_compartilhada',
        'Conteúdo compartilhado com você',
        'Você recebeu acesso a ' || coalesce(v_titulo_conteudo, 'um conteúdo') || '.',
        jsonb_build_object(
            'route',        NEW.tipo_conteudo,
            'conteudo_id',  NEW.conteudo_id,
            'permissao_id', NEW.id
        ),
        NEW.id,
        'conteudo_permissao'
    )
    on conflict (pessoa_id, tipo, conteudo_id, conteudo_tipo)
        where conteudo_id is not null and conteudo_tipo is not null
    do nothing;

    return NEW;
end;
$$;

drop trigger if exists trg_push_memoria_compartilhada on public.conteudo_permissoes;
create trigger trg_push_memoria_compartilhada
    after insert on public.conteudo_permissoes
    for each row
    execute function public.tg_push_memoria_compartilhada();


-- ============================================================================
-- 7c. TRIGGER — nova_contribuicao
-- ============================================================================
-- Evento : AFTER INSERT em contribuicoes
-- Destino: dono da memória (memorias.usuario_id = pessoas.id desde Sprint S.3)
-- Guard  : só memórias, não notifica o próprio dono

create or replace function public.tg_push_nova_contribuicao()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_pessoa_id_dono    bigint;
    v_pessoa_id_contrib bigint;
    v_titulo_memoria    text;
begin
    if NEW.tipo_conteudo is distinct from 'memoria' then
        return NEW;
    end if;

    -- memorias.usuario_id já é pessoas.id desde Sprint S.3
    select usuario_id, titulo
    into   v_pessoa_id_dono, v_titulo_memoria
    from   public.memorias
    where  id = NEW.conteudo_id
    limit  1;

    if v_pessoa_id_dono is null then
        return NEW;
    end if;

    -- Não notifica o dono se ele mesmo contribuiu
    select id into v_pessoa_id_contrib
    from   public.pessoas
    where  lower(email) = lower(NEW.usuario_contribuidor_email)
    limit  1;

    if v_pessoa_id_contrib is not null and v_pessoa_id_contrib = v_pessoa_id_dono then
        return NEW;
    end if;

    insert into public.notificacoes
        (pessoa_id, tipo, titulo, corpo, dados, conteudo_id, conteudo_tipo)
    values (
        v_pessoa_id_dono,
        'nova_contribuicao',
        'Nova contribuição recebida',
        'Alguém contribuiu com "' || coalesce(v_titulo_memoria, 'sua memória') || '".',
        jsonb_build_object(
            'route',           'memoria',
            'conteudo_id',     NEW.conteudo_id,
            'contribuicao_id', NEW.id
        ),
        NEW.id,
        'contribuicao'
    )
    on conflict (pessoa_id, tipo, conteudo_id, conteudo_tipo)
        where conteudo_id is not null and conteudo_tipo is not null
    do nothing;

    return NEW;
end;
$$;

drop trigger if exists trg_push_nova_contribuicao on public.contribuicoes;
create trigger trg_push_nova_contribuicao
    after insert on public.contribuicoes
    for each row
    execute function public.tg_push_nova_contribuicao();


-- ============================================================================
-- 7d. TRIGGER — convite_memorial
-- ============================================================================
-- Evento : AFTER INSERT em memorial_pessoas
-- Destino: NEW.pessoa_id (FK direto para pessoas.id)

create or replace function public.tg_push_convite_memorial()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_nome_memorial text;
begin
    if NEW.pessoa_id is null then
        return NEW;
    end if;

    select coalesce(nome, 'um memorial') into v_nome_memorial
    from   public.memoriais
    where  id = NEW.memorial_id
    limit  1;

    insert into public.notificacoes
        (pessoa_id, tipo, titulo, corpo, dados, conteudo_id, conteudo_tipo)
    values (
        NEW.pessoa_id,
        'convite_memorial',
        'Você foi convidado para um memorial',
        'Você foi adicionado ao memorial "' || v_nome_memorial || '".',
        jsonb_build_object('route', 'memorial', 'memorial_id', NEW.memorial_id),
        NEW.id,
        'memorial_pessoa'
    )
    on conflict (pessoa_id, tipo, conteudo_id, conteudo_tipo)
        where conteudo_id is not null and conteudo_tipo is not null
    do nothing;

    return NEW;
end;
$$;

drop trigger if exists trg_push_convite_memorial on public.memorial_pessoas;
create trigger trg_push_convite_memorial
    after insert on public.memorial_pessoas
    for each row
    execute function public.tg_push_convite_memorial();


-- ============================================================================
-- 7e. TRIGGER — atualizacao_conteudo
-- ============================================================================
-- Evento : AFTER UPDATE em memorias (quando título ou conteúdo muda)
-- Destino: todos os pessoa_id em conteudo_permissoes para esta memória
-- Sem idempotência por conteudo_id (múltiplas atualizações devem notificar)

create or replace function public.tg_push_atualizacao_conteudo()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_rec record;
begin
    -- Só notifica se conteúdo relevante mudou (não timestamps)
    -- memorias usa coluna 'conteudo' (não 'descricao')
    if OLD.titulo   is not distinct from NEW.titulo
   and OLD.conteudo is not distinct from NEW.conteudo then
        return NEW;
    end if;

    -- Fan-out para todos que têm acesso à memória
    for v_rec in
        select cp.pessoa_id
        from   public.conteudo_permissoes cp
        where  cp.tipo_conteudo = 'memoria'
          and  cp.conteudo_id   = NEW.id
          and  cp.pessoa_id is not null
    loop
        insert into public.notificacoes
            (pessoa_id, tipo, titulo, corpo, dados, conteudo_id, conteudo_tipo)
        values (
            v_rec.pessoa_id,
            'atualizacao_conteudo',
            'Memória atualizada',
            '"' || coalesce(NEW.titulo, 'Uma memória') || '" foi atualizada.',
            jsonb_build_object('route', 'memoria', 'conteudo_id', NEW.id),
            null,   -- sem idempotência: cada atualização gera nova notificação
            null
        );
    end loop;

    return NEW;

exception when others then
    raise warning '[PUSH] tg_push_atualizacao_conteudo falhou: %', sqlerrm;
    return NEW;
end;
$$;

drop trigger if exists trg_push_atualizacao_conteudo on public.memorias;
create trigger trg_push_atualizacao_conteudo
    after update on public.memorias
    for each row
    execute function public.tg_push_atualizacao_conteudo();


-- ============================================================================
-- 8. RLS e GRANTs
-- ============================================================================

-- push_dispositivos
alter table public.push_dispositivos enable row level security;

drop policy if exists "mvp anon select push_dispositivos"  on public.push_dispositivos;
create policy "mvp anon select push_dispositivos"
    on public.push_dispositivos for select to anon using (true);

drop policy if exists "mvp anon insert push_dispositivos"  on public.push_dispositivos;
create policy "mvp anon insert push_dispositivos"
    on public.push_dispositivos for insert to anon with check (true);

drop policy if exists "mvp anon update push_dispositivos"  on public.push_dispositivos;
create policy "mvp anon update push_dispositivos"
    on public.push_dispositivos for update to anon using (true);

grant usage  on sequence public.push_dispositivos_id_seq to anon;
grant select, insert, update on public.push_dispositivos to anon;

grant execute on function public.upsert_push_dispositivo  to anon;
grant execute on function public.desativar_dispositivo     to anon;
grant execute on function public.desativar_token_invalido  to anon;
grant execute on function public.marcar_notificacao_lida   to anon;

-- notificacoes
alter table public.notificacoes enable row level security;

drop policy if exists "mvp anon select notificacoes" on public.notificacoes;
create policy "mvp anon select notificacoes"
    on public.notificacoes for select to anon using (true);

drop policy if exists "mvp anon update notificacoes" on public.notificacoes;
create policy "mvp anon update notificacoes"
    on public.notificacoes for update to anon using (true);

-- INSERT em notificacoes é feito pelos triggers (security definer) e pela Edge Function (service role)
grant usage on sequence public.notificacoes_id_seq to anon;
grant select, update on public.notificacoes to anon;


-- ============================================================================
-- 9. MIGRAÇÃO best-effort: device_tokens → push_dispositivos
-- ============================================================================
-- device_tokens.usuario_id já armazena pessoas.id (PessoaRepository.usuarioId = pessoas.id
-- desde Sprint S.3 — o nome da coluna é legado, o valor já é correto).
-- Só migra tokens cujo usuario_id existe em pessoas.
-- A tabela device_tokens é mantida intacta (não removida).

insert into public.push_dispositivos
    (pessoa_id, token, plataforma, ativo, last_seen_at, created_at, updated_at)
select
    dt.usuario_id,
    dt.token,
    dt.plataforma,
    true,
    coalesce(dt.atualizado_em, dt.criado_em, now()),
    coalesce(dt.criado_em, now()),
    coalesce(dt.atualizado_em, now())
from public.device_tokens dt
where exists (select 1 from public.pessoas where id = dt.usuario_id)
on conflict (pessoa_id, token) do nothing;


-- ============================================================================
-- CONFIGURAÇÃO DO DATABASE WEBHOOK (fazer uma vez no Supabase Dashboard)
-- ============================================================================
--
-- Supabase Dashboard → Database → Webhooks → Create a new hook
--
--   Nome    : push_notificacoes
--   Tabela  : notificacoes
--   Eventos : INSERT
--   Tipo    : Supabase Edge Functions
--   Função  : send-push
--
-- Não precisa de mais nada. O Supabase passa o payload do registro novo
-- automaticamente para a Edge Function.
-- ============================================================================
