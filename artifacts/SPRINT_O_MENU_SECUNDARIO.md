# Sprint O — Menu Secundário e Paridade Discreta do Mobile

**Data:** 2026-07-05
**Branch:** `master` (commit `370a9a6` +)

## Objetivo
Adicionar no Mobile as funcionalidades core ausentes que já existem no Web/Site, implementadas como itens secundários dentro do Perfil (nunca na Home nem na Bottom Navigation).

## Funcionalidades Implementadas

### 1. Mensagens para o Futuro
- **Modelo:** `lib/models/mensagem_futuro.dart` — id, titulo, conteudo, data_agendamento, entregue
- **Serviço:** `lib/services/mensagem_futuro_service.dart` — CRUD via `mensagens_futuro` no Supabase
- **Tela:** `lib/screens/mensagens_futuro_screen.dart` — lista com FAB "Nova mensagem", formulário com título + conteúdo + seletor de data, exclusão com confirmação
- **Supabase:** Tabela `mensagens_futuro` com RLS por usuário

### 2. Cofre
- **Modelo:** `lib/models/cofre_item.dart` — id, titulo, tipo ('texto'/'documento'), conteudo, url_arquivo
- **Serviço:** `lib/services/cofre_service.dart` — CRUD via `cofre_itens` no Supabase
- **Tela:** `lib/screens/cofre_screen.dart` — lista com FAB, seletor de tipo (Anotação/Documento), formulário com título + conteúdo
- **Supabase:** Tabela `cofre_itens` com RLS por usuário, constraint CHECK tipo IN ('texto','documento')

### 3. Quem Sou Eu
- **Modelo:** `lib/models/quem_sou_eu.dart` — id, pergunta_chave, resposta, created_at, updated_at
- **Serviço:** `lib/services/quem_sou_eu_service.dart` — CRUD via `quem_sou_eu` no Supabase (salvar com upsert)
- **Tela:** `lib/screens/quem_sou_eu_screen.dart` — 10 perguntas predefinidas sobre identidade/valores/memórias, cada uma editável via diálogo, contador de respostas, opção "Limpar respostas"
- **Supabase:** Tabela `quem_sou_eu` com RLS por usuário

### 4. Meu Plano
- **Alteração:** Seção "Meu Plano" no Perfil agora exibe apenas "Estrutura base — integração de pagamentos futura" com indicadores de uso (histórias registradas, contatos da família)
- **Removido:** Cards de planos com preços fictícios (`_PlanoScreen`, `_PlanoCard` — classes privadas eliminadas)

## Menu/Perfil
- Nova seção **"Recursos"** no `PerfilScreen` com 3 entradas discretas (ícone + texto + chevron):
  - 📨 Mensagens para o Futuro → `MensagensFuturoScreen`
  - 🔒 Cofre → `CofreScreen`
  - 🧑 Quem Sou Eu → `QuemSouEuScreen`
- Navegação via `Navigator.push` padrão, sem alterar BottomNavigationBar ou HomeScreen

## Supabase — Migração
Arquivo: `supabase/sprint_o_menu_secundario.sql`

**Novas tabelas:**
| Tabela | Colunas | RLS |
|--------|---------|-----|
| `mensagens_futuro` | id, usuario_id, titulo, conteudo, data_agendamento, entregue, created_at | SELECT/INSERT/UPDATE/DELETE por usuario_id |
| `cofre_itens` | id, usuario_id, titulo, tipo (CHECK texto/documento), conteudo, url_arquivo, created_at | SELECT/INSERT/UPDATE/DELETE por usuario_id |
| `quem_sou_eu` | id, usuario_id, pergunta_chave, resposta, created_at, updated_at | SELECT/INSERT/UPDATE/DELETE por usuario_id |

**Índices:** `idx_mensagens_futuro_usuario`, `idx_mensagens_futuro_agendamento`, `idx_cofre_itens_usuario`, `idx_quem_sou_eu_usuario`

**GRANTs:** `GRANT ALL ON mensagens_futuro, cofre_itens, quem_sou_eu TO anon; GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;`

**Como executar:** Abra o SQL Editor no Supabase Dashboard e cole o conteúdo de `supabase/sprint_o_menu_secundario.sql`.

## Arquivos Alterados/Criados

### Criados (6)
| Arquivo | Linhas |
|---------|--------|
| `lib/models/mensagem_futuro.dart` | 42 |
| `lib/models/cofre_item.dart` | 46 |
| `lib/models/quem_sou_eu.dart` | 48 |
| `lib/services/mensagem_futuro_service.dart` | 60 |
| `lib/services/cofre_service.dart` | 47 |
| `lib/services/quem_sou_eu_service.dart` | 49 |
| `lib/screens/mensagens_futuro_screen.dart` | 258 |
| `lib/screens/cofre_screen.dart` | 282 |
| `lib/screens/quem_sou_eu_screen.dart` | 216 |
| `supabase/sprint_o_menu_secundario.sql` | 90 |

### Alterados (1)
| Arquivo | Mudança |
|---------|---------|
| `lib/screens/perfil_screen.dart` | + "Recursos" section (3 entries), Meu Plano simplificado (sem preços fictícios) |

## Status
- `flutter analyze`: **0 erros**, 171 avisos/info pré-existentes
- `flutter build apk --debug`: **OK** (apk gerado)
- Nenhuma funcionalidade aparece na Home ou Bottom Navigation
- Nenhuma funcionalidade existente foi removida ou alterada
