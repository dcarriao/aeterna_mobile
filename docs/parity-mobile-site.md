# Paridade Mobile ↔ Site (aEterna)

Handoff para o agente do **site Streamlit**. Refatorar o app web existente para **paridade de features** com o mobile Flutter. Mesmo banco Supabase (`zfpvfljmnlgsqiqdxmka`).

**Repo mobile (referência de comportamento):** `github.com/dcarriao/aeterna_mobile`  
**Schema SQL / migrations:** pasta `supabase/` neste repo (não copiar schema inteiro neste documento).

---

## 1. Objetivo

Levar o site Streamlit ao mesmo conjunto de capacidades de produto do app mobile, usando as **mesmas tabelas e regras de domínio**. UI pode diferir (Streamlit ≠ Flutter); dados, ownership e fluxos de negócio devem ser equivalentes.

**Não** é reescrever o mobile. **Não** é criar um segundo produto. É alinhar o site ao que o mobile já faz.

---

## 2. Stack

| Camada | Mobile | Site |
|--------|--------|------|
| UI | Flutter (`lib/`) | Streamlit (repo separado) |
| Auth + dados | `supabase` Dart / `PessoaRepository` | Cliente Supabase Python (anon; secrets só no ambiente do site) |
| Banco | Mesmo projeto Supabase | Idem |

Identidade pós-login = `pessoas.id` da sessão. O default legado `usuarioId=2` no mobile existe **só antes do login** e é sobrescrito — **nunca** usar como ID de pessoa real no site.

---

## 3. Regras de dados / ownership (obrigatórias)

### Memória
- A memória **pertence a quem criou** (`memorias.usuario_id` = `pessoas.id` do autor).
- Participar ≠ ser dono.
- "N memórias" / patrimônio / "Pessoas importantes" no mobile usam **publicações** (`memorias.usuario_id`), **não** aparições em `conteudo_permissoes`.

### `conteudo_permissoes.papel`
| Papel | Significado |
|-------|-------------|
| `participante` | Aparece na memória (pessoa/pet vinculada). Participante humano pode receber compartilhamento automático. |
| `compartilhado` | Recebe acesso + (no mobile) push. |

### `pessoas.situacao` (CHECK: só `pendente` \| `ativo` \| `inativo`)
- Conta de **humano vivo**: `ativo` = tem senha/conta; `pendente` = convidado sem senha; `inativo` = soft-delete.
- **Não** é flag de visibilidade.
- **Falecido:** `falecido=true` + `situacao` no mesmo padrão dos outros falecidos (hoje `pendente`). Nunca `ativo` em falecido. Nunca NULL.

### `pessoas.tipo` (CHECK: só `humano` \| `pet`)
- Pet: **nunca** auth/senha/push; nunca em seletores de humanos.
- Tutoria: `PET_DE` (user→pet) / `TUTOR` (inversa). Fora do catálogo do Mapa da Família.

### Relacionamentos (`pessoas_relacionamentos`)
- `tipo` = papel de **B** em relação a **A**.
- `relacao_a_para_b` / `relacao_b_para_a` = rótulos nas duas direções.
- Toda relação tem **2 linhas** (direta + inversa).
- Perfil lê `pessoa_a_id` e exibe `relacao_b_para_a`.

### Memoriais
- `memorial_pessoas` = N:N de **participantes** (não só o falecido representado).
- Pessoa que o memorial **representa**: nome igual ao memorial > falecida > primeira (ver mobile `PessoaRepository.obterPessoaDoMemorial`).
- No Mapa, memorial “já na árvore” = pessoa **falecida** vinculada, não participante vivo.

### Hardcode
- **Proibido** no código: ids, e-mails, nomes ou dados de pessoas específicas. Tudo via sessão/queries.

---

## 4. Inventário de telas do mobile (`lib/screens/`)

29 arquivos — referência para mapa Feature → Local.

