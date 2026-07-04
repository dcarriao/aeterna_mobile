/// Sprint J — Tipos auxiliares do Curador Contextual.

/// DTO leve para passar o histórico ao serviço OpenAI. Espelha
/// `CuradorMensagem` (model persistido) mas é puramente em memória
/// — usado na chamada à OpenAI onde não precisamos de campos
/// específicos do banco.
class CuradorMensagemDTO {
  const CuradorMensagemDTO({
    required this.role,
    required this.conteudo,
    this.tipo,
  });

  final String role; // 'user' | 'assistant' | 'system'
  final String conteudo;
  final String? tipo; // opcional, mesmo enum do CuradorMensagemTipo
}

/// Resposta do LLM após o prompt contextual.
class CuradorRespostaIA {
  const CuradorRespostaIA({
    required this.pergunta,
    required this.deveEncerrar,
  });

  final String pergunta;

  /// Quando `true`, a IA está sugerindo que a conversa tem material
  /// suficiente. A `CuradorScreen` exibe a pergunta "deseja acrescentar
  /// mais?" para confirmação.
  final bool deveEncerrar;
}
