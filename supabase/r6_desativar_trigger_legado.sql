-- ============================================================================
-- r6_desativar_trigger_legado.sql
-- Sprint R.6 — Auditoria engine de parentesco
-- ============================================================================
-- Remove o trigger `trg_pessoa_cria_relacionamento_legado` que:
--   1. Cria relação com pessoa ALEATÓRIA (LIMIT 1) em vez do usuário correto
--   2. Duplica a criação explícita feita pelo Dart (NovaPessoaScreen._salvar)
--   3. Produz rótulos incorretos por inverter baseado em ID, não em semântica
--
-- A partir de agora, TODAS as relações são criadas exclusivamente pelo
-- `PessoaRelacionamentoService.criar()` no Dart.
-- ============================================================================

drop trigger if exists trg_pessoa_cria_relacionamento_legado on public.contatos;

drop function if exists public.tg_pessoa_cria_relacionamento_legado;

-- Validacao
-- SELECT trigger_name FROM information_schema.triggers
--   WHERE event_object_table = 'contatos'
--   AND trigger_name = 'trg_pessoa_cria_relacionamento_legado';
--  => 0 rows (trigger removido)
