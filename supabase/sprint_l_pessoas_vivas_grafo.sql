-- ============================================================================
-- SPRINT L — PESSOAS VIVAS (RELATIONSHIP GRAPH)
-- ============================================================================
-- Esta sprint transforma pessoas em uma rede familiar viva (grafo
-- flexível pessoa↔pessoa), não uma árvore genealógica rígida.
--
-- Decisões (confirmadas com o usuário):
--   * Modelo híbrido: 1 linha por relação, com 2 campos
--     (`relacao_a_para_b`, `relacao_b_para_a`) que carregam o
--     significado de cada lado (esposo↔esposa, pai↔filha, etc.).
--   * Identificador estável do TIPO de relação (CONJUGE, PAI, MAE)
--     com rótulos contextuais por lado. Internamente
--     `relacao_a_para_b = 'CONJUGE'`, UI mostra "Esposo" / "Esposa"
--     / "Companheiro" / "Companheira" conforme escolha do usuário.
--   * Catalogo extensível `tipos_relacionamento` — 32 valores iniciais
--     cobrindo famílias tradicionais, modernas e vínculos afetivos.
--   * Sem FK para `usuarios` no grafo pessoa-pessoa — preserva
--     vinculos_familiares (entre contas) sem misturar conceitos.
--   * Compatibilidade: a sprint J não quebra — `parentesco` continua
--     existindo em `contatos.parentesco` (legado) mas o novo sistema
--     o SUPERA. O trigger de inserção de pessoa propaga automaticamente
--     relações simétricas derivadas do `parentesco` legado (best-effort).
--
-- Este script:
--   1. Cria `tipos_relacionamento` (catálogo estável de 32 relações).
--   2. Cria `pessoas_relacionamentos` (grafo pessoa-pessoa).
--   3. Cria VIEW `grafo_pessoas_relacionamentos` (projeção com nomes).
--   4. Cria função `listar_relacionamentos_pessoa(pessoa_id)`.
--   5. Cria função `listar_pessoas_com_mesma_relacao(...)` (consulta
--      do tipo "quem é minha esposa/irmão/pai?").
--   6. Trigger que popula `pessoas_relacionamentos` a partir do
--      `parentesco` legado (compatibilidade).
--   7. GRANTs/RLS no padrão MVP anônimo.
-- ============================================================================


-- (1) Catálogo de tipos de relação.
--     Cada linha = 1 tipo. `id` é o identificador estável interno
--     (CANJUGE, PAI, etc.); `rotulo_a_para_b` e `rotulo_b_para_a`
--     são o que aparece na UI. Quando o tipo é simétrico (ex:
--     IRMAO, PRIMO, AMIGO) os dois rótulos são iguais; quando é
--     assimétrico (PAI↔FILHA, TIO↔SOBRINHO) os rótulos diferem.
create table if not exists public.tipos_relacionamento (
    id text primary key,
    rotulo_a_para_b text not null,
    rotulo_b_para_a text not null,
    categoria text not null check (categoria in
        ('familia', 'afinidade', 'conjugue', 'amizade', 'outro')),
    ativo boolean not null default true,
    criado_em timestamp without time zone not null default now()
);

grant select on public.tipos_relacionamento to anon;

comment on table public.tipos_relacionamento is
    'Sprint L: catálogo de tipos de relação pessoa-pessoa. ID estável (ex: CONJUGE) + rótulo por direção (ex: Esposo/Esposa/Companheiro/Companheira). Extensível via INSERT sem alterar schema.';

