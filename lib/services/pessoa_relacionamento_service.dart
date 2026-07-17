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

  /// S.9.3.1 (Item 9) — cache do catálogo de tipos. O catálogo é quase
  /// estático e era buscado no servidor a CADA carga de perfil/relação.
  /// Reinício do app renova; catálogo só muda em migration.
  static List<TipoRelacionamento>? _tiposCache;

  /// Carrega o catálogo de tipos de relação (do servidor, com
  /// fallback client-side se a chamada falhar).
  Future<List<TipoRelacionamento>> listarTipos() async {
    if (_tiposCache != null) return _tiposCache!;
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
      final lista = rows
          .cast<Map<String, dynamic>>()
          .map(TipoRelacionamento.fromMap)
          .toList();
      if (lista.isNotEmpty) _tiposCache = lista;
      return lista;
    } catch (e) {
      print('[PessoaRelacionamento] listarTipos ERRO: $e');
      return TIPOS_RELACIONAMENTO_INICIAIS;
    }
  }

  /// Lista as relações exibidas no perfil da pessoa.
  ///
  /// S.9.3.1 (Item 6) — QUERY OFICIAL do perfil: linhas em que a pessoa do
  /// perfil é `pessoa_a_id`, exibindo `relacao_b_para_a` (o que a OUTRA é
  /// para ela). Se a linha inversa existir sem a direta (dados legados),
  /// completa pelo lado B usando `relacao_a_para_b`.
  Future<List<OutraPessoaNaFamilia>> listarRelacionamentos(
    int pessoaId,
  ) async {
    if (!PessoaRepository.isConfigured) return const [];
    final sw = Stopwatch()..start();
    try {
      // Perfil da pessoa A: quem B é para A
      final rowsA = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_b_id, relacao_a_para_b, relacao_b_para_a, tipo, id')
          .eq('pessoa_a_id', pessoaId)
          .order('pessoa_b_id');

      // Dados incompletos: só existe a linha inversa (pessoa é B).
      // Sem isso, a UI caía no fallback `pessoas.parentesco` (rótulo do
      // CRIADOR, não da pessoa do perfil / sessão).
      final rowsB = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_a_id, relacao_a_para_b, relacao_b_para_a, tipo, id')
          .eq('pessoa_b_id', pessoaId)
          .order('pessoa_a_id');
      print('[PERF] query=listarRelacionamentos duracao_ms=${sw.elapsedMilliseconds} '
          'ladoA=${rowsA.length} ladoB=${rowsB.length}');

      // Busca nomes de todas as pessoas envolvidas
      final todosIds = <int>{
        for (final r in rowsA) (r['pessoa_b_id'] as num).toInt(),
        for (final r in rowsB) (r['pessoa_a_id'] as num).toInt(),
      };
      final nomes = <int, String>{};
      final fotos = <int, String>{};
      if (todosIds.isNotEmpty) {
        final pRows = await PessoaRepository.supabaseClient
            .from('pessoas')
            .select('id, nome, sobrenome, foto_perfil')
            .inFilter('id', todosIds.toList());
        for (final r in pRows) {
          nomes[(r['id'] as num).toInt()] =
              '${r['nome'] ?? ''} ${r['sobrenome'] ?? ''}'.trim();
          final foto = r['foto_perfil'] as String?;
          if (foto != null && foto.startsWith('http')) {
            fotos[(r['id'] as num).toInt()] = foto;
          }
        }
      }

      final lista = <OutraPessoaNaFamilia>[];

      // Carrega catálogo para fallback de rótulos nulos
      final tipos = await listarTipos();
      final rotuloBPorTipo = <String, String>{
        for (final t in tipos) t.id: t.rotuloB,
      };
      final rotuloAPorTipo = <String, String>{
        for (final t in tipos) t.id: t.rotuloA,
      };

      for (final r in rowsA) {
        final outraId = (r['pessoa_b_id'] as num).toInt();
        final tipo = r['tipo'] as String? ?? 'OUTRO';
        final rotB = r['relacao_b_para_a'] as String? ?? rotuloAPorTipo[tipo] ?? 'Pessoa';
        final rotA = r['relacao_a_para_b'] as String? ?? rotuloBPorTipo[tipo] ?? 'Pessoa';
        lista.add(OutraPessoaNaFamilia(
          relacionamentoId: (r['id'] as num).toInt(),
          outraPessoaId: outraId,
          outraPessoaNome: nomes[outraId] ?? 'Pessoa #$outraId',
          tipo: tipo,
          rotuloDaOutraParaMim: rotB,
          rotuloDeMimParaAOutra: rotA,
          fotoUrl: fotos[outraId],
        ));
      }

      // Completa com o lado B (só se ainda não houver a direta).
      // Na linha A→B invertida: A é a "outra"; o que A é para mim (B) =
      // relacao_a_para_b.
      final jaTem = lista.map((f) => f.outraPessoaId).toSet();
      for (final r in rowsB) {
        final outraId = (r['pessoa_a_id'] as num).toInt();
        if (jaTem.contains(outraId)) continue;
        final tipo = r['tipo'] as String? ?? 'OUTRO';
        final rotDaOutra =
            r['relacao_a_para_b'] as String? ?? rotuloBPorTipo[tipo] ?? 'Pessoa';
        final rotDeMim =
            r['relacao_b_para_a'] as String? ?? rotuloAPorTipo[tipo] ?? 'Pessoa';
        lista.add(OutraPessoaNaFamilia(
          relacionamentoId: (r['id'] as num).toInt(),
          outraPessoaId: outraId,
          outraPessoaNome: nomes[outraId] ?? 'Pessoa #$outraId',
          tipo: tipo,
          rotuloDaOutraParaMim: rotDaOutra,
          rotuloDeMimParaAOutra: rotDeMim,
          fotoUrl: fotos[outraId],
        ));
      }

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

  /// Lista de contatos — query oficial.
  /// select a.pessoa_b_id, a.relacao_b_para_a, b.nome
  /// from pessoas_relacionamentos a
  /// inner join pessoas b on a.pessoa_b_id = b.id
  /// where a.pessoa_a_id = ?
  /// order by pessoa_b_id;
  ///
  /// [excludeId] opcional: exclui uma pessoa específica do resultado
  /// (usado no Perfil da Pessoa para não mostrar a si mesma).
  Future<List<Map<String, dynamic>>> listarContatos({
    int? pessoaId,
    int? excludeId,
  }) async {
    if (!PessoaRepository.isConfigured) return const [];
    final pid = pessoaId ?? PessoaRepository.usuarioId;
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_b_id, relacao_b_para_a')
          .eq('pessoa_a_id', pid)
          .order('pessoa_b_id');

      if (rows.isEmpty) return [];

      final bIds = rows
          .map<int>((r) => (r['pessoa_b_id'] as num).toInt())
          .toList();

      final nomes = await PessoaRepository.supabaseClient
          .from('pessoas')
          .select('id, nome, sobrenome, tipo')
          .inFilter('id', bIds);

      final nomePorId = <int, String>{
        for (final r in nomes)
          (r['id'] as num).toInt():
              '${r['nome'] ?? ''} ${r['sobrenome'] ?? ''}'.trim(),
      };
      // S.9.3.1 — tipo da pessoa (humano/pet) para os seletores separados.
      final tipoPorId = <int, String>{
        for (final r in nomes)
          (r['id'] as num).toInt(): (r['tipo'] as String?) ?? 'humano',
      };

      return rows
          .map<Map<String, dynamic>>((r) {
            final bid = (r['pessoa_b_id'] as num).toInt();
            return {
              'pessoa_b_id': bid,
              'relacao_b_para_a': r['relacao_b_para_a'] as String? ?? '',
              'nome': nomePorId[bid] ?? 'Pessoa #$bid',
              'tipo': tipoPorId[bid] ?? 'humano',
            };
          })
          .where((m) =>
              excludeId == null || (m['pessoa_b_id'] as int) != excludeId)
          .toList();
    } catch (e) {
      print('[PessoaRelacionamento] listarContatos ERRO: $e');
      return const [];
    }
  }

  /// Mapa da Família — query oficial.
  /// select a.pessoa_b_id, a.relacao_b_para_a, a.tipo, a.relacao_a_para_b,
  ///        b.nome, c.nivel
  /// from pessoas_relacionamentos a
  /// inner join pessoas b on a.pessoa_b_id = b.id
  /// inner join tipos_relacionamento c on c.id = a.tipo
  /// where a.pessoa_a_id = ?
  /// order by c.nivel;
  Future<List<Map<String, dynamic>>> carregarGrafo() async {
    if (!PessoaRepository.isConfigured) return const [];
    final pessoaId = PessoaRepository.usuarioId;
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_b_id, relacao_b_para_a, tipo, relacao_a_para_b')
          .eq('pessoa_a_id', pessoaId)
          .neq('pessoa_b_id', pessoaId)
          .neq('tipo', 'AMIGO')
          .neq('tipo', 'CONHECIDO')
          .neq('tipo', 'OUTRO')
          // S.9.3 — pets não aparecem no Mapa da Família
          .neq('tipo', 'TUTOR')
          .neq('tipo', 'PET_DE')
          .order('pessoa_b_id');

      if (rows.isEmpty) return [];

      final bIds = rows
          .map<int>((r) => (r['pessoa_b_id'] as num).toInt())
          .toList();

      final nomes = await PessoaRepository.supabaseClient
          .from('pessoas')
          .select('id, nome, sobrenome')
          .inFilter('id', bIds);

      final nv = await PessoaRepository.supabaseClient
          .from('tipos_relacionamento')
          .select('id, nivel');

      final nomePorId = <int, String>{
        for (final r in nomes)
          (r['id'] as num).toInt():
              '${r['nome'] ?? ''} ${r['sobrenome'] ?? ''}'.trim(),
      };
      final nivelPorTipo = <String, int>{
        for (final r in nv) (r['id'] as String): (r['nivel'] as num?)?.toInt() ?? 99,
      };

      final out = rows.map<Map<String, dynamic>>((r) {
        final bid = (r['pessoa_b_id'] as num).toInt();
        final tipo = r['tipo'] as String? ?? 'OUTRO';
        return {
          'pessoa_b_id': bid,
          'relacao_b_para_a': r['relacao_b_para_a'] as String? ?? '',
          'tipo': tipo,
          'relacao_a_para_b': r['relacao_a_para_b'] as String? ?? '',
          'nome': nomePorId[bid] ?? 'Pessoa #$bid',
          'nivel': nivelPorTipo[tipo] ?? 99,
        };
      }).toList();

      out.sort((a, b) => (a['nivel'] as int).compareTo(b['nivel'] as int));
      return out;
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

    // Verifica se já existe relação entre as duas pessoas
    final existentes = await PessoaRepository.supabaseClient
        .from('pessoas_relacionamentos')
        .select('id')
        .or('and(pessoa_a_id.eq.$pessoaAId,pessoa_b_id.eq.$pessoaBId),and(pessoa_a_id.eq.$pessoaBId,pessoa_b_id.eq.$pessoaAId)')
        .limit(1);
    if (existentes.isNotEmpty) {
      throw Exception('duplicate: relação já existe entre as pessoas');
    }

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
  /// Usado para criar a linha inversa em `criar()` e pelas telas que
  /// precisam gravar o tipo correto do ponto de vista de cada linha.
  String inverseTipo(String tipo, String rotuloB) => _inverseTipo(tipo, rotuloB);

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
      case 'ENTEADO':
      case 'ENTEADA':
        return rotuloB == 'Madrasta' ? 'MADRASTA' : 'PADRASTO';
      case 'PADRASTO':
      case 'MADRASTA':
        return rotuloB == 'Enteada' ? 'ENTEADA' : 'ENTEADO';
      case 'GENRO':
      case 'NORA':
        return 'SOGRO';
      case 'SOGRO':
        return rotuloB == 'Genro' ? 'GENRO' : 'NORA';
      // S.9.3 — Pets
      case 'TUTOR':
        return 'PET_DE';
      case 'PET_DE':
        return 'TUTOR';
      // Simétricos: mesmo tipo nos dois lados
      default:
        return tipo; // IRMAO, CONJUGE, PRIMO, CUNHADO, AMIGO, OUTRO, COMPANHEIRO
    }
  }

  /// Atualiza os dados de uma relação (ambas as direções).
  /// Usado para alterar tipo, rótulos, observações, etc.
  Future<void> atualizarRotulos({
    required int relacionamentoId,
    String? tipo,
    String? relacaoA,
    String? relacaoB,
    String? observacoes,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      // Busca dados atuais para encontrar a linha inversa
      final row = await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .select('pessoa_a_id, pessoa_b_id, usuario_id')
          .eq('id', relacionamentoId)
          .single();
      final aId = (row['pessoa_a_id'] as num).toInt();
      final bId = (row['pessoa_b_id'] as num).toInt();
      final uId = (row['usuario_id'] as num?)?.toInt() ?? PessoaRepository.usuarioId;

      final data = <String, dynamic>{};
      if (relacaoA != null) data['relacao_a_para_b'] = relacaoA;
      if (relacaoB != null) data['relacao_b_para_a'] = relacaoB;
      if (tipo != null) data['tipo'] = tipo;
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

      // Atualiza a linha direta
      await PessoaRepository.supabaseClient
          .from('pessoas_relacionamentos')
          .update(data)
          .eq('id', relacionamentoId);

      // Atualiza a linha inversa com labels trocados
      final invData = <String, dynamic>{};
      if (relacaoB != null) invData['relacao_a_para_b'] = relacaoB;
      if (relacaoA != null) invData['relacao_b_para_a'] = relacaoA;
      if (tipo != null) {
        invData['tipo'] = _inverseTipo(tipo, relacaoB ?? relacaoA ?? '');
      }
      if (observacoes != null) invData['observacoes'] = observacoes;
      if (dataInicio != null) {
        invData['data_inicio'] =
            '${dataInicio.year}-${dataInicio.month.toString().padLeft(2, '0')}-${dataInicio.day.toString().padLeft(2, '0')}';
      }
      if (dataFim != null) {
        invData['data_fim'] =
            '${dataFim.year}-${dataFim.month.toString().padLeft(2, '0')}-${dataFim.day.toString().padLeft(2, '0')}';
      }

      if (invData.isNotEmpty) {
        await PessoaRepository.supabaseClient
            .from('pessoas_relacionamentos')
            .update(invData)
            .eq('usuario_id', uId)
            .or('and(pessoa_a_id.eq.$bId,pessoa_b_id.eq.$aId)');
      }
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
