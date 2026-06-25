# aEterna Mobile

MVP Flutter para captura rápida de memórias vivas.

## Executar em modo local

Sem a chave pública, o app continua funcionando durante a sessão e identifica
claramente o modo local:

```powershell
D:\flutter\bin\flutter.bat run -d chrome
```

## Executar com Supabase

Use somente a chave pública `anon`. Nunca use `service_role` no aplicativo.
A URL do projeto já está configurada no serviço.

```powershell
D:\flutter\bin\flutter.bat run -d chrome `
  --dart-define=SUPABASE_ANON_KEY=SUA_CHAVE_PUBLICA_ANON
```

Também é possível substituir a URL:

```powershell
--dart-define=SUPABASE_URL=https://zfpvfljmnlgsqiqdxmka.supabase.co
```

O serviço usa temporariamente `usuario_id = 2`, com um `TODO` explícito para
substituição pelo usuário autenticado.

## Fluxo de gravação

1. Insere em `memorias`.
2. Envia a imagem ao bucket público `fotos`, quando houver.
3. Insere os metadados em `fotos`.
4. Cria o vínculo em `memoria_fotos`.
5. Abre `Minha História` e lista os dados do Supabase.

As políticas RLS precisam permitir `select`, `insert` e a eventual limpeza de
rollback para o usuário temporário. O bucket precisa permitir upload com a
chave pública usada no MVP.

O SQL temporário do MVP está em:

`supabase/mvp_anon_policies.sql`

Ele deve ser revisado e executado no SQL Editor do Supabase. Essas políticas
são apenas para o protótipo sem login e devem ser removidas quando o Supabase
Auth for implementado.
