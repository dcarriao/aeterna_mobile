-- ============================================================================
-- BACKFILL — Preenche vínculos/permissões para contas JÁ CADASTRADAS hoje
-- ============================================================================
-- Rode este script DEPOIS de `vinculos_familiares_e_permissoes.sql`.
--
-- O que ele faz (100% idempotente — pode rodar quantas vezes quiser):
--
-- 1. Para todo `contato` cujo e-mail bate (case-insensitive) com o e-mail de
--    login de outra conta em `usuarios`, cria o vínculo familiar BILATERAL
--    (dono do contato <-> conta encontrada) em `vinculos_familiares`.
--
-- 2. Para cada `conteudo_permissoes` (memórias já compartilhadas com aquele
--    contato antes desta sprint), cria a permissão real equivalente em
--    `conteudo_colaboradores` (papel = 'leitor', igual ao comportamento
--    antigo, que era só leitura) — isto corrige retroativamente o "BUG 1"
--    para todo mundo que já tinha compartilhado memórias antes de hoje.
--
-- 3. Para cada `contato` já vinculado a um memorial (`contatos.memorial_id`
--    não nulo) cujo e-mail bate com uma conta cadastrada, cria a permissão
--    de colaboração no memorial (papel = 'colaborador', pois o texto do app
--    já prometia "podem ver e enviar lembranças").
--
-- Nada é apagado. Tudo usa `ON CONFLICT DO NOTHING` (respeitando as
-- constraints UNIQUE criadas na migração anterior).
-- ============================================================================


-- 1. Vínculo familiar bilateral (contato.email == usuarios.email)
insert into public.vinculos_familiares (usuario_id, vinculado_usuario_id)
select distinct c.usuario_id, u.id
from public.contatos c
join public.usuarios u
  on lower(u.email) = lower(c.email)
where c.usuario_id is not null
  and c.usuario_id <> u.id
on conflict (usuario_id, vinculado_usuario_id) do nothing;

insert into public.vinculos_familiares (usuario_id, vinculado_usuario_id)
select distinct u.id, c.usuario_id
from public.contatos c
join public.usuarios u
  on lower(u.email) = lower(c.email)
where c.usuario_id is not null
  and c.usuario_id <> u.id
on conflict (usuario_id, vinculado_usuario_id) do nothing;


-- 2. Migra compartilhamentos de memória já existentes (conteudo_permissoes)
--    para o novo sistema real de permissões (conteudo_colaboradores),
--    concedendo papel 'leitor' (equivalente ao comportamento antigo).
insert into public.conteudo_colaboradores
    (tipo_conteudo, conteudo_id, usuario_id, papel, concedido_por)
select distinct
    cp.tipo_conteudo,
    cp.conteudo_id,
    u.id,
    'leitor',
    c.usuario_id
from public.conteudo_permissoes cp
join public.contatos c on c.id = cp.contato_id
join public.usuarios u on lower(u.email) = lower(c.email)
where c.usuario_id is not null
  and c.usuario_id <> u.id
on conflict (tipo_conteudo, conteudo_id, usuario_id) do nothing;


-- 3. Migra contatos já vinculados a um memorial (contatos.memorial_id) para
--    permissão real de colaboração no memorial (papel 'colaborador').
insert into public.conteudo_colaboradores
    (tipo_conteudo, conteudo_id, usuario_id, papel, concedido_por)
select distinct
    'memorial',
    c.memorial_id,
    u.id,
    'colaborador',
    c.usuario_id
from public.contatos c
join public.usuarios u on lower(u.email) = lower(c.email)
where c.memorial_id is not null
  and c.usuario_id is not null
  and c.usuario_id <> u.id
on conflict (tipo_conteudo, conteudo_id, usuario_id) do nothing;


-- ============================================================================
-- Conferência (rode manualmente para ver o resultado, opcional):
-- ============================================================================
-- select * from vinculos_familiares order by criado_em desc;
-- select * from conteudo_colaboradores order by criado_em desc;
-- ============================================================================
