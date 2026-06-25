enum CategoriaPergunta { factual, emocional, legado }

class PerguntaCurador {
  const PerguntaCurador({
    required this.texto,
    required this.categoria,
  });

  final String texto;
  final CategoriaPergunta categoria;
}

const _factuais = [
  PerguntaCurador(
    texto: 'Quando isso aconteceu?',
    categoria: CategoriaPergunta.factual,
  ),
  PerguntaCurador(
    texto: 'Onde aconteceu?',
    categoria: CategoriaPergunta.factual,
  ),
  PerguntaCurador(
    texto: 'Quem estava presente nesse momento?',
    categoria: CategoriaPergunta.factual,
  ),
];

const _emocionais = [
  PerguntaCurador(
    texto: 'Como você se sentiu nesse momento?',
    categoria: CategoriaPergunta.emocional,
  ),
  PerguntaCurador(
    texto: 'O que mais marcou você nessa experiência?',
    categoria: CategoriaPergunta.emocional,
  ),
  PerguntaCurador(
    texto: 'Se você pudesse guardar apenas uma lembrança desta história, qual seria?',
    categoria: CategoriaPergunta.emocional,
  ),
];

const _legado = [
  PerguntaCurador(
    texto: 'O que essa história revela sobre essa pessoa?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'Qual característica marcante ela tinha?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'O que você mais admirava nela?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'Existe algum conselho que ela repetia?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'O que você aprendeu com essa pessoa?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'Qual valor ela transmitiu para sua família?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'O que você gostaria que seus filhos soubessem sobre ela?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'O que dessa pessoa continua vivo em você?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'Existe alguma frase que você nunca esqueceu dela?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'Como essa pessoa influenciou sua vida?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'O que tornava essa pessoa especial?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'Como ela gostaria de ser lembrada?',
    categoria: CategoriaPergunta.legado,
  ),
  PerguntaCurador(
    texto: 'Qual foi o maior aprendizado que esta experiência deixou para sua vida?',
    categoria: CategoriaPergunta.legado,
  ),
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

  List<PerguntaCurador> selecionar(String contexto) {
    final texto = contexto.trim().toLowerCase();
    final palavras = texto.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final tamanho = palavras.length;

    final temPessoas = texto.contains(RegExp(
      r'\b(pai|m[aã]e|av[oô]|av[óo]|bisav[oô]|bisav[óo]|'
      r'tio|tia|irm[aã]o|irm[aã]|filho|filha|amigo|amiga)\b',
    ));
    final temAprendizado = texto.contains(RegExp(
      r'\b(aprendi|ensinou|conselho|li[cç][aã]o|exemplo|inspir[aã][cç][aã]o)\b',
    ));
    final temEmocao = texto.contains(RegExp(
      r'\b(saudade|amor|feliz|triste|orgulho|medo|alegria|gratid[aã]o)\b',
    ));

    final selecionadas = <PerguntaCurador>[];
    final curto = tamanho < 25;

    // REGRA OBRIGATÓRIA: sempre 1 pergunta de legado
    selecionadas.add(_legado[0]);

    if (curto) {
      selecionadas.addAll([
        _factuais[1], // Onde?
        _factuais[2], // Quem?
      ]);
    } else {
      selecionadas.add(_factuais[0]); // Quando?
    }

    if (temPessoas) {
      selecionadas.addAll([
        _legado[1], // Característica marcante
        _legado[4], // O que aprendeu com essa pessoa
        _legado[7], // O que continua vivo
      ]);
    }

    if (temAprendizado) {
      selecionadas.addAll([
        _legado[12], // Maior aprendizado
        _legado[5],  // Valor transmitido
      ]);
    }

    if (temEmocao) {
      selecionadas.addAll([
        _emocionais[0], // Como se sentiu
        _emocionais[1], // O que marcou
      ]);
      if (temPessoas) {
        selecionadas.add(_legado[10]); // O que tornava especial
      }
    }

    if (!temEmocao && !curto) {
      selecionadas.add(_emocionais[1]); // O que marcou
    }

    if (!temAprendizado) {
      selecionadas.add(_legado[12]); // Maior aprendizado
    }

    // Pergunta do momento mais importante
    if (!curto) {
      selecionadas.add(_emocionais[2]);
    }

    final unicas = <PerguntaCurador>[];
    final textos = <String>{};
    for (final p in selecionadas) {
      if (textos.add(p.texto)) {
        unicas.add(p);
      }
    }

    if (unicas.length < 5) {
      for (final p in [..._legado, ..._emocionais, ..._factuais]) {
        if (textos.add(p.texto)) {
          unicas.add(p);
        }
        if (unicas.length >= 6) break;
      }
    }

    if (unicas.length > 7) {
      return unicas.sublist(0, 7);
    }

    return unicas;
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

    // Detectar valores
    final termosValores = {
      'honestidade': 'Honestidade',
      'respeito': 'Respeito',
      'família': 'Família',
      'familia': 'Família',
      'trabalho': 'Trabalho',
      'amor': 'Amor',
      'fé': 'Fé',
      'fe': 'Fé',
      'perseverança': 'Perseverança',
      'perseveranca': 'Perseverança',
      'humildade': 'Humildade',
      'generosidade': 'Generosidade',
      'coragem': 'Coragem',
      'sabedoria': 'Sabedoria',
      'gratidão': 'Gratidão',
      'gratidao': 'Gratidão',
      'união': 'União',
      'uniao': 'União',
      'dedicação': 'Dedicação',
      'dedicacao': 'Dedicação',
      'fé em': 'Fé',
    };

    final encontrados = <String>{};
    for (final entry in termosValores.entries) {
      if (todasAsRespostas.contains(entry.key)) {
        if (encontrados.add(entry.value)) {
          valores.add(entry.value);
        }
        if (valores.length >= 4) break;
      }
    }

    // Detectar aprendizados
    final regexAprendizado = RegExp(
      r'(?:aprendi|ensinou|entendi|descobri|compreendi)\s[^.!?]+',
    );
    final matches = regexAprendizado.allMatches(todasAsRespostas);
    for (final m in matches.take(3)) {
      final frase = m.group(0)!.trim();
      final capitalizada =
          '${frase[0].toUpperCase()}${frase.substring(1)}';
      if (frase.length > 10 && frase.length < 120) {
        aprendizados.add(capitalizada);
      }
    }

    // Detectar características
    final termosCaracteristicas = {
      'forte': 'Forte',
      'corajos': 'Corajoso(a)',
      'gentil': 'Gentil',
      'sábio': 'Sábio(a)',
      'sabio': 'Sábio(a)',
      'alegre': 'Alegre',
      'determinad': 'Determinado(a)',
      'generos': 'Generoso(a)',
      'cuidados': 'Cuidadoso(a)',
      'inteligente': 'Inteligente',
      'trabalhador': 'Trabalhador(a)',
      'honesto': 'Honesto(a)',
      'batalhador': 'Batalhador(a)',
      'guerreir': 'Guerreiro(a)',
      'amoroso': 'Amoroso(a)',
      'carinhoso': 'Carinhoso(a)',
      'divertid': 'Divertido(a)',
      'engraçad': 'Engraçado(a)',
      'engracad': 'Engraçado(a)',
      'simples': 'Simples',
      'humilde': 'Humilde',
    };

    final encontradosC = <String>{};
    for (final entry in termosCaracteristicas.entries) {
      if (todasAsRespostas.contains(entry.key)) {
        if (encontradosC.add(entry.value)) {
          caracteristicas.add(entry.value);
        }
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
