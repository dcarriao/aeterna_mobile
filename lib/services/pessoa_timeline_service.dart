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
      final rows = await PessoaRepository.supabaseClient
          .rpc('pessoa_linha_tempo', params: {})
          .select('*')
          // A view retorna todos os contatos; filtramos no client.
          // (Se a base ficar grande, criar função parametrizada depois.)
          .limit(limite * 5);
      final eventos = rows
          .cast<Map<String, dynamic>>()
          .where((r) => (r['contato_id'] as num?)?.toInt() == pessoaId)
          .take(limite)
          .map<PessoaTimelineEvento>((r) => PessoaTimelineEvento.fromMap(r))
          .toList();
      return eventos;
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
  /// em `contatos` ainda. Alimenta a descoberta automática.
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
}

