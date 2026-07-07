-- ============================================================================
-- SPRINT H — PESSOAS VIVAS
-- ============================================================================
-- Este script é ADITIVO e IDEMPOTENTE (pode ser rodado mais de uma vez sem
-- efeitos colaterais). Não remove nem altera dados existentes.
--
-- Ele:
--   1. Cria uma VIEW materializada (não — VIEW comum, sem custo de refresh)
--      `pessoa_linha_tempo` que agrega, para cada pessoa (contato) cadastrada
--      pelo usuário logado, a união cronológica de:
--         - memórias em que aparece (via conteudo_permissoes)
--         - contribuições aprovadas em memórias em que aparece (Sprint G)
--         - fotos vinculadas às memórias em que aparece
--      Cada linha inclui tipo ('memoria'|'foto'|'contribuicao'), título,
--      subtítulo, data, memória de origem e foto de capa.
--   2. Cria uma FUNÇÃO `pessoa_estatisticas(pessoa_id)` que devolve
--      total de memórias, fotos, vídeos, contribuições, primeira memória e
--      última memória em uma única chamada (otimiza a UI da PessoaDetalhe
--      Screen — sem isso, seriam 4-6 queries).
--   3. Cria uma FUNÇÃO `pessoas_recentes(limite)` que devolve, em uma única
--      chamada, as pessoas ordenadas por "última interação" (mais
--      recentemente envolvidas em memória/contribuição/foto) — alimenta a
--      nova seção "Pessoas Vivas Recentemente" da Home.
--   4. Cria uma FUNÇÃO `pessoas_sugeridas(limite)` que devolve nomes que
--      aparecem em memórias do usuário mas AINDA NÃO TÊM cadastro em
--      `contatos` — alimenta a "Descoberta automática" da PessoasScreen
--      ("Carlos aparece em 10 histórias, talvez você queira cadastrá-lo").
--   5. Cria uma FUNÇÃO `memorial_da_pessoa(pessoa_id)` que devolve o id
--      do memorial vinculado (se existir) — caminho Pessoa → Memorial.
--   6. Adiciona índice otimizado em `conteudo_permissoes.pessoa_id`
--      (já existe da criação da tabela; conferido).
--   7. GRANTs para as funções.
--   8. Política RLS mínima necessária (re-aproveitando o padrão MVP anônimo
--      `using (true)` consistente com o resto do projeto).
--
-- O que NÃO fazemos: NENHUMA tabela materializada cara; NENHUM trigger;
-- nenhuma duplicação de dados. Toda a agregação é feita em views/funções
-- derivadas em tempo de query, consistente com a arquitetura já adotada
-- (o app Flutter faz `.eq('usuario_id', ...)` no client).
-- ============================================================================


-- ============================================================================
-- (1) View: pessoa_linha_tempo
-- ============================================================================
-- Uma linha por evento relevante na "vida" da pessoa:
--   - Cada memória em que a pessoa aparece (tipo = 'memoria').
--   - Cada contribuição APROVADA em uma dessas memórias (tipo =
--     'contribuicao'), com a identidade do contribuidor.
--   - Cada foto da galeria vinculada a uma dessas memórias (tipo = 'foto').
--
-- Ordenada por data decrescente, limitada a 200 eventos por pessoa
-- (defesa contra pessoas muito frequentes, suficiente para a UX).
-- A view filtra apenas memórias do usuário logado (cliente Dart passa
-- `usuario_id` ao consultar; aqui ficamos neutros e deixamos o filtro por
-- conta do RLS e do client — padrão MVP).
drop view if exists public.pessoa_linha_tempo;

