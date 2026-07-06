-- ============================================================================
-- r6_limpar_relacoes_fantasmas.sql
-- Sprint R.6 — Auditoria/limpeza de relações criadas pelo trigger legado
-- ============================================================================
-- O trigger `trg_pessoa_cria_relacionamento_legado` (agora removido) criava
-- relações automaticamente no `AFTER INSERT ON contatos` quando o campo
-- `parentesco` estava preenchido. Ele:
--   1. Mapeava `parentesco` (string livre) para um tipo estável
--   2. Ligava a pessoa nova ao PRIMEIRo outro contato encontrado (`LIMIT 1`)
--   3. Invertia rótulos baseado na ORDEM DOS IDs, não na semântica
--
-- Como o Dart (NovaPessoaScreen._salvar) TAMBÉM cria a relação correta
-- envolvendo o usuário da conta, o trigger pode ter gerado DUPLICATAS
-- ou RELAÇÕES INCORRETAS (com a pessoa errada).
--
-- USO:
--   1. Defina @SEU_USUARIO_ID
--   2. Execute os SELECTs para AUDITAR
--   3. Se confirmar que há relações fantasmas, descomente o DELETE
-- ============================================================================

-- ============================================================================
-- PASS0: CONFIGURACAO
-- ============================================================================
-- !!! SUBSTITUA PELO SEU usuario_id !!!
-- (opcional: comente esta linha e use um filtro diferente)
-- DO $$ BEGIN RAISE 'Defina @SEU_USUARIO_ID antes de executar'; END $$;

-- ============================================================================
-- PASS1: LISTAR TODOS OS CONTATOS COM parentesco PREENCHIDO
-- ============================================================================
-- O trigger só disparava quando `parentesco` não era nulo/vazio.
-- Estes são os contatos que PODEM ter gerado relações automáticas.
select
    c.id as contato_id,
    c.nome as contato_nome,
    c.parentesco,
    c.data_criacao,
    c.usuario_id
from public.contatos c
where c.usuario_id = <SEU_USUARIO_ID>          -- FILTRO OBRIGATORIO
  and c.parentesco is not null
  and c.parentesco <> ''
order by c.data_criacao;

-- ============================================================================
-- PASS2: LISTAR O MAPEAMENTO parentesco → TIPO (o que o trigger faria)
-- ============================================================================
-- Mostra qual tipo estável o trigger teria usado baseado no parentesco.
with mapeamento as (
    select
        c.id as contato_id,
        c.nome as contato_nome,
        c.parentesco,
        c.data_criacao,
        case lower(trim(c.parentesco))
            when 'pai' then 'PAI'
            when 'mãe', 'mae' then 'MAE'
            when 'filho' then 'FILHO'
            when 'filha' then 'FILHA'
            when 'irmão', 'irmao' then 'IRMAO'
            when 'irmã', 'irma' then 'IRMAO'
            when 'avô', 'avó', 'avo' then 'AVO'
            when 'neto' then 'NETO'
            when 'neta' then 'NETO'
            when 'tio' then 'TIO'
            when 'tia' then 'TIO'
            when 'primo' then 'PRIMO'
            when 'prima' then 'PRIMO'
            when 'amigo' then 'AMIGO'
            when 'amiga' then 'AMIGO'
            else null
        end as tipo_mapeado
    from public.contatos c
    where c.usuario_id = <SEU_USUARIO_ID>
      and c.parentesco is not null
      and c.parentesco <> ''
)
select * from mapeamento
where tipo_mapeado is not null
order by data_criacao;

