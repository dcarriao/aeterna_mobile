-- =============================================================================
-- SPRINT S.9.3.2 — PARTICIPAR ≠ COMPARTILHAR em conteudo_permissoes
-- Executar : SQL Editor — ANTES de distribuir o build com este código
--            (o app passa a filtrar/gravar a coluna `papel`).
-- Downtime : nenhum. Rollback: DROP COLUMN papel + recriar função anterior.
-- =============================================================================

-- 1. Coluna papel
ALTER TABLE conteudo_permissoes
  ADD COLUMN IF NOT EXISTS papel text NOT NULL DEFAULT 'participante';

ALTER TABLE conteudo_permissoes DROP CONSTRAINT IF EXISTS chk_papel_permissao;
ALTER TABLE conteudo_permissoes
  ADD CONSTRAINT chk_papel_permissao
  CHECK (papel IN ('participante', 'compartilhado'));

CREATE INDEX IF NOT EXISTS idx_conteudo_permissoes_papel
  ON conteudo_permissoes (tipo_conteudo, papel, pessoa_id);

-- 2. Push SÓ para compartilhamento (a intenção original da função que
--    referenciava NEW.tipo — agora com a coluna que de fato existe).
CREATE OR REPLACE FUNCTION public.tg_push_memoria_compartilhada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_titulo_conteudo text;
begin
    -- Participante apenas aparece na memória: NÃO recebe notificação.
    if NEW.papel is distinct from 'compartilhado' then
        return NEW;
    end if;
    if NEW.pessoa_id is null then
        return NEW;
    end if;
    -- Pet nunca recebe notificação/push.
    if exists (
        select 1 from public.pessoas p
        where p.id = NEW.pessoa_id and p.tipo = 'pet'
    ) then
        return NEW;
    end if;

    if NEW.tipo_conteudo = 'memoria' then
        select coalesce(titulo, 'uma memória') into v_titulo_conteudo
        from public.memorias where id = NEW.conteudo_id limit 1;
    elsif NEW.tipo_conteudo = 'memorial' then
        select coalesce(nome, 'um memorial') into v_titulo_conteudo
        from public.memoriais where id = NEW.conteudo_id limit 1;
    else
        v_titulo_conteudo := 'um conteúdo';
    end if;

    insert into public.notificacoes
        (pessoa_id, tipo, titulo, corpo, dados, conteudo_id, conteudo_tipo)
    values (
        NEW.pessoa_id,
        'memoria_compartilhada',
        'Conteúdo compartilhado com você',
        'Você recebeu acesso a ' || coalesce(v_titulo_conteudo, 'um conteúdo') || '.',
        jsonb_build_object(
            'route',        NEW.tipo_conteudo,
            'conteudo_id',  NEW.conteudo_id,
            'permissao_id', NEW.id
        ),
        NEW.id,
        'conteudo_permissao'
    )
    on conflict (pessoa_id, tipo, conteudo_id, conteudo_tipo)
        where conteudo_id is not null and conteudo_tipo is not null
    do nothing;
    return NEW;
end;
$function$;

-- 3. DADOS EXISTENTES: linhas antigas não têm como ser classificadas
--    automaticamente (participante e compartilhado eram idênticos).
--    Todas ficam como 'participante' (default). Duas formas de acertar:
--    a) Reabrir e salvar cada memória no app novo (regrava os dois papéis); ou
--    b) Manual — listar e classificar:
SELECT cp.id, cp.conteudo_id, m.titulo, cp.pessoa_id, p.nome, cp.papel
FROM conteudo_permissoes cp
JOIN memorias m ON m.id = cp.conteudo_id
JOIN pessoas  p ON p.id = cp.pessoa_id
WHERE cp.tipo_conteudo = 'memoria'
ORDER BY cp.conteudo_id, p.nome;
--    Para marcar alguém como apenas-compartilhado (ex.: Dionir na memória X):
--    UPDATE conteudo_permissoes SET papel='compartilhado' WHERE id = <id da linha>;

-- 4. INVESTIGAR (origem do "Dionir tem última memória" na Home): se a view
--    pessoa_linha_tempo usa conteudo_permissoes, ela precisa filtrar
--    papel='participante'. Rodar e me enviar o resultado:
SELECT pg_get_viewdef('public.pessoa_linha_tempo'::regclass, true);
-- (se der "does not exist", é RPC: enviar o resultado de)
-- SELECT pg_get_functiondef('public.pessoa_linha_tempo'::regproc);
