SELECT id, nome, email, situacao, created_at
FROM public.pessoas
WHERE auth_user_id IS NULL
ORDER BY id;