-- ============================================================================
-- r3_parte2_view_rpc_rls.sql
-- Sprint R.3 — Parte 2: View, RPCs, indices e RLS
-- ============================================================================
-- Executar DEPOIS de r3_parte1_seed_tipos.sql.
-- ============================================================================

-- 1. View grafo_pessoas_relacionamentos
create or replace view public.grafo_pessoas_relacionamentos
with (security_invoker = true) as
select
    r.id as relacionamento_id,
    r.usuario_id,
    ca.id as pessoa_mais_antiga_id,
    cb.id as pessoa_mais_nova_id,
    r.tipo,
    case
        when r.pessoa_a_id = ca.id then r.relacao_a_para_b
        else r.relacao_b_para_a
    end as rotulo_a,
    case
        when r.pessoa_b_id = cb.id then r.relacao_b_para_a
        else r.relacao_a_para_b
    end as rotulo_b,
    ca.nome as nome_a,
    cb.nome as nome_b,
    r.confirmado, r.observacoes, r.data_inicio, r.data_fim, r.criado_em, r.atualizado_em
from public.pessoas_relacionamentos r
left join public.contatos ca on ca.id = least(r.pessoa_a_id, r.pessoa_b_id)
left join public.contatos cb on cb.id = greatest(r.pessoa_a_id, r.pessoa_b_id);

-- 2. RPC listar_relacionamentos_pessoa
create or replace function public.listar_relacionamentos_pessoa(p_pessoa_id bigint)
returns table (relacionamento_id bigint, outra_pessoa_id bigint, outra_pessoa_nome text,
               tipo text, rotulo_da_outra_para_mim text, rotulo_de_mim_para_outra text,
               confirmado boolean, observacoes text, data_inicio date, data_fim date,
               criado_em timestamp without time zone)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select r.id,
           case when r.pessoa_a_id = p_pessoa_id then r.pessoa_b_id else r.pessoa_a_id end,
           co.nome,
           r.tipo,
           case when r.pessoa_a_id = p_pessoa_id then r.relacao_b_para_a else r.relacao_a_para_b end,
           case when r.pessoa_a_id = p_pessoa_id then r.relacao_a_para_b else r.relacao_b_para_a end,
           r.confirmado, r.observacoes, r.data_inicio, r.data_fim, r.criado_em
    from public.pessoas_relacionamentos r
    inner join public.contatos cr on cr.id = p_pessoa_id
    left join public.contatos co on co.id = case when r.pessoa_a_id = p_pessoa_id then r.pessoa_b_id else r.pessoa_a_id end
    where r.usuario_id = cr.usuario_id
      and (r.pessoa_a_id = p_pessoa_id or r.pessoa_b_id = p_pessoa_id)
    order by r.tipo, r.criado_em desc;
end;
$$;

-- 3. RPC listar_pessoas_com_mesma_relacao
create or replace function public.listar_pessoas_com_mesma_relacao(
    p_usuario_id bigint, p_pessoa_referencia_id bigint, p_tipo text
)
returns table (pessoa_id bigint, nome text, tipo text, relacao_a_para_b text, relacao_b_para_a text)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select cp.id, cp.nome, r.tipo, r.relacao_a_para_b, r.relacao_b_para_a
    from public.pessoas_relacionamentos r
    left join public.contatos cp
        on cp.id = case when r.pessoa_a_id = p_pessoa_referencia_id then r.pessoa_b_id else r.pessoa_a_id end
    where r.usuario_id = p_usuario_id
      and r.tipo = p_tipo
      and (r.pessoa_a_id = p_pessoa_referencia_id or r.pessoa_b_id = p_pessoa_referencia_id);
end;
$$;

-- 4. Indices
create unique index if not exists uq_pessoas_relacionamentos_par_tipo
    on public.pessoas_relacionamentos (usuario_id, pessoa_a_id, pessoa_b_id, tipo);
create unique index if not exists uq_pessoas_relacionamentos_ordenado
    on public.pessoas_relacionamentos (usuario_id, least(pessoa_a_id, pessoa_b_id), greatest(pessoa_a_id, pessoa_b_id), tipo);
create index if not exists idx_pessoas_relacionamentos_a
    on public.pessoas_relacionamentos (pessoa_a_id);
create index if not exists idx_pessoas_relacionamentos_b
    on public.pessoas_relacionamentos (pessoa_b_id);
create index if not exists idx_pessoas_relacionamentos_usuario_tipo
    on public.pessoas_relacionamentos (usuario_id, tipo);

-- 5. RLS
alter table if exists public.pessoas_relacionamentos enable row level security;
alter table if exists public.tipos_relacionamento enable row level security;

drop policy if exists "mvp anon select tipos_relacionamento" on public.tipos_relacionamento;
create policy "mvp anon select tipos_relacionamento"
    on public.tipos_relacionamento for select to anon using (true);

drop policy if exists "mvp anon select pessoas_relacionamentos" on public.pessoas_relacionamentos;
create policy "mvp anon select pessoas_relacionamentos"
    on public.pessoas_relacionamentos for select to anon using (true);
drop policy if exists "mvp anon insert pessoas_relacionamentos" on public.pessoas_relacionamentos;
create policy "mvp anon insert pessoas_relacionamentos"
    on public.pessoas_relacionamentos for insert to anon with check (true);
drop policy if exists "mvp anon update pessoas_relacionamentos" on public.pessoas_relacionamentos;
create policy "mvp anon update pessoas_relacionamentos"
    on public.pessoas_relacionamentos for update to anon using (true);
drop policy if exists "mvp anon delete pessoas_relacionamentos" on public.pessoas_relacionamentos;
create policy "mvp anon delete pessoas_relacionamentos"
    on public.pessoas_relacionamentos for delete to anon using (true);

-- 6. GRANTs
grant select on public.tipos_relacionamento to anon;
grant select, insert, update, delete on public.pessoas_relacionamentos to anon;
grant select on public.grafo_pessoas_relacionamentos to anon;
grant execute on function public.listar_relacionamentos_pessoa to anon;
grant execute on function public.listar_pessoas_com_mesma_relacao to anon;

-- Validacao
-- SELECT * FROM public.grafo_pessoas_relacionamentos WHERE usuario_id = <SEU_ID>;
-- SELECT * FROM public.listar_relacionamentos_pessoa(<PESSOA_ID>);