-- ============================================================================
-- PASS3: LISTAR RELAÇÕES CRIADAS PELO TRIGGER (suspeitas)
-- ============================================================================
-- Critério: para cada contato com parentesco mapeável, encontra as relações
-- em `pessoas_relacionamentos` que:
--   a) envolvem esse contato
--   b) têm o tipo que o trigger teria usado
--   c) NÃO seguem o padrão do Dart (pessoaA = usuarioId + inversão correta)
--
-- O trigger usava `LIMIT 1` para escolher o outro lado. Se o usuário tem
-- MAIS de 2 contatos, a relação pode ter sido com a PESSOA ERRADA.
--
-- Relações SEGURAS (NÃO listadas aqui):
--   - Criadas pelo AdicionarRelacionamentoScreen (qualquer par de pessoas)
--   - Criadas pelo NovaPessoaScreen._salvar() (sempre envolvem o usuário)
--   - Relações com tipos não mapeados pelo trigger (CONJUGE, PADRINHO, etc.)
with
contatos_do_usuario as (
    select id, nome, data_criacao
    from public.contatos
    where usuario_id = <SEU_USUARIO_ID>
),
contatos_com_parentesco as (
    select
        c.id,
        c.nome,
        c.parentesco,
        c.data_criacao,
        case lower(trim(c.parentesco))
            when 'pai' then 'PAI'
            when 'mãe', 'mae' then 'MAE'
            when 'filho' then 'FILHO'
            when 'filha' then 'FILHA'
            when 'irmão', 'irmao' then 'IRMAO'
            when 'irmã', 'irma' then 'IRMAO'
            when 'avô', 'avó', 'avo' then 'AVO'
            when 'neto' then 'NETO'
            when 'neta' then 'NETO'
            when 'tio' then 'TIO'
            when 'tia' then 'TIO'
            when 'primo' then 'PRIMO'
            when 'prima' then 'PRIMO'
            when 'amigo' then 'AMIGO'
            when 'amiga' then 'AMIGO'
            else null
        end as tipo_mapeado
    from public.contatos c
    where c.usuario_id = <SEU_USUARIO_ID>
      and c.parentesco is not null
      and c.parentesco <> ''
),
relacoes_dos_contatos_com_parentesco as (
    select
        r.id as relacao_id,
        r.pessoa_a_id,
        r.pessoa_b_id,
        r.tipo,
        r.relacao_a_para_b,
        r.relacao_b_para_a,
        r.criado_em,
        cp.id as contato_com_parentesco_id,
        cp.nome as contato_com_parentesco_nome,
        cp.parentesco as contato_parentesco_str,
        cp.tipo_mapeado,
        case
            when r.pessoa_a_id = cp.id then r.pessoa_b_id
            else r.pessoa_a_id
        end as outra_pessoa_id,
        -- O trigger SEMPRE usava new.id como pessoa_a_id se new.id < outro.id
        -- Vamos verificar se a relação tem labels que batem com o trigger
        -- vs. labels que batem com o Dart
        case
            when cp.tipo_mapeado is not null and r.tipo = cp.tipo_mapeado
            then 'TIPO_CONFERE'
            else 'TIPO_DIVERGE'
        end as status_tipo
    from public.pessoas_relacionamentos r
    join contatos_com_parentesco cp
        on (r.pessoa_a_id = cp.id or r.pessoa_b_id = cp.id)
    where r.usuario_id = <SEU_USUARIO_ID>
)
select
    r.relacao_id,
    r.contato_com_parentesco_nome as contato_com_parentesco,
    r.contato_parentesco_str as parentesco_original,
    r.tipo_mapeado as tipo_que_trigger_geraria,
    r.tipo as tipo_armazenado,
    r.status_tipo,
    (select nome from contatos_do_usuario where id = r.pessoa_a_id) as pessoa_a_nome,
    r.relacao_a_para_b,
    (select nome from contatos_do_usuario where id = r.pessoa_b_id) as pessoa_b_nome,
    r.relacao_b_para_a,
    r.criado_em as relacao_criada_em,
    -- Se a outra pessoa NÃO é o primeiro contato do usuário, é PROVAVELMENTE
    -- uma relação fantasma (trigger linkou com a pessoa errada)
    case
        when r.outra_pessoa_id = (select id from contatos_do_usuario order by data_criacao limit 1)
        then 'PROVAVELMENTE_CORRETA (outra pessoa é o 1o contato)'
        else 'SUSPEITA (outra pessoa NÃO é o 1o contato)'
    end as analise
from relacoes_dos_contatos_com_parentesco r
where r.status_tipo = 'TIPO_CONFERE'  -- só relações cujo tipo o trigger geraria
order by r.criado_em;

-- ============================================================================
-- PASS4: LISTAR POSSÍVEIS DUPLICATAS
-- ============================================================================
-- Mesmo contato pode ter 2 relações com o MESMO tipo mas pessoas DIFERENTES
-- (uma do trigger, uma do Dart). Isto é anômalo.
with
relacoes_por_contato as (
    select
        case
            when r.pessoa_a_id = <SEU_CONTATO_ID> then r.pessoa_a_id
            else r.pessoa_b_id
        end as contato_id,
        r.tipo,
        count(*) as qtd_relacoes
    from public.pessoas_relacionamentos r
    where r.usuario_id = <SEU_USUARIO_ID>
    group by contato_id, r.tipo
    having count(*) > 1
)
select
    rc.contato_id,
    c.nome as contato_nome,
    rc.tipo,
    rc.qtd_relacoes
from relacoes_por_contato rc
left join public.contatos c on c.id = rc.contato_id
order by rc.qtd_relacoes desc;

