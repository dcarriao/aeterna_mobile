-- ============================================================================
-- SPRINT J — CURADOR CONTEXTUAL
-- ============================================================================
-- Persistência da conversa do Curador. Antes desta sprint, o Curador
-- gerava perguntas uma única vez e armazenava respostas só em memória;
-- agora ele conduz uma conversa com histórico completo, persistido entre
-- sessões e entre devices.
--
-- Este script:
--   1. Cria a tabela `curador_sessoes` — uma sessão por conversa do
--      Curador (1:N com `usuarios`).
--   2. Cria a tabela `curador_mensagens` — histórico da conversa
--      (1:N com `curador_sessoes`).
--   3. Cria a view `curador_sessao_ativa_por_usuario` — retorna a
--      sessão `em_andamento` mais recente (se houver) de um usuário.
--   4. Cria a função `curador_salvar_mensagem` — usada pelo client
--      para gravar cada turno.
--   5. Cria a função `curador_finalizar_sessao` — marca como
--      `concluida` e devolve o `contexto_atual` consolidado.
--   6. Trigger: atualiza `atualizado_em` em `curador_sessoes`
--      automaticamente a cada insert em `curador_mensagens`.
--   7. GRANTs/policies no padrão MVP anônimo.
--
-- ============================================================================


-- (1) Tabela `curador_sessoes`
create table if not exists public.curador_sessoes (
    id bigserial primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    -- titulo é a frase de entrada que o usuário digitou antes de abrir
    -- o Curador; pode ser nula (caso Complemento, Sprint I).
    titulo text,
    -- contexto_inicial é o texto que o usuário já tinha digitado ao
    -- abrir o Curador (rascunho de memória). Usado para devolver o
    -- contexto completo ao retomar.
    contexto_inicial text not null default '',
    -- contexto_atual é o snapshot incremental; a OpenAI gera isso
    -- internamente via messages, mas mantemos o último valor para que
    -- o Home possa mostrar a memória "viva".
    contexto_atual text not null default '',
    -- status do ciclo de vida: 'em_andamento' | 'concluida' | 'cancelada'.
    status text not null default 'em_andamento'
        check (status in ('em_andamento', 'concluida', 'cancelada')),
    -- etapa: fase atual do Curador (preparado para evolução
    -- futura, hoje sempre 'conversa').
    etapa text not null default 'conversa',
    -- total_turnos: contador de pares user/assistant (incrementa por
    -- turno do usuário).
    total_turnos integer not null default 0,
    -- se preenchido, é a FK da memoria que essa sessão já gerou
    -- (Sprint I — modo complemento) ou que será gerada ao finalizar.
    -- Nullable para sessões que ainda não geraram memória.
    memoria_id bigint references public.memorias(id) on delete set null,
    -- metadata: data_evento da memória (para o prompt) + pessoas
    -- vinculadas (snapshot, não relacionado a `conteudo_permissoes`).
    data_evento date,
    pessoas_json jsonb not null default '[]'::jsonb,
    criado_em timestamp without time zone not null default now(),
    atualizado_em timestamp without time zone not null default now()
);

-- Trigger para manter `atualizado_em` sempre consistente.
create or replace function public.tg_curador_sessoes_updated()
returns trigger
language plpgsql
as $$
begin
    new.atualizado_em = now();
    return new;
end;
$$;

drop trigger if exists trg_curador_sessoes_updated on public.curador_sessoes;
create trigger trg_curador_sessoes_updated
    before update on public.curador_sessoes
    for each row
    execute function public.tg_curador_sessoes_updated();

-- Constraint: 1 sessão em_andamento por usuario (evita sessões zumbis).
drop index if exists uq_curador_sessoes_em_andamento_por_usuario;
create unique index uq_curador_sessoes_em_andamento_por_usuario
    on public.curador_sessoes (usuario_id)
    where status = 'em_andamento';

