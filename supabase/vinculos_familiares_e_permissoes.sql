-- ============================================================================
-- SPRINT — Modelo de Vínculos Familiares e Permissões Colaborativas
-- ============================================================================
-- Este script é ADITIVO e IDEMPOTENTE (pode ser rodado mais de uma vez sem
-- efeitos colaterais). Ele NÃO remove nem altera dados existentes em
-- `usuarios`, `contatos`, `memorias`, `memoriais`, `conteudo_permissoes`.
--
-- Rode este arquivo INTEIRO no SQL Editor do Supabase.
-- Depois rode `vinculos_familiares_backfill.sql` (script separado) para
-- preencher vínculos/permissões para contas já cadastradas hoje.
-- ============================================================================


-- ============================================================================
-- PARTE 1 — Tabela `convites_familiares`
-- ============================================================================
-- Convite real, bilateral, com status controlado (pendente/aceito/recusado/
-- expirado). Separada da tabela legada `convites_pessoas` (usada pelo site
-- Streamlit apenas para disparo de e-mail informativo, sem aceite) para não
-- alterar o comportamento existente do site.
--
-- Pode, opcionalmente, já nascer vinculado a um conteúdo específico
-- (`tipo_conteudo_alvo` + `conteudo_id_alvo` + `papel_sugerido`), permitindo
-- convidar alguém DIRETO para colaborar em um memorial/memória em um único
-- passo. Se esses campos forem nulos, o convite é só de vínculo familiar.

create table if not exists public.convites_familiares (
    id bigserial primary key,
    usuario_origem_id bigint not null references public.usuarios(id) on delete cascade,
    contato_id bigint references public.contatos(id) on delete set null,
    email_destino text not null,
    usuario_destino_id bigint references public.usuarios(id) on delete set null,
    status text not null default 'pendente',
    token text,
    papel_sugerido text,
    tipo_conteudo_alvo text,
    conteudo_id_alvo bigint,
    criado_em timestamp without time zone not null default now(),
    aceito_em timestamp without time zone
);

-- Constraints (idempotentes via DROP IF EXISTS + ADD)
alter table public.convites_familiares drop constraint if exists ck_convites_familiares_status;
alter table public.convites_familiares add constraint ck_convites_familiares_status
    check (status in ('pendente', 'aceito', 'recusado', 'expirado'));

alter table public.convites_familiares drop constraint if exists ck_convites_familiares_papel;
alter table public.convites_familiares add constraint ck_convites_familiares_papel
    check (papel_sugerido is null or papel_sugerido in ('editor', 'colaborador', 'leitor'));

alter table public.convites_familiares drop constraint if exists ck_convites_familiares_tipo_alvo;
alter table public.convites_familiares add constraint ck_convites_familiares_tipo_alvo
    check (tipo_conteudo_alvo is null or tipo_conteudo_alvo in ('memoria', 'memorial', 'foto', 'video'));

alter table public.convites_familiares drop constraint if exists ck_convites_familiares_origem_destino;
alter table public.convites_familiares add constraint ck_convites_familiares_origem_destino
    check (usuario_destino_id is null or usuario_destino_id <> usuario_origem_id);

-- Um e-mail só pode ter 1 convite PENDENTE por remetente (evita duplicar spam
-- de convite); depois de aceito/recusado, pode-se convidar de novo.
drop index if exists uq_convites_familiares_pendente;
create unique index uq_convites_familiares_pendente
    on public.convites_familiares (usuario_origem_id, lower(email_destino))
    where status = 'pendente';

create index if not exists idx_convites_familiares_email
    on public.convites_familiares (lower(email_destino));
create index if not exists idx_convites_familiares_destino
    on public.convites_familiares (usuario_destino_id);
create index if not exists idx_convites_familiares_origem
    on public.convites_familiares (usuario_origem_id);
create unique index if not exists uq_convites_familiares_token
    on public.convites_familiares (token) where token is not null;


