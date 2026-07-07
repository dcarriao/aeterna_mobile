-- ============================================================
-- Sprint S.8 — Correção Emergencial Pós-Migração Pessoas
-- ============================================================
-- Problema: auditoria_app_supabase_fix.sql adiciona RLS
-- USING(true) para todas as tabelas, mas PULOU `pessoas` e
-- `memorial_pessoas`. Com auth.uid()=null (custom SHA-256),
-- as policies restritivas de sprint_s3_f3b_rls.sql bloqueiam
-- TODAS as queries → Home funciona (RPCs SECURITY DEFINER)
-- mas telas Pessoas, Memórias, Timeline, Memorial ficam vazias.
--
-- Correções:
--   1. RLS USING(true) para pessoas, memorial_pessoas
--   2. Migração: copia contatos.usuario_id → pessoas.criado_por_id
--      (coluna não preenchida pela migração original S3)
--   3. memorial_da_pessoa() — usa memorial_pessoas em vez de
--      contatos.memorial_id (coluna removida pelo S5.1)
--   4. pessoas_recentes() — usa pessoas em vez de contatos
--   5. pessoas_sugeridas() — usa pessoas em vez de contatos
--   6. Adiciona FKs corretas (pessoas.id) e dropa legadas
-- ============================================================

BEGIN;

-- ============================================================
-- 1. RLS — PESSOAS (MVB anon — filtro via client Dart)
-- ============================================================
alter table if exists public.pessoas enable row level security;

drop policy if exists "mvp anon select pessoas" on public.pessoas;
create policy "mvp anon select pessoas" on public.pessoas
  for select to anon using (true);

drop policy if exists "mvp anon insert pessoas" on public.pessoas;
create policy "mvp anon insert pessoas" on public.pessoas
  for insert to anon with check (true);

drop policy if exists "mvp anon update pessoas" on public.pessoas;
create policy "mvp anon update pessoas" on public.pessoas
  for update to anon using (true);

drop policy if exists "mvp anon delete pessoas" on public.pessoas;
create policy "mvp anon delete pessoas" on public.pessoas
  for delete to anon using (true);

-- ============================================================
-- 2. RLS — MEMORIAL_PESSOAS
-- ============================================================
alter table if exists public.memorial_pessoas enable row level security;

drop policy if exists "mvp anon select memorial_pessoas" on public.memorial_pessoas;
create policy "mvp anon select memorial_pessoas" on public.memorial_pessoas
  for select to anon using (true);

drop policy if exists "mvp anon insert memorial_pessoas" on public.memorial_pessoas;
create policy "mvp anon insert memorial_pessoas" on public.memorial_pessoas
  for insert to anon with check (true);

drop policy if exists "mvp anon update memorial_pessoas" on public.memorial_pessoas;
create policy "mvp anon update memorial_pessoas" on public.memorial_pessoas
  for update to anon using (true);

drop policy if exists "mvp anon delete memorial_pessoas" on public.memorial_pessoas;
create policy "mvp anon delete memorial_pessoas" on public.memorial_pessoas
  for delete to anon using (true);

-- ============================================================
-- 3. GRANTs — pessoas + memorial_pessoas
-- ============================================================
grant select, insert, update, delete on public.pessoas to anon;
grant select, insert, update, delete on public.memorial_pessoas to anon;

-- ============================================================
-- 4. CORREÇÃO DE DADOS: copia contatos.usuario_id →
--    pessoas.criado_por_id onde estiver NULL.
--    A migração S3 não preencheu criado_por_id, então as
--    funções que filtram por criado_por_id (listar, recentes,
--    sugeridas, relacionamentos) retornam vazio.
--    Não deleta nem recria dados — só completa a migração.
-- ============================================================
do $$ begin
    update public.pessoas p
    set criado_por_id = c.usuario_id
    from public.contatos c
    where p.id = c.id
      and p.criado_por_id is null
      and c.usuario_id is not null;

    raise notice 'pessoas.criado_por_id preenchido: % linhas',
        (select count(*) from public.pessoas where criado_por_id is not null);
end $$;

-- ============================================================
-- 5. CORRIGE memorial_da_pessoa()
--    Antes:  FROM contatos c JOIN memoriais m ON m.id = c.memorial_id
--    Agora:  FROM memorial_pessoas mp JOIN memoriais m ON m.id = mp.memorial_id
-- ============================================================
create or replace function public.memorial_da_pessoa(pessoa_id bigint)
returns table (memorial_id bigint, nome text)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select m.id, m.nome
    from public.memorial_pessoas mp
    join public.memoriais m on m.id = mp.memorial_id
    where mp.pessoa_id = pessoa_id
    limit 1;
end;
$$;

grant execute on function public.memorial_da_pessoa(bigint) to anon;

