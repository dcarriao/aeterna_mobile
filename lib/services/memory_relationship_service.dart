import 'dart:async';
import 'dart:convert';

import '../models/memoria.dart';
import '../models/memoria_relacionamento.dart';
import '../models/pessoa.dart';
import 'supabase_service.dart';

/// Sprint K — Serviço de relacionamentos entre memórias.
///
/// Arquitetura (decidida com o usuário):
///   * A RPC `buscar_candidatas_relacionamento(memoria_id)` retorna
///     MEMÓRIAS candidatas (com sinais pré-computados no servidor).
///   * O score final é calculado no client (heurísticas puras).
///   * Só relações com score >= threshold são persistidas em
///     `memoria_relacionamentos`.
///   * Ao abrir uma memória, o app só consulta essa tabela — sem O(n²).
///   * Quando uma memória é criada/editada/recebe contribuição, o app
///     recalcula APENAS para aquela memória (incremental).
///
/// Pesos (centralizados em [MemoryRelationshipWeights] — fácil de ajustar).
class MemoryRelationshipWeights {
  const MemoryRelationshipWeights._();

  /// Limite mínimo para persistir a relação.
  static const int minimumScore = 40;

  // ── Pesos por sinal ──
  static const int mesmoTitulo = 40;
  static const int pessoasEmComum = 25; // por pessoa compartilhada
  static const int mesmoMes = 25; // mesmo mês/ano
  static const int datasProximas = 15; // até 60 dias
  static const int mesmoLocal = 20; // detectado por keywords do titulo
  static const int mesmaCategoria = 10;
  static const int contextoSemelhante = 10; // primeiras 30 chars

  // ── Limite da RPC de candidatas ──
  static const int rpcLimite = 30;

  // ── Janela de "datas próximas" (em dias) ──
  static const int janelaDatasProximasDias = 60;
}

class MemoryRelationshipService {
  MemoryRelationshipService._();
  static final instance = MemoryRelationshipService._();

  final _supabase = SupabaseService.instance;

