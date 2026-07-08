-- ============================================================
-- Sprint S.8.5 — Reparo: migração LEGADO → Auth
-- ============================================================
-- ATENÇÃO: Só execute DEPOIS de rodar o diagnóstico
-- (sprint_s8_5_diagnostico_auth.sql) e CONFIRMAR que existem
-- pessoas sem auth_user_id.
--
-- Este script:
--   ✅ Cria Auth users para pessoas sem vínculo
--   ✅ Aproveita Auth users já existentes (mesmo email)
--   ✅ Corrige auth_user_id inválido
--   ❌ NUNCA apaga pessoas
--   ❌ NUNCA apaga auth.users
--   ❌ NUNCA recria pessoas
--   ❌ NUNCA altera IDs de pessoas
--   ❌ NUNCA executa DELETE/TRUNCATE/DROP (F4)
--
-- Execute no SQL Editor do Supabase Dashboard:
--   https://supabase.com/dashboard/project/zfpvfljmnlgsqiqdxmka/sql/new
-- ============================================================

-- ============================================================
-- PASSO 1: CORRIGIR auth_user_id INVÁLIDO
-- (= aponta para UUID que não existe mais em auth.users)
-- ============================================================
-- Zera o vínculo quebrado (sem apagar nada)
UPDATE public.pessoas p
SET auth_user_id = NULL
WHERE p.auth_user_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.auth_user_id);

-- ============================================================
-- PASSO 2: CRIAR AUTH USERS FALTANTES
-- ============================================================
DO $$
DECLARE
    r RECORD;
    v_user_id UUID;
    v_count INT := 0;
    v_now TIMESTAMPTZ := now();
BEGIN
    FOR r IN
        SELECT p.id, p.email, p.nome
        FROM public.pessoas p
        WHERE p.auth_user_id IS NULL
          AND p.email IS NOT NULL
          AND p.email <> ''
        ORDER BY p.id
    LOOP
        -- Já existe Auth user com este e-mail?
        SELECT id INTO v_user_id
        FROM auth.users
        WHERE email = LOWER(TRIM(r.email));

        IF v_user_id IS NULL THEN
            v_user_id := gen_random_uuid();

            INSERT INTO auth.users (
                id, instance_id,
                email, encrypted_password,
                email_confirmed_at, confirmation_sent_at,
                confirmation_token, recovery_token,
                email_change_token_current, email_change_token_new,
                raw_app_meta_data, raw_user_meta_data,
                created_at, updated_at, aud, role
            ) VALUES (
                v_user_id,
                '00000000-0000-0000-0000-000000000000',
                LOWER(TRIM(r.email)),
                -- Senha temporária (bcrypt) - usuário deve usar "Esqueci senha"
                '$2a$10$' || encode(gen_random_bytes(13), 'hex'),
                v_now, v_now,
                encode(gen_random_bytes(32), 'hex'),
                encode(gen_random_bytes(32), 'hex'),
                '', '',
                '{"provider":"email","providers":["email"]}',
                jsonb_build_object('nome', r.nome),
                v_now, v_now,
                'authenticated', 'authenticated'
            );

            INSERT INTO auth.identities (
                id, user_id, identity_data, provider,
                last_sign_in_at, created_at, updated_at
            ) VALUES (
                v_user_id, v_user_id,
                jsonb_build_object(
                    'sub', v_user_id::text,
                    'email', LOWER(TRIM(r.email))
                ),
                'email',
                v_now, v_now, v_now
            );
        END IF;

        -- auth_user_id é UUID, v_user_id é UUID → comparação direta
        UPDATE public.pessoas
        SET auth_user_id = v_user_id
        WHERE id = r.id;

        v_count := v_count + 1;
        RAISE NOTICE 'OK: pessoa_id=%, email=%, auth_user_id=%', r.id, r.email, v_user_id;
    END LOOP;

    RAISE NOTICE 'Total de pessoas reparadas: %', v_count;
END $$;

-- ============================================================
-- PASSO 3: VALIDAÇÃO PÓS-REPARO
-- ============================================================
SELECT 'PÓS-REPARO: Ainda sem auth_user_id' AS info;
SELECT COUNT(*) AS total
FROM public.pessoas
WHERE auth_user_id IS NULL;

SELECT 'PÓS-REPARO: Com auth_user_id agora' AS info;
SELECT COUNT(*) AS total
FROM public.pessoas
WHERE auth_user_id IS NOT NULL;

SELECT 'PÓS-REPARO: auth_user_id inválido (deve ser 0)' AS info;
SELECT COUNT(*) AS total
FROM public.pessoas p
LEFT JOIN auth.users u ON u.id = p.auth_user_id
WHERE u.id IS NULL AND p.auth_user_id IS NOT NULL;

SELECT 'PÓS-REPARO: Pessoas migradas — lista' AS info;
SELECT p.id, p.nome, p.email, p.auth_user_id, u.created_at AS auth_criado_em
FROM public.pessoas p
JOIN auth.users u ON u.id = p.auth_user_id
ORDER BY p.id;

-- ============================================================
-- APÓS O REPARO:
-- Cada usuário deve usar "Esqueci senha" para definir senha real.
-- O Supabase enviará e-mail com link de redefinição.
-- ============================================================