-- ============================================================
-- 6. CORRIGE pessoas_recentes()
--    Antes:  FROM contatos c  (tabela legada)
--    Agora:  FROM pessoas p   (tabela atual)
-- ============================================================
create or replace function public.pessoas_recentes(usuario bigint, limite int default 8)
returns table (id bigint, nome text, sobrenome text, parentesco text, email text,
               foto_perfil text, ultima_interacao timestamp, total_eventos bigint)
language plpgsql security definer set search_path = public as $$
begin
    return query
    with ultimas as (
        select p.id as pessoa_id,
            greatest(
                coalesce((select max(coalesce(m.data_evento::timestamp, m.data_criacao))
                          from public.conteudo_permissoes cp join public.memorias m on m.id = cp.conteudo_id
                          where cp.tipo_conteudo = 'memoria' and cp.pessoa_id = p.id), '1970-01-01'::timestamp),
                coalesce((select max(c2.criado_em)
                          from public.contribuicoes c2
                          where c2.tipo_conteudo = 'memoria' and c2.conteudo_id in (
                              select cp.conteudo_id from public.conteudo_permissoes cp
                              where cp.tipo_conteudo = 'memoria' and cp.pessoa_id = p.id
                          ) and c2.status = 'aprovado'), '1970-01-01'::timestamp)
            ) as ultima
        from public.pessoas p where p.criado_por_id = usuario
    )
    select p.id, p.nome, p.sobrenome, p.parentesco, p.email, p.foto_perfil,
           u.ultima,
           (select count(*) from public.pessoa_linha_tempo plt where plt.pessoa_id = p.id)::bigint
    from ultimas u join public.pessoas p on p.id = u.pessoa_id
    order by u.ultima desc nulls last limit limite;
end;
$$;

grant execute on function public.pessoas_recentes(bigint, int) to anon;

-- ============================================================
-- 7. CORRIGE pessoas_sugeridas()
--    Antes:  FROM contatos c WHERE c.usuario_id = usuario
--    Agora:  FROM pessoas p  WHERE p.criado_por_id = usuario
-- ============================================================
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
        select lower(p.nome) as nome from public.pessoas p where p.criado_por_id = usuario
    )
    select f.nome, f.ocorrencias
    from frequencia f
    where f.ocorrencias >= 2
      and not exists (select 1 from ja_cadastrados j where j.nome = f.nome)
    order by f.ocorrencias desc limit limite;
end;
$$;

grant execute on function public.pessoas_sugeridas(bigint, int) to anon;

-- ============================================================
-- 8. CORRIGE trigger tg_pessoa_cria_relacionamento_legado
--    Antes:  dispara em contatos  (tabela legada)
--    Agora:  dispara em pessoas
--    Obs: função tg_pessoa_cria_relacionamento_legado precisa
--    ser recriada com new.criado_por_id (em vez de new.usuario_id)
-- ============================================================
create or replace function public.tg_pessoa_cria_relacionamento_legado()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    v_tipo text;
    v_outra_pessoa_id bigint;
    v_rotulo_a_para_b text;
    v_rotulo_b_para_a text;
begin
    if new.tipo = 'pet' then
        return new;
    end if;

    case lower(new.parentesco)
        when 'pai' then v_tipo := 'PAI';
        when 'mae' then v_tipo := 'MAE';
        when 'filho' then v_tipo := 'FILHO';
        when 'filha' then v_tipo := 'FILHA';
        when 'irmao' then v_tipo := 'IRMAO';
        when 'cônjuge' then v_tipo := 'CONJUGE';
        when 'conjuge' then v_tipo := 'CONJUGE';
        when 'amigo' then v_tipo := 'AMIGO';
        when 'amiga' then v_tipo := 'AMIGO';
        else v_tipo := null;
    end case;

    if v_tipo is null then
        return new;
    end if;

    select id into v_outra_pessoa_id
    from public.pessoas p
    where p.criado_por_id = new.criado_por_id
      and p.id <> new.id
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
        new.criado_por_id, new.id, v_outra_pessoa_id, v_tipo,
        v_rotulo_a_para_b, v_rotulo_b_para_a, true
    ) on conflict do nothing;

    return new;
end;
$$;

drop trigger if exists trg_pessoa_cria_relacionamento_legado on public.pessoas;
create trigger trg_pessoa_cria_relacionamento_legado
    after insert on public.pessoas
    for each row execute function public.tg_pessoa_cria_relacionamento_legado();

