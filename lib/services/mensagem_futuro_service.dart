import '../models/mensagem_futuro.dart';
import '../models/pessoa.dart';

class MensagemFuturoService {
  MensagemFuturoService._();
  static final instance = MensagemFuturoService._();

  Future<List<MensagemFuturo>> listar() async {
    if (!PessoaRepository.isConfigured) return [];
    final rows = await PessoaRepository.supabaseClient
        .from('mensagens_futuro')
        .select('id, titulo, conteudo, data_agendamento, entregue, created_at')
        .eq('usuario_id', PessoaRepository.usuarioId)
        .order('data_agendamento', ascending: false);
    return rows.map<MensagemFuturo>((r) => MensagemFuturo.fromMap(r)).toList();
  }

  Future<int?> criar(MensagemFuturo msg) async {
    if (!PessoaRepository.isConfigured) return null;
    final data = msg.toMap();
    data['usuario_id'] = PessoaRepository.usuarioId;
    final resp = await PessoaRepository.supabaseClient
        .from('mensagens_futuro')
        .insert(data)
        .select('id')
        .single();
    return resp['id'] as int?;
  }

  Future<void> atualizar(int id, MensagemFuturo msg) async {
    if (!PessoaRepository.isConfigured) return;
    await PessoaRepository.supabaseClient
        .from('mensagens_futuro')
        .update(msg.toMap())
        .eq('id', id)
        .eq('usuario_id', PessoaRepository.usuarioId);
  }

  Future<void> remover(int id) async {
    if (!PessoaRepository.isConfigured) return;
    await PessoaRepository.supabaseClient
        .from('mensagens_futuro')
        .delete()
        .eq('id', id)
        .eq('usuario_id', PessoaRepository.usuarioId);
  }
}