-- ============================================================================
-- PARTE 2 — Tabela `vinculos_familiares` (vínculo bilateral confirmado)
-- ============================================================================
-- Quando um convite é aceito, são gravadas DUAS linhas (A→B e B→A), para que
-- a consulta "quem está vinculado a mim" seja um simples
-- `select * from vinculos_familiares where usuario_id = :meuId` — sem
-- necessidade de OR/JOIN complexos no client.

create table if not exists public.vinculos_familiares (
    id bigserial primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    vinculado_usuario_id bigint not null references public.usuarios(id) on delete cascade,
    origem_convite_id bigint references public.convites_familiares(id) on delete set null,
    criado_em timestamp without time zone not null default now()
);

alter table public.vinculos_familiares drop constraint if exists ck_vinculos_familiares_distintos;
alter table public.vinculos_familiares add constraint ck_vinculos_familiares_distintos
    check (usuario_id <> vinculado_usuario_id);

alter table public.vinculos_familiares drop constraint if exists uq_vinculos_familiares;
alter table public.vinculos_familiares add constraint uq_vinculos_familiares
    unique (usuario_id, vinculado_usuario_id);

create index if not exists idx_vinculos_familiares_usuario
    on public.vinculos_familiares (usuario_id);


-- ============================================================================
-- PARTE 3 — Tabela `conteudo_colaboradores` (permissões granulares por papel)
-- ============================================================================
-- Generaliza `conteudo_permissoes` (que só sabia "vinculado/não vinculado" a
-- um CONTATO local) para permissões reais entre CONTAS (usuarios), com papel:
--   - editor:      pode alterar o conteúdo (ex.: biografia do memorial)
--   - colaborador: pode adicionar/enviar contribuições (foto, vídeo, texto)
--   - leitor:      só visualiza
-- "dono" NÃO é armazenado aqui — é sempre inferido de `memorias.usuario_id`
-- ou `memoriais.usuario_id` (dono já existente, sem duplicar a informação).

create table if not exists public.conteudo_colaboradores (
    id bigserial primary key,
    tipo_conteudo text not null,
    conteudo_id bigint not null,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    papel text not null default 'leitor',
    convite_id bigint references public.convites_familiares(id) on delete set null,
    concedido_por bigint references public.usuarios(id) on delete set null,
    criado_em timestamp without time zone not null default now()
);

alter table public.conteudo_colaboradores drop constraint if exists ck_conteudo_colaboradores_tipo;
alter table public.conteudo_colaboradores add constraint ck_conteudo_colaboradores_tipo
    check (tipo_conteudo in ('memoria', 'memorial', 'foto', 'video'));

alter table public.conteudo_colaboradores drop constraint if exists ck_conteudo_colaboradores_papel;
alter table public.conteudo_colaboradores add constraint ck_conteudo_colaboradores_papel
    check (papel in ('editor', 'colaborador', 'leitor'));

alter table public.conteudo_colaboradores drop constraint if exists uq_conteudo_colaboradores;
alter table public.conteudo_colaboradores add constraint uq_conteudo_colaboradores
    unique (tipo_conteudo, conteudo_id, usuario_id);

create index if not exists idx_conteudo_colaboradores_usuario
    on public.conteudo_colaboradores (usuario_id);
create index if not exists idx_conteudo_colaboradores_conteudo
    on public.conteudo_colaboradores (tipo_conteudo, conteudo_id);


-- ============================================================================
-- PARTE 4 — Correção crítica de schema: `contribuicoes`
-- ============================================================================
-- ACHADO DA AUDITORIA: o app Flutter (antes desta sprint) gravava/lia colunas
-- (autor, relacao, conteudo, foto_url, video_url, aprovado, created_at) que
-- NÃO existem no schema real criado pelo lado Python/produção
-- (usuario_dono_id, usuario_contribuidor_email, usuario_contribuidor_nome,
-- tipo_conteudo, conteudo_id, tipo_contribuicao, texto, arquivo_url, status,
-- criado_em, avaliado_em, avaliado_por, memorial_id). Isso fazia com que
-- QUALQUER tentativa de enviar contribuição pelo app mobile falhasse contra
-- o Supabase real (colunas inexistentes). Corrigido no código Dart nesta
-- sprint; os comandos abaixo garantem que todas as colunas necessárias
-- existem (idempotente, não apaga nada existente).

