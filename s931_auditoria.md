# SPRINT S.9.3.1 — AUDITORIA E CORREÇÕES

Data: 11/07/2026 · Branch: master · Escopo: somente os 10 itens do prompt.
**Prompts 2 e 3 NÃO foram implementados** (múltiplos tutores, "Meus Pets" no
Mapa da Família, checkbox de convite — nada disso foi tocado).

---

## ITEM 1 — Pet é pet; humano é pessoa

**Auditoria (causa raiz comprovada)**

1. Arquivo/linha/função: `lib/screens/pessoa_detalhe_screen.dart` → `_editar()`
   (linha 115). Abria `NovaPessoaScreen(pessoa: _pessoa)` para QUALQUER pessoa,
   inclusive pet → formulário humano (sobrenome/e-mail/telefone) no pet.
2. Encadeado com `lib/screens/nova_pessoa_screen.dart` → `_salvar()` (linha
   ~321): o construtor `Pessoa(...)` **omitia `tipo`**, cujo default é
   `'humano'`. Operação: `UPDATE pessoas SET ..., tipo='humano' WHERE id=<pet>`
   (via `PessoaRepository.salvar`, `lib/models/pessoa.dart:364`).
   - Retorno atual: pet regravado com `tipo='humano'` → some de Pets, aparece
     em Pessoas/Família (é também a raiz do Item 4 "pet some da área Pets").
   - Retorno esperado: `pessoas.tipo` imutável em edição.
3. Listas: `pessoas_screen.dart:89` já excluía pets (`!p.isPet`) e
   `pets_screen.dart:46` já filtrava `isPet` — as listas "misturavam" porque o
   REGISTRO mudava de tipo, não porque o filtro faltasse.
4. Perfil do pet: textos humanos em `pessoa_detalhe_screen.dart`
   (linhas 559/624 "Família", 635/961 "Esta pessoa...", 231 `Icons.person`).

**Correções aplicadas**

- `_editar()` roteia pet → `NovaPetScreen` (formulário de pet: sem sobrenome,
  e-mail, telefone, relação humana; título "Editar pet" já existia).
- `NovaPessoaScreen._salvar()` agora preserva `tipo: widget.pessoa?.tipo`
  (e espécie/raça) — nenhuma edição altera a identidade.
- Perfil do pet: fallback de avatar com **ícone de pata**, seção **"Tutores"**
  (título, subtítulo e estado vazio), "**Este pet** ainda não apareceu…",
  "Criar memorial para **este pet**".
- Queries de lista permanecem com a semântica pedida
  (humanos: `tipo <> 'pet' or null`; pets: `tipo = 'pet'`), aplicadas
  client-side sobre `PessoaRepository.listar()` como já era o padrão.

---

## ITEM 2 — Espécie e raça

**Auditoria**: nenhum uso de `especie`/`raca` no app nem nas migrations
(`grep` em `lib/` e `supabase/` = 0 ocorrências) → campos NÃO existem.

**Correções aplicadas**

- Migration aditiva **`supabase/sprint_s9_3_1_pet_especie_raca.sql`**
  (`especie text null`, `raca text null`, constraint que impede espécie/raça
  em humanos; não toca em pets existentes nem em humanos).
- Modelo `Pessoa`: campos `especie`/`raca` + `especieRacaLabel`
  ("Gato", "Gato • Siamês"; **nunca grava texto artificial** — raça nula
  simplesmente não aparece).
- `NovaPetScreen`: dropdown de Espécie (Cachorro, Gato, Galinha, Pássaro,
  Coelho, Rato, Hamster, Cobra, Lagarto, Tartaruga, Peixe, Cavalo, **Outro**
  com texto livre — lista aberta, sem enum fechado). Obrigatória para novos
  pets; em edição de pet antigo não bloqueia. Raça: texto livre opcional.
- Exibição: selo no perfil do pet e chip na lista Pets. Nada disso é exibido
  em perfil humano (guard `isPet`).
- `PessoaRepository.salvar()` grava espécie/raça **somente** quando
  `pessoa.isPet`.

