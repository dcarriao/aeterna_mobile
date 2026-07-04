-- ============================================================================
-- SPRINT K — HISTÓRIAS RELACIONADAS E MAPA DA VIDA
-- ============================================================================
-- Arquitetura escolhida (confirmada com o usuário):
--   * A VIEW/RPC serve APENAS para encontrar CANDIDATAS rapidamente
--     (mesmo usuário, pessoas em comum, datas próximas, mesmo título).
--   * O SCORE é calculado no client (service Dart) — heurísticas puras.
--   * Só os relacionamentos com score >= threshold são PERSISTIDOS.
--   * Ao abrir uma memória, o app só lê da tabela
--     `memoria_relacionamentos` (sem O(n²)).
--   * Quando uma memória é criada/editada/recebe contribuição, o app
--     recalcula APENAS para aquela memória (incremental).
--
-- Este script:
--   1. Cria a tabela `memoria_relacionamentos` (relação confirmada).
--   2. Cria a função `buscar_candidatas_relacionamento(memoria_id,
--      limite)` que faz o trabalho pesado de JOINs no servidor.
--   3. Cria triggers em `memorias` (insert/update) que invalidam
--      relacionamentos antigos (cascade) — sem isso, uma memória
--      editada continuaria ligada a uma versão antiga.
--   4. Cria uma view `memorias_resumo_leve` (sem `conteudo` completo)
--      para a Home/Timeline carregarem rápido.
--   5. Adiciona 1 índice funcional em `memorias.titulo` (trigram)
--      para acelerar match por título sem IA.
--   6. GRANTs + RLS no padrão MVP.
-- ============================================================================


-- (1) Tabela `memoria_relacionamentos`
--    Relação IMPLÍCITA (calculada por heurística, mas persistida) entre
--    duas memórias do MESMO usuário. NÃO duplica conteúdo — guarda
--    apenas metadados: origem, destino, score, motivos (jsonb),
--    status (confirmado | pendente | ignorado).
create table if not exists public.memoria_relacionamentos (
    id bigserial primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    memoria_origem_id bigint not null references public.memorias(id) on delete cascade,
    memoria_destino_id bigint not null references public.memorias(id) on delete cascade,
    -- score numerico de 0-100. Quanto maior, mais forte a relacao.
    score integer not null check (score between 0 and 100),
    -- motivos em jsonb. Ex: {"mesma_pessoa": true, "mesmo_mes": true,
    -- "mesmo_local": "Torres", "mesmo_titulo": false}.
    motivos jsonb not null default '{}'::jsonb,
    -- status: 'pendente' (sugerido, aguardando confirmacao do usuario),
    -- 'confirmado' (usuario aceitou), 'ignorado' (usuario rejeitou).
    status text not null default 'pendente'
        check (status in ('pendente', 'confirmado', 'ignorado')),
    criado_em timestamp without time zone not null default now(),
    atualizado_em timestamp without time zone not null default now(),
    -- Nao faz sentido ter a mesma relacao duplicada (origem+destino).
    constraint ck_memoria_relacionamentos_distintas
        check (memoria_origem_id <> memoria_destino_id)
);

-- Garante 1 relacao por par (origem, destino).
drop index if exists uq_memoria_relacionamentos_par;
create unique index uq_memoria_relacionamentos_par
    on public.memoria_relacionamentos (memoria_origem_id, memoria_destino_id);

-- Indices para query "todas as relacoes de uma memoria".
create index if not exists idx_memoria_relacionamentos_origem
    on public.memoria_relacionamentos (memoria_origem_id, status, score desc);
create index if not exists idx_memoria_relacionamentos_destino
    on public.memoria_relacionamentos (memoria_destino_id, status);
create index if not exists idx_memoria_relacionamentos_usuario_pendentes
    on public.memoria_relacionamentos (usuario_id, status, atualizado_em desc)
    where status = 'pendente';