alter table public.contribuicoes add column if not exists usuario_dono_id bigint;
alter table public.contribuicoes add column if not exists usuario_contribuidor_email text;
alter table public.contribuicoes add column if not exists usuario_contribuidor_nome text;
alter table public.contribuicoes add column if not exists tipo_conteudo text;
alter table public.contribuicoes add column if not exists conteudo_id bigint;
alter table public.contribuicoes add column if not exists tipo_contribuicao text;
alter table public.contribuicoes add column if not exists texto text;
alter table public.contribuicoes add column if not exists arquivo_url text;
alter table public.contribuicoes add column if not exists arquivo_nome text;
alter table public.contribuicoes add column if not exists arquivo_tipo text;
alter table public.contribuicoes add column if not exists arquivo_tamanho bigint;
alter table public.contribuicoes add column if not exists status text default 'pendente';
alter table public.contribuicoes add column if not exists criado_em timestamp without time zone default now();
alter table public.contribuicoes add column if not exists avaliado_em timestamp without time zone;
alter table public.contribuicoes add column if not exists avaliado_por bigint;
alter table public.contribuicoes add column if not exists memorial_id bigint;

-- Amplia a constraint de tipo_conteudo para aceitar 'memorial' (contribuição
-- dirigida ao memorial como um todo, não a uma memória/foto/vídeo específica)
alter table public.contribuicoes drop constraint if exists ck_contribuicoes_tipo_conteudo;
alter table public.contribuicoes add constraint ck_contribuicoes_tipo_conteudo
    check (tipo_conteudo in ('memoria', 'foto', 'video', 'memorial'));

alter table public.contribuicoes drop constraint if exists ck_contribuicoes_tipo_contribuicao;
alter table public.contribuicoes add constraint ck_contribuicoes_tipo_contribuicao
    check (tipo_contribuicao in ('texto', 'foto', 'video'));

alter table public.contribuicoes drop constraint if exists ck_contribuicoes_status;
alter table public.contribuicoes add constraint ck_contribuicoes_status
    check (status in ('pendente', 'aprovado', 'rejeitado'));

create index if not exists idx_contribuicoes_memorial on public.contribuicoes (memorial_id);
create index if not exists idx_contribuicoes_dono on public.contribuicoes (usuario_dono_id);
create index if not exists idx_contribuicoes_status on public.contribuicoes (status);


-- ============================================================================
-- PARTE 5 — GRANTs e RLS (padrão MVP anônimo, igual às demais tabelas)
-- ============================================================================
-- Mesmo padrão de `mvp_anon_policies.sql`: isolamento por usuário é feito no
-- client Dart (.eq('usuario_id', ...)), não pelo banco — consistente com o
-- restante do MVP. Ver comentário no topo de mvp_anon_policies.sql.

grant usage on schema public to anon;
grant usage, select on all sequences in schema public to anon;

-- convites_familiares
grant select, insert, update, delete on table public.convites_familiares to anon;
alter table public.convites_familiares enable row level security;

drop policy if exists "mvp anon select convites_familiares" on public.convites_familiares;
create policy "mvp anon select convites_familiares"
on public.convites_familiares for select to anon using (true);

drop policy if exists "mvp anon insert convites_familiares" on public.convites_familiares;
create policy "mvp anon insert convites_familiares"
on public.convites_familiares for insert to anon with check (true);

drop policy if exists "mvp anon update convites_familiares" on public.convites_familiares;
create policy "mvp anon update convites_familiares"
on public.convites_familiares for update to anon using (true);

drop policy if exists "mvp anon delete convites_familiares" on public.convites_familiares;
create policy "mvp anon delete convites_familiares"
on public.convites_familiares for delete to anon using (true);