---

## ITEM 3 — Foto do pet / avatar do usuário sobrescrito (CRÍTICO)

**Auditoria (causa raiz comprovada)**

1. Arquivo/linha/função: `lib/models/pessoa.dart:571` →
   `uploadFotoPerfil(bytes, nome)`.
2. Query executada: upload no bucket `fotos`
   (path `usuario_<usuarioId>/app_mobile/perfil_<ts>_<nome>`) **e em seguida**
   `salvarUsuario({'foto_perfil': url})` = `UPDATE pessoas SET foto_perfil
   WHERE id = usuarioId` (linha 567).
3. Chamadores: `nova_pet_screen.dart:241` (foto do PET) e
   `pessoa.dart:334` (`salvar()` de contato) usavam essa mesma função.
4. Retorno atual: ao salvar a foto da Mili, além da linha do pet, a linha do
   **usuário logado** era atualizada → avatar do Darlan virou a foto da Mili
   (confirmado no relogin, pois o login lê `pessoas.foto_perfil` do usuário —
   `main.dart:234`).
5. Retorno esperado: editar pet atualiza somente `pessoas.id = pet.id`.

**Causa da "foto que não aparece na hora"**: a foto do pet é salva como URL
do Storage, mas lista (`pets_screen.dart:201`) e perfil
(`pessoa_detalhe_screen.dart:228`) só renderizavam `fotoBytes` (base64) —
URL era ignorada até algum outro fluxo regravar base64.

**Correções aplicadas**

- Novo `PessoaRepository.uploadFoto()` **puro** (só Storage + URL, zero
  UPDATE). `uploadFotoPerfil()` continua existindo apenas para a tela Perfil
  do usuário (único lugar onde atualizar `id = usuarioId` é intencional).
- `NovaPetScreen` e `salvar()` migrados para `uploadFoto()`.
- Lista Pets, perfil e chips agora renderizam `NetworkImage(fotoUrl)` quando
  não há bytes → a foto aparece imediatamente após salvar (as telas já
  recarregavam no pop; o que faltava era renderizar URL).
- Logs implantados: `[PET_PHOTO] pet_id / usuario_logado_id / storage_path /
  update_filter / public_url` e `[LOGIN_AVATAR] pessoa_id / foto_perfil`.

**Reparação do dado (foto do Darlan)** — pendente de evidência, como exigido:
rodar bloco **D4** de `supabase/sprint_s9_3_1_diagnosticos.sql` (lista
`pessoas.foto_perfil` atual + objetos `perfil_*` no Storage com datas). Com o
resultado, o UPDATE de restauração será proposto apontando para a foto
anterior real — sem hardcode e sem adivinhação.

---

## ITEM 4 — Relação Pet/Tutor invertida

**Auditoria**

- Nenhum código altera `pessoas.tipo` ao criar/editar relação (verificado em
  `pessoa_relacionamento_service.criar()/atualizarRotulos()` — só tocam
  `pessoas_relacionamentos`). O "pet virou humano" vinha do Item 1
  (edição via formulário humano), já corrigido.
- A INVERSÃO do rótulo "Pet de" vinha do mesmo bug do Item 6 (abaixo): a tela
  de relação gravava o papel escolhido na pessoa errada.
- **Convenção real da base (auditada em código + seed `s93_pets.sql`)**:
  `tipo` = papel de `pessoa_a`; `relacao_a_para_b` = o que A é para B;
  `relacao_b_para_a` = o que B é para A. Ex.: Tutor A → Pet B ⇒
  `tipo='TUTOR', relacao_a_para_b='Tutor', relacao_b_para_a='Pet de'` e a
  linha inversa `tipo='PET_DE'`.
  ⚠️ Isso difere do exemplo do prompt (`tipo=PET` na linha tutor→pet). Como o
  prompt manda auditar a convenção real antes de alterar, a convenção
  EXISTENTE foi mantida (mudar o significado de `tipo` exigiria migração de
  dados e mexer em telas estáveis). As linhas reais podem ser conferidas no
  bloco **D3** do arquivo de diagnósticos.
