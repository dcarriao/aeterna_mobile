# Auditoria S.8.8 — Legado `usuarios`/`contatos` no Mobile

## Sumário
- **Arquivos analisados**: 35 arquivos `.dart`
- **Arquivos limpos (0 ocorrências)**: 17
- **Arquivos com ocorrências mantidas**: 7
- **Arquivos com ocorrências a corrigir**: 10 + 1 (pessoa.dart)
- **Riscos restantes**: 3
- **Legado mantido**: `usuario_id` em `memorias`/`memoriais`/`fotos`/`videos` (FK não migrada no banco)

---

## 1. Ocorrências por arquivo

### `lib/models/pessoa.dart` — 48 ocorrências (MAIOR CONCENTRAÇÃO)

| Linha | Trecho | Uso atual | Decisão | Motivo |
|-------|--------|-----------|---------|--------|
| 79 | `criado_por_id` | Construção de mapa para salvar pessoa | **MANTER** | Coluna real da tabela, metadado de criação |
| 103 | `criado_por_id` | fromMap da Pessoa | **MANTER** | Campo do modelo, OK como metadado |
| 121 | `usuarioId = 2` | ID da pessoa logada (default) | **MANTER** | Nome confuso mas é o `pessoas.id` — renomear seria refactor grande |
| 123-124 | `legadoUsuarioId` | Fallback para SHA-256 legacy | **MANTER** | Ainda usado em auth legada (login e cadastro) |
| 126-128 | `dbUsuarioId` | Getter fallback legado → novo | **MANTER (mas não usado mais para família)** | Usado apenas em `excluirPessoa()` e upload de fotos (metadado) |
| 307 | `usuarioId` | `ids = {usuarioId}` no `listar()` | **CORRIGIDO (S.8.8)** | Agora usa `pessoas_relacionamentos` |
| 341 | `criado_por_id` | Inserção de nova pessoa | **CORRIGIR** | `criado_por_id` deve ser o id de quem criou, não filtro de família — OK como metadado |
| 388 | `conteudo_permissoes` | Excluir vínculos ao remover pessoa | **MANTER** | Tabela real de permissões |
| 393 | `criado_por_id` | Exclusão de fotos do bucket | **MANTER** | Metadado do bucket Storage |
| 403 | `conteudo_permissoes` | Carregar vínculos da memória | **MANTER** | Tabela real |
| 429 | `visibilidade = 'contatos'` | Visibilidade da memória | **MANTER** | É string literal no banco (`'contatos'` = compartilhado), não ref à tabela |
| 460 | `usuario_id` | Inserir foto no Storage | **MANTER** | FK real no banco, não migrada |
| 499 | `usuario_$usuarioId` | Caminho Storage | **MANTER** | Organização de buckets |
| 515 | `usuario_id` | Inserir vídeo | **MANTER** | FK real no banco |
| 556 | `usuarioId` | Query select de pessoa logada | **MANTER** | `pessoas.id` do usuário logado |
| 567 | `usuarioId` | Update da própria pessoa | **MANTER** | Atualizar avatar próprio |
| 578 | `usuario_$usuarioId` | Caminho avatar no Storage | **MANTER** | Bucket path |
| 651 | `visibilidade: 'contatos'` | Atualizar visibilidade | **MANTER** | String literal |
| 655-711 | `conteudo_permissoes` | Vínculos/compartilhamentos | **MANTER** | Tabela real de permissões |
| 706 | `familiaresIds` | Parâmetro que recebe IDs de pessoas | **MANTER** | É lista de `pessoas.id` (nome legado, mas semântica correta) |
| 714-817 | `listarMemoriasCompartilhadasComigo()` | Duas fontes: `conteudo_colaboradores` (primária) + `conteudo_permissoes` + `criado_por_id` (legada) | **CORRIGIR** (2 fontes) | Fonte legada usa `criado_por_id` para inferir dono — frágil |
| 737 | `usuario_id` em `conteudo_colaboradores` | Filtro pelo usuário logado | **MANTER** | Tabela real de colaboradores |
| 751 | `usuario_id` em resultado | Map key | **MANTER** | Chave informacional |
| 769 | `criado_por_id` | Fonte legada: busca `pessoas` pelo email do login | **REMOVER (futuro)** | Depende de `criado_por_id` + email cruzado — frágil e legado. Mas ainda usado como fallback |
| 870-887 | `memorial_pessoas` | Listar/atualizar pessoas do memorial | **MANTER** | Tabela real |
| 934 | `usuario_origem_id` | Convite familiar | **MANTER** | FK real |
| 994 | `usuario_origem_id` | Listar convites enviados | **MANTER** | FK real |
| 1012 | `usuario_destino_id` | Aceitar convite | **MANTER** | FK real |
| 1019-1027 | `usuario_id` em `vinculos_familiares` | Inserir vínculo bilateral | **MANTER** | FK real |
| 1039 | `usuarioId` (como colaborador) | Conceder permissão | **MANTER** | Dono logado |
| 1062-1067 | `vinculos_familiares` + `usuarioId` | Listar vínculos | **MANTER** | FK real |
| 1069-1076 | `pessoas` query + `usuarioId` | Buscar nomes dos vinculados | **MANTER** | Correto: busca em `pessoas` usando o `vinculado_usuario_id` |
| 1094-1110 | `usuarioIdColaborador` | Conceder permissão em `conteudo_colaboradores` | **MANTER** | FK real |
| 1117-1125 | `usuarioIdColaborador` | Remover permissão | **MANTER** | FK real |
| 1136-1157 | `conteudo_colaboradores` + `usuario_id` | Listar colaboradores | **MANTER** | FK real |
| 1171-1183 | `usuario_id` em `conteudo_colaboradores` | Obter papel do usuário logado | **MANTER** | FK real |