-- vinculos_familiares
grant select, insert, update, delete on table public.vinculos_familiares to anon;
alter table public.vinculos_familiares enable row level security;

drop policy if exists "mvp anon select vinculos_familiares" on public.vinculos_familiares;
create policy "mvp anon select vinculos_familiares"
on public.vinculos_familiares for select to anon using (true);

drop policy if exists "mvp anon insert vinculos_familiares" on public.vinculos_familiares;
create policy "mvp anon insert vinculos_familiares"
on public.vinculos_familiares for insert to anon with check (true);

drop policy if exists "mvp anon update vinculos_familiares" on public.vinculos_familiares;
create policy "mvp anon update vinculos_familiares"
on public.vinculos_familiares for update to anon using (true);

drop policy if exists "mvp anon delete vinculos_familiares" on public.vinculos_familiares;
create policy "mvp anon delete vinculos_familiares"
on public.vinculos_familiares for delete to anon using (true);

-- conteudo_colaboradores
grant select, insert, update, delete on table public.conteudo_colaboradores to anon;
alter table public.conteudo_colaboradores enable row level security;

drop policy if exists "mvp anon select conteudo_colaboradores" on public.conteudo_colaboradores;
create policy "mvp anon select conteudo_colaboradores"
on public.conteudo_colaboradores for select to anon using (true);

drop policy if exists "mvp anon insert conteudo_colaboradores" on public.conteudo_colaboradores;
create policy "mvp anon insert conteudo_colaboradores"
on public.conteudo_colaboradores for insert to anon with check (true);

drop policy if exists "mvp anon update conteudo_colaboradores" on public.conteudo_colaboradores;
create policy "mvp anon update conteudo_colaboradores"
on public.conteudo_colaboradores for update to anon using (true);

drop policy if exists "mvp anon delete conteudo_colaboradores" on public.conteudo_colaboradores;
create policy "mvp anon delete conteudo_colaboradores"
on public.conteudo_colaboradores for delete to anon using (true);

-- memoriais e contribuicoes: a auditoria confirmou que NÃO existia nenhum
-- GRANT/RLS documentado para essas duas tabelas em nenhum arquivo do
-- repositório. Adicionamos aqui, no mesmo padrão MVP, para que o app mobile
-- (que usa apenas a anon key) consiga de fato ler/escrever nelas.
grant select, insert, update, delete on table public.memoriais to anon;
alter table public.memoriais enable row level security;

drop policy if exists "mvp anon select memoriais" on public.memoriais;
create policy "mvp anon select memoriais"
on public.memoriais for select to anon using (true);

drop policy if exists "mvp anon insert memoriais" on public.memoriais;
create policy "mvp anon insert memoriais"
on public.memoriais for insert to anon with check (true);

drop policy if exists "mvp anon update memoriais" on public.memoriais;
create policy "mvp anon update memoriais"
on public.memoriais for update to anon using (true);

drop policy if exists "mvp anon delete memoriais" on public.memoriais;
create policy "mvp anon delete memoriais"
on public.memoriais for delete to anon using (true);

grant select, insert, update, delete on table public.contribuicoes to anon;
alter table public.contribuicoes enable row level security;

drop policy if exists "mvp anon select contribuicoes" on public.contribuicoes;
create policy "mvp anon select contribuicoes"
on public.contribuicoes for select to anon using (true);

drop policy if exists "mvp anon insert contribuicoes" on public.contribuicoes;
create policy "mvp anon insert contribuicoes"
on public.contribuicoes for insert to anon with check (true);

drop policy if exists "mvp anon update contribuicoes" on public.contribuicoes;
create policy "mvp anon update contribuicoes"
on public.contribuicoes for update to anon using (true);

drop policy if exists "mvp anon delete contribuicoes" on public.contribuicoes;
create policy "mvp anon delete contribuicoes"
on public.contribuicoes for delete to anon using (true);

-- Fim da migração.