- Bloco **D3b** localiza pets que já foram convertidos em humano pelo bug
  antigo — reparo de dados será proposto sobre esse resultado.

---

## ITEM 5 — Memorial para pet

**Auditoria**: o bloqueio era client-side, em dois pontos de
`pessoa_detalhe_screen.dart`: linha 338 (`if (!isPet) _buildSecaoMemorial()`)
e linha 503 (`if (pessoa.isPet) return SizedBox.shrink()`).
`NovoMemorialScreen` não tem guard de pet e o vínculo já usa `pessoas.id`.

**Correção**: guards removidos; botão com texto "Criar memorial para este
pet"; fluxo reutilizado sem nova tabela, sem e-mail/conta/autenticação do
pet. RLS: nenhum indício de bloqueio server-side no código; se o teste 
end-to-end acusar RLS, o diagnóstico D1 (triggers) + policies serão auditados
antes de qualquer SQL.

---

## ITEM 6 — Relações pai/mãe/filho invertidas no perfil

**Auditoria (causa raiz comprovada, duas frentes)**

1. **Gravação invertida** — `lib/screens/adicionar_relacionamento_screen.dart`
   `_salvar()` (linha ~500). A pergunta da tela é
   "Quem **{outra}** é para **{origem}**?" (linha 311-336) — o tipo escolhido
   descreve a OUTRA pessoa. Mas o código chamava
   `criar(pessoaA: origem, pessoaB: outra, relacaoA: t.rotuloA, ...)`,
   gravando o papel da outra pessoa como se fosse da origem.
   Ex. real: no perfil da Delaine, "Quem Dionir é para Delaine?" → "Pai"
   gravava `relacao_a_para_b='Pai'` na linha Delaine→Dionir ⇒ o perfil
   mostrava Dionir como "Filho(a)" e, no espelho, Andrey como "Pai".
2. **Leitura ambígua** — `listarRelacionamentos()` lia as DUAS direções
   (`pessoa_a_id` E `pessoa_b_id`) e deduplicava; com pares gravados de forma
   contraditória, o rótulo exibido dependia da ordem das linhas.

**Correções aplicadas (somente na camada da tela/serviço do perfil)**

- `_salvar()` agora insere a linha direta com a OUTRA pessoa como `pessoa_a`
  (quem tem o papel escolhido). `criar()` continua gerando as duas direções.
- `listarRelacionamentos()` reescrita para a **query oficial do prompt**:
  somente `pessoa_a_id = :pessoa_perfil_id`, exibindo `relacao_b_para_a` —
  sem inversão em Dart, sem fallback de parentesco, sem convenção por ID.
- `_alterarRelacao()` (trocar relação pelo perfil) corrigida para gravar
  `tipo` da linha do perfil como o inverso do papel escolhido (rótulos já
  estavam certos).
- Home / Pessoas / Mapa da Família / gravação geral: **não tocados** (usam
  `listarRelacionados`/`listarContatos`/`carregarGrafo`, que já liam só o
  lado A).

**Dados existentes**: linhas gravadas pelo fluxo bugado continuam invertidas
no banco. Rodar blocos **D2a–D2d** dos diagnósticos (inclui a query oficial
para a Delaine e a comparação das duas direções de cada par). Com o retorno,
gero o SQL de reparo para aprovação — conforme a regra "se a base também
estiver errada: parar e mostrar as linhas".

---

## ITEM 7 — Push não chega no iPhone

**Auditoria do que é verificável no repositório**

- `ios/Runner/Runner.entitlements` tinha **`aps-environment = development`**.
  Em build TestFlight (profile App Store), o dispositivo se registra no APNs
  e o FCM envia pelo APNs de **produção** — com o entitlement de sandbox o
  push "é aceito" e nunca chega. Essa é a causa estrutural mais provável e
  foi corrigida para **`production`**.