create index if not exists idx_curador_sessoes_status
    on public.curador_sessoes (usuario_id, status, atualizado_em desc);

comment on table public.curador_sessoes is
    'Sprint J: sessões do Curador Contextual. Cada conversa com o Curador é uma sessão com histórico de mensagens. Permite retomar de onde parou.';
comment on column public.curador_sessoes.contexto_inicial is
    'Texto que o usuário já tinha digitado antes de abrir o Curador (rascunho).';
comment on column public.curador_sessoes.contexto_atual is
    'Snapshot do contexto à medida que a conversa evolui (atualizado pelo app ao salvar cada turno).';


-- (2) Tabela `curador_mensagens`
create table if not exists public.curador_mensagens (
    id bigserial primary key,
    sessao_id bigint not null references public.curador_sessoes(id) on delete cascade,
    role text not null check (role in ('user', 'assistant', 'system')),
    conteudo text not null,
    ordem integer not null,
    -- metadado opcional: 'pergunta' | 'resposta' | 'finalizacao' (sinal
    -- explícito da IA de que a conversa chegou ao fim).
    tipo text,
    criado_em timestamp without time zone not null default now()
);

-- Constraint: ordem única por sessão.
drop index if exists uq_curador_mensagens_sessao_ordem;
create unique index uq_curador_mensagens_sessao_ordem
    on public.curador_mensagens (sessao_id, ordem);

create index if not exists idx_curador_mensagens_sessao
    on public.curador_mensagens (sessao_id, ordem);

comment on table public.curador_mensagens is
    'Sprint J: histórico de mensagens da conversa do Curador. `role` segue convenção OpenAI (user/assistant/system). `ordem` é sequencial por sessão.';


-- (3) View `curador_sessao_ativa_por_usuario` — 1 sessão em_andamento
-- mais recente por usuário.
drop view if exists public.curador_sessao_ativa_por_usuario;

create view public.curador_sessao_ativa_por_usuario
with (security_invoker = true) as
select
    s.id as sessao_id,
    s.usuario_id,
    s.titulo,
    s.contexto_inicial,
    s.contexto_atual,
    s.total_turnos,
    s.criado_em,
    s.atualizado_em,
    s.data_evento,
    s.pessoas_json,
    s.memoria_id
from public.curador_sessoes s
where s.status = 'em_andamento';

grant select on public.curador_sessao_ativa_por_usuario to anon;

comment on view public.curador_sessao_ativa_por_usuario is
    'Sprint J: view com a sessão ativa (em_andamento) por usuário. Já vem com o índice único garantindo no máximo 1.';