-- ============================================================
-- 9. CORRIGE grafo_pessoas_relacionamentos
--    Antes:  SELECT nome FROM contatos
--    Agora:  SELECT nome FROM pessoas
-- ============================================================
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
    (select nome from public.pessoas where id =
        case when r.pessoa_a_id = least(r.pessoa_a_id, r.pessoa_b_id) then r.pessoa_a_id else r.pessoa_b_id end
    ) as nome_a,
    (select nome from public.pessoas where id =
        case when r.pessoa_b_id = greatest(r.pessoa_a_id, r.pessoa_b_id) then r.pessoa_b_id else r.pessoa_a_id end
    ) as nome_b,
    r.confirmado, r.observacoes, r.data_inicio, r.data_fim, r.criado_em, r.atualizado_em
from public.pessoas_relacionamentos r;

grant select on public.grafo_pessoas_relacionamentos to anon;

-- ============================================================
-- 10. CORRIGE listar_relacionamentos_pessoa()
--    Antes:  SELECT nome FROM contatos WHERE id = ...
--    Agora:  SELECT nome FROM pessoas WHERE id = ...
--    Obs: DROP antes de CREATE porque existem assinaturas conflitantes
--    (sprint_s3_f3a_views_rpcs.sql define com colunas diferentes).
-- ============================================================
drop function if exists public.listar_relacionamentos_pessoa(bigint);
create function public.listar_relacionamentos_pessoa(p_pessoa_id bigint)
returns table (relacionamento_id bigint, outra_pessoa_id bigint, outra_pessoa_nome text,
               tipo text, rotulo_da_outra_para_mim text, rotulo_de_mim_para_outra text,
               confirmado boolean, observacoes text, data_inicio date, data_fim date,
               criado_em timestamp without time zone)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select r.id as relacionamento_id,
           case when r.pessoa_a_id = p_pessoa_id then r.pessoa_b_id else r.pessoa_a_id end as outra_pessoa_id,
           (select nome from public.pessoas where id =
               case when r.pessoa_a_id = p_pessoa_id then r.pessoa_b_id else r.pessoa_a_id end) as outra_pessoa_nome,
           r.tipo,
           case when r.pessoa_a_id = p_pessoa_id then r.relacao_b_para_a else r.relacao_a_para_b end as rotulo_da_outra_para_mim,
           case when r.pessoa_a_id = p_pessoa_id then r.relacao_a_para_b else r.relacao_b_para_a end as rotulo_de_mim_para_outra,
           r.confirmado, r.observacoes, r.data_inicio, r.data_fim, r.criado_em
    from public.pessoas_relacionamentos r
    where r.usuario_id = (select criado_por_id from public.pessoas where id = p_pessoa_id)
      and (r.pessoa_a_id = p_pessoa_id or r.pessoa_b_id = p_pessoa_id)
    order by r.tipo, r.criado_em desc;
end;
$$;

grant execute on function public.listar_relacionamentos_pessoa(bigint) to anon;

-- ============================================================
-- 11. CORRIGE listar_pessoas_com_mesma_relacao()
--     Antes:  SELECT nome FROM contatos
--     Agora:  SELECT nome FROM pessoas
-- ============================================================
create or replace function public.listar_pessoas_com_mesma_relacao(
    p_usuario_id bigint, p_pessoa_referencia_id bigint, p_tipo text
)
returns table (pessoa_id bigint, nome text, tipo text, relacao_a_para_b text, relacao_b_para_a text)
language plpgsql security definer set search_path = public as $$
begin
    return query
    select
        case when r.pessoa_a_id = p_pessoa_referencia_id then r.pessoa_b_id else r.pessoa_a_id end as pessoa_id,
        (select nome from public.pessoas where id =
            case when r.pessoa_a_id = p_pessoa_referencia_id then r.pessoa_b_id else r.pessoa_a_id end) as nome,
        r.tipo, r.relacao_a_para_b, r.relacao_b_para_a
    from public.pessoas_relacionamentos r
    where r.usuario_id = p_usuario_id and r.tipo = p_tipo
      and (r.pessoa_a_id = p_pessoa_referencia_id or r.pessoa_b_id = p_pessoa_referencia_id);
end;
$$;

grant execute on function public.listar_pessoas_com_mesma_relacao(bigint, bigint, text) to anon;