| Arquivo | Propósito (resumo) |
|---------|-------------------|
| `login_screen.dart` | Login (e-mail/senha; biometria opcional no device) |
| `cadastro_screen.dart` | Criar conta — fluxo **transparente** (ATIVA pendente / entra se senha bate) |
| `onboarding_screen.dart` | Onboarding inicial |
| `home_screen.dart` | Home: curador proativo, cards, pessoas importantes, memórias, nav 5 itens |
| `pessoas_screen.dart` | Lista pessoas (humanos do grafo/rede) |
| `pets_screen.dart` | Lista pets |
| `nova_pessoa_screen.dart` | Cadastro/edição pessoa + relação + convite |
| `nova_pet_screen.dart` | Cadastro/edição pet |
| `pessoa_detalhe_screen.dart` | Perfil humano/pet: patrimônio, timeline, família |
| `adicionar_relacionamento_screen.dart` | Conectar pessoa à família |
| `grafo_familia_screen.dart` | Mapa da Família (gerações + memoriais órfãos) |
| `timeline_screen.dart` | Timeline agregada |
| `memoriais_screen.dart` | Lista memoriais (próprios + colaborativos) |
| `novo_memorial_screen.dart` | Criar memorial |
| `memorial_detalhe_screen.dart` | Detalhe: biografia, lembranças, moderar, curador IA, colaboradores, relações |
| `compartilhadas_screen.dart` | Memórias compartilhadas com o usuário |
| `nova_memoria_screen.dart` | Criar/editar memória (+ pessoas, foto/vídeo) |
| `memoria_detalhe_screen.dart` | Detalhe da memória |
| `memoria_contribuicao_screen.dart` | Contribuição em memória/memorial |
| `curador_screen.dart` | Curador contextual (sessão conversacional → memória) |
| `perfil_screen.dart` | Preferências do usuário logado (+ diagnóstico push iOS) |
| `convites_screen.dart` | Convites familiares |
| `conexoes_descobertas_screen.dart` | Conexões entre memórias (pendentes) |
| `explorador_screen.dart` | Exploração de conteúdo |
| `minha_historia_screen.dart` | Minha história |
| `mapa_vida_screen.dart` | Mapa da vida |
| `quem_sou_eu_screen.dart` | Quem sou eu |
| `cofre_screen.dart` | Cofre |
| `mensagens_futuro_screen.dart` | Mensagens para o futuro |

### Home — blocos relevantes (`home_screen.dart` + services)
- Nav inferior: Pessoas / Pets / Timeline / Memoriais / Compartilhadas (+ Perfil via callback).
- Curador Proativo: `CuradorProativoService` + `ProactiveOpportunityCard` (prioridade vídeo 48h > grupo fotos > etc.; limites 1/dia, 2/semana).
- Continuar sessão curador: `CuradorSessaoService`.
- Pessoas importantes / recentes: `PessoaTimelineService` + ownership por publicação.
- Memórias do dia, “pode crescer”, conexões descobertas, momentos detectados (galeria do **device** — só mobile).
- Aniversários de memória.

### Services-chave (espelhar regra no site, não a API Dart)
| Service | Papel |
|---------|--------|
| `PessoaRepository` (`lib/models/pessoa.dart`) | Auth/pessoas/memorial/permissões/storage |
| `supabase_service.dart` | Memórias, memoriais, fotos/vídeos em lote |
| `pessoa_relacionamento_service.dart` | Grafo, tipos, criar 2 vias |
| `pessoa_timeline_service.dart` | Stats / linha do tempo (RPCs) |
| `curador_proativo_service.dart` / `curador_sessao_service.dart` | Oportunidades e sessão do curador |
| `push_notification_service.dart` | FCM/APNs (só mobile) |

---

## 5. Checklist de paridade

Status do site = **TBD** (preencher após auditoria do repo Streamlit). Critérios de aceite = comportamento alinhado ao mobile/dados.