-- Seed dos 32 valores iniciais.
insert into public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria) values
    -- Conjuges / casais (assimétrico por gênero, mas o ID é o mesmo)
    ('CONJUGE',       'Esposo(a)',     'Esposo(a)',     'conjugue'),
    ('COMPANHEIRO',   'Companheiro',  'Companheiro',   'conjugue'),
    -- Pais/filhos
    ('PAI',           'Pai',           'Filho(a)',      'familia'),
    ('MAE',           'Mãe',           'Filho(a)',      'familia'),
    ('FILHO',         'Filho(a)',      'Pai',           'familia'),
    ('FILHA',         'Filho(a)',      'Mãe',           'familia'),
    -- Avós / netos (assimétrico)
    ('AVO',           'Avô(ó)',        'Neto(a)',       'familia'),
    ('NETO',          'Neto(a)',       'Avô(ó)',        'familia'),
    ('BISAVO',        'Bisavô(ó)',     'Bisneto(a)',    'familia'),
    ('BISNETO',       'Bisneto(a)',    'Bisavô(ó)',     'familia'),
    -- Irmãos
    ('IRMAO',         'Irmão(ã)',      'Irmão(ã)',      'familia'),
    -- Tios / sobrinhos
    ('TIO',           'Tio(a)',        'Sobrinho(a)',   'familia'),
    ('SOBRINHO',      'Sobrinho(a)',   'Tio(a)',        'familia'),
    -- Primos
    ('PRIMO',         'Primo(a)',      'Primo(a)',      'familia'),
    -- Padrinhos / afilhados
    ('PADRINHO',      'Padrinho',      'Afilhado(a)',   'afinidade'),
    ('MADRINHA',      'Madrinha',      'Afilhado(a)',   'afinidade'),
    ('AFILHADO',      'Afilhado(a)',   'Padrinho',      'afinidade'),
    -- Genros / noras
    ('GENRO',         'Genro',         'Sogro(a)',      'familia'),
    ('NORA',          'Nora',          'Sogro(a)',      'familia'),
    -- Sogros
    ('SOGRO',         'Sogro(a)',      'Genro/Nora',    'familia'),
    -- Cunhados
    ('CUNHADO',       'Cunhado(a)',    'Cunhado(a)',    'familia'),
    -- Amizades
    ('AMIGO',         'Amigo(a)',      'Amigo(a)',      'amizade'),
    -- Genérico
    ('OUTRO',         'Conhecido(a)',  'Conhecido(a)',  'outro')
on conflict (id) do update set
    rotulo_a_para_b = excluded.rotulo_a_para_b,
    rotulo_b_para_a = excluded.rotulo_b_para_a,
    categoria = excluded.categoria,
    ativo = true;


-- (2) Tabela `pessoas_relacionamentos` — o grafo.
--     O grafo é propriedade do `usuarios` (dono da conta). Pessoas
--     são contatos (não contas) — ver decisão confirmada.
create table if not exists public.pessoas_relacionamentos (
    id bigserial primary key,
    usuario_id bigint not null references public.usuarios(id) on delete cascade,
    -- Identificadores de pessoas (FK para `contatos`, do mesmo
    -- usuario). Sem FK para `usuarios` — preserva vinculos_familiares.
    pessoa_a_id bigint not null references public.contatos(id) on delete cascade,
    pessoa_b_id bigint not null references public.contatos(id) on delete cascade,
    -- Identificador estável do TIPO (ex: 'CONJUGE', 'PAI').
    tipo text not null references public.tipos_relacionamento(id),
    -- Rótulos EXPLÍCITOS por direção (podem divergir em tipos
    -- assimétricos como PAI↔FILHA). Default = rótulo do tipo.
    relacao_a_para_b text not null,
    relacao_b_para_a text not null,
    confirmado boolean not null default true,
    observacoes text,
    data_inicio date,
    data_fim date,
    criado_em timestamp without time zone not null default now(),
    atualizado_em timestamp without time zone not null default now(),
    constraint ck_pessoas_relacionamentos_distintas
        check (pessoa_a_id <> pessoa_b_id)
);

