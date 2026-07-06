import '../models/pessoa.dart';
import '../models/pessoa_relacionamento.dart';
import '../models/tipo_relacionamento.dart';

/// Sprint L — Serviço do grafo pessoa-pessoa.
///
/// Persistência 100% via Supabase (tabela `pessoas_relacionamentos`).
/// Lê a VIEW `grafo_pessoas_relacionamentos` para a UI do Mapa da
/// Família. Lê o catálogo `tipos_relacionamento` para popular dropdowns.
class PessoaRelacionamentoService {
  PessoaRelacionamentoService._();
  static final instance = PessoaRelacionamentoService._();

  /// Converte uma linha da view `grafo_pessoas_relacionamentos` em
  /// `OutraPessoaNaFamilia` para a pessoa `pessoaId`.
  static OutraPessoaNaFamilia _linhaParaOutraPessoa(
    Map<String, dynamic> row,
    int pessoaId,
  ) {
    final a = (row['pessoa_mais_antiga_id'] as num?)?.toInt() ?? 0;
    final b = (row['pessoa_mais_nova_id'] as num?)?.toInt() ?? 0;
    final outraId = a == pessoaId ? b : a;
    final rotuloDaOutra = a == pessoaId
        ? (row['rotulo_b'] as String? ?? 'Conhecido(a)')
        : (row['rotulo_a'] as String? ?? 'Conhecido(a)');
    final rotuloDeMim = a == pessoaId
        ? (row['rotulo_a'] as String? ?? 'Conhecido(a)')
        : (row['rotulo_b'] as String? ?? 'Conhecido(a)');
    final nomeB = a == pessoaId
        ? (row['nome_a'] as String?)
        : (row['nome_b'] as String?);
    return OutraPessoaNaFamilia(
      relacionamentoId: (row['relacionamento_id'] as num?)?.toInt() ?? 0,
      outraPessoaId: outraId,
      outraPessoaNome: nomeB ?? 'Pessoa #$outraId',
      tipo: row['tipo'] as String? ?? 'OUTRO',
      rotuloDaOutraParaMim: rotuloDaOutra,
      rotuloDeMimParaAOutra: rotuloDeMim,
      observacoes: row['observacoes'] as String?,
      dataInicio: row['data_inicio'] != null
          ? DateTime.tryParse('${row['data_inicio']}')
          : null,
      dataFim: row['data_fim'] != null
          ? DateTime.tryParse('${row['data_fim']}')
          : null,
    );
  }

