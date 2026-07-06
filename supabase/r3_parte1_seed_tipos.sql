-- ============================================================================
-- r3_parte1_seed_tipos.sql
-- Sprint R.3 — Parte 1: Seed de tipos_relacionamento (23 linhas)
-- ============================================================================
-- Executar PRIMEIRO. Cada linha e idempotente (individual WHERE NOT EXISTS).
-- ============================================================================

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'CONJUGE', 'Esposo(a)', 'Esposo(a)', 'conjugue'
where not exists (select 1 from public.tipos_relacionamento where id = 'CONJUGE');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'COMPANHEIRO', 'Companheiro', 'Companheiro', 'conjugue'
where not exists (select 1 from public.tipos_relacionamento where id = 'COMPANHEIRO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'PAI', 'Pai', 'Filho(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'PAI');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'MAE', 'Mae', 'Filho(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'MAE');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'FILHO', 'Filho(a)', 'Pai', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'FILHO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'FILHA', 'Filho(a)', 'Mae', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'FILHA');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'IRMAO', 'Irmao(a)', 'Irmao(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'IRMAO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'AVO', 'Avo(o)', 'Neto(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'AVO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'NETO', 'Neto(a)', 'Avo(o)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'NETO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'BISAVO', 'Bisavo(o)', 'Bisneto(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'BISAVO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'BISNETO', 'Bisneto(a)', 'Bisavo(o)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'BISNETO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'TIO', 'Tio(a)', 'Sobrinho(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'TIO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'SOBRINHO', 'Sobrinho(a)', 'Tio(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'SOBRINHO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'PRIMO', 'Primo(a)', 'Primo(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'PRIMO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'PADRINHO', 'Padrinho', 'Afilhado(a)', 'afinidade'
where not exists (select 1 from public.tipos_relacionamento where id = 'PADRINHO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'MADRINHA', 'Madrinha', 'Afilhado(a)', 'afinidade'
where not exists (select 1 from public.tipos_relacionamento where id = 'MADRINHA');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'AFILHADO', 'Afilhado(a)', 'Padrinho', 'afinidade'
where not exists (select 1 from public.tipos_relacionamento where id = 'AFILHADO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'GENRO', 'Genro', 'Sogro(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'GENRO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'NORA', 'Nora', 'Sogro(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'NORA');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'SOGRO', 'Sogro(a)', 'Genro/Nora', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'SOGRO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'CUNHADO', 'Cunhado(a)', 'Cunhado(a)', 'familia'
where not exists (select 1 from public.tipos_relacionamento where id = 'CUNHADO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'AMIGO', 'Amigo(a)', 'Amigo(a)', 'amizade'
where not exists (select 1 from public.tipos_relacionamento where id = 'AMIGO');

insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria)
select 'OUTRO', 'Conhecido(a)', 'Conhecido(a)', 'outro'
where not exists (select 1 from public.tipos_relacionamento where id = 'OUTRO');

-- Validacao
-- SELECT count(*) FROM public.tipos_relacionamento;  -- 23
