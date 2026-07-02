-- Políticas TEMPORÁRIAS para o MVP sem autenticação real.
-- Permitir acesso dinâmico por usuário no MVP anônimo.
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
drop policy if exists "mvp anon select memorias" on public.memorias;
create policy "mvp anon select memorias"
on public.memorias
for select
to anon
using (true);

drop policy if exists "mvp anon insert memorias usuario 2" on public.memorias;
drop policy if exists "mvp anon insert memorias" on public.memorias;
create policy "mvp anon insert memorias"
on public.memorias
for insert
to anon
with check (origem = 'app_mobile');

drop policy if exists "mvp anon delete memorias usuario 2" on public.memorias;
drop policy if exists "mvp anon delete memorias" on public.memorias;
create policy "mvp anon delete memorias"
on public.memorias
for delete
to anon
using (origem = 'app_mobile');

drop policy if exists "mvp anon select fotos usuario 2" on public.fotos;
drop policy if exists "mvp anon select fotos" on public.fotos;
create policy "mvp anon select fotos"
on public.fotos
for select
to anon
using (true);

drop policy if exists "mvp anon insert fotos usuario 2" on public.fotos;
drop policy if exists "mvp anon insert fotos" on public.fotos;
create policy "mvp anon insert fotos"
on public.fotos
for insert
to anon
with check (true);

drop policy if exists "mvp anon delete fotos usuario 2" on public.fotos;
drop policy if exists "mvp anon delete fotos" on public.fotos;
create policy "mvp anon delete fotos"
on public.fotos
for delete
to anon
using (true);

drop policy if exists "mvp anon select memoria fotos usuario 2" on public.memoria_fotos;
drop policy if exists "mvp anon select memoria fotos" on public.memoria_fotos;
create policy "mvp anon select memoria fotos"
on public.memoria_fotos
for select
to anon
using (true);

drop policy if exists "mvp anon insert memoria fotos usuario 2" on public.memoria_fotos;
drop policy if exists "mvp anon insert memoria fotos" on public.memoria_fotos;
create policy "mvp anon insert memoria fotos"
on public.memoria_fotos
for insert
to anon
with check (true);

drop policy if exists "mvp anon delete memoria fotos usuario 2" on public.memoria_fotos;
drop policy if exists "mvp anon delete memoria fotos" on public.memoria_fotos;
create policy "mvp anon delete memoria fotos"
on public.memoria_fotos
for delete
to anon
using (true);

drop policy if exists "mvp anon upload fotos usuario 2" on storage.objects;
drop policy if exists "mvp anon upload fotos" on storage.objects;
create policy "mvp anon upload fotos"
on storage.objects
for insert
to anon
with check (
  bucket_id = 'fotos'
  and name like 'usuario_%/app_mobile/%'
);

drop policy if exists "mvp anon select fotos usuario 2" on storage.objects;
drop policy if exists "mvp anon select fotos" on storage.objects;
create policy "mvp anon select fotos"
on storage.objects
for select
to anon
using (
  bucket_id = 'fotos'
  and name like 'usuario_%/app_mobile/%'
);

drop policy if exists "mvp anon delete fotos usuario 2" on storage.objects;
drop policy if exists "mvp anon delete fotos" on storage.objects;
create policy "mvp anon delete fotos"
on storage.objects
for delete
to anon
using (
  bucket_id = 'fotos'
  and name like 'usuario_%/app_mobile/%'
);

-- Contatos (MVP sem auth)
grant select, insert, delete on table public.contatos to anon;
grant usage, select on all sequences in schema public to anon;

alter table public.contatos enable row level security;

drop policy if exists "mvp anon select contatos usuario 2" on public.contatos;
drop policy if exists "mvp anon select contatos" on public.contatos;
create policy "mvp anon select contatos"
on public.contatos
for select
to anon
using (true);

drop policy if exists "mvp anon insert contatos usuario 2" on public.contatos;
drop policy if exists "mvp anon insert contatos" on public.contatos;
create policy "mvp anon insert contatos"
on public.contatos
for insert
to anon
with check (true);

drop policy if exists "mvp anon delete contatos usuario 2" on public.contatos;
drop policy if exists "mvp anon delete contatos" on public.contatos;
create policy "mvp anon delete contatos"
on public.contatos
for delete
to anon
using (true);

-- Usuários (Perfil)
grant select, update on table public.usuarios to anon;
alter table public.usuarios enable row level security;

drop policy if exists "mvp anon select usuarios usuario 2" on public.usuarios;
drop policy if exists "mvp anon select usuarios" on public.usuarios;
create policy "mvp anon select usuarios"
on public.usuarios for select to anon
using (true);

drop policy if exists "mvp anon update usuarios usuario 2" on public.usuarios;
drop policy if exists "mvp anon update usuarios" on public.usuarios;
create policy "mvp anon update usuarios"
on public.usuarios for update to anon
using (true);