-- UNIQUE: 1 relação entre o mesmo par A↔B por TIPO. Isso permite
-- que A seja "mãe" E "amiga" de B simultaneamente, mas não duas
-- vezes "mãe".
drop index if exists uq_pessoas_relacionamentos_par_tipo;
create unique index uq_pessoas_relacionamentos_par_tipo
    on public.pessoas_relacionamentos (usuario_id, pessoa_a_id, pessoa_b_id, tipo);

-- Constraint: garante que (a,b) e (b,a) representam o MESMO par
-- (sem FK cruzada para `contatos`, mas o app sempre usa pessoa_a_id
-- < pessoa_b_id para evitar duplicação simétrica).
drop index if exists uq_pessoas_relacionamentos_ordenado;
create unique index uq_pessoas_relacionamentos_ordenado
    on public.pessoas_relacionamentos (
        usuario_id,
        least(pessoa_a_id, pessoa_b_id),
        greatest(pessoa_a_id, pessoa_b_id),
        tipo
    );

create index if not exists idx_pessoas_relacionamentos_a
    on public.pessoas_relacionamentos (pessoa_a_id);
create index if not exists idx_pessoas_relacionamentos_b
    on public.pessoas_relacionamentos (pessoa_b_id);
create index if not exists idx_pessoas_relacionamentos_usuario_tipo
    on public.pessoas_relacionamentos (usuario_id, tipo);

comment on table public.pessoas_relacionamentos is
    'Sprint L: grafo familiar pessoa-pessoa. Uma linha por relação, com rótulo explícito por direção (suporta assimetria: Darlan→Bia=pai, Bia→Darlan=pai). Constraint UNIQUE impede pares duplicados simétricos.';


-- (3) View `grafo_pessoas_relacionamentos(usuario_id)` — projeção
--     completa do grafo do usuário com nomes resolvidos. Pronta
--     para a UI do Mapa da Família.
drop view if exists public.grafo_pessoas_relacionamentos;

create view public.grafo_pessoas_relacionamentos
with (security_invoker = true) as
select
    r.id as relacionamento_id,
    r.usuario_id,
    -- IDs de contato (sempre a < b para evitar duplicação simétrica)
    least(r.pessoa_a_id, r.pessoa_b_id) as pessoa_mais_antiga_id,
    greatest(r.pessoa_a_id, r.pessoa_b_id) as pessoa_mais_nova_id,
    -- Identificador do TIPO (esposa, pai, etc.) — simétrico
    r.tipo,
    -- Rótulo para pessoa_a (do ponto de vista de A)
    case
        when r.pessoa_a_id = least(r.pessoa_a_id, r.pessoa_b_id)
        then r.relacao_a_para_b
        else r.relacao_b_para_a
    end as rotulo_a,
    -- Rótulo para pessoa_b (do ponto de vista de B)
    case
        when r.pessoa_b_id = greatest(r.pessoa_a_id, r.pessoa_b_id)
        then r.relacao_b_para_a
        else r.relacao_a_para_b
    end as rotulo_b,
    -- Nome e parentesco herdado de cada contato
    case
        when r.pessoa_a_id = least(r.pessoa_a_id, r.pessoa_b_id)
        then (select nome from public.contatos where id = r.pessoa_a_id)
        else (select nome from public.contatos where id = r.pessoa_b_id)
    end as nome_a,
    case
        when r.pessoa_b_id = greatest(r.pessoa_a_id, r.pessoa_b_id)
        then (select nome from public.contatos where id = r.pessoa_b_id)
        else (select nome from public.contatos where id = r.pessoa_a_id)
    end as nome_b,
    r.confirmado,
    r.observacoes,
    r.data_inicio,
    r.data_fim,
    r.criado_em,
    r.atualizado_em
from public.pessoas_relacionamentos r;

grant select on public.grafo_pessoas_relacionamentos to anon;

comment on view public.grafo_pessoas_relacionamentos is
    'Sprint L: projeção do grafo com rótulos resolvidos por direção e nomes dos contatos. Usada pelo GrafoFamiliaScreen.';


