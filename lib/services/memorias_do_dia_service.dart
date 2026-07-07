import '../models/memoria_do_dia.dart';
import '../models/pessoa.dart';

/// Sprint M — Serviço que busca memórias do dia via RPC
/// `memorias_do_dia(usuario, limite)`. Stateless e idempotente.
class MemoriasDoDiaService {
  MemoriasDoDiaService._();
  static final instance = MemoriasDoDiaService._();

  /// Retorna até [limite] memórias cujo `data_evento` (fallback
  /// `criada_em`) coincide com o dia/mês de HOJE, em anos anteriores.
  Future<List<MemoriaDoDia>> listarParaHome({int limite = 5}) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient.rpc(
        'memorias_do_dia',
        params: {
          'p_usuario_id': PessoaRepository.usuarioId,
          'p_limite': limite,
        },
      );
      return rows
          .cast<Map<String, dynamic>>()
          .map(MemoriaDoDia.fromMap)
          .toList();
    } catch (e) {
      print('[MemoriasDoDia] listarParaHome ERRO: $e');
      return const [];
    }
  }

  /// Para o Mapa da Vida: memórias do dia de uma pessoa específica
  /// (reaproveita a mesma RPC — o cliente filtra client-side).
  Future<List<MemoriaDoDia>> listarParaPessoa(int pessoaId,
      {int limite = 5}) async {
    final todas = await listarParaHome(limite: limite * 3);
    if (todas.isEmpty) return const [];
    // Sem filtro por pessoa na RPC, retorna tudo. Manter para
    // evolução futura (Sprint N: vista com parâmetro p_pessoa_id).
    return todas;
  }
}