-- ============================================================================
-- PASS5: DELETE COMENTADO (NÃO EXECUTA AUTOMATICAMENTE)
-- ============================================================================
-- Só descomente DEPOIS de auditar os PASSOS 1-4 e confirmar as relações.
--
-- Opcao A: Remover relações onde o tipo NÃO confere com o parentesco
-- (o trigger NÃO criaria estas — provavelmente são manuais e corretas)
-- ==> PULAR (não remover relações manuais)
--
-- Opcao B: Remover relações SUSPEITAS (tipo confere + outra pessoa não
-- é o primeiro contato do usuário).
--
-- ATENÇÃO: Antes de executar o DELETE, confirme MANUALMENTE cada
-- `relacao_id` listado no PASS3 com `analise = 'SUSPEITA'`.
--
-- delete from public.pessoas_relacionamentos
-- where id IN (
--     with
--     contatos_do_usuario as (
--         select id, data_criacao
--         from public.contatos
--         where usuario_id = <SEU_USUARIO_ID>
--     ),
--     contatos_com_parentesco as (
--         select
--             c.id,
--             case lower(trim(c.parentesco))
--                 when 'pai' then 'PAI'
--                 when 'mãe', 'mae' then 'MAE'
--                 when 'filho' then 'FILHO'
--                 when 'filha' then 'FILHA'
--                 when 'irmão', 'irmao' then 'IRMAO'
--                 when 'irmã', 'irma' then 'IRMAO'
--                 when 'avô', 'avó', 'avo' then 'AVO'
--                 when 'neto' then 'NETO'
--                 when 'neta' then 'NETO'
--                 when 'tio' then 'TIO'
--                 when 'tia' then 'TIO'
--                 when 'primo' then 'PRIMO'
--                 when 'prima' then 'PRIMO'
--                 when 'amigo' then 'AMIGO'
--                 when 'amiga' then 'AMIGO'
--                 else null
--             end as tipo_mapeado
--         from public.contatos c
--         where c.usuario_id = <SEU_USUARIO_ID>
--           and c.parentesco is not null
--           and c.parentesco <> ''
--     ),
--     suspeitas as (
--         select r.id,
--                case
--                    when r.pessoa_a_id = cp.id then r.pessoa_b_id
--                    else r.pessoa_a_id
--                end as outra_pessoa_id
--         from public.pessoas_relacionamentos r
--         join contatos_com_parentesco cp
--             on (r.pessoa_a_id = cp.id or r.pessoa_b_id = cp.id)
--         where r.usuario_id = <SEU_USUARIO_ID>
--           and r.tipo = cp.tipo_mapeado
--           and cp.tipo_mapeado is not null
--     )
--     select s.id
--     from suspeitas s
--     where s.outra_pessoa_id <> (
--         select id from contatos_do_usuario order by data_criacao limit 1
--     )
-- )
-- returning id;

-- ============================================================================
-- PASS6: VALIDACAO DEPOIS DA LIMPEZA
-- ============================================================================
-- (execute DEPOIS do DELETE, se aplicável)
--
-- -- Verificar se sobraram relações órfãs
-- select count(*) as relacoes_restantes
-- from public.pessoas_relacionamentos
-- where usuario_id = <SEU_USUARIO_ID>;
--
-- -- Listar relações restantes (só as manuais/corretas)
-- select
--     r.id,
--     a.nome as pessoa_a,
--     r.relacao_a_para_b,
--     b.nome as pessoa_b,
--     r.relacao_b_para_a,
--     r.tipo,
--     r.criado_em
-- from public.pessoas_relacionamentos r
-- left join public.contatos a on a.id = r.pessoa_a_id
-- left join public.contatos b on b.id = r.pessoa_b_id
-- where r.usuario_id = <SEU_USUARIO_ID>
-- order by r.criado_em;

-- ============================================================================
-- NOTAS DE SEGURANCA
-- ============================================================================
-- 1. TODAS as queries têm filtro obrigatório por usuario_id
-- 2. Nenhum DELETE é executado sem descomentar manualmente
-- 3. A primeira criação de contato de cada usuário (data_criacao mais antiga)
--    é provavelmente o PRÓPRIO usuário. Relações com outros contatos são suspeitas.
-- 4. Se o usuário tem APENAS 2 contatos (ele mesmo + 1), o trigger e o Dart
--    criam a MESMA relação (não há duplicata). Execute apenas se houver 3+.
-- 5. Relações com tipos NÃO mapeados (CONJUGE, PADRINHO, CUNHADO, etc.)
--    foram criadas exclusivamente pelo Dart → sempre corretas.
