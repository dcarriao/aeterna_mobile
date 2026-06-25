-- Políticas TEMPORÁRIAS para o MVP sem autenticação real.
-- Restritas ao usuario_id = 2 e ao diretório usuario_2/app_mobile.
-- Remover quando Supabase Auth for implementado.

grant usage on schema public to anon;
grant select, insert, delete on table public.memorias to anon;
grant select, insert, delete on table public.fotos to anon;
grant select, insert, delete on table public.memoria_fotos to anon;
grant usage, select on all sequences in schema public to anon;

alter table public.memorias enable row level security;
alter table public.fotos enable row level security;
alter table public.memoria_fotos enable row level security;

drop policy if exists "mvp anon select memorias usuario 2" on public.memorias;
create policy "mvp anon select memorias usuario 2"
on public.memorias
for select
to anon
using (usuario_id = 2);

drop policy if exists "mvp anon insert memorias usuario 2" on public.memorias;
create policy "mvp anon insert memorias usuario 2"
on public.memorias
for insert
to anon
with check (
  usuario_id = 2
  and origem = 'app_mobile'
);

drop policy if exists "mvp anon delete memorias usuario 2" on public.memorias;
create policy "mvp anon delete memorias usuario 2"
on public.memorias
for delete
to anon
using (usuario_id = 2 and origem = 'app_mobile');

drop policy if exists "mvp anon select fotos usuario 2" on public.fotos;
create policy "mvp anon select fotos usuario 2"
on public.fotos
for select
to anon
using (usuario_id = 2);

drop policy if exists "mvp anon insert fotos usuario 2" on public.fotos;
create policy "mvp anon insert fotos usuario 2"
on public.fotos
for insert
to anon
with check (usuario_id = 2);

drop policy if exists "mvp anon delete fotos usuario 2" on public.fotos;
create policy "mvp anon delete fotos usuario 2"
on public.fotos
for delete
to anon
using (usuario_id = 2);

drop policy if exists "mvp anon select memoria fotos usuario 2"
on public.memoria_fotos;
create policy "mvp anon select memoria fotos usuario 2"
on public.memoria_fotos
for select
to anon
using (
  exists (
    select 1
    from public.memorias m
    where m.id = memoria_id
      and m.usuario_id = 2
  )
);

drop policy if exists "mvp anon insert memoria fotos usuario 2"
on public.memoria_fotos;
create policy "mvp anon insert memoria fotos usuario 2"
on public.memoria_fotos
for insert
to anon
with check (
  exists (
    select 1
    from public.memorias m
    where m.id = memoria_id
      and m.usuario_id = 2
  )
  and exists (
    select 1
    from public.fotos f
    where f.id = foto_id
      and f.usuario_id = 2
  )
);

drop policy if exists "mvp anon delete memoria fotos usuario 2"
on public.memoria_fotos;
create policy "mvp anon delete memoria fotos usuario 2"
on public.memoria_fotos
for delete
to anon
using (
  exists (
    select 1
    from public.memorias m
    where m.id = memoria_id
      and m.usuario_id = 2
  )
);

drop policy if exists "mvp anon upload fotos usuario 2"
on storage.objects;
create policy "mvp anon upload fotos usuario 2"
on storage.objects
for insert
to anon
with check (
  bucket_id = 'fotos'
  and name like 'usuario_2/app_mobile/%'
);

drop policy if exists "mvp anon select fotos usuario 2"
on storage.objects;
create policy "mvp anon select fotos usuario 2"
on storage.objects
for select
to anon
using (
  bucket_id = 'fotos'
  and name like 'usuario_2/app_mobile/%'
);

drop policy if exists "mvp anon delete fotos usuario 2"
on storage.objects;
create policy "mvp anon delete fotos usuario 2"
on storage.objects
for delete
to anon
using (
  bucket_id = 'fotos'
  and name like 'usuario_2/app_mobile/%'
);