| Feature | Mobile (screen / service) | Site status | Critérios de aceite |
|---------|---------------------------|-------------|---------------------|
| Login | `login_screen` + `PessoaRepository.autenticarUsuario` | TBD | Entra com e-mail/senha; sessão = `pessoas.id` real; não depender de tabela `usuarios` legada |
| Cadastro transparente | `cadastro_screen` + `criarUsuario` | TBD | Preenche e entra; e-mail inédito → cria ativo; humano sem senha → ATIVA mesma linha; com senha certa → entra; senha errada → só “Senha incorreta…” **sem** revelar conta nem redirecionar para login; pet → falha genérica |
| Onboarding | `onboarding_screen` | TBD | Equivalente opcional no web; não bloqueia privilégios de dado |
| Home | `home_screen` + serviços acima | TBD | Lista memórias do usuário; card(s) de curador/continuar se existirem no web; “pessoas importantes” só humanos vivos com publicações; nav/acesso às seções abaixo |
| Pessoas (lista) | `pessoas_screen` | TBD | Lista humanos do relacionamento do logado; abre detalhe/cadastro |
| Nova/editar pessoa | `nova_pessoa_screen` | TBD | Cria/edita; dropdown relação (papel de B); cria 2 linhas de relacionamento; pendente + e-mail → convite; ao editar, relação pré-selecionada não some |
| Perfil pessoa | `pessoa_detalhe_screen` | TBD | Humano: patrimônio = o que **ele** publicou; família via relacionamentos; falecido com indicador de luto; queries filtradas (não carregar tabela inteira) |
| Pets (lista) | `pets_screen` | TBD | Só `tipo=pet`; fora de seletores humanos |
| Nova/editar pet | `nova_pet_screen` | TBD | Tutoria PET_DE/TUTOR; sem auth |
| Perfil pet | `pessoa_detalhe_screen` (modo pet) | TBD | Stats por aparições/participação (RPC); “N memórias vinculadas” ok p/ pet |
| Relacionamentos | `adicionar_relacionamento_screen` + `PessoaRelacionamentoService` | TBD | Sem duplicata; 2 vias; rótulos corretos; inversa tipada |
| Mapa da Família | `grafo_familia_screen` | TBD | Gerações por `tipo`; exclui AMIGO/CONHECIDO/OUTRO/TUTOR/PET_DE; memoriais órfãos; memorial na árvore só se falecido vinculado |
| Timeline | `timeline_screen` + `pessoa_timeline_service` | TBD | Eventos agregados do usuário; stats consistentes com RPCs/regras mobile |
| Memoriais (lista) | `memoriais_screen` | TBD | Próprios + colaborativos (`conteudo_colaboradores` **e** `memorial_pessoas`); parentesco do memorial colaborativo via relacionamento com pessoa representada, não parentesco do criador |
| Novo memorial | `novo_memorial_screen` | TBD | Cria em `memoriais` + vínculos necessários |
| Detalhe memorial | `memorial_detalhe_screen` | TBD | Abas/áreas: biografia, lembranças, moderação, curador; relação abre para pessoa **representada** (não participante arbitrário); colaboradores |
| Compartilhadas | `compartilhadas_screen` + `listarMemoriasRecebidas` | TBD | Memórias com papel `compartilhado` para o logado; preview foto/vídeo; “compartilhada por” |
| Nova memória | `nova_memoria_screen` + `supabase_service` | TBD | Cria com `usuario_id` = autor; participantes/compartilhados corretos; foto/vídeo no storage |
| Detalhe memória | `memoria_detalhe_screen` | TBD | Conteúdo, mídia, pessoas, edição se dono |
| Contribuições | `memoria_contribuicao_screen` / memorial | TBD | Fluxo pendente/aprovado conforme `contribuicoes` |
| Curador (sessão) | `curador_screen` + `curador_sessao_service` | TBD | Sessão em `curador_sessoes`/`curador_mensagens`; resultado → memória; chaves OpenAI só em secrets do site |
| Curador proativo | `CuradorProativoService` + card na Home | TBD | Web: adaptar regras (sem galeria do device = sem “vídeo encontrado” nativo); se implementado, mesmos limites de frequência e ownership |
| Convites | `convites_screen` / familiar | TBD | Status pendente/aceito; ao ativar conta, mapa e compartilhamentos do **mesmo** `pessoas.id` já aparecem |
| Perfil / preferências | `perfil_screen` | TBD | Dados da sessão; preferências curador se houver tabela `configuracoes_curador` |
| Share (OS) | Share Extension iOS / Intent Android + `main.dart` | TBD | **N/A nativo no Streamlit.** Web: upload manual suficiente; não inventar App Group/FCM |
| Push | `push_notification_service` + `push_dispositivos` | TBD | **Só mobile.** Site: não registrar token fake; notificação in-app opcional via `notificacoes` se já existir no produto |
| Diagnóstico push | painel em `perfil_screen` | TBD | **Irrelevante no web** — não portar |
| Cofre / mensagens futuro / quem sou eu / mapa vida / minha história / explorador / conexões | telas respectivas | TBD | Paridade desejável após core; mesmas tabelas; sem hardcode |

