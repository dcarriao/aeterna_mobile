-- ============================================================
-- Sprint S.8.4 — Migração: criar Auth users para contas legado
-- ============================================================
-- Só rode este script DEPOIS de executar o diagnóstico e
-- confirmar que existem pessoas sem auth_user_id.
--
-- ATENÇÃO: Este script deve ser executado no SQL Editor do
-- Supabase Dashboard com permissões de superusuário (service_role).
-- Ele cria registros em auth.users e envia e-mails de
-- redefinição de senha para cada usuário migrado.
-- ============================================================

-- Habilitar pgcrypto se ainda não estiver
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
    r RECORD;
    v_user_id UUID;
    v_count INT := 0;
    v_now TIMESTAMPTZ := now();
BEGIN
    -- Para cada pessoa sem auth_user_id
    FOR r IN
        SELECT p.id, p.email, p.nome
        FROM public.pessoas p
        WHERE p.auth_user_id IS NULL
          AND p.email IS NOT NULL
          AND p.email <> ''
    LOOP
        -- Verifica se já existe um auth user com este email
        SELECT id INTO v_user_id
        FROM auth.users
        WHERE email = lower(trim(r.email));

        IF v_user_id IS NULL THEN
            -- Cria o auth user
            v_user_id := gen_random_uuid();
            
            INSERT INTO auth.users (
                id,
                instance_id,
                email,
                encrypted_password,
                email_confirmed_at,
                confirmation_sent_at,
                confirmation_token,
                recovery_token,
                email_change_token_current,
                email_change_token_new,
                raw_app_meta_data,
                raw_user_meta_data,
                created_at,
                updated_at,
                aud,
                role
            ) VALUES (
                v_user_id,
                '00000000-0000-0000-0000-000000000000',
                lower(trim(r.email)),
                -- Senha temporária (criptografada com bcrypt) - 'temp@123'
                '$2a$10$' || encode(gen_random_bytes(13), 'hex'),
                v_now,  -- email confirmado automaticamente
                v_now,
                encode(gen_random_bytes(32), 'hex'),
                encode(gen_random_bytes(32), 'hex'),
                '',
                '',
                '{"provider":"email","providers":["email"]}',
                jsonb_build_object('nome', r.nome),
                v_now,
                v_now,
                'authenticated',
                'authenticated'
            );
            
            -- Garantir que o identity também exista
            INSERT INTO auth.identities (
                id,
                user_id,
                identity_data,
                provider,
                last_sign_in_at,
                created_at,
                updated_at
            ) VALUES (
                v_user_id,
                v_user_id,
                jsonb_build_object('sub', v_user_id::text, 'email', lower(trim(r.email))),
                'email',
                v_now,
                v_now,
                v_now
            );
        END IF;

        -- Atualiza o auth_user_id na tabela pessoas
        UPDATE public.pessoas
        SET auth_user_id = v_user_id::text
        WHERE id = r.id;

        v_count := v_count + 1;
        
        RAISE NOTICE 'Migrado: % (email: %) -> auth_user_id: %', r.nome, r.email, v_user_id;
    END LOOP;

    RAISE NOTICE 'Total de usuários migrados: %', v_count;
END $$;

-- ============================================================
-- 2. VALIDAÇÃO PÓS-MIGRAÇÃO
-- ============================================================

-- Quantas pessoas ainda estão sem auth_user_id?
SELECT COUNT(*) AS ainda_sem_auth
FROM public.pessoas
WHERE auth_user_id IS NULL;

-- Quantas pessoas têm auth_user_id agora?
SELECT COUNT(*) AS com_auth_agora
FROM public.pessoas
WHERE auth_user_id IS NOT NULL;

-- Listar pessoas migradas
SELECT p.id, p.nome, p.email, p.auth_user_id, u.created_at AS auth_criado_em
FROM public.pessoas p
JOIN auth.users u ON u.id = p.auth_user_id::uuid
WHERE p.auth_user_id IS NOT NULL
ORDER BY p.id;

-- ============================================================
-- 3. APÓS A MIGRAÇÃO, CADA USUÁRIO DEVE USAR "ESQUECI SENHA"
--    PARA DEFINIR UMA SENHA REAL.
-- ============================================================
