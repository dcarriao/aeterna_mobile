import '../models/pessoa_linha_tempo.dart';
import '../models/pessoa.dart';

/// Sprint H — Serviço que agrega a "Linha do Tempo da Pessoa" usando as
/// views/funções RPC do Supabase criadas em `sprint_h_pessoas_vivas.sql`.
///
/// Princípio: NENHUMA tabela materializada no client. Toda a agregação
/// é feita no Supabase em views/funções SQL, retornando apenas as
/// projeções que a UI precisa.
class PessoaTimelineService {
  PessoaTimelineService._();
  static final instance = PessoaTimelineService._();

  // ── Constantes de chaves de cache em SharedPreferences ──
  // Usado como cache simples (in-memory) por sessão para evitar
  // refazer a mesma query pesada ao navegar entre abas da pessoa.

  /// Retorna a linha do tempo de uma pessoa (eventos de memória, foto,
  /// vídeo e contribuição aprovados). Ordenado do mais recente para o
  /// mais antigo.
  Future<List<PessoaTimelineEvento>> obterLinhaDoTempo(int pessoaId,
      {int limite = 200}) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      return _obterLinhaDoTempoImpl(pessoaId, limite);
    } catch (e) {
      print('[PessoaTimeline] obterLinhaDoTempo ERRO: $e');
      return const [];
    }
  }

  Future<List<PessoaTimelineEvento>> _obterLinhaDoTempoImpl(
    int pessoaId, int limite,
  ) async {
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('pessoa_linha_tempo')
          .select('*')
          .eq('pessoa_id', pessoaId)
          .limit(limite);
      final eventos = rows
          .cast<Map<String, dynamic>>()
          .map<PessoaTimelineEvento>((r) => PessoaTimelineEvento.fromMap(r))
          .toList();
      return _enriquecerMidia(eventos);
    } catch (e) {
      print('[PessoaTimelineService] obterLinhaDoTempo ERRO: $e');
      return const [];
    }
  }

  Future<PessoaEstatisticas> obterEstatisticas(int pessoaId) async {
    if (!PessoaRepository.isConfigured) {
      return const PessoaEstatisticas(
        totalMemorias: 0,
        totalFotos: 0,
        totalVideos: 0,
        totalContribuicoes: 0,
      );
    }
    try {
      final rows = await PessoaRepository.supabaseClient
          .rpc('pessoa_estatisticas', params: {'pessoa_id': pessoaId})
          .select('*')
          .limit(1);
      if (rows.isEmpty) {
        return const PessoaEstatisticas(
          totalMemorias: 0,
          totalFotos: 0,
          totalVideos: 0,
          totalContribuicoes: 0,
        );
      }
      return PessoaEstatisticas.fromMap(
          (rows.first as Map).cast<String, dynamic>());
    } catch (e) {
      print('[PessoaTimelineService] obterEstatisticas ERRO: $e');
      return const PessoaEstatisticas(
        totalMemorias: 0,
        totalFotos: 0,
        totalVideos: 0,
        totalContribuicoes: 0,
      );
    }
  }

  /// Pessoas com maior "última interação" — alimenta a Home.
  Future<List<PessoaVivaResumo>> obterPessoasRecentes({
    int limite = 8,
  }) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .rpc('pessoas_recentes', params: {
        'usuario': PessoaRepository.usuarioId,
        'limite': limite,
      })
          .select('*');
      return rows
          .cast<Map<String, dynamic>>()
          .map<PessoaVivaResumo>((r) => PessoaVivaResumo.fromMap(r))
          .toList();
    } catch (e) {
      print('[PessoaTimelineService] obterPessoasRecentes ERRO: $e');
      return const [];
    }
  }

  /// "Fantasmas" — nomes que aparecem em memórias mas não têm cadastro
  /// em `pessoas` ainda. Alimenta a descoberta automática.
  Future<List<PessoaSugerida>> obterSugestoes({int limite = 5}) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .rpc('pessoas_sugeridas', params: {
        'usuario': PessoaRepository.usuarioId,
        'limite': limite,
      })
          .select('*');
      return rows
          .cast<Map<String, dynamic>>()
          .map<PessoaSugerida>((r) => PessoaSugerida.fromMap(r))
          .toList();
    } catch (e) {
      print('[PessoaTimelineService] obterSugestoes ERRO: $e');
      return const [];
    }
  }

  /// Vínculo Pessoa → Memorial (se existir).
  /// S.9.4b — REGRA (Darlan): no perfil de um HUMANO, patrimônio afetivo
  /// e linha do tempo mostram o que ELE PUBLICOU (memorias.usuario_id =
  /// pessoa), nunca participações em memórias de terceiros. Pendente
  /// nunca publicou => vazio. (Pets continuam por aparições — eles não
  /// publicam.)
  Future<PessoaEstatisticas> obterEstatisticasPublicadas(int pessoaId) async {
    if (!PessoaRepository.isConfigured) {
      return const PessoaEstatisticas(totalMemorias: 0, totalFotos: 0,
          totalVideos: 0, totalContribuicoes: 0);
    }
    // S.9.4c — cada contagem isolada em seu próprio try/catch: se UMA
    // consulta falhar (coluna ausente numa tabela, RLS, etc.) as demais
    // continuam somando, em vez de zerar todo o patrimônio (bug Alice).
    final db = PessoaRepository.supabaseClient;

    int totalMemorias = 0;
    DateTime? primeira, ultima;
    try {
      final mems = await db
          .from('memorias')
          .select('id, data_evento, data_criacao')
          .eq('usuario_id', pessoaId);
      totalMemorias = mems.length;
      for (final m in mems) {
        final d = DateTime.tryParse(
            '${m['data_evento'] ?? m['data_criacao'] ?? ''}');
        if (d == null) continue;
        if (primeira == null || d.isBefore(primeira)) primeira = d;
        if (ultima == null || d.isAfter(ultima)) ultima = d;
      }
    } catch (e) {
      print('[PessoaTimeline] estatisticasPublicadas memorias ERRO: $e');
    }

    int totalFotos = 0;
    try {
      final fotos = await db
          .from('fotos').select('id').eq('usuario_id', pessoaId);
      totalFotos = fotos.length;
    } catch (e) {
      print('[PessoaTimeline] estatisticasPublicadas fotos ERRO: $e');
    }

    int totalVideos = 0;
    try {
      final videos = await db
          .from('videos').select('id').eq('usuario_id', pessoaId);
      totalVideos = videos.length;
    } catch (e) {
      print('[PessoaTimeline] estatisticasPublicadas videos ERRO: $e');
    }

    int totalContribuicoes = 0;
    try {
      final contribs = await db
          .from('contribuicoes')
          .select('id')
          .eq('usuario_id', pessoaId)
          .eq('status', 'aprovado');
      totalContribuicoes = contribs.length;
    } catch (e) {
      print('[PessoaTimeline] estatisticasPublicadas contribuicoes ERRO: $e');
    }

    return PessoaEstatisticas(
      totalMemorias: totalMemorias,
      totalFotos: totalFotos,
      totalVideos: totalVideos,
      totalContribuicoes: totalContribuicoes,
      primeiraData: primeira,
      ultimaData: ultima,
    );
  }

  /// S.9.4b — linha do tempo do humano: memórias que ELE publicou
  /// (o RLS limita às que o usuário atual pode ver).
  Future<List<PessoaTimelineEvento>> obterLinhaDoTempoPublicada(
      int pessoaId) async {
    if (!PessoaRepository.isConfigured) return const [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('memorias')
          .select('id, titulo, data_evento, data_criacao')
          .eq('usuario_id', pessoaId)
          .order('data_criacao', ascending: false)
          .limit(50);
      final eventos = <PessoaTimelineEvento>[
        for (final r in rows)
          PessoaTimelineEvento(
            tipo: PessoaTimelineTipo.memoria,
            conteudoId: (r['id'] as num).toInt(),
            titulo: (r['titulo'] as String?) ?? 'Memória',
            data: DateTime.tryParse(
                    '${r['data_evento'] ?? r['data_criacao'] ?? ''}') ??
                DateTime.now(),
          ),
      ];
      return _enriquecerMidia(eventos);
    } catch (e) {
      print('[PessoaTimeline] linhaPublicada ERRO: $e');
      return const [];
    }
  }

  /// Anexa fotoUrl/videoUrl em lote para eventos de memória.
  Future<List<PessoaTimelineEvento>> _enriquecerMidia(
    List<PessoaTimelineEvento> eventos,
  ) async {
    final memoriaIds = <int>{
      for (final e in eventos)
        if (e.tipo == PessoaTimelineTipo.memoria) e.conteudoId,
      for (final e in eventos)
        if (e.memoriaOrigemId != null) e.memoriaOrigemId!,
    }.toList();
    if (memoriaIds.isEmpty) return eventos;

    final fotoPorMemoria = <int, String>{};
    final videoPorMemoria = <int, String>{};
    try {
      final db = PessoaRepository.supabaseClient;
      final vinculosFoto = await db
          .from('memoria_fotos')
          .select('memoria_id, foto_id')
          .inFilter('memoria_id', memoriaIds);
      if (vinculosFoto.isNotEmpty) {
        final fotoIds = vinculosFoto
            .map<int>((r) => (r['foto_id'] as num).toInt())
            .toSet()
            .toList();
        final fotos = await db
            .from('fotos')
            .select('id, caminho_arquivo')
            .inFilter('id', fotoIds);
        final urlPorFoto = <int, String>{
          for (final f in fotos)
            if (f['caminho_arquivo'] != null)
              (f['id'] as num).toInt():
                  PessoaRepository.resolverUrlFoto(
                          f['caminho_arquivo'] as String?) ??
                      f['caminho_arquivo'] as String,
        };
        for (final v in vinculosFoto) {
          final mid = (v['memoria_id'] as num).toInt();
          final url = urlPorFoto[(v['foto_id'] as num).toInt()];
          if (url != null) fotoPorMemoria.putIfAbsent(mid, () => url);
        }
      }
      final vinculosVid = await db
          .from('memoria_videos')
          .select('memoria_id, video_id')
          .inFilter('memoria_id', memoriaIds);
      if (vinculosVid.isNotEmpty) {
        final videoIds = vinculosVid
            .map<int>((r) => (r['video_id'] as num).toInt())
            .toSet()
            .toList();
        final videos = await db
            .from('videos')
            .select('id, caminho_arquivo')
            .inFilter('id', videoIds);
        final urlPorVideo = <int, String>{
          for (final v in videos)
            if (v['caminho_arquivo'] != null)
              (v['id'] as num).toInt():
                  PessoaRepository.resolverUrlFoto(
                          v['caminho_arquivo'] as String?) ??
                      v['caminho_arquivo'] as String,
        };
        for (final v in vinculosVid) {
          final mid = (v['memoria_id'] as num).toInt();
          final url = urlPorVideo[(v['video_id'] as num).toInt()];
          if (url != null) videoPorMemoria.putIfAbsent(mid, () => url);
        }
      }
    } catch (e) {
      print('[PessoaTimeline] enriquecerMidia ERRO: $e');
      return eventos;
    }

    return [
      for (final e in eventos)
        _comMidia(
          e,
          fotoPorMemoria,
          videoPorMemoria,
        ),
    ];
  }

  PessoaTimelineEvento _comMidia(
    PessoaTimelineEvento e,
    Map<int, String> fotoPorMemoria,
    Map<int, String> videoPorMemoria,
  ) {
    final mid = e.tipo == PessoaTimelineTipo.memoria
        ? e.conteudoId
        : e.memoriaOrigemId;
    if (mid == null) return e;
    final foto = fotoPorMemoria[mid];
    final video = videoPorMemoria[mid];
    if (foto == null && video == null) return e;
    return PessoaTimelineEvento(
      tipo: e.tipo,
      conteudoId: e.conteudoId,
      titulo: e.titulo,
      data: e.data,
      memoriaOrigemId: e.memoriaOrigemId,
      contribuicaoId: e.contribuicaoId,
      autorContribuicao: e.autorContribuicao,
      fotoUrl: foto ?? e.fotoUrl,
      videoUrl: video ?? e.videoUrl,
    );
  }

  Future<MemorialResumo?> obterMemorialDaPessoa(int pessoaId) async {
    if (!PessoaRepository.isConfigured) return null;
    try {
      final rows = await PessoaRepository.supabaseClient
          .rpc('memorial_da_pessoa', params: {'pessoa_id': pessoaId})
          .select('*')
          .limit(1);
      if (rows.isEmpty) return null;
      return MemorialResumo.fromMap(
          (rows.first as Map).cast<String, dynamic>());
    } catch (e) {
      print('[PessoaTimelineService] obterMemorialDaPessoa ERRO: $e');
      return null;
    }
  }

  /// Sprint L — calcula há quantos anos a pessoa `pessoaReferenciaId`
  /// aparece em memórias, e se HOJE é o aniversário de uma dessas
  /// memórias. Retorna `null` se não houver registro hoje.
  ///
  /// Heurística: o evento mais antigo da `pessoa_linha_tempo` cuja data
  /// coincide com o dia de hoje. Limitado a memórias e contribuições
  /// (não conta fotos/vídeos puros).
  Future<({int? anos, DateTime? dataMaisAntiga})> calcularAniversario(
    int pessoaReferenciaId,
  ) async {
    if (!PessoaRepository.isConfigured) return (anos: null, dataMaisAntiga: null);
    final eventos = await _obterLinhaDoTempoImpl(pessoaReferenciaId, 200);
    if (eventos.isEmpty) return (anos: null, dataMaisAntiga: null);
    // Filtra só memórias e contribuições.
    final relevantes = eventos
        .where((e) => e.tipo == PessoaTimelineTipo.memoria)
        .toList();
    if (relevantes.isEmpty) return (anos: null, dataMaisAntiga: null);
    // O RPC ordena por data_ordem DESC. Pegamos a ÚLTIMA (mais antiga).
    final maisAntiga = relevantes.last.data;
    final hoje = DateTime.now();
    final mesmoDia = maisAntiga.year == hoje.year &&
        maisAntiga.month == hoje.month &&
        maisAntiga.day == hoje.day;
    if (!mesmoDia) return (anos: null, dataMaisAntiga: maisAntiga);
    final anos = hoje.year - maisAntiga.year;
    return (anos: anos, dataMaisAntiga: maisAntiga);
  }
}

