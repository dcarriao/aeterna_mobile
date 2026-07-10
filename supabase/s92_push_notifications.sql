-- ============================================================================
-- S.9.2 — Push Notifications Transacionais
-- ============================================================================
-- Sprint : S.9.2
-- Data   : 2026-07-10
--
-- O QUE ESTE ARQUIVO FAZ (em ordem):
--   1. Cria tabela `push_dispositivos`  — tokens FCM por pessoa (FK correta: pessoas.id)
--   2. Cria tabela `notificacoes`       — trilha de auditoria + idempotência por envio
--   3. Função  `upsert_push_dispositivo`   — Flutter chama ao logar / token refresh
--   4. Função  `desativar_dispositivo`     — Flutter chama ao fazer logout
--   5. Função  `desativar_token_invalido`  — Edge Function chama quando FCM rejeita token
--   6. Função  `marcar_notificacao_lida`   — Flutter chama quando usuário toca na notificação
--   7. Função  `fn_enviar_push_evento`     — helper interno dos triggers
--   8. Triggers para 5 dos 6 eventos autorizados:
--        a) convite_familiar_recebido   → AFTER INSERT em convites_familiares
--        b) memoria_compartilhada       → AFTER INSERT em conteudo_permissoes
--        c) nova_contribuicao           → AFTER INSERT em contribuicoes
--        d) convite_memorial            → AFTER INSERT em memorial_pessoas
--        e) atualizacao_conteudo        → AFTER UPDATE em memorias
--        (f) mensagem_futura_liberada   → requer pg_cron — implementar separadamente)
--   9. RLS e GRANTs padrão MVP anônimo
--  10. Migração best-effort de device_tokens → push_dispositivos
--
-- PRÉ-REQUISITOS:
--   a) Extensão pg_net habilitada (Supabase Dashboard → Settings → Extensions)
--   b) Variáveis de banco configuradas (execute uma vez antes deste arquivo):
--        ALTER DATABASE postgres SET "app.supabase_url" = 'https://SEU_ID.supabase.co';
--        ALTER DATABASE postgres SET "app.supabase_service_role_key" = 'eyJ...';
--   c) Segredo FIREBASE_SERVICE_ACCOUNT_JSON em Supabase → Edge Functions → Secrets
--   d) Edge Function send-push deployada antes de os triggers dispararem em produção
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
comment on column public.push_dispositivos.last_seen_at is
    'Atualizado a cada upsert; permite expirar tokens antigos por inatividade.';

-- Um token por (pessoa, token) — o mesmo token nunca é duplicado para a mesma pessoa
create unique index if not exists uq_push_dispositivos_pessoa_token
    on public.push_dispositivos (pessoa_id, token);

-- Índices de consulta
create index if not exists idx_push_dispositivos_pessoa_ativo
    on public.push_dispositivos (pessoa_id, ativo)
    where ativo = true;

create index if not exists idx_push_dispositivos_token
    on public.push_dispositivos (token);


-- ============================================================================
-- 2. TABELA notificacoes
-- ============================================================================
-- Uma linha por envio tentado. Usada para:
--   - Auditoria (o que foi enviado, para quem, quando)
--   - Idempotência: UNIQUE impede disparar duas vezes o mesmo evento para a mesma pessoa
--   - Retry: campos tentativas + erro_envio permitem reenvio futuro
--   - Lida/não lida: o app marca como lida ao tocar na notificação

create table if not exists public.notificacoes (
    id             bigint generated always as identity primary key,
    pessoa_id      bigint not null references public.pessoas(id) on delete cascade,
    tipo           text   not null,
    titulo         text   not null,
    corpo          text   not null,
    dados          jsonb,                      -- payload de rota para o Flutter
    conteudo_id    bigint,                     -- id do registro-origem (para idempotência)
    conteudo_tipo  text,                       -- tabela-origem (para idempotência)
    lida           boolean not null default false,
    enviada        boolean not null default false,
    tentativas     int     not null default 0,
    erro_envio     text,
    created_at     timestamptz not null default now(),
    enviada_at     timestamptz,
    lida_at        timestamptz
);

comment on table public.notificacoes is
    'S.9.2: trilha de notificações push. Uma linha por envio tentado.';
comment on column public.notificacoes.dados is
    'Payload de rota enviado no FCM data message. Nunca contém dados sensíveis.';
comment on column public.notificacoes.conteudo_id is
    'ID do registro que originou o evento (ex.: contribuicao.id). Usado na UNIQUE de idempotência.';

