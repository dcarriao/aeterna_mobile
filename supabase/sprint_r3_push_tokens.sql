-- ============================================================================
-- sprint_r3_push_tokens.sql
-- Sprint R.3 — Push notifications: tabela device_tokens
-- ============================================================================
-- O QUE FAZ:
--   Cria a tabela `device_tokens` para armazenar tokens FCM por
--   usuário/dispositivo, com RLS e índices.
--
-- ORDEM DE EXECUÇÃO:
--   Executar DEPOIS do auditoria_app_supabase_fix.sql.
--   Executar ANTES de compilar o app com firebase_messaging.
-- ============================================================================

-- 1. Tabela device_tokens
create table if not exists public.device_tokens (
    id bigint generated always as identity primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    token text not null,
    plataforma text not null default 'unknown' check (plataforma in ('ios', 'android', 'web', 'unknown')),
    criado_em timestamptz not null default now(),
    atualizado_em timestamptz not null default now()
);

-- 2. Unique por usuário + token (evita duplicatas)
create unique index if not exists uq_device_tokens_usuario_token
    on public.device_tokens (usuario_id, token);

-- 3. Índice para consulta por usuário
create index if not exists idx_device_tokens_usuario
    on public.device_tokens (usuario_id);

-- 4. Trigger para atualizar atualizado_em
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

-- 5. Função upsert: insere ou atualiza token
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
    do update set atualizado_em = now(), plataforma = p_plataforma
    returning id into v_id;
    return v_id;
end;
$$;

-- 6. RLS
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

-- 7. GRANTs
grant usage on sequence public.device_tokens_id_seq to anon;
grant select, insert, update, delete on public.device_tokens to anon;
grant execute on function public.upsert_device_token to anon;

-- 8. Comentários
comment on table public.device_tokens is
    'Sprint R.3: tokens FCM para push notifications. Um token por (usuário, dispositivo).';
comment on function public.upsert_device_token is
    'Insere ou atualiza um token FCM para um usuário. Retorna o ID do registro.';

-- ============================================================================
-- Validação
-- ============================================================================
-- SELECT * FROM public.device_tokens;
-- SELECT upsert_device_token(1, 'fcm-token-exemplo', 'ios');
-- SELECT * FROM public.device_tokens WHERE usuario_id = 1;