- Fluxo Flutter (`push_notification_service.dart`): permissão → getToken →
  RPC `upsert_push_dispositivo(p_pessoa_id, p_token, p_plataforma)` — ok.
  Faltava auditar o elo APNs: adicionado `getAPNSToken()` com retry + logs.
- Logs implantados: `[PUSH_IOS] permission / apns_token / fcm_token /
  pessoa_id / persistido / erro`.

**Checklist do teste real (executar após o build; não dá para validar daqui)**

1. Instalar via TestFlight, abrir o app, aceitar permissão.
2. Coletar logs `[PUSH_IOS]` (Console.app com o iPhone conectado, filtro
   "PUSH_IOS").
3. Linha do token no Supabase:
   `select * from push_dispositivos where plataforma='ios' order by 1 desc;`
   (ajustar nome da tabela se a RPC gravar em outra — ver corpo da função
   `upsert_push_dispositivo`).
4. Firebase Console → Cloud Messaging → conferir **APNs Auth Key (.p8)**
   configurada para o app iOS `br.com.aeternalegado.app`.
5. Envio de teste real pelo backend atual e captura da resposta completa da
   FCM (sucesso/`Unregistered`/`InvalidApnsCredential` — este último indica
   Key/TeamID errados).
6. Validar app aberto / segundo plano / encerrado / toque abre a rota.

---

## ITEM 8 — Share Extension não entrega a foto

**Auditoria do handoff (nada de target/profile/bundle/activation foi tocado)**

- Cadeia atual: `ShareViewController.viewDidLoad → loadItem → cópia para App
  Group (group.com.aeterna.app) → manifesto share_<id>.json → completeRequest`
  → app principal consome via MethodChannel `com.aeterna.app/share`
  (`AppDelegate.consumePendingShare`) no cold start e no `resumed`
  (`main.dart:_verificarCompartilhamentoPendente`).
- **Comportamento observado ("fecha e volta para a foto") é o desenho atual**:
  Share Extension não pode abrir o app principal (API não suportada — como o
  próprio código documenta). O conteúdo só aparece quando o usuário abre o
  aEterna em seguida. Se, ao abrir o app, a foto NÃO chega, o elo quebrado só
  pode ser identificado com os logs — por isso a instrumentação completa:
  - `[IOS_SHARE] did_select_post / attachments / uti / copied_path /
    manifest / completion` (via `os_log` + `NSLog`, visíveis no Console.app);
  - `[IOS_SHARE]` no AppDelegate (registro do canal e resultado de
    `getSharedImage`);
  - `[FLUTTER_SHARE] payload_received / erro` no main.dart.
- Pontos que os logs vão discriminar: (a) container do App Group nulo na
  extensão (profile da extensão sem o App Group); (b) manifesto gravado mas
  canal Flutter nunca registrado (log "canal registrado" ausente);
  (c) manifesto nunca gravado (loadItem/UTI); (d) tudo ok e o bug está no
  processamento Flutter.
- **Não** foi adotada nova arquitetura silenciosamente. Se o teste mostrar
  que o mecanismo é insuficiente para a expectativa de UX (abrir o app na
  hora), as alternativas suportadas são: banner de confirmação na extensão
  ("Enviado para o aEterna — abra o app") ou UI própria
  (`SLComposeServiceViewController`). Decisão fica com o Darlan.

---

## ITEM 9 — Lentidão

**Instrumentação implantada (medir antes de otimizar)**

- `[PERF] tela=... inicio / pronta_em_ms` em: Home, Pessoas, Pets,
  PerfilPessoa (humano e pet — mesma tela), MapaFamilia, Memoriais.
- `[PERF] query=...` em `PessoaRepository.listar()` e
  `listarRelacionamentos()` (duração + linhas).

**Gargalos comprovados por leitura de código e corrigidos (sem mudar regra
funcional):**

- `pessoas_screen._carregar`: 3 queries independentes executavam em série →
  `Future.wait` (paralelo).