### `lib/supabase_service.dart` — 13 ocorrências

| Linha | Trecho | Uso | Decisão |
|-------|--------|-----|---------|
| 22 | `usuarioId = 2` | Singleton do serviço | **MANTER** — sync com `PessoaRepository.usuarioId` |
| 62 | `usuario_id` | Query storage quotas | **MANTER** — FK real |
| 158 | `usuario_id` extraído de resultado | Map de dono | **MANTER** — informacional |
| 184 | `usuario_id` | Inserir `conteudo_colaboradores` | **MANTER** — FK real |
| 213 | `usuario_id` | Inserir `conteudo_colaboradores` | **MANTER** — FK real |
| 271 | `usuario_$usuarioId` | Path Storage | **MANTER** — bucket |
| 317-318 | `usuario_id` | Listar memoriais do usuário | **MANTER** — FK real |
| 355-372 | `usuario_id` + `memorial_pessoas` | CRUD memoriais | **MANTER** — FK real |
| 404 | `usuario_id` | Query conteudo_colaboradores | **MANTER** — FK real |
| 414 | `usuario_id` | Select legada | **MANTER** — FK real |

### `lib/main.dart` — 13 ocorrências

| Linha | Trecho | Uso | Decisão |
|-------|--------|-----|---------|
| 165-167 | `session_pessoa_id`, `session_user_id` | Ler sessão do SharedPreferences | **MANTER** — necessário para compatibilidade de sessão |
| 170-177 | `_legacy_usuario_id` | Mapear sessão antiga → novo pessoas.id | **MANTER** — migração de sessão legada |
| 181-223 | `session_pessoa_id` | Salvar/remover sessão | **MANTER** |
| 222-440 | `session_pessoa_id`, `session_user_id` | Logout | **MANTER** |
| 266 | `familiaresIds` | Rascunho de memória | **MANTER** — nome legado, conteúdo são `pessoas.id` |

### `lib/screens/compartilhadas_screen.dart` — 2 ocorrências

| Linha | Uso | Decisão |
|-------|-----|---------|
| 60 | `m.familiaresIds` | Carregar compartilhamentos | **MANTER** — modelo retorna `pessoas.id` |
| 140 | `m.familiaresIds` | Exibir | **MANTER** |

### `lib/screens/memoria_detalhe_screen.dart` — 5 ocorrências

| Linha | Uso | Decisão |
|-------|-----|---------|
| 91 | `usuarioId` de `SupabaseService` | Dono da memória | **MANTER** |
| 119 | `familiaresIds` | Carregar vínculos | **MANTER** |
| 156 | `familiaresIds` | Salvar | **MANTER** |
| 267 | `usuarioId` | Enviar ao Curador | **MANTER** |
| 283 | `usuarioId` | Avaliar sugestão | **MANTER** |

### `lib/services/supabase_service.dart` — ver tabela acima