---

## 6. Cadastro transparente (detalhe operacional)

Espelhar `PessoaRepository.criarUsuario`:

1. SELECT `id, senha_hash, salt, tipo` por e-mail.
2. Inédito → criar (Auth + insert `situacao='ativo'` com hash/salt).
3. Existe, `tipo != humano` → falha genérica.
4. Existe, humano, **sem** senha → UPDATE hash/salt/`situacao='ativo'` na **mesma** linha → entrar.
5. Existe, humano, **com** senha → se hash confere, entrar; senão mensagem mínima de senha incorreta.

**Não** usar “recuperar senha” para contato pendente (SMTP Auth do projeto pode não estar configurado; pendente nem sempre existe no Supabase Auth).

---

## 7. DO NOTs (agente do site)

1. **Não** hardcodar `pessoas.id`, e-mails, nomes ou dados de pessoas reais.
2. **Não** colocar secrets (`service_role`, OpenAI, etc.) no git do site nem no mobile.
3. **Não** tratar a tabela `usuarios` como fonte de verdade (legado morto).
4. **Não** usar `usuarioId=2` (ou qualquer default) como identidade do usuário logado.
5. **Não** confundir `participante` com `compartilhado`; **não** confundir publicação (`memorias.usuario_id`) com aparição.
6. **Não** marcar falecido como `situacao='ativo'`; **não** dar auth a pet.
7. **Não** assumir que `memorial_pessoas.limit(1)` = pessoa do memorial — aplicar a ordem nome/falecido/primeira.
8. **Não** portar push iOS, Share Extension, App Groups, Codemagic entitlements ou painel de diagnóstico APNs.
9. **Não** dumpalhar schema completo neste handoff — consultar `supabase/` / migrations compartilhadas e `information_schema` no projeto.
10. **Não** alterar dados de produção sem SELECT de evidência antes/depois.
11. **Não** declarar “paridade concluída” sem o humano validar no site (mesma regra do mobile: só confirmado no uso real).
12. **Não** criar documentos extras não pedidos; preencher a coluna “Site status” deste arquivo (ou checklist equivalente no repo do site) ao auditar.

---

## 8. Como usar este handoff

1. Auditar o repo Streamlit e preencher **Site status** (existe / parcial / falta / N/A).
2. Priorizar: auth transparente → home/memórias → pessoas/pets/relacionamentos → memoriais → compartilhadas → curador → extras.
3. Validar cada critério contra o banco real (mesmo Supabase do mobile).
4. Em dúvida de regra de domínio, o comportamento do mobile + este arquivo prevalecem sobre inferência.

---

*Gerado a partir de auditoria de `lib/screens/*.dart` + AGENTS.md do mobile. Sem secrets. Sem IDs de pessoas no código de exemplo.*