comment on table public.memoria_relacionamentos is
    'Sprint K: relacoes IMPLICITAS entre memorias do mesmo usuario, calculadas por heuristica client-side e persistidas aqui. NUNCA duplica conteudo. Cacheia o trabalho de O(n) por memoria em vez de O(n²) na base.';


-- (2) Trigger: atualiza `atualizado_em` em updates.
create or replace function public.tg_memoria_relacionamentos_updated()
returns trigger language plpgsql as $$
begin
    new.atualizado_em = now();
    return new;
end;
$$;

drop trigger if exists trg_memoria_relacionamentos_updated
    on public.memoria_relacionamentos;
create trigger trg_memoria_relacionamentos_updated
    before update on public.memoria_relacionamentos
    for each row execute function public.tg_memoria_relacionamentos_updated();


-- (3) Trigger em `memorias`: quando a memoria e editada/excluida,
--     as relacoes antigas dela sao limpas (cascade via FK ja cuida de
--     DELETE; para UPDATE, invalidamos `atualizado_em` da relacao
--     para que o client saiba que precisa recalcular).
create or replace function public.tg_memoria_invalida_relacionamentos()
returns trigger language plpgsql as $$
begin
    if (tg_op = 'UPDATE') then
        -- Nao apagamos as relacoes — apenas marcamos a relacao como
        -- pendente de recalculo via `atualizado_em` mais antigo.
        update public.memoria_relacionamentos
        set atualizado_em = now() - interval '1 year'
        where (memoria_origem_id = new.id or memoria_destino_id = new.id)
          and status = 'pendente';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_memorias_invalida_relacionamentos
    on public.memorias;
create trigger trg_memorias_invalida_relacionamentos
    after update on public.memorias
    for each row execute function public.tg_memoria_invalida_relacionamentos();


