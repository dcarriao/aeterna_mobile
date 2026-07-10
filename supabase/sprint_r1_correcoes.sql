-- ============================================================================
-- Sprint R.1 — Correções críticas pós-Sprint R (bugs TestFlight iOS)
-- ============================================================================
-- Corrige:
--   1. RLS policies das tabelas do Sprint O: troca auth.uid() por USING(true)
--      (o app usa auth custom SHA-256+salt, não Supabase Auth — auth.uid()
--       retorna null, bloqueando todas as queries)
--   2. Adiciona coluna destinatario_id + FK em mensagens_futuro
-- ============================================================================

-- 1. CORREÇÃO RLS — todas as tabelas do Sprint O
--    Usam USING(true) / WITH CHECK(true), mesmo padrão do Sprint L
--    (pessoas_relacionamentos). A filtragem por usuario_id é feita
--    exclusivamente via .eq('usuario_id', ...) no cliente.
--
--    Cada bloco DO verifica se a tabela existe antes de alterar
--    policies, evitando erro 42P01 se a tabela ainda não foi criada.

do $$ begin
  if exists (select from pg_tables where schemaname='public' and tablename='quem_sou_eu') then
    drop policy if exists "quem_sou_eu_select" on public.quem_sou_eu;
    drop policy if exists "quem_sou_eu_insert" on public.quem_sou_eu;
    drop policy if exists "quem_sou_eu_update" on public.quem_sou_eu;
    drop policy if exists "quem_sou_eu_delete" on public.quem_sou_eu;

    create policy "quem_sou_eu_select" on public.quem_sou_eu
      for select to anon using (true);
    create policy "quem_sou_eu_insert" on public.quem_sou_eu
      for insert to anon with check (true);
    create policy "quem_sou_eu_update" on public.quem_sou_eu
      for update to anon using (true);
    create policy "quem_sou_eu_delete" on public.quem_sou_eu
      for delete to anon using (true);
    raise notice 'quem_sou_eu RLS atualizado';
  end if;
end $$;

do $$ begin
  if exists (select from pg_tables where schemaname='public' and tablename='mensagens_futuro') then
    drop policy if exists "mensagens_futuro_select" on public.mensagens_futuro;
    drop policy if exists "mensagens_futuro_insert" on public.mensagens_futuro;
    drop policy if exists "mensagens_futuro_update" on public.mensagens_futuro;
    drop policy if exists "mensagens_futuro_delete" on public.mensagens_futuro;

    create policy "mensagens_futuro_select" on public.mensagens_futuro
      for select to anon using (true);
    create policy "mensagens_futuro_insert" on public.mensagens_futuro
      for insert to anon with check (true);
    create policy "mensagens_futuro_update" on public.mensagens_futuro
      for update to anon using (true);
    create policy "mensagens_futuro_delete" on public.mensagens_futuro
      for delete to anon using (true);
    raise notice 'mensagens_futuro RLS atualizado';
  end if;
end $$;

do $$ begin
  if exists (select from pg_tables where schemaname='public' and tablename='cofre_itens') then
    drop policy if exists "cofre_itens_select" on public.cofre_itens;
    drop policy if exists "cofre_itens_insert" on public.cofre_itens;
    drop policy if exists "cofre_itens_update" on public.cofre_itens;
    drop policy if exists "cofre_itens_delete" on public.cofre_itens;

    create policy "cofre_itens_select" on public.cofre_itens
      for select to anon using (true);
    create policy "cofre_itens_insert" on public.cofre_itens
      for insert to anon with check (true);
    create policy "cofre_itens_update" on public.cofre_itens
      for update to anon using (true);
    create policy "cofre_itens_delete" on public.cofre_itens
      for delete to anon using (true);
    raise notice 'cofre_itens RLS atualizado';
  end if;
end $$;


-- 2. DESTINATARIO_ID em mensagens_futuro
do $$ begin
  if exists (select from pg_tables where schemaname='public' and tablename='mensagens_futuro') then
    alter table public.mensagens_futuro
      add column if not exists destinatario_id bigint
      references public.contatos(id) on delete set null;

    create index if not exists idx_mensagens_futuro_destinatario
      on public.mensagens_futuro (destinatario_id);
    raise notice 'destinatario_id adicionado em mensagens_futuro';
  end if;
end $$;


-- 3. GRANTs
grant usage on all sequences in schema public to anon;

-- Fim.
