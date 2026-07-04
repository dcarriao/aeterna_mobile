-- ============================================================================
-- SPRINT M — MEMÓRIAS DO DIA
-- ============================================================================
-- Esta sprint transforma datas em gatilhos naturais de memória.
-- A Home mostra memórias cujo `data_evento` caiu no mesmo dia/mês
-- em anos anteriores (ou cujo `criada_em` coincide com a data, com
-- filtro de "muito recente" para evitar ruído).
--
-- Decisões (confirmadas com o usuário):
--   * Função RPC `memorias_do_dia(usuario_id, limite)` única.
--   * SEM IA — apenas match exato de (DAY, MONTH) + ranking
--     determinístico por relevância.
--   * Prioriza `data_evento` quando existir; fallback `criada_em`
--     (com janela de 30 dias para excluir memórias recentes demais).
--   * Exclui o ANO corrente (memória criada em 2026 não é
--     "memória do dia" em 2026).
--   * SEM nova tabela — apenas VIEW/RPC.
--   * NÃO usa IA, embeddings, RAG, vetores, ML.
--
-- Esta sprint:
--   1. Cria a função `memorias_do_dia(usuario_id, limite)`.
--   2. Adiciona índice funcional em `EXTRACT(DAY FROM data_evento)`
--      + `EXTRACT(MONTH FROM data_evento)`.
--   3. GRANTs no padrão MVP anônimo.
-- ============================================================================


