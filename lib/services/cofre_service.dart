import '../models/cofre_item.dart';
import '../models/pessoa.dart';

class CofreService {
  CofreService._();
  static final instance = CofreService._();

  Future<List<CofreItem>> listar() async {
    if (!PessoaRepository.isConfigured) return [];
    final rows = await PessoaRepository.supabaseClient
        .from('cofre_itens')
        .select('id, titulo, tipo, conteudo, url_arquivo, created_at')
        .eq('usuario_id', PessoaRepository.usuarioId)
        .order('created_at', ascending: false);
    return rows.map<CofreItem>((r) => CofreItem.fromMap(r)).toList();
  }

  Future<int?> criar(CofreItem item) async {
    if (!PessoaRepository.isConfigured) return null;
    final data = item.toMap();
    data['usuario_id'] = PessoaRepository.usuarioId;
    final resp = await PessoaRepository.supabaseClient
        .from('cofre_itens')
        .insert(data)
        .select('id')
        .single();
    return resp['id'] as int?;
  }

  Future<void> remover(int id) async {
    if (!PessoaRepository.isConfigured) return;
    await PessoaRepository.supabaseClient
        .from('cofre_itens')
        .delete()
        .eq('id', id)
        .eq('usuario_id', PessoaRepository.usuarioId);
  }
}