-- Idempotência: o mesmo evento não gera dois pushes para a mesma pessoa
create unique index if not exists uq_notificacoes_evento_pessoa
    on public.notificacoes (pessoa_id, tipo, conteudo_id, conteudo_tipo)
    where conteudo_id is not null and conteudo_tipo is not null;

create index if not exists idx_notificacoes_pessoa_lida
    on public.notificacoes (pessoa_id, lida, created_at desc);

create index if not exists idx_notificacoes_nao_enviadas
    on public.notificacoes (enviada, tentativas, created_at)
    where enviada = false;

-- CHECK nos tipos autorizados
alter table public.notificacoes
    drop constraint if exists ck_notificacoes_tipo;
alter table public.notificacoes
    add  constraint ck_notificacoes_tipo
    check (tipo in (
        'convite_familiar_recebido',
        'memoria_compartilhada',
        'nova_contribuicao',
        'convite_memorial',
        'atualizacao_conteudo',
        'mensagem_futura_liberada'
    ));


-- ============================================================================
-- 3. FUNÇÃO upsert_push_dispositivo
-- ============================================================================
-- Chamada pelo Flutter após login, restore de sessão e token refresh.
-- Parâmetros:
--   p_pessoa_id  — PessoaRepository.usuarioId (que desde S.3 contém pessoas.id)
--   p_token      — token FCM obtido pelo firebase_messaging
--   p_plataforma — 'ios' | 'android'
--   p_device_id  — identificador do dispositivo (opcional)
--   p_app_version — versão do app (opcional)

