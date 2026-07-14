# aEterna Mobile

App Flutter do **aEterna** — produto de memórias familiares (pessoas, pets, timeline, memoriais e compartilhamentos).

Complementa o site Streamlit. Ambos usam o **mesmo projeto Supabase**.

| | |
|---|---|
| Bundle | `br.com.aeternalegado.app` |
| iOS | Codemagic → TestFlight |
| Android | AAB → Google Play |

## Stack

Flutter (Dart), Supabase (`supabase` Dart), Firebase Cloud Messaging, `photo_manager`, `image_picker`, `video_player`, `app_links`, `workmanager`, `local_auth`, entre outros (ver `pubspec.yaml`).

No iOS há Share Extension e push via APNs/FCM. No Android, o app aceita compartilhamento de foto/vídeo via intent.

## Estrutura

```
lib/
  main.dart          # bootstrap
  models/            # entidades + PessoaRepository
  screens/           # telas
  services/          # Supabase, push, curador, timeline, etc.
  widgets/           # UI reutilizável
supabase/            # scripts SQL por sprint (migrations / policies)
ios/                 # Runner + Share Extension
android/             # app Android
codemagic.yaml       # CI iOS TestFlight
```

## Rodar localmente

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install) estável, dispositivo/emulador iOS ou Android (ou Chrome para smoke test).

```bash
flutter pub get
```

Sem chave, o app sobe em modo limitado (sem backend):

```bash
flutter run
```

Com Supabase (use **somente** a chave pública `anon`):

```bash
flutter run \
  --dart-define=SUPABASE_ANON_KEY=SUA_CHAVE_PUBLICA_ANON
```

Opcionais:

```bash
--dart-define=SUPABASE_URL=https://SEU_PROJETO.supabase.co
--dart-define=OPENAI_API_KEY=SUA_CHAVE   # curador / IA
```

No Windows (PowerShell), o equivalente usa `` ` `` para quebra de linha ou passe tudo numa linha.

## Repositório público — não commitar segredos

Este repositório é **público**.

- Nunca versionar `service_role`, chaves OpenAI, tokens Codemagic, `.env` com segredos, nem provisioning profiles.
- `SUPABASE_ANON_KEY` e `OPENAI_API_KEY` entram só via `--dart-define` (local) ou secrets do CI (Codemagic) — **não** hardcoded no código.
- No app, use apenas a chave **anon**. A `service_role` não pertence ao cliente mobile.
- Prefira `git add` com lista explícita de arquivos; evite `git add -A`.

## Contribuição rápida

1. `flutter pub get`
2. Rodar com `--dart-define=SUPABASE_ANON_KEY=...` apontando ao mesmo Supabase do site.
3. `flutter analyze` antes de abrir PR / disparar build.
4. Builds de distribuição (TestFlight / Play) compilam do **GitHub** — commit + push antes do CI.

## Licença / publicação

`publish_to: 'none'` no `pubspec.yaml` — pacote não destinado ao pub.dev.