- `pessoa_detalhe._carregarAgregacoes`: 4 queries em série → `Future.wait`.
- `grafo_familia._carregar`: 2 queries em série → `Future.wait`.
- `listarRelacionamentos`: eliminada a 2ª query (`pessoa_b_id`) — metade das
  idas ao banco no perfil, além de corrigir o Item 6.

**Candidatos identificados, NÃO alterados por falta de medição** (aguardam os
números do `[PERF]` num device real): Home dispara 7 loaders com várias
subqueries; `listarVinculos()` baixa a tabela inteira de permissões;
imagens de rede sem cache (`NetworkImage` puro — avaliar
`cached_network_image`); `listarTipos()` consultado a cada carga de perfil.
Tabela antes/depois será preenchida com os logs do primeiro build.

---

## ITEM 10 — Pet participante da memória + erro 42703

**Correções de interface aplicadas**

- Seção "Quem participou deste momento?" agora tem **dois botões**:
  "Adicionar pessoas" e "Adicionar pets" (chip com pata).
- `PessoaPickerSheet` ganhou filtro `humanos | pets` (usa `pessoas.tipo` via
  `listarContatos`, que agora retorna `tipo`); cada seletor preserva a
  seleção do outro grupo; chips de pet mostram pata.
- Compartilhamento (`_abrirSelecaoFamiliares`) filtra **somente humanos** —
  pet participa da memória, mas nunca é destinatário de permissão/push e
  nunca autentica (participação ≠ compartilhamento; ambos persistem em
  `conteudo_permissoes` hoje, ver observação abaixo).

**Erro 42703 — auditoria sem suposição**

- Operação exata do app ao salvar participantes:
  `DELETE from conteudo_permissoes where conteudo_id=<memoria> and
  tipo_conteudo='memoria'` seguido de INSERTs
  `{tipo_conteudo:'memoria', conteudo_id, pessoa_id}`
  (`pessoa.dart:salvarVinculo`, linha ~677).
- `conteudo_permissoes` não tem coluna `tipo` → o `record "new" has no field
  "tipo"` vem de um **trigger** dessa tabela referenciando `NEW.tipo`.
  O corpo do trigger não existe no repositório — está no banco.
- Blocos **D1/D1b/D1c/D1d** dos diagnósticos entregam: triggers da tabela,
  função exata com `NEW.tipo` e estrutura real da tabela. Com esse retorno,
  a correção será na FUNÇÃO (consultando `pessoas.tipo` pelo `pessoa_id`
  correto, se comprovadamente necessário) — nunca adicionando coluna `tipo`
  para esconder o problema.

---

## SUPABASE

```
[x] SQL necessário:
1º supabase/sprint_s9_3_1_pet_especie_raca.sql  (ANTES do deploy do app)
   - onde: SQL Editor do Supabase (projeto zfpvfljmnlgsqiqdxmka)
   - validação: queries V1/V2/V3 no próprio arquivo
   - evidência esperada: V1=2 linhas nullable; V2=0 linhas; V3=pets intactos
   - rollback: DROP COLUMN IF EXISTS especie/raca + DROP CONSTRAINT
   - downtime: nenhum
2º supabase/sprint_s9_3_1_diagnosticos.sql  (SOMENTE LEITURA)
   - blocos D1 (42703), D2 (Delaine), D3 (tutor/pet), D4 (foto do usuário)
   - enviar os resultados no chat → SQLs de REPARO serão gerados para
     aprovação com base na evidência (nenhum dado será alterado antes disso)
```

⚠️ O app S.9.3.1 SELECIONA `especie/raca` — **executar o item 1º antes de
rodar o app novo**, senão `PessoaRepository.listar()` falha por coluna
inexistente.

## Arquivos alterados (17) + criados (2)

- lib/models/pessoa.dart — modelo (especie/raca), uploadFoto puro, logs
- lib/screens/nova_pessoa_screen.dart — preserva tipo/especie/raca
- lib/screens/nova_pet_screen.dart — espécie/raça, uploadFoto, logs
- lib/screens/pessoa_detalhe_screen.dart — edição de pet, pata, Tutores,
  memorial de pet, textos, Future.wait, correção _alterarRelacao