create or replace function public.upsert_push_dispositivo(
    p_pessoa_id   bigint,
    p_token       text,
    p_plataforma  text    default 'unknown',
    p_device_id   text    default null,
    p_app_version text    default null
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
    on conflict (pessoa_id, token) do update set
        plataforma   = excluded.plataforma,
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
    'S.9.2: registra ou atualiza token FCM de um dispositivo. Sempre reactiva token se estava inativo.';


-- ============================================================================
-- 4. FUNÇÃO desativar_dispositivo
-- ============================================================================
-- Chamada pelo Flutter ao fazer logout.
-- Não apaga o registro — apenas marca ativo = false para não receber pushes.

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
    'S.9.2: desativa token FCM ao fazer logout. Não apaga — permite reativar ao logar novamente.';


-- ============================================================================
-- 5. FUNÇÃO desativar_token_invalido
-- ============================================================================
-- Chamada pela Edge Function send-push quando a FCM HTTP v1 API retorna
-- NOT_REGISTERED ou INVALID_ARGUMENT (token expirado/desinstalado).

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
    'S.9.2: chamada pela Edge Function send-push ao receber NOT_REGISTERED do FCM.';


-- ============================================================================
-- 6. FUNÇÃO marcar_notificacao_lida
-- ============================================================================
-- Chamada pelo Flutter quando o usuário toca na notificação.

create or replace function public.marcar_notificacao_lida(
    p_notificacao_id bigint,
    p_pessoa_id      bigint      -- guard: só a própria pessoa pode marcar
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    update public.notificacoes
    set    lida    = true,
           lida_at = now()
    where  id        = p_notificacao_id
      and  pessoa_id = p_pessoa_id
      and  lida      = false;
end;
$$;

comment on function public.marcar_notificacao_lida is
    'S.9.2: marca notificação como lida. Guard: só a própria pessoa pode marcar.';


-- ============================================================================
-- 7. FUNÇÃO fn_enviar_push_evento (helper interno dos triggers)
-- ============================================================================
-- Constrói o payload JSON e chama net.http_post() para a Edge Function.
-- Parâmetros:
--   p_tipo          — tipo do evento (deve estar em ck_notificacoes_tipo)
--   p_pessoa_id     — destinatário (pessoas.id)
--   p_titulo        — título da notificação
--   p_corpo         — corpo da notificação
--   p_dados         — payload de rota para o Flutter (sem dados sensíveis)
--   p_conteudo_id   — ID do registro-origem (para idempotência)
--   p_conteudo_tipo — tabela-origem (para idempotência)
--
-- NOTA: usa current_setting('app.supabase_url') e
--       current_setting('app.supabase_service_role_key').
--       Configure com ALTER DATABASE postgres SET "app.supabase_url" = '...';

create or replace function public.fn_enviar_push_evento(
    p_tipo          text,
    p_pessoa_id     bigint,
    p_titulo        text,
    p_corpo         text,
    p_dados         jsonb   default '{}'::jsonb,
    p_conteudo_id   bigint  default null,
    p_conteudo_tipo text    default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_supabase_url      text;
    v_service_role_key  text;
    v_payload           jsonb;
begin
    -- Ler configurações de banco (configuradas uma vez por ALTER DATABASE)
    v_supabase_url     := current_setting('app.supabase_url',            true);
    v_service_role_key := current_setting('app.supabase_service_role_key', true);

    -- Guardar silenciosamente se não configurado (não quebra transação de origem)
    if v_supabase_url is null or v_supabase_url = '' then
        raise warning '[PUSH] app.supabase_url não configurado — trigger silenciado';
        return;
    end if;
    if v_service_role_key is null or v_service_role_key = '' then
        raise warning '[PUSH] app.supabase_service_role_key não configurado — trigger silenciado';
        return;
    end if;

    v_payload := jsonb_build_object(
        'tipo',          p_tipo,
        'pessoa_id',     p_pessoa_id,
        'titulo',        p_titulo,
        'corpo',         p_corpo,
        'dados',         p_dados,
        'conteudo_id',   p_conteudo_id,
        'conteudo_tipo', p_conteudo_tipo
    );

    -- Disparo assíncrono via pg_net (não bloqueia a transação de origem)
    perform net.http_post(
        url     := v_supabase_url || '/functions/v1/send-push',
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_service_role_key
        ),
        body    := v_payload
    );

exception when others then
    -- Nunca deixar o trigger de envio de push quebrar a transação de origem
    raise warning '[PUSH] fn_enviar_push_evento falhou: % — tipo=% pessoa_id=%',
        sqlerrm, p_tipo, p_pessoa_id;
end;
$$;

comment on function public.fn_enviar_push_evento is
    'S.9.2: helper interno. Chama a Edge Function send-push via pg_net de forma assíncrona.';


-- ============================================================================
-- 8a. TRIGGER — convite_familiar_recebido
-- ============================================================================
-- Evento : AFTER INSERT em convites_familiares
-- Destino: usuario_destino_id → look up pessoas.usuario_id → pessoas.id
-- Guard  : usuario_destino_id NOT NULL (sem conta = sem push)

create or replace function public.tg_push_convite_familiar()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_pessoa_id    bigint;
    v_nome_origem  text;
begin
    -- Só notifica se o destinatário já tem conta
    if NEW.usuario_destino_id is null then
        return NEW;
    end if;

    -- Resolve pessoa_id do destinatário
    select p.id into v_pessoa_id
    from public.pessoas p
    where p.usuario_id = NEW.usuario_destino_id
    limit 1;

    if v_pessoa_id is null then
        return NEW;
    end if;

    -- Busca nome do remetente para texto da notificação
    select coalesce(p.nome, u.nome, 'Alguém') into v_nome_origem
    from public.usuarios u
    left join public.pessoas p on p.usuario_id = u.id
    where u.id = NEW.usuario_origem_id
    limit 1;

    perform public.fn_enviar_push_evento(
        p_tipo          := 'convite_familiar_recebido',
        p_pessoa_id     := v_pessoa_id,
        p_titulo        := 'Convite familiar recebido',
        p_corpo         := v_nome_origem || ' convidou você para se conectar.',
        p_dados         := jsonb_build_object(
            'route',      'familia',
            'convite_id', NEW.id
        ),
        p_conteudo_id   := NEW.id,
        p_conteudo_tipo := 'convite_familiar'
    );

    return NEW;
end;
$$;

drop trigger if exists trg_push_convite_familiar on public.convites_familiares;
create trigger trg_push_convite_familiar
    after insert on public.convites_familiares
    for each row
    execute function public.tg_push_convite_familiar();


-- ============================================================================
-- 8b. TRIGGER — memoria_compartilhada
-- ============================================================================
-- Evento : AFTER INSERT em conteudo_permissoes
-- Destino: NEW.pessoa_id (já é pessoas.id desde Sprint S.5.1)
-- Guard  : NEW.tipo = 'compartilhamento'

create or replace function public.tg_push_memoria_compartilhada()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_titulo_memoria text;
begin
    -- Só notifica evento de compartilhamento (não outras permissões)
    if NEW.tipo is distinct from 'compartilhamento' then
        return NEW;
    end if;

    if NEW.pessoa_id is null then
        return NEW;
    end if;

    -- Tenta buscar título do conteúdo compartilhado
    if NEW.tipo_conteudo = 'memoria' then
        select coalesce(titulo, 'uma memória') into v_titulo_memoria
        from public.memorias
        where id = NEW.conteudo_id
        limit 1;
    elsif NEW.tipo_conteudo = 'memorial' then
        select coalesce(nome, 'um memorial') into v_titulo_memoria
        from public.memoriais
        where id = NEW.conteudo_id
        limit 1;
    else
        v_titulo_memoria := 'um conteúdo';
    end if;

    perform public.fn_enviar_push_evento(
        p_tipo          := 'memoria_compartilhada',
        p_pessoa_id     := NEW.pessoa_id,
        p_titulo        := 'Conteúdo compartilhado com você',
        p_corpo         := 'Você recebeu acesso a ' || coalesce(v_titulo_memoria, 'um conteúdo') || '.',
        p_dados         := jsonb_build_object(
            'route',        NEW.tipo_conteudo,
            'conteudo_id',  NEW.conteudo_id,
            'permissao_id', NEW.id
        ),
        p_conteudo_id   := NEW.id,
        p_conteudo_tipo := 'conteudo_permissao'
    );

    return NEW;
end;
$$;

drop trigger if exists trg_push_memoria_compartilhada on public.conteudo_permissoes;
create trigger trg_push_memoria_compartilhada
    after insert on public.conteudo_permissoes
    for each row
    execute function public.tg_push_memoria_compartilhada();


-- ============================================================================
-- 8c. TRIGGER — nova_contribuicao
-- ============================================================================
-- Evento : AFTER INSERT em contribuicoes (status = 'pendente')
-- Destino: dono da memória → memorias.usuario_id → pessoas.usuario_id → pessoas.id
-- Guard  : só memórias (tipo_conteudo = 'memoria'), não notifica o próprio dono

create or replace function public.tg_push_nova_contribuicao()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_pessoa_id_dono    bigint;
    v_pessoa_id_contrib bigint;
    v_titulo_memoria    text;
begin
    -- Só para contribuições de memórias
    if NEW.tipo_conteudo is distinct from 'memoria' then
        return NEW;
    end if;

    -- Busca o pessoa_id do dono da memória
    select p.id, m.titulo
    into   v_pessoa_id_dono, v_titulo_memoria
    from   public.memorias m
    join   public.pessoas  p on p.usuario_id = m.usuario_id
    where  m.id = NEW.conteudo_id
    limit  1;

    if v_pessoa_id_dono is null then
        return NEW;
    end if;

    -- Não notifica o dono se ele mesmo contribuiu
    -- (tenta resolver o pessoa_id do contribuidor pelo e-mail)
    select p.id into v_pessoa_id_contrib
    from   public.pessoas  p
    join   public.usuarios u on u.id = p.usuario_id
    where  lower(u.email) = lower(NEW.usuario_contribuidor_email)
    limit  1;

    if v_pessoa_id_contrib is not null and v_pessoa_id_contrib = v_pessoa_id_dono then
        return NEW;
    end if;

    perform public.fn_enviar_push_evento(
        p_tipo          := 'nova_contribuicao',
        p_pessoa_id     := v_pessoa_id_dono,
        p_titulo        := 'Nova contribuição recebida',
        p_corpo         := 'Alguém contribuiu com "' || coalesce(v_titulo_memoria, 'sua memória') || '".',
        p_dados         := jsonb_build_object(
            'route',          'memoria',
            'conteudo_id',    NEW.conteudo_id,
            'contribuicao_id', NEW.id
        ),
        p_conteudo_id   := NEW.id,
        p_conteudo_tipo := 'contribuicao'
    );

    return NEW;
end;
$$;

drop trigger if exists trg_push_nova_contribuicao on public.contribuicoes;
create trigger trg_push_nova_contribuicao
    after insert on public.contribuicoes
    for each row
    execute function public.tg_push_nova_contribuicao();


-- ============================================================================
-- 8d. TRIGGER — convite_memorial
-- ============================================================================
-- Evento : AFTER INSERT em memorial_pessoas
-- Destino: NEW.pessoa_id (já é pessoas.id — FK direto)

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

    perform public.fn_enviar_push_evento(
        p_tipo          := 'convite_memorial',
        p_pessoa_id     := NEW.pessoa_id,
        p_titulo        := 'Você foi convidado para um memorial',
        p_corpo         := 'Você foi adicionado ao memorial "' || v_nome_memorial || '".',
        p_dados         := jsonb_build_object(
            'route',       'memorial',
            'memorial_id', NEW.memorial_id
        ),
        p_conteudo_id   := NEW.id,
        p_conteudo_tipo := 'memorial_pessoa'
    );

    return NEW;
end;
$$;

drop trigger if exists trg_push_convite_memorial on public.memorial_pessoas;
create trigger trg_push_convite_memorial
    after insert on public.memorial_pessoas
    for each row
    execute function public.tg_push_convite_memorial();


-- ============================================================================
-- 8e. TRIGGER — atualizacao_conteudo
-- ============================================================================
-- Evento : AFTER UPDATE em memorias (quando título ou descrição muda)
-- Destino: todos os pessoa_id em conteudo_permissoes para esta memória
-- Guard  : titulo ou descricao efetivamente mudaram (evitar loops por trigger de timestamps)

create or replace function public.tg_push_atualizacao_conteudo()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
    v_rec record;
begin
    -- Só notifica se conteúdo relevante mudou (não timestamps)
    if OLD.titulo is not distinct from NEW.titulo
   and OLD.descricao is not distinct from NEW.descricao then
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
        perform public.fn_enviar_push_evento(
            p_tipo          := 'atualizacao_conteudo',
            p_pessoa_id     := v_rec.pessoa_id,
            p_titulo        := 'Memória atualizada',
            p_corpo         := '"' || coalesce(NEW.titulo, 'Uma memória') || '" foi atualizada.',
            p_dados         := jsonb_build_object(
                'route',      'memoria',
                'conteudo_id', NEW.id
            ),
            p_conteudo_id   := null,   -- sem idempotência por conteudo_id (múltiplas atualizações devem notificar)
            p_conteudo_tipo := null
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
-- 9. RLS e GRANTs
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

-- INSERT em notificacoes é feito apenas pela Edge Function (via service role) e pelo trigger
-- A anon key não precisa inserir diretamente em notificacoes

grant usage on sequence public.notificacoes_id_seq to anon;
grant select, update on public.notificacoes to anon;


-- ============================================================================
-- 10. MIGRAÇÃO best-effort: device_tokens → push_dispositivos
-- ============================================================================
-- Tenta migrar tokens existentes linkando via pessoas.usuario_id.
-- Ignora tokens cujo usuario_id não tem um pessoas correspondente.
-- A tabela device_tokens é mantida intacta (não removida).

insert into public.push_dispositivos
    (pessoa_id, token, plataforma, ativo, last_seen_at, created_at, updated_at)
select
    p.id,
    dt.token,
    dt.plataforma,
    true,
    coalesce(dt.atualizado_em, dt.criado_em, now()),
    coalesce(dt.criado_em, now()),
    coalesce(dt.atualizado_em, now())
from public.device_tokens dt
join public.pessoas p on p.usuario_id = dt.usuario_id
on conflict (pessoa_id, token) do nothing;


-- ============================================================================
-- VALIDAÇÃO MANUAL (executar após deploy da Edge Function)
-- ============================================================================
--
-- 1. Verificar tokens migrados:
--    SELECT p.nome, pd.token, pd.plataforma, pd.ativo
--    FROM push_dispositivos pd
--    JOIN pessoas p ON p.id = pd.pessoa_id;
--
-- 2. Simular convite familiar (substitua pelos IDs reais):
--    INSERT INTO convites_familiares (usuario_origem_id, email_destino, usuario_destino_id)
--    VALUES (1, 'destino@email.com', 2);
--    -- Verificar em notificacoes:
--    SELECT * FROM notificacoes ORDER BY created_at DESC LIMIT 5;
--
-- 3. Verificar tokens ativos de uma pessoa:
--    SELECT * FROM push_dispositivos WHERE pessoa_id = 1 AND ativo = true;
--
-- 4. Testar upsert de dispositivo:
--    SELECT upsert_push_dispositivo(1, 'fcm-token-teste', 'ios', 'device-uuid', '2.0.0');
--
-- 5. Testar desativação (logout):
--    SELECT desativar_dispositivo(1, 'fcm-token-teste');
--    SELECT ativo FROM push_dispositivos WHERE token = 'fcm-token-teste';
--    -- Deve retornar: false
--
-- ============================================================================
-- Fim — S.9.2 Push Notifications Transacionais
-- ============================================================================