-- (4) Função `curador_salvar_mensagem` — append de uma mensagem
-- numa sessão (client usa para gravar cada turno do usuário ou da IA).
-- SECURITY DEFINER: o anon pode chamar.
create or replace function public.curador_salvar_mensagem(
    p_sessao_id bigint,
    p_role text,
    p_conteudo text,
    p_tipo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
    v_ordem integer;
    v_id bigint;
begin
    -- Próxima ordem = max(ordem)+1, ou 1 se vazio.
    select coalesce(max(ordem), 0) + 1
      into v_ordem
      from public.curador_mensagens
      where sessao_id = p_sessao_id;

    insert into public.curador_mensagens (sessao_id, role, conteudo, ordem, tipo)
    values (p_sessao_id, p_role, p_conteudo, v_ordem, p_tipo)
    returning id into v_id;

    -- Atualiza o contexto_atual com a última mensagem do usuário
    -- (se for uma resposta) ou mantém a da IA (pergunta).
    -- O app envia `conteudo_atual` explicitamente em finalizar_sessao.
    if p_role = 'user' then
        update public.curador_sessoes
        set contexto_atual = p_conteudo,
            total_turnos = total_turnos + 1
        where id = p_sessao_id;
    end if;

    return v_id;
end;
$$;

grant execute on function public.curador_salvar_mensagem(bigint, text, text, text) to anon;


-- (5) Função `curador_finalizar_sessao` — marca como `concluida` e
-- devolve o contexto_atual consolidado. O app envia o contexto
-- completo (montado localmente com a IA).
create or replace function public.curador_finalizar_sessao(
    p_sessao_id bigint,
    p_contexto_atual text,
    p_status text default 'concluida'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.curador_sessoes
    set status = p_status,
        contexto_atual = p_contexto_atual
    where id = p_sessao_id;
end;
$$;

grant execute on function public.curador_finalizar_sessao(bigint, text, text) to anon;


-- (6) Função `curador_cancelar_sessao` — descarta sem finalizar.
create or replace function public.curador_cancelar_sessao(p_sessao_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.curador_sessoes
    set status = 'cancelada'
    where id = p_sessao_id;
end;
$$;

grant execute on function public.curador_cancelar_sessao(bigint) to anon;


-- (7) Função `curador_listar_mensagens` — retorna o histórico completo
-- de uma sessão (ordenado).
create or replace function public.curador_listar_mensagens(p_sessao_id bigint)
returns table (
    id bigint,
    sessao_id bigint,
    role text,
    conteudo text,
    ordem integer,
    tipo text,
    criado_em timestamp without time zone
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select m.id, m.sessao_id, m.role, m.conteudo, m.ordem, m.tipo, m.criado_em
    from public.curador_mensagens m
    where m.sessao_id = p_sessao_id
    order by m.ordem;
end;
$$;

grant execute on function public.curador_listar_mensagens(bigint) to anon;


-- (8) GRANTs + RLS para `curador_sessoes` e `curador_mensagens`
grant select, insert, update, delete on table public.curador_sessoes to anon;
grant usage, select on all sequences in schema public to anon;

alter table public.curador_sessoes enable row level security;

drop policy if exists "mvp anon select curador_sessoes" on public.curador_sessoes;
create policy "mvp anon select curador_sessoes"
    on public.curador_sessoes for select to anon using (true);

drop policy if exists "mvp anon insert curador_sessoes" on public.curador_sessoes;
create policy "mvp anon insert curador_sessoes"
    on public.curador_sessoes for insert to anon with check (true);

drop policy if exists "mvp anon update curador_sessoes" on public.curador_sessoes;
create policy "mvp anon update curador_sessoes"
    on public.curador_sessoes for update to anon using (true);

drop policy if exists "mvp anon delete curador_sessoes" on public.curador_sessoes;
create policy "mvp anon delete curador_sessoes"
    on public.curador_sessoes for delete to anon using (true);

grant select, insert, update, delete on table public.curador_mensagens to anon;

alter table public.curador_mensagens enable row level security;

drop policy if exists "mvp anon select curador_mensagens" on public.curador_mensagens;
create policy "mvp anon select curador_mensagens"
    on public.curador_mensagens for select to anon using (true);

drop policy if exists "mvp anon insert curador_mensagens" on public.curador_mensagens;
create policy "mvp anon insert curador_mensagens"
    on public.curador_mensagens for insert to anon with check (true);

drop policy if exists "mvp anon update curador_mensagens" on public.curador_mensagens;
create policy "mvp anon update curador_mensagens"
    on public.curador_mensagens for update to anon using (true);

drop policy if exists "mvp anon delete curador_mensagens" on public.curador_mensagens;
create policy "mvp anon delete curador_mensagens"
    on public.curador_mensagens for delete to anon using (true);


-- (9) Verificação sugerida (rode manualmente para auditar)
-- select * from curador_sessao_ativa_por_usuario where usuario_id = 2;
-- select * from curador_mensagens where sessao_id = 1 order by ordem;
-- select curador_salvar_mensagem(1, 'user', 'Gravei na praia', 'resposta');
-- select curador_finalizar_sessao(1, 'Contexto consolidado...');
--
-- Resultado esperado: cada chamada registra uma mensagem e
-- atualiza `atualizado_em` automaticamente. Fim.