-- (4) Função `buscar_candidatas_relacionamento(memoria_id, limite)`.
--     Retorna memorias do MESMO usuario que são candidatas a se
--     relacionar com a `memoria_id`, com 3 sinais de score pré-computados:
--       - pessoas em comum (via conteudo_permissoes)
--       - proximidade temporal (data_evento dentro de 60 dias)
--       - mesmo título (ILIKE normalizado)
--     O client Dart usa isso para fazer o score fino e decidir o que
--     persiste. SECURITY DEFINER para que o anon possa chamar.
create or replace function public.buscar_candidatas_relacionamento(
    p_memoria_id bigint,
    p_limite int default 30
)
returns table (
    id bigint,
    titulo text,
    categoria text,
    data_evento date,
    criada_em timestamp without time zone,
    -- Quantas pessoas a candidata compartilha com a memoria_id.
    pessoas_em_comum integer,
    -- Dias de diferenca entre data_evento (absoluto, 0 = mesmo dia).
    dias_diferenca_evento integer,
    -- Indica match de titulo por normalizacao.
    mesmo_titulo boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_usuario_id bigint;
    v_titulo_norm text;
    v_data_evento date;
begin
    select m.usuario_id, lower(trim(m.titulo)), m.data_evento
      into v_usuario_id, v_titulo_norm, v_data_evento
      from public.memorias m
      where m.id = p_memoria_id;

    if v_usuario_id is null then
        return;
    end if;

    return query
    select
        m.id, m.titulo, m.categoria, m.data_evento, m.criado_em,
        coalesce((
            select count(distinct cp.contato_id)::int
            from public.conteudo_permissoes cp
            where cp.tipo_conteudo = 'memoria'
              and cp.conteudo_id = m.id
              and cp.contato_id in (
                  select cp2.contato_id
                  from public.conteudo_permissoes cp2
                  where cp2.tipo_conteudo = 'memoria'
                    and cp2.conteudo_id = p_memoria_id
              )
        ), 0) as pessoas_em_comum,
        case
            when v_data_evento is null or m.data_evento is null then null
            else abs((m.data_evento - v_data_evento)::int)
        end as dias_diferenca_evento,
        (v_titulo_norm is not null
         and v_titulo_norm <> ''
         and lower(trim(m.titulo)) = v_titulo_norm) as mesmo_titulo
    from public.memorias m
    where m.usuario_id = v_usuario_id
      and m.id <> p_memoria_id
    order by
        pessoas_em_comum desc,
        case when dias_diferenca_evento is null then 1 else 0 end,
        dias_diferenca_evento asc nulls last,
        m.criado_em desc
    limit p_limite;
end;
$$;

grant execute on function public.buscar_candidatas_relacionamento(bigint, int) to anon;


-- (5) View `memorias_resumo_leve` — snapshot sem o `conteudo` completo.
--     Usada pela Home/Timeline para reduzir tráfego de rede.
drop view if exists public.memorias_resumo_leve;

create view public.memorias_resumo_leve
with (security_invoker = true) as
select
    m.id, m.usuario_id, m.titulo, m.categoria,
    m.data_evento, m.criado_em, m.ultima_atualizacao_em, m.aprovacao_obrigatoria,
    -- Tamanho do conteudo (em chars) — util para a UI mostrar
    -- "historia longa" / "rascunho curto" sem baixar tudo.
    length(coalesce(m.conteudo, '')) as tamanho_conteudo,
    -- Flag: existe alguma relacao CONFIRMADA envolvendo esta memoria.
    exists (
        select 1 from public.memoria_relacionamentos r
        where (r.memoria_origem_id = m.id or r.memoria_destino_id = m.id)
          and r.status = 'confirmado'
    ) as tem_relacionamentos_confirmados,
    -- Contagem de candidatos PENDENTES (ainda nao confirmados).
    (select count(*) from public.memoria_relacionamentos r
     where (r.memoria_origem_id = m.id or r.memoria_destino_id = m.id)
       and r.status = 'pendente') as total_relacionamentos_pendentes
from public.memorias m;

grant select on public.memorias_resumo_leve to anon;

comment on view public.memorias_resumo_leve is
    'Sprint K: snapshot leve das memorias (sem o `conteudo` longo) para Home/Timeline. Inclui contadores de relacionamentos.';


-- (6) Índice funcional em `memorias.titulo` (trigram, case-insensitive).
--     Pré-requisito: `CREATE EXTENSION pg_trgm` (geralmente já habilitado
--     em Supabase; se não, rodar manualmente antes deste script).
create index if not exists idx_memorias_titulo_trgm
    on public.memorias using gin (lower(titulo) gin_trgm_ops);


-- (7) GRANTs + RLS no padrão MVP anônimo.
grant select, insert, update, delete on table public.memoria_relacionamentos to anon;

alter table public.memoria_relacionamentos enable row level security;

drop policy if exists "mvp anon select memoria_relacionamentos" on public.memoria_relacionamentos;
create policy "mvp anon select memoria_relacionamentos"
    on public.memoria_relacionamentos for select to anon using (true);

drop policy if exists "mvp anon insert memoria_relacionamentos" on public.memoria_relacionamentos;
create policy "mvp anon insert memoria_relacionamentos"
    on public.memoria_relacionamentos for insert to anon with check (true);

drop policy if exists "mvp anon update memoria_relacionamentos" on public.memoria_relacionamentos;
create policy "mvp anon update memoria_relacionamentos"
    on public.memoria_relacionamentos for update to anon using (true);

drop policy if exists "mvp anon delete memoria_relacionamentos" on public.memoria_relacionamentos;
create policy "mvp anon delete memoria_relacionamentos"
    on public.memoria_relacionamentos for delete to anon using (true);


-- (8) Verificação sugerida (rode manualmente para auditar)
-- select * from public.buscar_candidatas_relacionamento(2, 10);
-- select * from public.memorias_resumo_leve where usuario_id = 2 limit 5;
-- select * from public.memoria_relacionamentos where usuario_id = 2;
--
-- Fim.