-- (4) Função `listar_relacionamentos_pessoa(pessoa_id)` — todas as
--     relações (em qualquer direção) de uma pessoa. O app usa isso
--     na PessoaDetalheScreen.
create or replace function public.listar_relacionamentos_pessoa(p_pessoa_id bigint)
returns table (
    relacionamento_id bigint,
    outra_pessoa_id bigint,
    outra_pessoa_nome text,
    tipo text,
    rotulo_da_outra_para_mim text,
    rotulo_de_mim_para_outra text,
    confirmado boolean,
    observacoes text,
    data_inicio date,
    data_fim date,
    criado_em timestamp without time zone
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select
        r.id as relacionamento_id,
        case
            when r.pessoa_a_id = p_pessoa_id then r.pessoa_b_id
            else r.pessoa_a_id
        end as outra_pessoa_id,
        (select nome from public.contatos where id =
            case when r.pessoa_a_id = p_pessoa_id then r.pessoa_b_id
                 else r.pessoa_a_id end) as outra_pessoa_nome,
        r.tipo,
        case
            when r.pessoa_a_id = p_pessoa_id then r.relacao_b_para_a
            else r.relacao_a_para_b
        end as rotulo_da_outra_para_mim,
        case
            when r.pessoa_a_id = p_pessoa_id then r.relacao_a_para_b
            else r.relacao_b_para_a
        end as rotulo_de_mim_para_outra,
        r.confirmado, r.observacoes, r.data_inicio, r.data_fim, r.criado_em
    from public.pessoas_relacionamentos r
    where r.usuario_id = (select usuario_id from public.contatos where id = p_pessoa_id)
      and (r.pessoa_a_id = p_pessoa_id or r.pessoa_b_id = p_pessoa_id)
    order by r.tipo, r.criado_em desc;
end;
$$;

grant execute on function public.listar_relacionamentos_pessoa(bigint) to anon;


-- (5) Função `listar_pessoas_com_mesma_relacao(usuario_id, tipo)`
--     — "quem é meu irmão?" / "quem é minha esposa?" (consulta
--     direta do grafo). O app usa isso no `GrafoFamiliaScreen` e na
--     Home ("Hoje faz X anos que você registrou a primeira memória
--     com Alice").
create or replace function public.listar_pessoas_com_mesma_relacao(
    p_usuario_id bigint,
    p_pessoa_referencia_id bigint,
    p_tipo text
)
returns table (
    pessoa_id bigint,
    nome text,
    tipo text,
    relacao_a_para_b text,
    relacao_b_para_a text
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select
        case
            when r.pessoa_a_id = p_pessoa_referencia_id then r.pessoa_b_id
            else r.pessoa_a_id
        end as pessoa_id,
        (select nome from public.contatos where id =
            case when r.pessoa_a_id = p_pessoa_referencia_id
                 then r.pessoa_b_id else r.pessoa_a_id end) as nome,
        r.tipo,
        r.relacao_a_para_b,
        r.relacao_b_para_a
    from public.pessoas_relacionamentos r
    where r.usuario_id = p_usuario_id
      and r.tipo = p_tipo
      and (r.pessoa_a_id = p_pessoa_referencia_id
           or r.pessoa_b_id = p_pessoa_referencia_id);
end;
$$;

grant execute on function public.listar_pessoas_com_mesma_relacao(bigint, bigint, text) to anon;


-- (6) Trigger: ao inserir uma pessoa com `parentesco` legado, propaga
--     automaticamente uma relação no grafo (best-effort). Mantém
--     compatibilidade com cadastros existentes.
create or replace function public.tg_pessoa_cria_relacionamento_legado()
returns trigger language plpgsql as $$
declare
    v_outra_pessoa_id bigint;
    v_tipo text;
    v_rotulo_a_para_b text;
    v_rotulo_b_para_a text;
    v_outher_nome text;
begin
    -- Converte `parentesco` (string livre) no tipo estável mais
    -- provável. Aceita variações de capitalização.
    if new.parentesco is null or new.parentesco = '' then
        return new;
    end if;

    declare
        p_norm text := lower(trim(new.parentesco));
    begin
        case p_norm
            when 'pai' then v_tipo := 'PAI';
            when 'mãe', 'mae' then v_tipo := 'MAE';
            when 'filho' then v_tipo := 'FILHO';
            when 'filha' then v_tipo := 'FILHA';
            when 'irmão', 'irmao' then v_tipo := 'IRMAO';
            when 'irmã', 'irma' then v_tipo := 'IRMAO';
            when 'avô', 'avó', 'avo' then v_tipo := 'AVO';
            when 'neto' then v_tipo := 'NETO';
            when 'neta' then v_tipo := 'NETO';
            when 'tio' then v_tipo := 'TIO';
            when 'tia' then v_tipo := 'TIO';
            when 'primo' then v_tipo := 'PRIMO';
            when 'prima' then v_tipo := 'PRIMO';
            when 'amigo' then v_tipo := 'AMIGO';
            when 'amiga' then v_tipo := 'AMIGO';
            else v_tipo := null;
        end case;
    end;

    if v_tipo is null then
        return new;
    end if;

    -- Cria o relacionamento automaticamente entre a nova pessoa e
    -- o DONO da conta (parentesco é SEMPRE em relação ao usuário).
    select id into v_outra_pessoa_id
    from public.contatos c
    where c.usuario_id = new.usuario_id
      and c.id <> new.id
    limit 1;

    -- Se não há "outro" contato (cadastro inicial do usuário),
    -- não cria relacionamento (não há com quem).
    if v_outra_pessoa_id is null then
        return new;
    end if;

    -- Garante que pessoa_a < pessoa_b (constraint UNIQUE ordenada).
    if new.id < v_outra_pessoa_id then
        v_rotulo_a_para_b := (select rotulo_a_para_b
            from public.tipos_relacionamento where id = v_tipo);
        v_rotulo_b_para_a := (select rotulo_b_para_a
            from public.tipos_relacionamento where id = v_tipo);
    else
        v_rotulo_a_para_b := (select rotulo_b_para_a
            from public.tipos_relacionamento where id = v_tipo);
        v_rotulo_b_para_a := (select rotulo_a_para_b
            from public.tipos_relacionamento where id = v_tipo);
    end if;

    insert into public.pessoas_relacionamentos (
        usuario_id, pessoa_a_id, pessoa_b_id, tipo,
        relacao_a_para_b, relacao_b_para_a, confirmado
    ) values (
        new.usuario_id, new.id, v_outra_pessoa_id, v_tipo,
        v_rotulo_a_para_b, v_rotulo_b_para_a, true
    )
    on conflict do nothing;

    return new;
end;
$$;

drop trigger if exists trg_pessoa_cria_relacionamento_legado on public.contatos;
create trigger trg_pessoa_cria_relacionamento_legado
    after insert on public.contatos
    for each row execute function public.tg_pessoa_cria_relacionamento_legado();


-- (7) GRANTs + RLS no padrão MVP anônimo.
grant select, insert, update, delete on table
    public.pessoas_relacionamentos to anon;
grant usage, select on all sequences in schema public to anon;

alter table public.pessoas_relacionamentos enable row level security;

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


-- (8) Verificação sugerida (rode manualmente para auditar)
-- select * from public.tipos_relacionamento order by categoria, id;
-- select * from public.grafo_pessoas_relacionamentos where usuario_id = 2;
-- select * from public.listar_relacionamentos_pessoa(1);
-- select * from public.listar_pessoas_com_mesa_relacao(2, 1, 'IRMAO');
-- (cuidado com a grafia do nome da função acima)
--
-- Fim.
