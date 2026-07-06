-- ============================================================================
-- sprint_r4_push_integration.sql
-- Sprint R.4 — Integração Firebase Cloud Messaging (FCM)
-- ============================================================================
-- O QUE FAZ:
--   1. Cria tabela `device_tokens` (idempotente) para armazenar tokens
--      FCM por (usuário, dispositivo).
--   2. Cria função `upsert_device_token` para persistir tokens.
--   3. Cria função `admin_get_device_tokens` para consulta/validação.
--   4. Cria view `vw_device_tokens_por_usuario` para diagnose.
--   5. Aplica RLS, índices e GRANTs.
--
-- ORDEM DE EXECUÇÃO:
--   1. auditoria_app_supabase_fix.sql (se não executado)
--   2. sprint_r4_push_integration.sql  ← este script
--
-- DEPOIS DE EXECUTAR:
--   Abrir o app, fazer login, verificar se o token foi salvo:
--     SELECT * FROM vw_device_tokens_por_usuario;
-- ============================================================================

-- ============================================================================
-- 1. TABELA device_tokens
-- ============================================================================
create table if not exists public.device_tokens (
    id bigint generated always as identity primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    token text not null,
    plataforma text not null default 'unknown'
        check (plataforma in ('ios', 'android', 'web', 'unknown')),
    criado_em timestamptz not null default now(),
    atualizado_em timestamptz not null default now()
);

comment on table public.device_tokens is
    'Sprint R.4: tokens FCM para push notifications. Um registro por (usuário, dispositivo).';

-- ============================================================================
-- 2. ÍNDICES
-- ============================================================================
create unique index if not exists uq_device_tokens_usuario_token
    on public.device_tokens (usuario_id, token);

create index if not exists idx_device_tokens_usuario
    on public.device_tokens (usuario_id);

-- ============================================================================
-- 3. TRIGGER — atualiza atualizado_em automaticamente
-- ============================================================================
create or replace function public.trigger_set_atualizado_em_device_tokens()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
    new.atualizado_em = now();
    return new;
end;
$$;

drop trigger if exists trg_device_tokens_set_atualizado_em on public.device_tokens;
create trigger trg_device_tokens_set_atualizado_em
    before update on public.device_tokens
    for each row
    execute function public.trigger_set_atualizado_em_device_tokens();

-- ============================================================================
-- 4. FUNÇÃO — upsert_device_token
-- ============================================================================
create or replace function public.upsert_device_token(
    p_usuario_id bigint,
    p_token text,
    p_plataforma text default 'unknown'
)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
    v_id bigint;
begin
    insert into public.device_tokens (usuario_id, token, plataforma)
    values (p_usuario_id, p_token, p_plataforma)
    on conflict (usuario_id, token)
    do update set
        atualizado_em = now(),
        plataforma = excluded.plataforma
    returning id into v_id;
    return v_id;
end;
$$;

grant execute on function public.upsert_device_token to anon;

comment on function public.upsert_device_token is
    'Insere ou atualiza um token FCM para um usuário. Retorna o ID do registro.';

-- ============================================================================
-- 5. VIEW — vw_device_tokens_por_usuario (diagnose)
-- ============================================================================
create or replace view public.vw_device_tokens_por_usuario
with (security_invoker = true) as
select
    u.id as usuario_id,
    u.nome as usuario_nome,
    dt.token,
    dt.plataforma,
    dt.criado_em,
    dt.atualizado_em
from public.usuarios u
left join public.device_tokens dt on dt.usuario_id = u.id
order by u.nome, dt.atualizado_em desc;

grant select on public.vw_device_tokens_por_usuario to anon;

comment on view public.vw_device_tokens_por_usuario is
    'Sprint R.4: diagnóstico — exibe todos os tokens FCM por usuário.';

-- ============================================================================
-- 6. FUNÇÃO — admin_get_device_tokens (validação)
-- ============================================================================
create or replace function public.admin_get_device_tokens(
    p_usuario_id bigint default null
)
returns table (
    usuario_id bigint,
    token text,
    plataforma text,
    criado_em timestamptz,
    atualizado_em timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
    if p_usuario_id is not null then
        return query
        select dt.usuario_id, dt.token, dt.plataforma, dt.criado_em, dt.atualizado_em
        from public.device_tokens dt
        where dt.usuario_id = p_usuario_id
        order by dt.atualizado_em desc;
    else
        return query
        select dt.usuario_id, dt.token, dt.plataforma, dt.criado_em, dt.atualizado_em
        from public.device_tokens dt
        order by dt.usuario_id, dt.atualizado_em desc;
    end if;
end;
$$;

grant execute on function public.admin_get_device_tokens to anon;

comment on function public.admin_get_device_tokens is
    'Sprint R.4: retorna tokens FCM. Se p_usuario_id for informado, filtra por usuário.';

-- ============================================================================
-- 7. RLS
-- ============================================================================
alter table if exists public.device_tokens enable row level security;

drop policy if exists "mvp anon select device_tokens" on public.device_tokens;
create policy "mvp anon select device_tokens"
    on public.device_tokens for select to anon using (true);

drop policy if exists "mvp anon insert device_tokens" on public.device_tokens;
create policy "mvp anon insert device_tokens"
    on public.device_tokens for insert to anon with check (true);

drop policy if exists "mvp anon update device_tokens" on public.device_tokens;
create policy "mvp anon update device_tokens"
    on public.device_tokens for update to anon using (true);

-- ============================================================================
-- 8. GRANTs
-- ============================================================================
grant usage on sequence public.device_tokens_id_seq to anon;
grant select, insert, update, delete on public.device_tokens to anon;

-- ============================================================================
-- 9. VALIDAÇÃO
-- ============================================================================
-- Após abrir o app e fazer login, execute:
--
--   -- Listar todos os tokens cadastrados
--   SELECT * FROM admin_get_device_tokens();
--
--   -- Filtrar por um usuário específico
--   SELECT * FROM admin_get_device_tokens(p_usuario_id := 1);
--
--   -- Ver pela view de diagnóstico
--   SELECT * FROM vw_device_tokens_por_usuario;
--
--   -- Testar o upsert manualmente
--   SELECT upsert_device_token(1, 'fcm-token-teste', 'ios');
--
--   -- Ver o registro criado
--   SELECT * FROM device_tokens WHERE usuario_id = 1;
--
-- PARA TESTAR NOTIFICAÇÃO VIA FIREBASE CONSOLE:
--   1. Abra https://console.firebase.google.com/project/aeterna-94450/notification
--   2. Clique em "Enviar primeira mensagem"
--   3. Insira o texto da notificação
--   4. Em "Testar", cole o token retornado por admin_get_device_tokens()
--   5. O dispositivo deve receber a notificação em alguns segundos
-- ============================================================================
