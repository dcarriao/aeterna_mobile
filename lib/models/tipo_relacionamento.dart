/// Sprint L — Catálogo de tipos de relação pessoa-pessoa.
///
/// O ID é o identificador estável interno (ex: `'PAI'`, `'CONJUGE'`,
/// `'IRMAO'`). Os rótulos `rotuloA`/`rotuloB` são o que aparece na
/// UI, e podem divergir em tipos assimétricos (PAI↔FILHA).
class TipoRelacionamento {
  const TipoRelacionamento({
    required this.id,
    required this.rotuloA,
    required this.rotuloB,
    required this.categoria,
    this.ativo = true,
  });

  final String id;
  final String rotuloA;
  final String rotuloB;
  final String categoria; // 'familia' | 'afinidade' | 'conjugue' | 'amizade' | 'outro'
  final bool ativo;

  bool get simetrico => rotuloA == rotuloB;

  factory TipoRelacionamento.fromMap(Map<String, dynamic> map) {
    return TipoRelacionamento(
      id: map['id'] as String,
      rotuloA: map['rotulo_a_para_b'] as String? ?? map['id'] as String,
      rotuloB: map['rotulo_b_para_a'] as String? ?? map['id'] as String,
      categoria: map['categoria'] as String? ?? 'outro',
      ativo: map['ativo'] as bool? ?? true,
    );
  }
}

/// Gênero de uma relação. Usado pela UI para mostrar rótulos
/// simétricos com concordância (ex: "Mãe" / "Filho(a)").
enum GeneroRelacao {
  masculino,
  feminino,
  neutro;

  String get rotuloFlexivel {
    switch (this) {
      case GeneroRelacao.masculino:
        return 'Masculino';
      case GeneroRelacao.feminino:
        return 'Feminino';
      case GeneroRelacao.neutro:
        return 'Neutro';
    }
  }
}

/// Constante client-side: lista de tipos de relação que a UI pode
/// mostrar ANTES de chamar o servidor. Usada como fallback se a
/// chamada RPC falhar. O servidor é a fonte da verdade.
const _TIPOS_INICIAIS = <TipoRelacionamento>[
  TipoRelacionamento(
      id: 'CONJUGE', rotuloA: 'Esposo(a)', rotuloB: 'Esposo(a)', categoria: 'conjugue'),
  TipoRelacionamento(
      id: 'COMPANHEIRO',
      rotuloA: 'Companheiro',
      rotuloB: 'Companheiro',
      categoria: 'conjugue'),
  TipoRelacionamento(
      id: 'PAI', rotuloA: 'Pai', rotuloB: 'Filho(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'MAE', rotuloA: 'Mãe', rotuloB: 'Filho(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'FILHO', rotuloA: 'Filho(a)', rotuloB: 'Pai', categoria: 'familia'),
  TipoRelacionamento(
      id: 'FILHA', rotuloA: 'Filho(a)', rotuloB: 'Mãe', categoria: 'familia'),
  TipoRelacionamento(
      id: 'IRMAO', rotuloA: 'Irmão(ã)', rotuloB: 'Irmão(ã)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'AVO', rotuloA: 'Avô(ó)', rotuloB: 'Neto(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'NETO', rotuloA: 'Neto(a)', rotuloB: 'Avô(ó)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'BISAVO', rotuloA: 'Bisavô(ó)', rotuloB: 'Bisneto(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'BISNETO', rotuloA: 'Bisneto(a)', rotuloB: 'Bisavô(ó)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'TIO', rotuloA: 'Tio(a)', rotuloB: 'Sobrinho(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'SOBRINHO', rotuloA: 'Sobrinho(a)', rotuloB: 'Tio(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'PRIMO', rotuloA: 'Primo(a)', rotuloB: 'Primo(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'PADRINHO', rotuloA: 'Padrinho', rotuloB: 'Afilhado(a)', categoria: 'afinidade'),
  TipoRelacionamento(
      id: 'MADRINHA', rotuloA: 'Madrinha', rotuloB: 'Afilhado(a)', categoria: 'afinidade'),
  TipoRelacionamento(
      id: 'AFILHADO', rotuloA: 'Afilhado(a)', rotuloB: 'Padrinho', categoria: 'afinidade'),
  TipoRelacionamento(
      id: 'GENRO', rotuloA: 'Genro', rotuloB: 'Sogro(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'NORA', rotuloA: 'Nora', rotuloB: 'Sogro(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'SOGRO', rotuloA: 'Sogro(a)', rotuloB: 'Genro/Nora', categoria: 'familia'),
  TipoRelacionamento(
      id: 'CUNHADO', rotuloA: 'Cunhado(a)', rotuloB: 'Cunhado(a)', categoria: 'familia'),
  TipoRelacionamento(
      id: 'AMIGO', rotuloA: 'Amigo(a)', rotuloB: 'Amigo(a)', categoria: 'amizade'),
  TipoRelacionamento(
      id: 'OUTRO', rotuloA: 'Conhecido(a)', rotuloB: 'Conhecido(a)', categoria: 'outro'),
];

List<TipoRelacionamento> get TIPOS_RELACIONAMENTO_INICIAIS => _TIPOS_INICIAIS;