- lib/screens/pets_screen.dart — NetworkImage, chip espécie•raça, PERF
- lib/screens/pessoas_screen.dart — Future.wait, PERF
- lib/screens/adicionar_relacionamento_screen.dart — direção da relação
- lib/services/pessoa_relacionamento_service.dart — query oficial do perfil,
  listarContatos com tipo, inverseTipo público, PERF
- lib/screens/nova_memoria_screen.dart — seletores separados pessoa/pet
- lib/screens/home_screen.dart / grafo_familia_screen.dart /
  memoriais_screen.dart — PERF (+paralelização no grafo)
- lib/main.dart — [LOGIN_AVATAR], [FLUTTER_SHARE]
- lib/services/push_notification_service.dart — [PUSH_IOS] + getAPNSToken
- ios/Runner/Runner.entitlements — aps-environment=production
- ios/Runner/AppDelegate.swift — logs [IOS_SHARE]
- ios/ShareExtension/ShareViewController.swift — logs [IOS_SHARE]
- supabase/sprint_s9_3_1_pet_especie_raca.sql (novo)
- supabase/sprint_s9_3_1_diagnosticos.sql (novo)

## Validação final (mapeada)

Itens 1–5, 8(UI), 15, 16 → testáveis no app após SQL 1º + build.
Item 6/11 → corrigido para relações novas; dados antigos dependem do D2.
Item 7/12 → depende de build TestFlight + checklist do Item 7.
Item 13 → instrumentado; logs dirão o elo quebrado.
Item 14 → instrumentado + 4 paralelizações seguras; medições no 1º build.
Item 10 (42703) → UI pronta; erro de banco depende do D1.

`flutter analyze` e builds: executar no ambiente com Flutter
(`flutter analyze && flutter build apk --debug` e o pipeline Codemagic para
iOS). Este workspace não tem o SDK Flutter — checagem estática local foi
feita, mas o analyze oficial deve rodar antes do push, como de costume.

---

## CORREÇÃO S.9.3.1-b — Convenção do campo `tipo` (pós-auditoria de dados)

O dump completo de `pessoas_relacionamentos` + o código do Mapa da Família
provaram a convenção OFICIAL do projeto:

    tipo             = papel de pessoa_b em relação a pessoa_a
                       (a relação "de B para A" — ex.: linha Darlan→Dionir
                       tem tipo=PAI porque Dionir é o pai)
    relacao_a_para_b = o que A é para B
    relacao_b_para_a = o que B é para A

O Mapa da Família posiciona B na geração pelo `nivel` do `tipo` da linha —
o que só funciona com tipo = papel de B (e funciona hoje).

A primeira versão desta sprint havia assumido tipo = papel de A. Ajustes:

- adicionar_relacionamento_screen: tipo = escolhido (papel da outra pessoa,
  como sempre foi); apenas os RÓTULOS trocam (relacaoA=rotuloB do catálogo,
  relacaoB=rotuloA).
- pessoa_detalhe (_alterarRelacao): tipo = escolhido (sem inversão).
- nova_pessoa_screen: dropdown "Relação com você" descreve a pessoa nova (B)
  → tipo ok; rótulos trocados (era a mesma inversão de rótulos do Item 6).
- nova_pet_screen: relação criada com tipo='PET_DE' (B = pet é "Pet de");
  a linha inversa recebe TUTOR automaticamente.
- listarRelacionamentos: fallback de rótulos nulos alinhado (rótulo de B =
  rotuloA do catálogo).

Reparo de dados correspondente: bloco SQL "S.9.3.1-b" (tipo das 6 linhas da
Delaine, Darlan↔Beatriz(18), Alice↔Jonathas, tipos das linhas de pets,
trim de rótulos com espaços).

Nota de estrutura: os nomes das colunas do catálogo
(`rotulo_a_para_b`='Pai' no tipo PAI, onde A é o filho) não batem com a
convenção — legado. Não foram alterados; apenas documentados.
