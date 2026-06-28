enum CategoriaPergunta { factual, emocional, legado }

class PerguntaCurador {
  const PerguntaCurador({
    required this.texto,
    required this.categoria,
  });

  final String texto;
  final CategoriaPergunta categoria;
}

// ── Perguntas por contexto ──

const _factuais = [
  PerguntaCurador(texto: 'Quando isso aconteceu?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Onde aconteceu?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Quem estava presente nesse momento?', categoria: CategoriaPergunta.factual),
];

const _emocionais = [
  PerguntaCurador(texto: 'Como você se sentiu nesse momento?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'O que mais marcou você?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'Se pudesse guardar só uma lembrança, qual seria?', categoria: CategoriaPergunta.emocional),
];

const _eventoFamiliar = [
  PerguntaCurador(texto: 'O que tornou esse momento especial?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'Onde aconteceu?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Quem estava presente?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Alguma conversa ficou marcada?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'Como você lembra desse dia?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'Existe algum detalhe que uma foto não mostraria?', categoria: CategoriaPergunta.emocional),
];

const _viagem = [
  PerguntaCurador(texto: 'Para onde vocês foram?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'O que motivou essa viagem?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'O que mais marcou você?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'Houve algum imprevisto ou surpresa?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'Qual lembrança você gostaria de preservar?', categoria: CategoriaPergunta.emocional),
];

const _conquista = [
  PerguntaCurador(texto: 'Qual era o objetivo?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Quanto tempo levou para alcançar?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Quem esteve ao seu lado?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Qual foi a maior dificuldade?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'Como você se sentiu ao concluir?', categoria: CategoriaPergunta.emocional),
];

const _pessoa = [
  PerguntaCurador(texto: 'Como essa pessoa fazia parte da sua vida?', categoria: CategoriaPergunta.legado),
  PerguntaCurador(texto: 'O que mais a caracterizava?', categoria: CategoriaPergunta.legado),
  PerguntaCurador(texto: 'Existe alguma história que represente bem quem ela era?', categoria: CategoriaPergunta.legado),
  PerguntaCurador(texto: 'Existe algum ensinamento marcante dessa pessoa?', categoria: CategoriaPergunta.legado),
  PerguntaCurador(texto: 'O que você gostaria que seus filhos soubessem sobre ela?', categoria: CategoriaPergunta.legado),
];

const _infancia = [
  PerguntaCurador(texto: 'Quantos anos você tinha?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Onde você morava naquela época?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Como você se sentia naquele tempo?', categoria: CategoriaPergunta.emocional),
  PerguntaCurador(texto: 'Quem fazia parte desse momento?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'O que mudou de lá para cá?', categoria: CategoriaPergunta.emocional),
];

const _trabalho = [
  PerguntaCurador(texto: 'Como conseguiu essa oportunidade?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'O que você aprendeu nessa experiência?', categoria: CategoriaPergunta.legado),
  PerguntaCurador(texto: 'Alguém te ajudou ou inspirou?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Qual foi o maior desafio?', categoria: CategoriaPergunta.emocional),
];

const _reflexao = [
  PerguntaCurador(texto: 'O que motivou esse pensamento?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Sua forma de pensar mudou depois disso?', categoria: CategoriaPergunta.legado),
  PerguntaCurador(texto: 'Como isso impactou suas decisões?', categoria: CategoriaPergunta.legado),
  PerguntaCurador(texto: 'Existe uma mensagem que gostaria de deixar?', categoria: CategoriaPergunta.legado),
];

const _aprendizado = [
  PerguntaCurador(texto: 'O que você aprendeu?', categoria: CategoriaPergunta.legado),
  PerguntaCurador(texto: 'Quem te ensinou ou inspirou?', categoria: CategoriaPergunta.factual),
  PerguntaCurador(texto: 'Como você aplica isso na sua vida hoje?', categoria: CategoriaPergunta.legado),
];

class AnaliseLegado {
  const AnaliseLegado({
    this.valores = const [],
    this.aprendizados = const [],
    this.caracteristicas = const [],
  });

  final List<String> valores;
  final List<String> aprendizados;
  final List<String> caracteristicas;

  bool get temConteudo =>
      valores.isNotEmpty || aprendizados.isNotEmpty || caracteristicas.isNotEmpty;
}

class MotorPerguntas {
  const MotorPerguntas();

  String? _classificar(String texto) {
    final t = texto.toLowerCase();

    if (RegExp(r'\b(pai|m[aã]e|av[oô]|av[óo]|bisavô|bisavó|irm[ãa]o|irm[ãa]|tio|tia)\b').hasMatch(t) &&
        (t.length < 60 || RegExp(r'\b(era|foi\s+um[ae]?|pessoa|lembr[oa]|saudade)\b').hasMatch(t))) {
      return 'pessoa';
    }
    if (RegExp(r'\b(viagem|viaj[aeo]|viajei|passeio|f[eé]rias|conheci\s+\w+|gramado|cidade|praia|hotel|estrada)\b').hasMatch(t)) return 'viagem';
    if (RegExp(r'\b(formatura|formei|conquistei|consegui|promo[cç][aã]o|vestibular|aprovado|passei|pr[eê]mio|certificado|trofeu|medalha)\b').hasMatch(t)) return 'conquista';
    if (RegExp(r'\b(almo[cç]o|jantar|festa|natal|ano\s+novo|p[aá]scoa|anivers[aá]rio|ceia|churrasco|reuni[aã]o\s+(de\s+)?fam[ií]lia|encontro\s+familiar)\b').hasMatch(t)) return 'evento_familiar';
    if (RegExp(r'\b(trabalho|emprego|empresa|carreira|escrit[oó]rio|entrevista|contrata[cç][aã]o|demiss[aã]o|chefe|colega\s+de\s+trabalho)\b').hasMatch(t)) return 'trabalho';
    if (RegExp(r'\b(aprendi|ensinou|curso|aula|estud[ae]|professor)\b').hasMatch(t)) return 'aprendizado';
    if (RegExp(r'\b(crian[cç]a|pequen[oa]|cresci|inf[aâ]ncia|escola|brincava|brinquedo|quando\s+eu\s+era\s+(criança|pequeno|pequena|novo|nova))\b').hasMatch(t)) return 'infancia';
    if (RegExp(r'\b(refleti[r]?|pens[ae]|conversa\s+que\s+mudou|mudou\s+minha\s+forma|percebi|entendi\s+que)\b').hasMatch(t)) return 'reflexao';

    if (RegExp(r'\b(pai|m[aã]e|av[oô]|tio|tia)\b').hasMatch(t)) return 'pessoa';
    return null;
  }

  List<PerguntaCurador> selecionar(
    String contexto, {
    bool temPessoas = false,
    bool temData = false,
  }) {
    final categoria = _classificar(contexto);

    List<PerguntaCurador> selecionadas;
    switch (categoria) {
      case 'evento_familiar':
        selecionadas = [..._eventoFamiliar];
        if (temPessoas) {
          selecionadas.removeWhere((p) => p.texto.contains('Quem estava'));
        }
        if (temData) {
          selecionadas.removeWhere((p) => p.texto.contains('Quando') || p.texto.contains('onde'));
        }
      case 'viagem':
        selecionadas = [..._viagem];
      case 'conquista':
        selecionadas = [..._conquista];
        if (temPessoas) {
          selecionadas.removeWhere((p) => p.texto.contains('ao seu lado'));
        }
      case 'pessoa':
        selecionadas = [..._pessoa];
      case 'infancia':
        selecionadas = [..._infancia];
        if (temPessoas) {
          selecionadas.removeWhere((p) => p.texto.contains('Quem fazia'));
        }
      case 'trabalho':
        selecionadas = [..._trabalho];
      case 'reflexao':
        selecionadas = [..._reflexao];
      case 'aprendizado':
        selecionadas = [..._aprendizado];
      default:
        selecionadas = [
          if (!temPessoas) _factuais[2],
          if (!temData) _factuais[0],
          _emocionais[0],
          _emocionais[1],
          _emocionais[2],
        ];
    }

    // Filtros de segurança gerais
    if (temPessoas) {
      selecionadas.removeWhere((p) => p.texto.toLowerCase().contains('quem estava') || p.texto.toLowerCase().contains('quem participou'));
    }
    if (temData) {
      selecionadas.removeWhere((p) => p.texto.toLowerCase().contains('quando isso aconteceu'));
    }

    if (selecionadas.length > 7) {
      selecionadas = selecionadas.sublist(0, 7);
    }
    if (selecionadas.length < 3) {
      selecionadas.addAll(_emocionais.take(3 - selecionadas.length));
    }

    return selecionadas;
  }

  String montarNarrativa(String contextoOriginal, Map<String, String> respostas) {
    if (respostas.isEmpty) return contextoOriginal;

    final pessoas = <String>[];
    final locais = <String>[];
    final sentimentos = <String>[];
    final aprendizados = <String>[];
    final outros = <String>[];

    for (final entry in respostas.entries) {
      final p = entry.key.toLowerCase();
      final r = entry.value.trim();
      if (r.isEmpty) continue;

      if (p.contains('quem') || p.contains('pessoa') || p.contains('presente')) {
        pessoas.add(r);
      } else if (p.contains('onde') || p.contains('local')) {
        locais.add(r);
      } else if (p.contains('sentiu') || p.contains('emoção') || p.contains('marcou') || p.contains('lembrança')) {
        sentimentos.add(r);
      } else if (p.contains('aprend') || p.contains('ensin') || p.contains('lição')) {
        aprendizados.add(r);
      } else {
        outros.add(r);
      }
    }

    final buffer = StringBuffer();
    buffer.writeln(contextoOriginal.trim());
    buffer.writeln();

    final todasAsPartes = <String>[];

    if (pessoas.isNotEmpty) {
      todasAsPartes.add('Estavam presentes ${pessoas.join(', ')}.');
    }
    if (locais.isNotEmpty) {
      todasAsPartes.add('Aconteceu em ${locais.join(', ')}.');
    }
    for (final s in sentimentos) {
      todasAsPartes.add(s);
    }
    for (final o in outros) {
      todasAsPartes.add(o);
    }
    if (aprendizados.isNotEmpty) {
      todasAsPartes.add(aprendizados.join(' '));
    }

    if (todasAsPartes.isNotEmpty) {
      buffer.write(todasAsPartes.join(' '));
    }

    return buffer.toString().trim();
  }

  AnaliseLegado analisarLegado(
    String contexto,
    Map<String, String> respostas,
  ) {
    final todasAsRespostas =
        [contexto, ...respostas.values].join(' ').toLowerCase();

    final valores = <String>[];
    final aprendizados = <String>[];
    final caracteristicas = <String>[];

    final termosValores = {
      'honestidade': 'Honestidade', 'respeito': 'Respeito',
      'família': 'Família', 'familia': 'Família',
      'trabalho': 'Trabalho', 'amor': 'Amor',
      'fé': 'Fé', 'fe': 'Fé',
      'perseverança': 'Perseverança', 'perseveranca': 'Perseverança',
      'humildade': 'Humildade', 'generosidade': 'Generosidade',
      'coragem': 'Coragem', 'sabedoria': 'Sabedoria',
      'gratidão': 'Gratidão', 'gratidao': 'Gratidão',
      'união': 'União', 'uniao': 'União',
      'dedicação': 'Dedicação', 'dedicacao': 'Dedicação',
    };

    final encontrados = <String>{};
    for (final entry in termosValores.entries) {
      if (todasAsRespostas.contains(entry.key)) {
        if (encontrados.add(entry.value)) valores.add(entry.value);
        if (valores.length >= 4) break;
      }
    }

    final regexAprendizado = RegExp(r'(?:aprendi|ensinou|entendi|descobri|compreendi)\s[^.!?]+');
    for (final m in regexAprendizado.allMatches(todasAsRespostas).take(3)) {
      final frase = m.group(0)!.trim();
      if (frase.length > 10 && frase.length < 120) {
        aprendizados.add('${frase[0].toUpperCase()}${frase.substring(1)}');
      }
    }

    final termosCaracteristicas = {
      'forte': 'Forte', 'corajos': 'Corajoso(a)', 'gentil': 'Gentil',
      'sábio': 'Sábio(a)', 'sabio': 'Sábio(a)', 'alegre': 'Alegre',
      'determinad': 'Determinado(a)', 'generos': 'Generoso(a)',
      'cuidados': 'Cuidadoso(a)', 'inteligente': 'Inteligente',
      'trabalhador': 'Trabalhador(a)', 'honesto': 'Honesto(a)',
      'batalhador': 'Batalhador(a)', 'guerreir': 'Guerreiro(a)',
      'amoroso': 'Amoroso(a)', 'carinhoso': 'Carinhoso(a)',
      'divertid': 'Divertido(a)', 'engraçad': 'Engraçado(a)',
      'engracad': 'Engraçado(a)', 'simples': 'Simples', 'humilde': 'Humilde',
    };

    final encontradosC = <String>{};
    for (final entry in termosCaracteristicas.entries) {
      if (todasAsRespostas.contains(entry.key)) {
        if (encontradosC.add(entry.value)) caracteristicas.add(entry.value);
        if (caracteristicas.length >= 4) break;
      }
    }

    return AnaliseLegado(
      valores: valores,
      aprendizados: aprendizados,
      caracteristicas: caracteristicas,
    );
  }
}
