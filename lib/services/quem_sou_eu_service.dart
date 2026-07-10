import '../models/pessoa.dart';
import '../models/quem_sou_eu.dart';

class QuemSouEuService {
  QuemSouEuService._();
  static final instance = QuemSouEuService._();

  Future<List<QuemSouEuRegistro>> listar() async {
    if (!PessoaRepository.isConfigured) return [];
    try {
      final rows = await PessoaRepository.supabaseClient
          .from('quem_sou_eu')
          .select('id, pergunta_chave, resposta, created_at, updated_at')
          .eq('usuario_id', PessoaRepository.usuarioId)
          .order('created_at', ascending: false);
      return rows
          .map<QuemSouEuRegistro>((r) => QuemSouEuRegistro.fromMap(r))
          .toList();
    } catch (e) {
      print('[QuemSouEu] listar ERRO: $e');
      return [];
    }
  }

  Future<int?> salvar(QuemSouEuRegistro reg) async {
    if (!PessoaRepository.isConfigured) return null;
    if (reg.id != null) {
      await PessoaRepository.supabaseClient
          .from('quem_sou_eu')
          .update({...reg.toMap(), 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', reg.id!)
          .eq('usuario_id', PessoaRepository.usuarioId);
      return reg.id;
    }
    final data = reg.toMap();
    data['usuario_id'] = PessoaRepository.usuarioId;
    final resp = await PessoaRepository.supabaseClient
        .from('quem_sou_eu')
        .insert(data)
        .select('id')
        .single();
    return resp['id'] as int?;
  }

  Future<void> remover(int id) async {
    if (!PessoaRepository.isConfigured) return;
    await PessoaRepository.supabaseClient
        .from('quem_sou_eu')
        .delete()
        .eq('id', id)
        .eq('usuario_id', PessoaRepository.usuarioId);
  }
}
