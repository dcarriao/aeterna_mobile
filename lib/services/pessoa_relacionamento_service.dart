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

  /// ID da pessoa logada para metadado de criação.
  static int get _usuarioId => PessoaRepository.usuarioId;

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
  /// Usa query direta em `pessoas_relacionamentos` — sem RPC, sem view.
  Future<List<OutraPessoaNaFamilia>> listarRelacionamentos(
    int pessoaId,
  ) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      // A→B: quem B é para A
      final rowsA = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_b_id, relacao_b_para_a, tipo, id, observacoes, data_inicio, data_fim')
          .eq('pessoa_a_id', pessoaId);
      // B→A: quem A é para B
      final rowsB = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_a_id, relacao_a_para_b, tipo, id, observacoes, data_inicio, data_fim')
          .eq('pessoa_b_id', pessoaId);

      // Busca nomes de todas as pessoas envolvidas
      final todosIds = <int>{
        for (final r in rowsA) (r['pessoa_b_id'] as num).toInt(),
        for (final r in rowsB) (r['pessoa_a_id'] as num).toInt(),
      };
      final nomes = <int, String>{};
      if (todosIds.isNotEmpty) {
        final pRows = await PessoaRepository.supabaseClient
            .from('pessoas')
            .select('id, nome, sobrenome')
            .inFilter('id', todosIds.toList());
        for (final r in pRows) {
          nomes[(r['id'] as num).toInt()] =
              '${r['nome'] ?? ''} ${r['sobrenome'] ?? ''}'.trim();
        }
      }

      final lista = <OutraPessoaNaFamilia>[];
      for (final r in rowsA) {
        final outraId = (r['pessoa_b_id'] as num).toInt();
        lista.add(OutraPessoaNaFamilia(
          relacionamentoId: (r['id'] as num).toInt(),
          outraPessoaId: outraId,
          outraPessoaNome: nomes[outraId] ?? 'Pessoa #$outraId',
          tipo: r['tipo'] as String? ?? 'OUTRO',
          rotuloDaOutraParaMim: r['relacao_b_para_a'] as String? ?? 'Conhecido(a)',
          rotuloDeMimParaAOutra: r['relacao_b_para_a'] as String? ?? 'Conhecido(a)',
          observacoes: r['observacoes'] as String?,
          dataInicio: r['data_inicio'] != null
              ? DateTime.tryParse('${r['data_inicio']}')
              : null,
          dataFim: r['data_fim'] != null
              ? DateTime.tryParse('${r['data_fim']}')
              : null,
        ));
      }
      for (final r in rowsB) {
        final outraId = (r['pessoa_a_id'] as num).toInt();
        lista.add(OutraPessoaNaFamilia(
          relacionamentoId: (r['id'] as num).toInt(),
          outraPessoaId: outraId,
          outraPessoaNome: nomes[outraId] ?? 'Pessoa #$outraId',
          tipo: r['tipo'] as String? ?? 'OUTRO',
          rotuloDaOutraParaMim: r['relacao_a_para_b'] as String? ?? 'Conhecido(a)',
          rotuloDeMimParaAOutra: r['relacao_a_para_b'] as String? ?? 'Conhecido(a)',
          observacoes: r['observacoes'] as String?,
          dataInicio: r['data_inicio'] != null
              ? DateTime.tryParse('${r['data_inicio']}')
              : null,
          dataFim: r['data_fim'] != null
              ? DateTime.tryParse('${r['data_fim']}')
              : null,
        ));
      }
      // Remove duplicatas
      final unique = <int, OutraPessoaNaFamilia>{};
      for (final f in lista) {
        unique.putIfAbsent(f.outraPessoaId, () => f);
      }
      return unique.values.toList();
    } catch (e) {
      print('[PessoaRelacionamento] listarRelacionamentos ERRO: $e');
      return const [];
    }
  }

  /// Carrega o grafo COMPLETO do usuário (projeção com rótulos
  /// resolvidos por direção). Usado pelo `GrafoFamiliaScreen`.
  /// Query direta em `pessoas_relacionamentos` — sem view.
  Future<List<Map<String, dynamic>>> carregarGrafo() async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('id, pessoa_a_id, pessoa_b_id, relacao_a_para_b, relacao_b_para_a, tipo')
          .or('pessoa_a_id.eq.${PessoaRepository.usuarioId},pessoa_b_id.eq.${PessoaRepository.usuarioId}');

      // Busca nomes de todas as pessoas envolvidas
      final todosIds = <int>{
        for (final r in rows)
          (r['pessoa_a_id'] as num).toInt(),
        for (final r in rows)
          (r['pessoa_b_id'] as num).toInt(),
      };
      final nomes = <int, String>{};
      if (todosIds.isNotEmpty) {
        final pRows = await PessoaRepository.supabaseClient
            .from('pessoas')
            .select('id, nome, sobrenome')
            .inFilter('id', todosIds.toList());
        for (final r in pRows) {
          nomes[(r['id'] as num).toInt()] =
              '${r['nome'] ?? ''} ${r['sobrenome'] ?? ''}'.trim();
        }
      }

      // Converte para o formato esperado pelo GrafoFamiliaScreen
      return rows.map<Map<String, dynamic>>((r) {
        final aId = (r['pessoa_a_id'] as num).toInt();
        final bId = (r['pessoa_b_id'] as num).toInt();
        return {
          'relacionamento_id': r['id'],
          'pessoa_mais_antiga_id': aId < bId ? aId : bId,
          'pessoa_mais_nova_id': aId < bId ? bId : aId,
          'rotulo_a': r['relacao_a_para_b'] as String? ?? '',
          'rotulo_b': r['relacao_b_para_a'] as String? ?? '',
          'nome_a': nomes[aId] ?? 'Pessoa #$aId',
          'nome_b': nomes[bId] ?? 'Pessoa #$bId',
          'tipo': r['tipo'] as String? ?? 'OUTRO',
        };
      }).toList();
    } catch (e) {
      print('[PessoaRelacionamento] carregarGrafo ERRO: $e');
      return const [];
    }
  }

  int get usuarioId => _usuarioId;

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
          'p_usuario_id': _usuarioId,
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

  /// Cria uma nova relação pessoa-pessoa com ambas as direções.
  /// Insere DUAS linhas: A→B (direta) e B→A (inversa).
  /// Se a inversa já existir, apenas insere a direta.
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

      // Linha direta: A → B
      final rows = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .insert({
            'usuario_id': _usuarioId,
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
          })
          .select('id')
          .single();
      final idDireta = (rows['id'] as num?)?.toInt();

      // Linha inversa: B → A (labels trocados, tipo invertido)
      final invTipo = _inverseTipo(tipo, rotB);
      await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .insert({
            'usuario_id': _usuarioId,
            'pessoa_a_id': pessoaBId,
            'pessoa_b_id': pessoaAId,
            'tipo': invTipo,
            'relacao_a_para_b': rotB,
            'relacao_b_para_a': rotA,
            'confirmado': confirmado,
            if (observacoes != null) 'observacoes': observacoes,
            if (dataInicio != null)
              'data_inicio':
                  '${dataInicio.year}-${dataInicio.month.toString().padLeft(2, '0')}-${dataInicio.day.toString().padLeft(2, '0')}',
            if (dataFim != null)
              'data_fim':
                  '${dataFim.year}-${dataFim.month.toString().padLeft(2, '0')}-${dataFim.day.toString().padLeft(2, '0')}',
          })
          .select('id')
          .single();

      return idDireta;
    } catch (e) {
      print('[PessoaRelacionamento] criar ERRO: $e');
      rethrow;
    }
  }

  /// Mapeia o tipo para seu inverso bidirecional.
  /// Usado para criar a linha inversa em `criar()`.
  String _inverseTipo(String tipo, String rotuloB) {
    switch (tipo) {
      case 'PAI':
      case 'MAE':
        return 'FILHO';
      case 'FILHO':
        return rotuloB == 'Mãe' ? 'MAE' : 'PAI';
      case 'FILHA':
        return 'PAI';
      case 'AVO':
        return 'NETO';
      case 'NETO':
        return 'AVO';
      case 'BISAVO':
        return 'BISNETO';
      case 'BISNETO':
        return 'BISAVO';
      case 'TIO':
        return 'SOBRINHO';
      case 'SOBRINHO':
        return 'TIO';
      case 'PADRINHO':
      case 'MADRINHA':
        return 'AFILHADO';
      case 'AFILHADO':
        return rotuloB == 'Madrinha' ? 'MADRINHA' : 'PADRINHO';
      case 'GENRO':
      case 'NORA':
        return 'SOGRO';
      case 'SOGRO':
        return rotuloB == 'Genro' ? 'GENRO' : 'NORA';
      // Simétricos: mesmo tipo nos dois lados
      default:
        return tipo; // IRMAO, CONJUGE, PRIMO, CUNHADO, AMIGO, OUTRO, COMPANHEIRO
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

  /// Marca a relação como inativa (ambas as direções).
  Future<void> inativar(int relacionamentoId) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      final row = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_a_id, pessoa_b_id, usuario_id')
          .eq('id', relacionamentoId)
          .single();
      final aId = (row['pessoa_a_id'] as num).toInt();
      final bId = (row['pessoa_b_id'] as num).toInt();
      final uId = (row['usuario_id'] as num?)?.toInt() ?? PessoaRepository.usuarioId;

      await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .update({'confirmado': false})
          .eq('usuario_id', uId)
          .or('and(pessoa_a_id.eq.$aId,pessoa_b_id.eq.$bId),and(pessoa_a_id.eq.$bId,pessoa_b_id.eq.$aId)');
    } catch (e) {
      print('[PessoaRelacionamento] inativar ERRO: $e');
    }
  }

  /// Deleta a relação E sua inversa (ambas as direções).
  Future<void> deletar(int relacionamentoId) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      // Busca os dados da relação para encontrar a inversa
      final row = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_a_id, pessoa_b_id, usuario_id')
          .eq('id', relacionamentoId)
          .single();
      final aId = (row['pessoa_a_id'] as num).toInt();
      final bId = (row['pessoa_b_id'] as num).toInt();
      final uId = (row['usuario_id'] as num?)?.toInt() ?? PessoaRepository.usuarioId;

      // Deleta ambas as direções
      await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .delete()
          .eq('usuario_id', uId)
          .or('and(pessoa_a_id.eq.$aId,pessoa_b_id.eq.$bId),and(pessoa_a_id.eq.$bId,pessoa_b_id.eq.$aId)');
    } catch (e) {
      print('[PessoaRelacionamento] deletar ERRO: $e');
    }
  }
}
