-- ============================================================================
-- S.9.2-fix — Caminho de ENTREGA do push (não registro de token)
-- ============================================================================
-- Problema: FCM token chega em push_dispositivos, mas o aparelho não recebe push.
-- Causa comum 1: trigger antigo checava NEW.tipo='compartilhamento' (coluna
--   inexistente; valor certo é papel='compartilhado') — ver sprint_s9_3_2.
-- Causa comum 2: Database Webhook `push_notificacoes` não criado no Dashboard
--   → notificacoes nasc com enviada=false / tentativas=0 para sempre.
-- Causa comum 3: secret FIREBASE_SERVICE_ACCOUNT_JSON ausente/errado na Edge Fn.
--
-- Este arquivo:
--   A) Garante o trigger correto (papel='compartilhado')
--   B) Cria RPC criar_notificacao_teste(pessoa_id) para teste controlado
--   C) Documenta SELECTs de diagnóstico (rodar e ler o resultado)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- A) Trigger correto (idempotente)
-- ---------------------------------------------------------------------------
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

DROP TRIGGER IF EXISTS trg_push_memoria_compartilhada ON public.conteudo_permissoes;
CREATE TRIGGER trg_push_memoria_compartilhada
    AFTER INSERT ON public.conteudo_permissoes
    FOR EACH ROW
    EXECUTE FUNCTION public.tg_push_memoria_compartilhada();


-- ---------------------------------------------------------------------------
-- B) RPC de teste — insere notificacao tipo='teste' (CHECK do schema aceita)
-- ---------------------------------------------------------------------------
-- Depois de rodar, se o Webhook existir a Edge Function dispara sozinha.
-- Sem webhook: o app novo chama send-push com { notificacao_id } após share;
-- ou invoque manualmente (Dashboard → Edge Functions → send-push → Invoke):
--   { "notificacao_id": <id retornado> }

CREATE OR REPLACE FUNCTION public.criar_notificacao_teste(p_pessoa_id bigint)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id bigint;
BEGIN
    INSERT INTO public.notificacoes
        (pessoa_id, tipo, titulo, corpo, dados, conteudo_id, conteudo_tipo)
    VALUES (
        p_pessoa_id,
        'teste',
        'Teste aEterna',
        'Se você recebeu isto, o caminho de entrega está ok.',
        jsonb_build_object('route', 'home', 'origem', 'criar_notificacao_teste'),
        NULL,
        NULL
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.criar_notificacao_teste(bigint) TO anon;
GRANT EXECUTE ON FUNCTION public.criar_notificacao_teste(bigint) TO authenticated;


-- ---------------------------------------------------------------------------
-- C) DIAGNÓSTICO — rode no SQL Editor e leia o resultado
-- ---------------------------------------------------------------------------
-- Substitua 5 pelo pessoas.id do destinatário (só para diagnóstico; NÃO no app).

-- C1) Token ativo?
-- SELECT id, pessoa_id, left(token,12)||'…'||right(token,8) AS token_hint,
--        plataforma, ativo, last_seen_at, updated_at
-- FROM push_dispositivos
-- WHERE pessoa_id = 5
-- ORDER BY updated_at DESC;

-- C2) Trigger instalado com a função correta (deve mencionar NEW.papel)?
-- SELECT tg.tgname, pg_get_functiondef(p.oid) AS def
-- FROM pg_trigger tg
-- JOIN pg_proc p ON p.oid = tg.tgfoid
-- WHERE tg.tgrelid = 'public.conteudo_permissoes'::regclass
--   AND NOT tg.tgisinternal
--   AND tg.tgname = 'trg_push_memoria_compartilhada';

-- C3) Notificações recentes do destinatário (enviada / erro_envio = prova do envio)
-- SELECT id, pessoa_id, tipo, titulo, enviada, tentativas, erro_envio, created_at, enviada_at
-- FROM notificacoes
-- WHERE pessoa_id = 5
-- ORDER BY created_at DESC
-- LIMIT 20;

-- Interpretação C3:
--   • Nenhuma linha após compartilhar memória → trigger não rodou / SQL s9.3.2+fix não aplicado
--   • Linha com enviada=false, tentativas=0, erro_envio IS NULL → Webhook NÃO chamou send-push
--   • Linha com erro_envio LIKE 'missing%' / 'FCM auth%' → secret FIREBASE_SERVICE_ACCOUNT_JSON
--   • Linha com erro_envio LIKE 'nenhum token%' → token não está em push_dispositivos ativo
--   • Linha com enviada=true → FCM aceitou; se aparelho não mostrou, ver APNs/Firebase console

-- C4) Teste controlado (pessoa.id do destinatário):
-- SELECT public.criar_notificacao_teste(5);
-- Depois: ver C3 — a nova linha deve mudar (tentativas/enviada/erro_envio) em segundos.
-- Se NÃO mudar: Webhook ausente E/OU Edge Function não deployada.
-- Deploy: supabase functions deploy send-push
-- Webhook: Dashboard → Database → Webhooks → Create
--   Nome: push_notificacoes | Tabela: notificacoes | Eventos: INSERT
--   Tipo: Supabase Edge Functions | Função: send-push

-- C5) Secret obrigatório (Dashboard → Edge Functions → Secrets):
--   FIREBASE_SERVICE_ACCOUNT_JSON = conteúdo JSON da service account do projeto
--   Firebase `aeterna-94450` (client_email + private_key). SUPABASE_URL e
--   SUPABASE_SERVICE_ROLE_KEY já vêm automaticamente no runtime da Edge Function.
-- ============================================================================