  /// Carrega o catálogo de tipos de relação (do servidor, com
  /// fallback client-side se a chamada falhar).
  Future<List<TipoRelacionamento>> listarTipos() async {
    if (!PessoaRepository.isConfigured) {
      return TIPOS_RELACIONAMENTO_INICIAIS;
    }
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('tipos_relacionamento')
          .select('*')
          .eq('ativo', true)
          .order('categoria')
          .order('id');
      return rows
          .cast<Map<String, dynamic>>()
          .map(TipoRelacionamento.fromMap)
          .toList();
    } catch (e) {
      print('[PessoaRelacionamento] listarTipos ERRO: $e');
      return TIPOS_RELACIONAMENTO_INICIAIS;
    }
  }

  /// Lista todas as relações de uma pessoa (em qualquer direção).
  /// Resultado usado pela PessoaDetalheScreen ("Família" section).
  /// Tenta RPC primeiro; se falhar, fallback para query direta na view.
  Future<List<OutraPessoaNaFamilia>> listarRelacionamentos(
    int pessoaId,
  ) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient.rpc(
        'listar_relacionamentos_pessoa',
        params: {'p_pessoa_id': pessoaId},
      );
      return rows
          .cast<Map<String, dynamic>>()
          .map(OutraPessoaNaFamilia.fromMap)
          .toList();
    } catch (e) {
      print('[PessoaRelacionamento] listarRelacionamentos RPC ERRO: $e');
    }
    // Fallback: query direta na view (sem RPC disponível)
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('grafo_pessoas_relacionamentos')
          .select('*')
          .eq('usuario_id', PessoaRepository.usuarioId);
      final lista = rows.cast<Map<String, dynamic>>();
      return lista
          .where((r) =>
              (r['pessoa_mais_antiga_id'] as num?)?.toInt() == pessoaId ||
              (r['pessoa_mais_nova_id'] as num?)?.toInt() == pessoaId)
          .map((r) => _linhaParaOutraPessoa(r, pessoaId))
          .toList();
    } catch (e2) {
      print('[PessoaRelacionamento] listarRelacionamentos fallback ERRO: $e2');
      return const [];
    }
  }

  /// Carrega o grafo COMPLETO do usuário (projeção com rótulos
  /// resolvidos por direção). Usado pelo `GrafoFamiliaScreen`.
  Future<List<Map<String, dynamic>>> carregarGrafo() async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('grafo_pessoas_relacionamentos')
          .select('*')
          .eq('usuario_id', PessoaRepository.usuarioId)
          .order('criado_em', ascending: false);
      return rows.cast<Map<String, dynamic>>().toList();
    } catch (e) {
      print('[PessoaRelacionamento] carregarGrafo ERRO: $e');
      return const [];
    }
  }

  /// "Quem é minha esposa/irmão/pai?" — consulta direta do grafo
  /// para um tipo. Útil para a Home ("Hoje faz X anos que você
  /// registrou a primeira memória com Alice") e para o
  /// CuradorPessoaScreen.
  Future<List<Map<String, dynamic>>> listarPessoasComRelacao(
    int pessoaReferenciaId,
    String tipo,
  ) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient.rpc(
        'listar_pessoas_com_mesma_relacao',
        params: {
          'p_usuario_id': PessoaRepository.usuarioId,
          'p_pessoa_referencia_id': pessoaReferenciaId,
          'p_tipo': tipo,
        },
      );
      return rows.cast<Map<String, dynamic>>().toList();
    } catch (e) {
      print('[PessoaRelacionamento] listarPessoasComRelacao ERRO: $e');
      return const [];
    }
  }

  /// Cria uma nova relação pessoa-pessoa. A constraint UNIQUE do
  /// schema garante idempotência (a<b normalizado, por tipo).
  /// `pessoaOrigem` é o usuário da conta; `pessoaAId`/`pessoaBId` são
  /// os IDs dos contatos.
  Future<int?> criar({
    required int pessoaAId,
    required int pessoaBId,
    required String tipo,
    String? relacaoA,
    String? relacaoB,
    bool confirmado = true,
    String? observacoes,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    if (!PessoaRepository.isConfigured) return null;
    if (pessoaAId == pessoaBId) return null;
    try {
      // Resolve rótulos do catálogo (se não vierem explícitos).
      String? rotA = relacaoA;
      String? rotB = relacaoB;
      if (rotA == null || rotB == null) {
        final tipos = await listarTipos();
        final t = tipos.firstWhere(
          (t) => t.id == tipo,
          orElse: () => const TipoRelacionamento(
            id: 'OUTRO',
            rotuloA: 'Conhecido(a)',
            rotuloB: 'Conhecido(a)',
            categoria: 'outro',
          ),
        );
        rotA ??= t.rotuloA;
        rotB ??= t.rotuloB;
      }

      final insertData = {
        'usuario_id': PessoaRepository.usuarioId,
        'pessoa_a_id': pessoaAId,
        'pessoa_b_id': pessoaBId,
        'tipo': tipo,
        'relacao_a_para_b': rotA,
        'relacao_b_para_a': rotB,
        'confirmado': confirmado,
        if (observacoes != null) 'observacoes': observacoes,
        if (dataInicio != null)
          'data_inicio':
              '${dataInicio.year}-${dataInicio.month.toString().padLeft(2, '0')}-${dataInicio.day.toString().padLeft(2, '0')}',
        if (dataFim != null)
          'data_fim':
              '${dataFim.year}-${dataFim.month.toString().padLeft(2, '0')}-${dataFim.day.toString().padLeft(2, '0')}',
      };

      final rows = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .insert(insertData)
          .select('id')
          .single();
      return (rows['id'] as num?)?.toInt();
    } catch (e) {
      print('[PessoaRelacionamento] criar ERRO: $e');
      rethrow;
    }
  }

  /// Atualiza o rótulo (ou rótulos) de uma relação. Útil para
  /// "Mudei de ideia — agora é genro/nora em vez de filho/filha".
  Future<void> atualizarRotulos({
    required int relacionamentoId,
    String? relacaoA,
    String? relacaoB,
    String? observacoes,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      final data = <String, dynamic>{};
      if (relacaoA != null) data['relacao_a_para_b'] = relacaoA;
      if (relacaoB != null) data['relacao_b_para_a'] = relacaoB;
      if (observacoes != null) data['observacoes'] = observacoes;
      if (dataInicio != null) {
        data['data_inicio'] =
            '${dataInicio.year}-${dataInicio.month.toString().padLeft(2, '0')}-${dataInicio.day.toString().padLeft(2, '0')}';
      }
      if (dataFim != null) {
        data['data_fim'] =
            '${dataFim.year}-${dataFim.month.toString().padLeft(2, '0')}-${dataFim.day.toString().padLeft(2, '0')}';
      }
      if (data.isEmpty) return;
      await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .update(data)
          .eq('id', relacionamentoId);
    } catch (e) {
      print('[PessoaRelacionamento] atualizarRotulos ERRO: $e');
    }
  }

  /// Marca a relação como inativa (soft-delete — preserva o histórico
  /// para que o "Mapa da Vida" da família nunca perca o fio de quem
  /// foi o quê no passado).
  Future<void> inativar(int relacionamentoId) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .update({'confirmado': false})
          .eq('id', relacionamentoId);
    } catch (e) {
      print('[PessoaRelacionamento] inativar ERRO: $e');
    }
  }

  Future<void> deletar(int relacionamentoId) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .delete()
          .eq('id', relacionamentoId);
    } catch (e) {
      print('[PessoaRelacionamento] deletar ERRO: $e');
    }
  }
}