  /// Busca candidatas a se relacionar com a memória `memoriaId` via RPC
  /// server-side. O app então calcula o score fino.
  Future<List<MemoriaCandidata>> buscarCandidatas(
    int memoriaId, {
    int limite = MemoryRelationshipWeights.rpcLimite,
  }) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .rpc('buscar_candidatas_relacionamento', params: {
        'p_memoria_id': memoriaId,
        'p_limite': limite,
      });
      return rows
          .cast<Map<String, dynamic>>()
          .map(MemoriaCandidata.fromMap)
          .toList();
    } catch (e) {
      print('[MemoryRelationship] buscarCandidatas ERRO: $e');
      return const [];
    }
  }

  /// Lista as relações CONFIRMADAS que envolvem `memoriaId` (em qualquer
  /// direção: origem ou destino).
  Future<List<MemoriaRelacionamento>> listarRelacionamentosConfirmados(
    int memoriaId, {
    int limite = 10,
  }) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('memoria_relacionamentos')
          .select('*')
          .or('memoria_origem_id.eq.$memoriaId,memoria_destino_id.eq.$memoriaId')
          .eq('status', 'confirmado')
          .order('score', ascending: false)
          .limit(limite);
      return rows
          .cast<Map<String, dynamic>>()
          .map(MemoriaRelacionamento.fromMap)
          .toList();
    } catch (e) {
      print('[MemoryRelationship] listarRelacionamentosConfirmados ERRO: $e');
      return const [];
    }
  }

  /// Lista TODAS as relações PENDENTES do usuário (Home: "Conexões
  /// descobertas"). Cada entrada vem com o título da memória de origem
  /// e destino para exibição direta.
  Future<List<MemoriaRelacionamento>> listarPendentesDoUsuario({
    int limite = 10,
  }) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      // A RPC `memorias_resumo_leve` traz contadores; aqui queremos
      // as relações em si com nome das memórias. Para evitar uma view
      // nova, fazemos o join client-side.
      final rows = await PessoaRepository.supabaseClient
          .from('memoria_relacionamentos')
          .select('*')
          .eq('usuario_id', PessoaRepository.usuarioId)
          .eq('status', 'pendente')
          .order('score', ascending: false)
          .limit(limite);
      if (rows.isEmpty) return const [];
      final lista = rows
          .cast<Map<String, dynamic>>()
          .map(MemoriaRelacionamento.fromMap)
          .toList();

      // Enriquece com títulos via 1 query em `memorias`.
      final ids = <int>{};
      for (final r in lista) {
        ids.add(r.memoriaOrigemId);
        ids.add(r.memoriaDestinoId);
      }
      final memRows = await PessoaRepository.supabaseClient
          .from('memorias')
          .select('id, titulo')
          .inFilter('id', ids.toList());
      final titulos = <int, String>{
        for (final m in memRows.cast<Map<String, dynamic>>())
          (m['id'] as num).toInt(): (m['titulo'] as String?) ?? '',
      };
      return lista.map((r) {
        return MemoriaRelacionamento(
          id: r.id,
          usuarioId: r.usuarioId,
          memoriaOrigemId: r.memoriaOrigemId,
          memoriaDestinoId: r.memoriaDestinoId,
          score: r.score,
          motivos: r.motivos,
          status: r.status,
          criadoEm: r.criadoEm,
          atualizadoEm: r.atualizadoEm,
          tituloOrigem: titulos[r.memoriaOrigemId],
          tituloDestino: titulos[r.memoriaDestinoId],
        );
      }).toList();
    } catch (e) {
      print('[MemoryRelationship] listarPendentesDoUsuario ERRO: $e');
      return const [];
    }
  }

  /// Calcula o score entre `origem` e `candidata` (heurísticas puras).
  /// Retorna a tupla (score, motivos) — apenas se score > 0.
  ({int score, RelacionamentoMotivos motivos})? calcularScore(
    Memoria origem,
    MemoriaCandidata candidata,
  ) {
    int score = 0;
    bool mesmaPessoa = false;
    bool mesmoMes = false;
    bool mesmoLocal = false;
    bool mesmoTitulo = false;
    bool mesmaCategoria = false;
    bool mesmoContexto = false;
    bool datasProximas = false;

    // 1) Mesmo título (peso alto) — sinal fortíssimo de duplicação ou
    // de continuação da mesma história.
    if (candidata.mesmoTitulo) {
      score += MemoryRelationshipWeights.mesmoTitulo;
      mesmoTitulo = true;
    }

    // 2) Pessoas em comum (peso cumulativo) — sinal fortíssimo.
    if (candidata.pessoasEmComum > 0) {
      score += candidata.pessoasEmComum *
          MemoryRelationshipWeights.pessoasEmComum;
      mesmaPessoa = true;
    }

    // 3) Proximidade temporal via data_evento.
    if (candidata.diasDiferencaEvento != null && origem.dataMemoria != null) {
      final diff = candidata.diasDiferencaEvento!;
      if (diff == 0) {
        // mesmo dia — peso alto
        score += MemoryRelationshipWeights.mesmoMes;
        mesmoMes = true;
        datasProximas = true;
      } else if (diff <=
          MemoryRelationshipWeights.janelaDatasProximasDias) {
        score += MemoryRelationshipWeights.datasProximas;
        datasProximas = true;
      }
    } else if (candidata.criadaEm != null) {
      // Fallback: usa criadaEm se data_evento ausente.
      final diff =
          DateTime.now().difference(candidata.criadaEm!).inDays.abs();
      if (diff <= MemoryRelationshipWeights.janelaDatasProximasDias) {
        score += 8;
        datasProximas = true;
      }
    }

    // 4) Mesma categoria.
    if (origem.categoria.isNotEmpty &&
        candidata.categoria != null &&
        origem.categoria == candidata.categoria) {
      score += MemoryRelationshipWeights.mesmaCategoria;
      mesmaCategoria = true;
    }

    // 5) "Mesmo local" — heurística leve: extrai a primeira palavra
    // com 4+ letras do título da origem e vê se está no título da
    // candidata (proxy barato para local compartilhado).
    final tituloOrigemNorm = origem.titulo.toLowerCase();
    final tituloCandidataNorm = candidata.titulo.toLowerCase();
    final palavrasOrigem = tituloOrigemNorm
        .split(RegExp(r'[^a-zà-ú]+'))
        .where((p) => p.length >= 4 && !_stopwords.contains(p))
        .toList();
    for (final p in palavrasOrigem) {
      if (tituloCandidataNorm.contains(p)) {
        score += MemoryRelationshipWeights.mesmoLocal;
        mesmoLocal = true;
        break;
      }
    }

    // 6) Contexto semelhante — se os primeiros 30 chars de cada
    // contexto (após normalizar) forem similares.
    if (origem.contexto.trim().length >= 10) {
      final a = origem.contexto
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-zà-ú ]'), '')
          .trim();
      final memBlob = _memoriasContextoCache[candidata.id];
      if (memBlob != null && memBlob.isNotEmpty) {
        final b = memBlob
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-zà-ú ]'), '')
            .trim();
        if (a.length >= 10 && b.length >= 10) {
          final prefixoA = a.substring(0, a.length > 30 ? 30 : a.length);
          final prefixoB = b.substring(0, b.length > 30 ? 30 : b.length);
          if (prefixoA == prefixoB) {
            score += MemoryRelationshipWeights.contextoSemelhante;
            mesmoContexto = true;
          }
        }
      }
    }

    final totalSinais = [
      mesmoTitulo,
      mesmaPessoa,
      mesmoMes,
      datasProximas,
      mesmoLocal,
      mesmaCategoria,
      mesmoContexto
    ].where((b) => b).length;

    final motivos = RelacionamentoMotivos(
      mesmaPessoa: mesmaPessoa,
      mesmoMes: mesmoMes,
      mesmoLocal: mesmoLocal,
      mesmoTitulo: mesmoTitulo,
      mesmaCategoria: mesmaCategoria,
      mesmoContexto: mesmoContexto,
      datasProximas: datasProximas,
      totalPessoasEmComum: candidata.pessoasEmComum,
      totalSinais: totalSinais,
    );

    if (score == 0) return null;
    return (score: score, motivos: motivos);
  }

  /// Cache local (in-memory) do `contexto` resumido das memórias
  /// para a heurística #6. Preenchido por [_preloadContexto].
  final Map<int, String> _memoriasContextoCache = {};

  Future<void> _preloadContexto(List<int> memoriaIds) async {
    if (memoriaIds.isEmpty) return;
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('memorias')
          .select('id, conteudo')
          .inFilter('id', memoriaIds);
      for (final m in rows.cast<Map<String, dynamic>>()) {
        _memoriasContextoCache[(m['id'] as num).toInt()] =
            (m['conteudo'] as String?) ?? '';
      }
    } catch (_) {
      // Silencioso — é apenas um sinal de score.
    }
  }

  /// Hook principal: chamado pela `NovaMemoriaScreen` após salvar uma
  /// memória. Calcula relacionamentos APENAS para esta memória
  /// (incremental — sem O(n²)).
  Future<void> aoSalvarMemoria(int memoriaId) async {
    await calcularEConfirmar(memoriaId);
  }

  /// Hook secundário: chamado pela `MemoriaContribuicaoScreen` quando
  /// uma contribuição é aprovada. Pode gerar novas relações.
  Future<void> aoReceberContribuicao(int memoriaId) async {
    await calcularEConfirmar(memoriaId);
  }

  /// Calcula as relações da `memoriaId` e persiste as que passarem o
  /// threshold. Idempotente — pode ser chamado várias vezes sem
  /// duplicar (usa upsert no par origem/destino).
  Future<int> calcularEConfirmar(int memoriaId) async {
    if (!PessoaRepository.isConfigured) return 0;
    try {
      // Carrega a memória de origem (precisa do contexto e da data).
      final origens = await _supabase.listarMemorias();
      final origem =
          origens.where((m) => m.id == memoriaId).cast<Memoria?>().firstOrNull;
      if (origem == null) {
        print('[MemoryRelationship] calcularEConfirmar: memoria $memoriaId nao encontrada');
        return 0;
      }

      // Busca candidatas (server-side) e pré-carrega contextos.
      final candidatas = await buscarCandidatas(memoriaId);
      if (candidatas.isEmpty) return 0;
      await _preloadContexto(candidatas.map((c) => c.id).toList());

      int persistidas = 0;
      // Calcula score para cada candidata e persiste as >= threshold.
      for (final c in candidatas) {
        final res = calcularScore(origem, c);
        if (res == null) continue;
        if (res.score < MemoryRelationshipWeights.minimumScore) continue;

        // Verifica se já existe relação (origem->destino OU destino->origem).
        final outrosLados = await PessoaRepository.supabaseClient
            .from('memoria_relacionamentos')
            .select('id, status')
            .or('and(memoria_origem_id.eq.${origem.id!},memoria_destino_id.eq.${c.id}),and(memoria_origem_id.eq.${c.id},memoria_destino_id.eq.${origem.id!}))')
            .limit(1);
        if (outrosLados.isNotEmpty) {
          // Atualiza a existente (recalcular score com base no estado
          // atual). Se estava ignorado, mantém.
          final existente = outrosLados.first as Map;
          if (existente['status'] == 'ignorado') continue;
          await PessoaRepository.supabaseClient
              .from('memoria_relacionamentos')
              .update({
                'score': res.score,
                'motivos': jsonEncode(res.motivos.toMap()),
                'atualizado_em': DateTime.now().toIso8601String(),
              })
              .eq('id', existente['id']);
          continue;
        }

        // Cria nova.
        await PessoaRepository.supabaseClient
            .from('memoria_relacionamentos')
            .insert({
              'usuario_id': PessoaRepository.usuarioId,
              'memoria_origem_id': origem.id,
              'memoria_destino_id': c.id,
              'score': res.score,
              'motivos': jsonEncode(res.motivos.toMap()),
              'status': 'pendente',
            });
        persistidas++;
      }
      return persistidas;
    } catch (e) {
      print('[MemoryRelationship] calcularEConfirmar ERRO: $e');
      return 0;
    }
  }

  /// Confirma uma relação PENDENTE (após o usuário aceitar na UI).
  Future<void> confirmar(int relacionamentoId) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      await PessoaRepository.supabaseClient
          .from('memoria_relacionamentos')
          .update({'status': 'confirmado'}).eq('id', relacionamentoId);
    } catch (e) {
      print('[MemoryRelationship] confirmar ERRO: $e');
    }
  }

  /// Ignora uma relação (não voltará a ser sugerida — a heurística
  /// sempre pula memória onde existe relação com status='ignorado').
  Future<void> ignorar(int relacionamentoId) async {
    if (!PessoaRepository.isConfigured) return;
    try {
      await PessoaRepository.supabaseClient
          .from('memoria_relacionamentos')
          .update({'status': 'ignorado'}).eq('id', relacionamentoId);
    } catch (e) {
      print('[MemoryRelationship] ignorar ERRO: $e');
    }
  }
}

/// Stopwords usadas na heurística de "mesmo local" — palavras comuns
/// em títulos de memórias familiares que não devem ser tratadas como
/// local.
const _stopwords = {
  'a', 'o', 'as', 'os', 'um', 'uma', 'uns', 'umas', 'de', 'da', 'do',
  'das', 'dos', 'em', 'na', 'no', 'nas', 'nos', 'pra', 'com',
  'sem', 'por', 'e', 'ou', 'aos', 'ao', 'ser',
  'ter', 'tinha', 'teve', 'muito', 'muita', 'dia', 'noite', 'hoje', 'ontem',
  'fizemos', 'fomos', 'fui', 'todo', 'toda',
  'todos', 'todas', 'meu', 'minha', 'meus', 'minhas', 'seu', 'sua',
  'teu', 'tua', 'nosso', 'nossa', 'aqui', 'ali',
  'casa', 'festa', 'aniversario', 'natal', 'ano', 'novo',
  'velho', 'primeiro', 'primeira', 'segundo', 'terceira', 'ultimo',
  'jantar', 'almoco', 'cafe',
  'passeio', 'viagem',
};
