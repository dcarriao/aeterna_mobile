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

  /// ID para queries no banco: usa o `legadoUsuarioId` (usuarios.id)
  /// se disponível, fallback para `usuarioId` (pessoas.id).
  static int get _dbUsuarioId =>
      PessoaRepository.legadoUsuarioId ?? PessoaRepository.usuarioId;

  /// Rótulos do lado "senior" da relação (quem é pai/mãe/avô/tio etc.).
  static const _seniorLabels = {
    'Pai', 'Mãe', 'Avô', 'Avó', 'Bisavô', 'Bisavó',
    'Tio', 'Tia', 'Padrinho', 'Madrinha', 'Genro', 'Nora',
    'Sogro(a)', 'Esposo(a)', 'Companheiro',
  };

  /// Rótulos do lado "junior" da relação (quem é filho/neto/sobrinho etc.).
  static const _juniorLabels = {
    'Filho(a)', 'Neto(a)', 'Bisneto(a)', 'Sobrinho(a)',
    'Afilhado(a)', 'Genro/Nora',
  };

  /// Corrige rótulos de dados legados que usam convenção antiga.
  ///
  /// Convenção nova (app): `rel_a_to_b` = o que A chama B (subjetivo).
  /// Convenção antiga (site): `rel_a_to_b` = o que A É para B (objetivo).
  ///
  /// Detectamos pela direção: se `rot_a` (rótulo da pessoa de ID menor
  /// para a de ID maior) é um rótulo sênior, os dados estão na convenção
  /// antiga e os campos `rotuloDaOutraParaMim`/`rotuloDeMimParaAOutra`
  /// precisam ser trocados.
  static (String, String) _corrigirSeOldConvention(
    String rotDaOutra,
    String rotDeMim,
    String rotA,
  ) {
    if (_seniorLabels.contains(rotA)) {
      return (rotDeMim, rotDaOutra);
    }
    return (rotDaOutra, rotDeMim);
  }

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
        ? (row['nome_b'] as String?)
        : (row['nome_a'] as String?);
    final rotA = row['rotulo_a'] as String? ?? '';
    final (corrigidoOutra, corrigidoMim) =
        _corrigirSeOldConvention(rotuloDaOutra, rotuloDeMim, rotA);
    return OutraPessoaNaFamilia(
      relacionamentoId: (row['relacionamento_id'] as num?)?.toInt() ?? 0,
      outraPessoaId: outraId,
      outraPessoaNome: nomeB ?? 'Pessoa #$outraId',
      tipo: row['tipo'] as String? ?? 'OUTRO',
      rotuloDaOutraParaMim: corrigidoOutra,
      rotuloDeMimParaAOutra: corrigidoMim,
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
      final lista = rows.cast<Map<String, dynamic>>().map((map) {
        final rotDaOutra = map['rotulo_da_outra_para_mim'] as String? ?? '';
        final rotDeMim = map['rotulo_de_mim_para_outra'] as String? ?? '';
        final outraId = (map['outra_pessoa_id'] as num?)?.toInt() ?? 0;
        final rotA = outraId < pessoaId ? rotDaOutra : rotDeMim;
        final (cOutra, cMim) =
            _corrigirSeOldConvention(rotDaOutra, rotDeMim, rotA);
        map['rotulo_da_outra_para_mim'] = cOutra;
        map['rotulo_de_mim_para_outra'] = cMim;
        return OutraPessoaNaFamilia.fromMap(map);
      });
      final unique = <int, OutraPessoaNaFamilia>{};
      for (final f in lista) {
        unique.putIfAbsent(f.outraPessoaId, () => f);
      }
      return unique.values.toList();
    } catch (e) {
      print('[PessoaRelacionamento] listarRelacionamentos RPC ERRO: $e');
    }
    // Fallback: query direta na view (sem RPC disponível)
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('grafo_pessoas_relacionamentos')
          .select('*')
          .eq('usuario_id', _dbUsuarioId);
      final lista = rows.cast<Map<String, dynamic>>();
      final filtrados = lista
          .where((r) =>
              (r['pessoa_mais_antiga_id'] as num?)?.toInt() == pessoaId ||
              (r['pessoa_mais_nova_id'] as num?)?.toInt() == pessoaId)
          .map((r) => _linhaParaOutraPessoa(r, pessoaId));
      final unique = <int, OutraPessoaNaFamilia>{};
      for (final f in filtrados) {
        unique.putIfAbsent(f.outraPessoaId, () => f);
      }
      return unique.values.toList();
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
          .eq('usuario_id', _dbUsuarioId)
          .order('criado_em', ascending: false);
      final data = rows.cast<Map<String, dynamic>>();
      if (data.isEmpty) {
        print('[PessoaRelacionamento] carregarGrafo: 0 linhas (view vazia ou usuario_id=$usuarioId sem dados)');
      }
      return data;
    } catch (e) {
      print('[PessoaRelacionamento] carregarGrafo ERRO: $e');
      return const [];
    }
  }

  int get usuarioId => _dbUsuarioId;

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
          'p_usuario_id': _dbUsuarioId,
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
            'usuario_id': _dbUsuarioId,
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
            'usuario_id': _dbUsuarioId,
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
