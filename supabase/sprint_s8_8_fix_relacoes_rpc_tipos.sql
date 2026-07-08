-- ============================================================================
-- S.8.8 — Correção de RPC, tipos_relacionamento, Beatriz duplicata
-- ============================================================================
-- Ordem de execução: rodar INTEIRO (BEGIN … COMMIT).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. CORRIGE RPC listar_relacionamentos_pessoa
--    Remove o filtro `r.usuario_id = (SELECT criado_por_id...)` que foi
--    adicionado pelo sprint_s8_fix_rls.sql e QUEBRA a consulta quando
--    o criado_por_id não coincide com o usuario_id das relações.
--    A query agora usa APENAS pessoa_a_id/pessoa_b_id (sem filtro de
--    usuario_id), pois o isolamento é responsabilidade da aplicação.
-- ============================================================================
SELECT '=== 1. Corrigindo RPC listar_relacionamentos_pessoa ===' AS info;

DROP FUNCTION IF EXISTS public.listar_relacionamentos_pessoa(BIGINT);

CREATE OR REPLACE FUNCTION public.listar_relacionamentos_pessoa(p_pessoa_id BIGINT)
RETURNS TABLE (
    relacionamento_id BIGINT,
    outra_pessoa_id BIGINT,
    outra_pessoa_nome TEXT,
    tipo TEXT,
    rotulo_da_outra_para_mim TEXT,
    rotulo_de_mim_para_outra TEXT,
    confirmado BOOLEAN,
    observacoes TEXT,
    data_inicio DATE,
    data_fim DATE,
    criado_em TIMESTAMP WITHOUT TIME ZONE
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id AS relacionamento_id,
        CASE WHEN r.pessoa_a_id = p_pessoa_id THEN r.pessoa_b_id ELSE r.pessoa_a_id END AS outra_pessoa_id,
        (SELECT nome FROM public.pessoas WHERE id =
            CASE WHEN r.pessoa_a_id = p_pessoa_id THEN r.pessoa_b_id ELSE r.pessoa_a_id END
        ) AS outra_pessoa_nome,
        r.tipo,
        CASE WHEN r.pessoa_a_id = p_pessoa_id THEN r.relacao_b_para_a ELSE r.relacao_a_para_b END AS rotulo_da_outra_para_mim,
        CASE WHEN r.pessoa_a_id = p_pessoa_id THEN r.relacao_a_para_b ELSE r.relacao_b_para_a END AS rotulo_de_mim_para_outra,
        r.confirmado,
        r.observacoes,
        r.data_inicio,
        r.data_fim,
        r.criado_em
    FROM public.pessoas_relacionamentos r
    WHERE (r.pessoa_a_id = p_pessoa_id OR r.pessoa_b_id = p_pessoa_id)
      AND r.confirmado = true
    ORDER BY r.tipo, r.criado_em DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.listar_relacionamentos_pessoa(BIGINT) TO anon;

-- ============================================================================
-- 2. ATUALIZA tipos_relacionamento com nível de hierarquia
--    Níveis:
--      0 = tataravô/bisavô (ancestrais distantes)
--      1 = bisavô/bisavó
--      2 = avô/avó
--      3 = pai/mãe/padrasto/madrasta
--      4 = irmão/cônjuge/primo/tio/enteado
--      5 = filho/sobrinho/neto/enteado
--    Adiciona: Enteado, Enteada
-- ============================================================================
SELECT '=== 2. Atualizando tipos_relacionamento ===' AS info;

-- Adiciona coluna nivel se não existir
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tipos_relacionamento'
        AND column_name = 'nivel'
    ) THEN
        ALTER TABLE public.tipos_relacionamento ADD COLUMN nivel INTEGER DEFAULT 4;
    END IF;
END $$;

-- Atualiza níveis existentes
UPDATE public.tipos_relacionamento SET nivel = 0 WHERE id IN ('TATARAVO');
UPDATE public.tipos_relacionamento SET nivel = 1 WHERE id IN ('BISAVO');
UPDATE public.tipos_relacionamento SET nivel = 2 WHERE id IN ('AVO');
UPDATE public.tipos_relacionamento SET nivel = 3 WHERE id IN ('PAI', 'MAE', 'PADRASTO', 'MADRASTA');
UPDATE public.tipos_relacionamento SET nivel = 4 WHERE id IN ('IRMAO', 'CONJUGE', 'COMPANHEIRO', 'PRIMO', 'TIO', 'CUNHADO', 'ENTEADO');
UPDATE public.tipos_relacionamento SET nivel = 5 WHERE id IN ('FILHO', 'FILHA', 'NETO', 'BISNETO', 'SOBRINHO', 'AFILHADO', 'GENRO', 'NORA', 'SOGRO');

-- Insere Enteado/Enteada se não existirem
INSERT INTO public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria, ativo, nivel)
SELECT 'ENTEADO', 'Enteado(a)', 'Padrasto/Madrasta', 'familia', true, 4
WHERE NOT EXISTS (SELECT 1 FROM public.tipos_relacionamento WHERE id = 'ENTEADO');

INSERT INTO public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria, ativo, nivel)
SELECT 'PADRASTO', 'Padrasto', 'Enteado(a)', 'familia', true, 3
WHERE NOT EXISTS (SELECT 1 FROM public.tipos_relacionamento WHERE id = 'PADRASTO');

