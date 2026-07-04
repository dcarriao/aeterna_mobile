import '../models/curador_sessao.dart';
import '../models/pessoa.dart';

/// Sprint J — Orquestrador da sessão do Curador Contextual.
///
/// Persistência 100% via Supabase (decidido na conversa com o usuário):
///   - Cada turno (user/assistant) é gravado em `curador_mensagens`
///     via RPC `curador_salvar_mensagem`.
///   - A sessão é criada/retomada via `curador_sessoes`.
///   - Quando o usuário finaliza, `curador_finalizar_sessao` é
///     chamada, marcando a sessão como `concluida` e gravando o
///     `contexto_atual` consolidado.
class CuradorSessaoService {
  CuradorSessaoService._();
  static final instance = CuradorSessaoService._();

  /// Retorna a sessão ativa (em_andamento) do usuário logado, ou null.
  Future<CuradorSessao?> obterSessaoAtiva() async {
    if (!PessoaRepository.isConfigured) return null;
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('curador_sessao_ativa_por_usuario')
          .select('*')
          .eq('usuario_id', PessoaRepository.usuarioId)
          .limit(1);
      if (rows.isEmpty) return null;
      return CuradorSessao.fromMap(
          (rows.first as Map).cast<String, dynamic>());
    } catch (e) {
      print('[CuradorSessao] obterSessaoAtiva ERRO: $e');
      return null;
    }
  }

  /// Lista todas as mensagens de uma sessão, ordenadas.
  Future<List<CuradorMensagem>> listarMensagens(int sessaoId) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .rpc('curador_listar_mensagens', params: {'p_sessao_id': sessaoId});
      return rows
          .cast<Map<String, dynamic>>()
          .map(CuradorMensagem.fromMap)
          .toList();
    } catch (e) {
      print('[CuradorSessao] listarMensagens ERRO: $e');
      return const [];
    }
  }

  /// Cria uma nova sessão e retorna seu id.
  /// Chamado pela `CuradorScreen` no momento em que o usuário
  /// aceita começar uma nova conversa (sem aproveitar sessão antiga).
  Future<int?> criarSessao({
    String? titulo,
    required String contextoInicial,
    DateTime? dataEvento,
    List<Map<String, String>> pessoas = const [],
    int? memoriaId,
  }) async {
    if (!PessoaRepository.isConfigured) return null;
    try {
      // Insere via SELECT returning id.
      final rows = await PessoaRepository.supabaseClient
          .from('curador_sessoes')
          .insert({
            'usuario_id': PessoaRepository.usuarioId,
            if (titulo != null) 'titulo': titulo,
            'contexto_inicial': contextoInicial,
            'status': 'em_andamento',
            if (dataEvento != null)
              'data_evento':
                  '${dataEvento.year}-${dataEvento.month.toString().padLeft(2, '0')}-${dataEvento.day.toString().padLeft(2, '0')}',
            'pessoas_json': pessoas,
            if (memoriaId != null) 'memoria_id': memoriaId,
          })
          .select('id')
          .single();
      return (rows['id'] as num?)?.toInt();
    } catch (e) {
      print('[CuradorSessao] criarSessao ERRO: $e');
      return null;
    }
  }

  /// Adiciona uma mensagem (user ou assistant) à sessão. A RPC
  /// `curador_salvar_mensagem` também já atualiza `contexto_atual`
  /// quando `role='user'` e incrementa `total_turnos`.
  Future<void> adicionarMensagem({
    required int sessaoId,
    required CuradorMensagemRole role,
    required String conteudo,
    CuradorMensagemTipo? tipo,
  }) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      await PessoaRepository.supabaseClient.rpc('curador_salvar_mensagem', params: {
        'p_sessao_id': sessaoId,
        'p_role': role.valor,
        'p_conteudo': conteudo,
        'p_tipo': tipo?.name,
      });
    } catch (e) {
      print('[CuradorSessao] adicionarMensagem ERRO: $e');
    }
  }

  /// Marca a sessão como `concluida` e grava o contexto_atual
  /// consolidado. Chamado quando o usuário decide encerrar a
  /// conversa no Curador.
  Future<void> finalizarSessao({
    required int sessaoId,
    required String contextoAtual,
  }) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      await PessoaRepository.supabaseClient.rpc('curador_finalizar_sessao', params: {
        'p_sessao_id': sessaoId,
        'p_contexto_atual': contextoAtual,
        'p_status': 'concluida',
      });
    } catch (e) {
      print('[CuradorSessao] finalizarSessao ERRO: $e');
    }
  }

  /// Cancela a sessão (descartar conversa sem salvar).
  Future<void> cancelarSessao(int sessaoId) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      await PessoaRepository.supabaseClient
          .rpc('curador_cancelar_sessao', params: {'p_sessao_id': sessaoId});
    } catch (e) {
      print('[CuradorSessao] cancelarSessao ERRO: $e');
    }
  }

  /// Vincula uma memória à sessão (chamado pela NovaMemoriaScreen
  /// após salvar a memória final).
  Future<void> vincularMemoria(int sessaoId, int memoriaId) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      await PessoaRepository.supabaseClient.from('curador_sessoes').update({
        'memoria_id': memoriaId,
      }).eq('id', sessaoId);
    } catch (e) {
      print('[CuradorSessao] vincularMemoria ERRO: $e');
    }
  }
}