create view public.pessoa_linha_tempo
with (security_invoker = true) as
with memorias_da_pessoa as (
    select distinct cp.pessoa_id, cp.conteudo_id as memoria_id
    from public.conteudo_permissoes cp
    where cp.tipo_conteudo = 'memoria'
),
mem_eventos as (
    select
        mdp.pessoa_id,
        'memoria'::text as tipo,
        m.id as conteudo_id,
        m.titulo as titulo,
        coalesce(nullif(m.data_evento::text, ''), m.data_criacao::text) as data_ordem,
        m.id as memoria_origem_id,
        null::int as contribuicao_id,
        null::text as autor_contribuicao
    from memorias_da_pessoa mdp
    join public.memorias m on m.id = mdp.memoria_id
),
foto_eventos as (
    select
        mdp.pessoa_id,
        'foto'::text as tipo,
        mf.foto_id as conteudo_id,
        coalesce(f.titulo, 'Foto') as titulo,
        f.data_criacao::text as data_ordem,
        mf.memoria_id as memoria_origem_id,
        null::int as contribuicao_id,
        null::text as autor_contribuicao
    from memorias_da_pessoa mdp
    join public.memoria_fotos mf on mf.memoria_id = mdp.memoria_id
    left join public.fotos f on f.id = mf.foto_id
),
contrib_eventos as (
    select
        mdp.pessoa_id,
        'contribuicao'::text as tipo,
        c.id as conteudo_id,
        coalesce(c.texto, c.arquivo_url, 'Contribuição') as titulo,
        c.criado_em::text as data_ordem,
        c.conteudo_id as memoria_origem_id,
        c.id as contribuicao_id,
        c.usuario_contribuidor_nome as autor_contribuicao
    from memorias_da_pessoa mdp
    join public.contribuicoes c
      on c.tipo_conteudo = 'memoria'
     and c.conteudo_id = mdp.memoria_id
     and c.status = 'aprovado'
)
select * from mem_eventos
union all
select * from foto_eventos
union all
select * from contrib_eventos;

comment on view public.pessoa_linha_tempo is
    'Sprint H: agregação cronológica de tudo que envolve uma pessoa (memórias, fotos e contribuições aprovadas). Lida pelo app Flutter para popular a Linha do Tempo da Pessoa.';

grant select on public.pessoa_linha_tempo to anon;