INSERT INTO public.tipos_relacionamento (id, rotulo_a_para_b, rotulo_b_para_a, categoria, ativo, nivel)
SELECT 'MADRASTA', 'Madrasta', 'Enteado(a)', 'familia', true, 3
WHERE NOT EXISTS (SELECT 1 FROM public.tipos_relacionamento WHERE id = 'MADRASTA');

SELECT id, rotulo_a_para_b, rotulo_b_para_a, categoria, nivel
FROM public.tipos_relacionamento ORDER BY nivel, id;

-- ============================================================================
-- 3. VALIDAÇÃO — listar_relacionamentos_pessoa funciona
-- ============================================================================
SELECT '=== 3. Validando RPC ===' AS info;
-- Teste: busca relações de Darlan (pessoa.id=5)
SELECT relacionamento_id, outra_pessoa_id, outra_pessoa_nome, tipo,
       rotulo_da_outra_para_mim, rotulo_de_mim_para_outra
FROM public.listar_relacionamentos_pessoa(5)
LIMIT 10;

-- Teste: busca relações de Alice (pessoa.id=6)
SELECT relacionamento_id, outra_pessoa_id, outra_pessoa_nome, tipo,
       rotulo_da_outra_para_mim, rotulo_de_mim_para_outra
FROM public.listar_relacionamentos_pessoa(6)
LIMIT 10;

-- ============================================================================
-- 4. QUERY PADRÃO PARA PERFIL DE PESSOA
--    select a.pessoa_b_id, a.relacao_a_para_b as relacao, b.nome, b.sobrenome
--    from pessoas_relacionamentos a
--    join pessoas b on a.pessoa_b_id = b.id
--    where a.pessoa_a_id = :pessoa_aberta;
-- ============================================================================
SELECT '=== 4. Query padrao para perfil (exemplo Darlan id=5) ===' AS info;
SELECT a.pessoa_b_id, a.relacao_a_para_b AS relacao, b.nome, b.sobrenome
FROM pessoas_relacionamentos a
JOIN pessoas b ON a.pessoa_b_id = b.id
WHERE a.pessoa_a_id = 5
  AND a.confirmado = true;

-- ============================================================================
-- 5. BEATRIZ — auditar duplicatas
-- ============================================================================
SELECT '=== 5. Auditando duplicatas de Beatriz ===' AS info;
SELECT id, nome, sobrenome, email, telefone, data_nascimento, situacao,
       criado_por_id, _legacy_contato_id, _legacy_usuario_id, merged_into_id
FROM pessoas
WHERE nome ILIKE 'beatriz%'
ORDER BY id;

-- Lista FK references das Beatriz encontradas
WITH beatriz_ids AS (
    SELECT id FROM pessoas WHERE nome ILIKE 'beatriz%'
)
SELECT 'pessoas_relacionamentos' AS tabela, pessoa_a_id, pessoa_b_id, tipo
FROM pessoas_relacionamentos WHERE pessoa_a_id IN (SELECT id FROM beatriz_ids) OR pessoa_b_id IN (SELECT id FROM beatriz_ids)
UNION ALL
SELECT 'conteudo_permissoes', pessoa_id, NULL, NULL
FROM conteudo_permissoes WHERE pessoa_id IN (SELECT id FROM beatriz_ids)
UNION ALL
SELECT 'memorial_pessoas', pessoa_id, NULL, NULL
FROM memorial_pessoas WHERE pessoa_id IN (SELECT id FROM beatriz_ids)
UNION ALL
SELECT 'convites_familiares', pessoa_id, NULL, NULL
FROM convites_familiares WHERE pessoa_id IN (SELECT id FROM beatriz_ids)
UNION ALL
SELECT 'pessoa_identificadores', pessoa_id, NULL, NULL
FROM pessoa_identificadores WHERE pessoa_id IN (SELECT id FROM beatriz_ids);

-- ============================================================================
-- 6. MEMORIAL DOUGLAS — auditar
-- ============================================================================
SELECT '=== 6. Auditando Memorial Douglas ===' AS info;
SELECT m.id, m.nome, m.usuario_id, m.criado_em, mp.pessoa_id, p.nome AS pessoa_nome
FROM memoriais m
LEFT JOIN memorial_pessoas mp ON mp.memorial_id = m.id
LEFT JOIN pessoas p ON p.id = mp.pessoa_id
WHERE m.nome ILIKE '%douglas%'
ORDER BY m.id;

-- Verifica se memorial_pessoas tem vínculo correto
SELECT mp.memorial_id, mp.pessoa_id, p.nome, m.nome AS memorial_nome
FROM memorial_pessoas mp
JOIN pessoas p ON p.id = mp.pessoa_id
JOIN memoriais m ON m.id = mp.memorial_id
ORDER BY mp.memorial_id;

-- ============================================================================
-- 7. COMPARTILHAMENTOS — comparação aba vs perfil
-- ============================================================================
SELECT '=== 7. Compartilhamentos: conteudo_permissoes vs memoriais.usuario_id ===' AS info;
-- Aba Compartilhadas: conteudo_permissoes para o usuario logado
SELECT 'conteudo_permissoes (compartilhadas)' AS origem, cp.tipo_conteudo, cp.conteudo_id, cp.pessoa_id
FROM conteudo_permissoes cp
WHERE cp.pessoa_id IN (5, 6)
LIMIT 10;

-- Perfil: memoriais pelo usuario_id
SELECT 'memoriais (perfil)' AS origem, m.id, m.nome, m.usuario_id
FROM memoriais m
WHERE m.usuario_id = 5;

COMMIT;