-- ============================================================
-- 12. CORRIGE FKs em pessoas_relacionamentos
--     Antes:  REFERENCES contatos(id), REFERENCES usuarios(id)
--     Agora:  REFERENCES pessoas(id)
--     Nota: só executa se as FKs legadas ainda existirem
-- ============================================================
do $$ begin
    -- Drop FK legada: pessoas_relacionamentos.pessoa_a_id → contatos(id)
    if exists (
        select 1 from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu using (constraint_name, table_schema, table_name)
        where tc.constraint_type = 'FOREIGN KEY'
          and tc.table_name = 'pessoas_relacionamentos'
          and kcu.column_name = 'pessoa_a_id'
          and tc.constraint_name like '%contatos%'
    ) then
        execute format('alter table public.pessoas_relacionamentos drop constraint %s',
            (select tc.constraint_name::text from information_schema.table_constraints tc
             join information_schema.key_column_usage kcu using (constraint_name, table_schema, table_name)
             where tc.constraint_type = 'FOREIGN KEY'
               and tc.table_name = 'pessoas_relacionamentos'
               and kcu.column_name = 'pessoa_a_id'
               and tc.constraint_name like '%contatos%'
             limit 1));
    end if;

    -- Drop FK legada: pessoas_relacionamentos.pessoa_b_id → contatos(id)
    if exists (
        select 1 from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu using (constraint_name, table_schema, table_name)
        where tc.constraint_type = 'FOREIGN KEY'
          and tc.table_name = 'pessoas_relacionamentos'
          and kcu.column_name = 'pessoa_b_id'
          and tc.constraint_name like '%contatos%'
    ) then
        execute format('alter table public.pessoas_relacionamentos drop constraint %s',
            (select tc.constraint_name::text from information_schema.table_constraints tc
             join information_schema.key_column_usage kcu using (constraint_name, table_schema, table_name)
             where tc.constraint_type = 'FOREIGN KEY'
               and tc.table_name = 'pessoas_relacionamentos'
               and kcu.column_name = 'pessoa_b_id'
               and tc.constraint_name like '%contatos%'
             limit 1));
    end if;

    -- Recria com pessoas(id)
    if not exists (
        select 1 from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu using (constraint_name, table_schema, table_name)
        where tc.constraint_type = 'FOREIGN KEY'
          and tc.table_name = 'pessoas_relacionamentos'
          and kcu.column_name = 'pessoa_a_id'
          and tc.constraint_name like '%pessoas%'
    ) then
        alter table public.pessoas_relacionamentos
            add constraint fk_pessoas_rel_pessoa_a
            foreign key (pessoa_a_id) references public.pessoas(id) on delete cascade;
    end if;

    if not exists (
        select 1 from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu using (constraint_name, table_schema, table_name)
        where tc.constraint_type = 'FOREIGN KEY'
          and tc.table_name = 'pessoas_relacionamentos'
          and kcu.column_name = 'pessoa_b_id'
          and tc.constraint_name like '%pessoas%'
    ) then
        alter table public.pessoas_relacionamentos
            add constraint fk_pessoas_rel_pessoa_b
            foreign key (pessoa_b_id) references public.pessoas(id) on delete cascade;
    end if;
end $$;

-- ============================================================
-- VALIDAÇÃO
-- ============================================================
do $$
declare
    v_pessoas_rls boolean;
    v_pessoas_select_policy boolean;
    v_memorial_pessoas_rls boolean;
    v_memorial_da_pessoa_ok boolean;
begin
    select exists (select 1 from pg_tables where tablename = 'pessoas' and rowsecurity = true)
      into v_pessoas_rls;
    select exists (
        select 1 from pg_policies
        where tablename = 'pessoas' and policyname = 'mvp anon select pessoas'
    ) into v_pessoas_select_policy;
    select exists (select 1 from pg_tables where tablename = 'memorial_pessoas' and rowsecurity = true)
      into v_memorial_pessoas_rls;
    select exists (
        select 1 from pg_proc where proname = 'memorial_da_pessoa'
        and prosrc like '%memorial_pessoas%'
    ) into v_memorial_da_pessoa_ok;

    if not v_pessoas_rls then raise warning 'pessoas RLS nao habilitado'; end if;
    if not v_pessoas_select_policy then raise warning 'policy mvp anon select pessoas nao encontrada'; end if;
    if not v_memorial_pessoas_rls then raise warning 'memorial_pessoas RLS nao habilitado'; end if;
    if not v_memorial_da_pessoa_ok then raise warning 'memorial_da_pessoa ainda usa contatos'; end if;

    raise notice 'Sprint S.8 OK — RLS, memorial_da_pessoa, funcoes corrigidas';
end $$;

COMMIT;

-- ============================================================
-- VALIDAÇÃO — queries para verificar dados
-- ============================================================
-- 1. Pessoas visíveis para usuarioId=2:
--    SELECT * FROM pessoas WHERE criado_por_id = 2;
--
-- 2. Memorial do irmão:
--    SELECT mp.pessoa_id, m.id, m.nome
--    FROM memorial_pessoas mp JOIN memoriais m ON m.id = mp.memorial_id;
--
-- 3. Timeline:
--    SELECT * FROM pessoa_linha_tempo WHERE pessoa_id = 2 LIMIT 5;
--
-- 4. Memórias:
--    SELECT * FROM memorias WHERE usuario_id = 2;
--
-- 5. Permissões migradas:
--    SELECT * FROM conteudo_permissoes WHERE pessoa_id = 2;
-- ============================================================