### Demais services (cofre, curador_sessao, mensagem_futuro, quem_sou_eu, etc.)
Todas as ocorrências usam `PessoaRepository.usuarioId` como filtro em tabelas que têm FK `usuario_id` (cofre_itens, curador_sessoes, mensagens_futuro, etc.). **MANTER** — são FKs reais que apontam para `pessoas.id`.

---

## 2. Arquivos limpos (0 ocorrências dos termos buscados)
- `lib/screens/cadastro_screen.dart` — 0 ocorrências (apenas `session_pessoa_id`, que não está na busca)
- `lib/screens/login_screen.dart` — 0 ocorrências
- `lib/screens/home_screen.dart` — 0 ocorrências (não lista mais na busca)
- `lib/screens/nova_pessoa_screen.dart` — 0 ocorrências
- `lib/screens/novo_memorial_screen.dart` — 0 ocorrências
- `lib/screens/pessoas_screen.dart` — 0 ocorrências
- `lib/screens/grafo_familia_screen.dart` — 0 ocorrências (import não utilizado removido previamente)
- `lib/screens/mapa_vida_screen.dart` — 0 ocorrências
- `lib/screens/perfil_screen.dart` — 0 ocorrências
- `lib/screens/conexoes_descobertas_screen.dart` — 0 ocorrências
- `lib/widgets/home/*` — 0 ocorrências
- `lib/services/push_notification_service.dart` — 0 ocorrências dos termos buscados
- `lib/services/pessoa_timeline_service.dart` — 0 ocorrências
- `lib/services/quem_sou_eu_service.dart` — 0 ocorrências
- `lib/services/memory_growth_invitation_service.dart` — 0 ocorrências
- `lib/services/memory_relationship_service.dart` — 0 ocorrências
- `lib/services/memorias_do_dia_service.dart` — 0 ocorrências

---

## 3. Arquivos corrigidos nesta S.8.8
- `lib/models/pessoa.dart` — `listar()`: removido filtro por `criado_por_id`, usa `pessoas_relacionamentos`
- `lib/services/pessoa_relacionamento_service.dart` — `carregarGrafo()`: query oficial direta, sem RPC/view
- `lib/services/pessoa_relacionamento_service.dart` — `listarRelacionamentos()`: query direta A→B + B→A

## 4. Riscos restantes

| Risco | Severidade | Detalhes |
|-------|-----------|----------|
| `listarMemoriasCompartilhadasComigo()` — fonte legada | **Média** | Fallback usa `criado_por_id` + email de `pessoas` para cruzar com `conteudo_permissoes`. Funciona mas é frágil. Remover após backfill confirmado. |
| `visibilidade = 'contatos'` (string literal) | **Baixa** | É string no banco, não reflete tabela. Nome sugestivo mas não problemático. |
| `familiaresIds` no modelo `Memoria` | **Baixa** | Nome herdado do legado, mas o conteúdo SEMPRE foi `pessoas.id`. Renomear quebra API. |
| `usuario_id` em `memorias`/`memoriais`/`fotos`/`videos` | **Média** | O DB ainda usa `usuario_id` = `pessoas.id` (já migrado via S.8.7). Nome da coluna é legado mas o valor é correto. Renomear coluna no banco é risky. |

## 5. Plano mínimo para remover legado depois

1. **Remover `legadoUsuarioId`** (S.8.9+): Confirmar que todos os `_legacy_usuario_id` foram migrados e que login SHA-256 usa `pessoas.id`. Então:
   - Remover `legadoUsuarioId` e `dbUsuarioId` de `PessoaRepository`
   - Simplificar `autenticarUsuario` para sempre usar `pessoas.id`
   - Remover mapeamento `session_user_id → session_pessoa_id` em `main.dart`

2. **Remover fallback legado de `listarMemoriasCompartilhadasComigo()`**: Após confirmar backfill de `conteudo_colaboradores` para todos os compartilhamentos, remover o bloco 2 (linhas 762-814).

3. **Remover `criado_por_id` de queries de curador**: `listarMemoriasPendentesCurador` e similares ainda usam `criado_por_id` como filtro. Migrar para filtro por `pessoas` (ou `pessoa_id` em `conteudo_colaboradores`).

4. **Renomear `familiaresIds` → `pessoaIds`**: Refatoração cosmética no modelo `Memoria` e consumidores.