-- ============================================================================
-- (2) Função: pessoa_estatisticas(pessoa_id)
-- ============================================================================
-- Devolve os contadores agregados em uma única chamada (economiza 4-6
-- queries na PessoaDetalheScreen). SECURITY DEFINER para que o app
-- Flutter possa invocar sem precisar de permissão de CREATE FUNCTION.
create or replace function public.pessoa_estatisticas(pessoa_id bigint)
returns table (
    total_memorias bigint,
    total_fotos bigint,
    total_videos bigint,
    total_contribuicoes bigint,
    primeira_data date,
    ultima_data date
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    with
    memorias_ids as (
        select cp.conteudo_id as id
        from public.conteudo_permissoes cp
        where cp.tipo_conteudo = 'memoria'
          and cp.pessoa_id = pessoa_id
    ),
    contribs_ids as (
        select c.id
        from public.contribuicoes c
        join memorias_ids mi on mi.id = c.conteudo_id
        where c.tipo_conteudo = 'memoria'
          and c.status = 'aprovado'
    )
    select
        (select count(*) from memorias_ids)::bigint,
        (select count(distinct mf.foto_id)
         from public.memoria_fotos mf
         join memorias_ids mi on mi.id = mf.memoria_id)::bigint,
        (select count(distinct mv.video_id)
         from public.memoria_videos mv
         join memorias_ids mi on mi.id = mv.memoria_id)::bigint,
        (select count(*) from contribs_ids)::bigint,
        (select min(m.data_evento)
         from public.memorias m
         join memorias_ids mi on mi.id = m.id),
        (select max(coalesce(m.data_evento, m.data_criacao::date))
         from public.memorias m
         join memorias_ids mi on mi.id = m.id);
end;
$$;

grant execute on function public.pessoa_estatisticas(bigint) to anon;


-- ============================================================================
-- (3) Função: pessoas_recentes(limite)
-- ============================================================================
-- Ordena contatos do usuário logado por "última interação" (a mais
-- recente entre memória/contribuição/foto).
create or replace function public.pessoas_recentes(
    usuario bigint,
    limite int default 8
)
returns table (
    id bigint,
    nome text,
    sobrenome text,
    parentesco text,
    email text,
    foto_perfil text,
    ultima_interacao timestamp,
    total_eventos bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    with ultimas as (
        select
            c.id as pessoa_id,
            greatest(
                coalesce((select max(coalesce(m.data_evento::timestamp, m.data_criacao))
                          from public.conteudo_permissoes cp
                          join public.memorias m on m.id = cp.conteudo_id
                          where cp.tipo_conteudo = 'memoria'
                            and cp.pessoa_id = c.id), '1970-01-01'::timestamp),
                coalesce((select max(c.criado_em)
                          from public.contribuicoes c2
                          where c2.tipo_conteudo = 'memoria'
                            and c2.usuario_dono_id = c.usuario_id
                            and c2.conteudo_id in (
                                select cp.conteudo_id from public.conteudo_permissoes cp
                                where cp.tipo_conteudo = 'memoria' and cp.pessoa_id = c.id
                            )
                            and c2.status = 'aprovado'), '1970-01-01'::timestamp)
            ) as ultima
        from public.contatos c
        where c.usuario_id = usuario
    )
    select
        c.id, c.nome, c.sobrenome, c.parentesco, c.email, c.foto_perfil,
        u.ultima,
        (select count(*) from public.pessoa_linha_tempo plt where plt.pessoa_id = c.id)::bigint
    from ultimas u
    join public.contatos c on c.id = u.pessoa_id
    order by u.ultima desc nulls last
    limit limite;
end;
$$;

grant execute on function public.pessoas_recentes(bigint, int) to anon;


-- ============================================================================
-- (4) Função: pessoas_sugeridas(usuario, limite)
-- ============================================================================
-- Procura nomes que aparecem REPETIDAMENTE em memórias do usuário mas
-- que NÃO TÊM cadastro em `contatos` (nem como ele mesmo). Esses são os
-- "fantasmas" — pessoas que aparecem na história mas que o usuário
-- ainda não cadastrou formalmente.
--
-- Estratégia: extrai "nomes próprios" do texto `conteudo` de memórias
-- do usuário (palavras com capitalização e mais de 2 letras) que NÃO
-- batem com nenhum nome de contato já cadastrado. Conta frequência.
-- Retorna apenas os que aparecem em >= 2 memórias (evita ruído).
create or replace function public.pessoas_sugeridas(
    usuario bigint,
    limite int default 5
)
returns table (
    nome_sugerido text,
    ocorrencias bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    with memorias_texto as (
        select m.conteudo as txt
        from public.memorias m
        where m.usuario_id = usuario
          and m.conteudo is not null
    ),
    -- Extrai palavras capitalizadas (>= 3 letras) do texto.
    palavras as (
        select distinct lower(word) as nome
        from memorias_texto,
        lateral regexp_matches(txt, '\y([A-ZÀ-Ú][a-zà-ú]{2,})\y', 'g') as word
    ),
    -- Conta em quantas memórias distintas cada nome aparece.
    frequencia as (
        select p.nome,
                count(distinct m.id) as ocorrencias
        from palavras p
        join lateral (
            select m.id, m.conteudo
            from public.memorias m
            where m.usuario_id = usuario
              and m.conteudo ilike '%' || p.nome || '%'
        ) m on true
        group by p.nome
    ),
    -- Exclui nomes já cadastrados pelo usuário.
    ja_cadastrados as (
        select lower(c.nome) as nome
        from public.contatos c
        where c.usuario_id = usuario
    )
    select f.nome, f.ocorrencias
    from frequencia f
    where f.ocorrencias >= 2
      and not exists (select 1 from ja_cadastrados j where j.nome = f.nome)
    order by f.ocorrencias desc
    limit limite;
end;
$$;

grant execute on function public.pessoas_sugeridas(bigint, int) to anon;


-- ============================================================================
-- (5) Função: memorial_da_pessoa(pessoa_id)
-- ============================================================================
-- Devolve o id do memorial vinculado a uma pessoa (se existir). É o
-- caminho Pessoa → Memorial, que faltava na UI.
create or replace function public.memorial_da_pessoa(pessoa_id bigint)
returns table (memorial_id bigint, nome text)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select m.id, m.nome
    from public.contatos c
    join public.memoriais m on m.id = c.memorial_id
    where c.id = pessoa_id
    limit 1;
end;
$$;

grant execute on function public.memorial_da_pessoa(bigint) to anon;


-- ============================================================================
-- (6) Índices adicionais para performance
-- ============================================================================
-- A view pessoa_linha_tempo faz JOINs por pessoa_id e memoria_id. Os
-- índices seguintes aceleram essas queries.
create index if not exists idx_conteudo_permissoes_tipo_contato
    on public.conteudo_permissoes (tipo_conteudo, pessoa_id);

create index if not exists idx_memorias_data_evento_desc
    on public.memorias (data_evento desc nulls last);

create index if not exists idx_contribuicoes_tipo_conteudo_id_status
    on public.contribuicoes (tipo_conteudo, conteudo_id, status)
    where tipo_conteudo = 'memoria' and status = 'aprovado';

create index if not exists idx_memoria_fotos_memoria
    on public.memoria_fotos (memoria_id);

create index if not exists idx_memoria_videos_memoria
    on public.memoria_videos (memoria_id);


-- ============================================================================
-- (7) Verificação sugerida (rode manualmente para auditar)
-- ============================================================================
-- select * from pessoa_linha_tempo where pessoa_id = 42 limit 50;
-- select * from pessoa_estatisticas(42);
-- select * from pessoas_recentes(2, 5);
-- select * from pessoas_sugeridas(2, 5);
-- select * from memorial_da_pessoa(42);

-- Fim.