-- (1) Função RPC principal.
--     Retorna memórias "aniversariantes" de hoje em anos anteriores
--     + memórias recentes (até 30 dias) cujo dia/mês coincide.
create or replace function public.memorias_do_dia(
    p_usuario_id bigint,
    p_limite int default 5
)
returns table (
    id bigint,
    titulo text,
    foto_principal text,
    total_pessoas bigint,
    total_contribuicoes bigint,
    total_midias bigint,
    possui_relacionamentos boolean,
    anos_decorridos integer,
    data_referencia date
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_hoje date := current_date;
    v_dia integer := extract(day from v_hoje);
    v_mes integer := extract(month from v_hoje);
    v_ano_corrente integer := extract(year from v_hoje);
    v_limite integer := greatest(p_limite, 1);
begin
    return query
    with memorias_relevantes as (
        -- Memórias com `data_evento` cujo (DAY, MONTH) coincide com
        -- hoje, mas em anos ANTERIORES ao corrente. Exclui o ano
        -- corrente para evitar "aniversário" da memória recém-criada.
        select
            m.id, m.titulo, m.data_evento as data_ref,
            coalesce(
                (select caminho_arquivo
                 from public.fotos f
                 join public.memoria_fotos mf on mf.foto_id = f.id
                 where mf.memoria_id = m.id
                 order by f.id asc
                 limit 1),
                (select caminho_arquivo
                 from public.videos v
                 join public.memoria_videos mv on mv.video_id = v.id
                 where mv.memoria_id = m.id
                 order by v.id asc
                 limit 1)
            ) as foto_principal,
            (select count(distinct cp.contato_id)
             from public.conteudo_permissoes cp
             where cp.tipo_conteudo = 'memoria'
               and cp.conteudo_id = m.id) as total_pessoas,
            (select count(*)
             from public.contribuicoes c
             where c.tipo_conteudo = 'memoria'
               and c.conteudo_id = m.id
               and c.status = 'aprovado') as total_contribuicoes,
            ((select count(*) from public.memoria_fotos mf
              where mf.memoria_id = m.id)
             + (select count(*) from public.memoria_videos mv
                where mv.memoria_id = m.id)) as total_midias,
            exists (
                select 1
                from public.memoria_relacionamentos r
                where (r.memoria_origem_id = m.id
                       or r.memoria_destino_id = m.id)
                  and r.status = 'confirmado'
            ) as possui_relacionamentos,
            (v_ano_corrente - extract(year from m.data_evento)::int)
                as anos_decorridos,
            'data_evento'::text as origem
        from public.memorias m
        where m.usuario_id = p_usuario_id
          and m.data_evento is not null
          and extract(day from m.data_evento)::int = v_dia
          and extract(month from m.data_evento)::int = v_mes
          and extract(year from m.data_evento)::int <> v_ano_corrente

        union all

        -- Memórias SEM `data_evento` que foram CRIADAS em dia/mês
        -- igual a hoje, mas com mais de 30 dias (para não sugerir
        -- memórias recém-criadas — elas já aparecem em "Suas memórias").
        select
            m.id, m.titulo, m.criada_em::date as data_ref,
            coalesce(
                (select caminho_arquivo
                 from public.fotos f
                 join public.memoria_fotos mf on mf.foto_id = f.id
                 where mf.memoria_id = m.id
                 order by f.id asc
                 limit 1),
                (select caminho_arquivo
                 from public.videos v
                 join public.memoria_videos mv on mv.video_id = v.id
                 where mv.memoria_id = m.id
                 order by v.id asc
                 limit 1)
            ) as foto_principal,
            (select count(distinct cp.contato_id)
             from public.conteudo_permissoes cp
             where cp.tipo_conteudo = 'memoria'
               and cp.conteudo_id = m.id) as total_pessoas,
            (select count(*) from public.contribuicoes c
             where c.tipo_conteudo = 'memoria'
               and c.conteudo_id = m.id
               and c.status = 'aprovado') as total_contribuicoes,
            ((select count(*) from public.memoria_fotos mf
              where mf.memoria_id = m.id)
             + (select count(*) from public.memoria_videos mv
                where mv.memoria_id = m.id)) as total_midias,
            exists (
                select 1
                from public.memoria_relacionamentos r
                where (r.memoria_origem_id = m.id
                       or r.memoria_destino_id = m.id)
                  and r.status = 'confirmado'
            ) as possui_relacionamentos,
            (v_ano_corrente - extract(year from m.criada_em)::int)
                as anos_decorridos,
            'criada_em'::text as origem
        from public.memorias m
        where m.usuario_id = p_usuario_id
          and m.data_evento is null
          and extract(day from m.criada_em)::int = v_dia
          and extract(month from m.criada_em)::int = v_mes
          and m.criada_em < (now() - interval '30 days')
    )
    select
        mr.id, mr.titulo, mr.foto_principal,
        mr.total_pessoas, mr.total_contribuicoes, mr.total_midias,
        mr.possui_relacionamentos, mr.anos_decorridos, mr.data_ref
    from memorias_relevantes mr
    order by
        mr.anos_decorridos desc nulls last,
        mr.total_pessoas desc nulls last,
        mr.total_contribuicoes desc nulls last,
        case when mr.possui_relacionamentos then 0 else 1 end,
        mr.total_midias desc nulls last,
        mr.data_ref desc nulls last
    limit v_limite;
end;
$$;

grant execute on function public.memorias_do_dia(bigint, int) to anon;

comment on function public.memorias_do_dia(bigint, int) is
    'Sprint M: retorna memórias cujo data_evento (fallback criada_em) coincide com o dia/mês de hoje, em anos anteriores. Sem IA — apenas match determinístico. Ranking por relevância (anos, pessoas, contribuições, relações, mídias).';


-- (2) Índices funcionais para acelerar o filtro por (DAY, MONTH).
--     Crítico para a RPC acima — sem eles, em bases grandes o
--     filtro faria sequential scan.
create index if not exists idx_memorias_data_evento_dia_mes
    on public.memorias (
        extract(day from data_evento)::int,
        extract(month from data_evento)::int
    )
    where data_evento is not null;

create index if not exists idx_memorias_criada_em_dia_mes
    on public.memorias (
        extract(day from criada_em)::int,
        extract(month from criada_em)::int
    )
    where data_evento is null
      and criada_em < (now() - interval '30 days');

-- Índice composto para o WHERE principal da RPC.
create index if not exists idx_memorias_do_dia_usuario
    on public.memorias (usuario_id, data_evento, ultima_atualizacao_em)
    where data_evento is not null;


-- (3) Verificação sugerida (rode manualmente para auditar)
-- select * from public.memorias_do_dia(2, 5);
--
-- Resultado esperado: lista de até 5 memórias do mesmo dia/mês
-- em anos anteriores (ou de memórias recentes com `criada_em` no
-- mesmo dia/més e mais de 30 dias), ordenadas por relevância.
-- Fim.
