import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../curador/perguntas.dart';
import '../models/curador_resposta_ia.dart';
import '../models/curador_sessao.dart' show CuradorMensagemTipo;

class LegacyCuratorService {
  LegacyCuratorService._();

  static final instance = LegacyCuratorService._();

  static const _apiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const _model =
      String.fromEnvironment('OPENAI_MODEL', defaultValue: 'gpt-4o-mini');

  bool get isConfigured => _apiKey.isNotEmpty;

  static const _baseUrl = 'https://api.openai.com/v1/chat/completions';

  static Future<void> initialize() async {
    if (!instance.isConfigured) return;
    debugPrint('LegacyCuratorService: configurado (model: $_model)');
  }

  Future<List<String>?> gerarPerguntasContextuais({
    required String tipo,
    required String data,
    required String hora,
    required int quantidadeFotos,
    required int quantidadeVideos,
  }) async {
    if (!isConfigured) return null;

    final buffer = StringBuffer();
    buffer.writeln('Você é a Curadora de Memórias da aEterna.');
    buffer.writeln('Seu papel é conduzir um diálogo caloroso e poético para registrar a história por trás de mídias recém-carregadas da galeria do usuário.');
    buffer.writeln('Dados do momento selecionado pelo usuário:');
    buffer.writeln('- Tipo principal de mídia: $tipo');
    buffer.writeln('- Data de registro: $data');
    buffer.writeln('- Horário aproximado: $hora');
    buffer.writeln('- Quantidade de fotos: $quantidadeFotos');
    buffer.writeln('- Quantidade de vídeos: $quantidadeVideos');
    buffer.writeln();
    buffer.writeln(
      'Gere de 3 a 4 perguntas curtas, acolhedoras e de profunda conexão emocional para que o usuário reviva esse instante concreto. '
      'Sua primeira pergunta DEVE ser obrigatoriamente: "O que estava acontecendo?" '
      'As próximas perguntas devem guiar o usuário de forma sutil (ex: "Quem estava com você?", "O que tornou esse momento especial?", ou sobre algum detalhe que uma foto não mostraria). '
      'Responda estritamente apenas com as perguntas, uma por linha, sem numeração, marcadores ou preâmbulos.'
    );

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'system',
                  'content': _systemPrompt,
                },
                {
                  'role': 'user',
                  'content': buffer.toString(),
                },
              ],
              'temperature': 0.7,
              'max_tokens': 300,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final dataJson = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = dataJson['choices'] as List<dynamic>;
      if (choices.isEmpty) return null;

      final texto = choices[0]['message']['content'] as String;
      final perguntas = texto
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '').trim())
          .where((l) => l.length > 5)
          .take(4)
          .toList();

      return perguntas.isNotEmpty ? perguntas : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>?> gerarPerguntas(
    String contextoOriginal,
    String titulo,
    List<Map<String, String>> pessoas, {
    DateTime? dataMemoria,
    String? categoria,
  }) async {
    if (!isConfigured) return null;

    final buffer = StringBuffer();
    buffer.writeln('Título: "$titulo"');
    buffer.writeln();
    buffer.writeln('Memória inicial:');
    buffer.writeln(contextoOriginal);
    buffer.writeln();

    if (categoria != null) {
      buffer.writeln('Categoria selecionada pelo usuário: $categoria');
    }

    if (dataMemoria != null) {
      final dataStr = '${dataMemoria.day.toString().padLeft(2, '0')}/${dataMemoria.month.toString().padLeft(2, '0')}/${dataMemoria.year}';
      buffer.writeln('Data do evento já cadastrada: $dataStr');
      buffer.writeln('RECO: NUNCA pergunte quando isso aconteceu ou a data do evento.');
    }

    if (pessoas.isNotEmpty) {
      buffer.writeln('Participantes já cadastrados:');
      for (final p in pessoas) {
        buffer.writeln('- ${p["nome"]} (${p["parentesco"]})');
      }
      buffer.writeln();
      buffer.writeln('RECO: NUNCA pergunte quem participou, quem estava presente ou os nomes dessas pessoas.');
    }

    buffer.writeln(
      'Gere de 3 a 5 perguntas curtas, profundas e extremamente contextualizadas '
      'com os fatos fornecidos na memória inicial. '
      'Seja um entrevistador sensível: foque em sentimentos, conversas que marcaram, '
      'detalhes sensoriais (cheiro, clima, risadas) ou lições/conselhos deixados. '
      'NUNCA pergunte o que já foi fornecido acima (data, local se houver, ou participantes). '
      'Responda apenas com as perguntas, uma por linha, sem numeração ou marcadores.',
    );

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'system',
                  'content': _systemPrompt,
                },
                {
                  'role': 'user',
                  'content': buffer.toString(),
                },
              ],
              'temperature': 0.7,
              'max_tokens': 400,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) return null;

      final texto = choices[0]['message']['content'] as String;
      final perguntas = texto
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '').trim())
          .where((l) => l.length > 10)
          .take(5)
          .toList();

      return perguntas.isNotEmpty ? perguntas : null;
    } catch (_) {
      return null;
    }
  }

  Future<AnaliseLegado?> analisarLegado(
    String contextoOriginal,
    Map<String, String> respostas,
  ) async {
    if (!isConfigured || respostas.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.writeln('Memória original:');
    buffer.writeln(contextoOriginal);
    buffer.writeln();

    buffer.writeln('Respostas do autor:');
    for (final entry in respostas.entries) {
      buffer.writeln('P: ${entry.key}');
      buffer.writeln('R: ${entry.value}');
      buffer.writeln();
    }

    buffer.writeln(
      'Analise as respostas e identifique: valores, aprendizados, conselhos '
      'e características da pessoa mencionada. '
      'Responda em JSON com este formato exato: '
      '{"valores":["valor1","valor2"],"aprendizados":["aprendizado1"],'
      '"caracteristicas":["trait1","trait2"]}. '
      'Máximo 4 itens por categoria.',
    );

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'system',
                  'content': _systemPrompt,
                },
                {
                  'role': 'user',
                  'content': buffer.toString(),
                },
              ],
              'temperature': 0.3,
              'max_tokens': 300,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) return null;

      final texto = choices[0]['message']['content'] as String;
      final json = jsonDecode(texto) as Map<String, dynamic>;

      return AnaliseLegado(
        valores: _parseToStringList(json['valores']),
        aprendizados: _parseToStringList(json['aprendizados']),
        caracteristicas: _parseToStringList(json['caracteristicas']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> gerarNarrativa(
    String contextoOriginal,
    String titulo,
    Map<String, String> respostas,
  ) async {
    if (!isConfigured || respostas.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.writeln('Título: $titulo');
    buffer.writeln();
    buffer.writeln('Memória original:');
    buffer.writeln(contextoOriginal);
    buffer.writeln();

    for (final entry in respostas.entries) {
      buffer.writeln('Pergunta: ${entry.key}');
      buffer.writeln('Resposta: ${entry.value}');
      buffer.writeln();
    }

    buffer.writeln(
      'Transforme as informações acima em um texto narrativo contínuo, '
      'em português, usando linguagem natural. '
      'Organize em parágrafos fluidos. '
      'NUNCA invente nomes, locais, sentimentos ou acontecimentos que não '
      'estejam nas respostas. '
      'Se uma informação não existir, simplesmente não a mencione. '
      'Não use listas. Não repita informações. '
      'O texto deve parecer uma lembrança contada por uma pessoa real.',
    );

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Você é um narrador de memórias familiares. '
                      'Seu objetivo é transformar perguntas e respostas em '
                      'um texto narrativo contínuo e natural. '
                      'Nunca invente informações. '
                      'Seja fiel ao que foi dito.',
                },
                {
                  'role': 'user',
                  'content': buffer.toString(),
                },
              ],
              'temperature': 0.5,
              'max_tokens': 600,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) return null;

      return choices[0]['message']['content'] as String;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>?> analisarMidia({
    required Uint8List bytes,
    required String nomeArquivo,
    required bool isVideo,
  }) async {
    if (!isConfigured) return null;

    try {
      final String systemMessage =
          'Você é a assistente de Inteligência de Mídia da aEterna. '
          'Seu papel é analisar uma foto ou metadados de vídeo e sugerir metadados para uma nova memória. '
          'Responda estritamente em formato JSON com chaves: '
          '{"titulo": "título curto e poético", "descricao": "descrição curta de 1-2 parágrafos", "categoria": "categoria ideal (momentos, familia, viagens, aprendizados, tradicoes)"}';

      dynamic contentPayload;

      if (isVideo) {
        contentPayload = 'Analise o nome deste arquivo de vídeo familiar: "$nomeArquivo". '
            'Sugira um título poético, descrição acolhedora de 1 parágrafo e a melhor categoria '
            '("momentos", "familia", "viagens", "aprendizados" ou "tradicoes") baseados nesse contexto.';
      } else {
        final base64Image = base64Encode(bytes);
        contentPayload = [
          {
            'type': 'text',
            'text':
                'Analise esta foto de família e sugira: 1. Um título curto, caloroso e poético. '
                '2. Uma descrição inicial de 1 a 2 parágrafos sobre a cena (seja natural, evite termos técnicos, foque na emoção). '
                '3. A melhor categoria entre: momentos, familia, viagens, aprendizados, tradicoes.'
          },
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$base64Image',
            }
          }
        ];
      }

      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'system',
                  'content': systemMessage,
                },
                {
                  'role': 'user',
                  'content': contentPayload,
                },
              ],
              'temperature': 0.5,
              'max_tokens': 400,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) return null;

      final textResult = choices[0]['message']['content'] as String;
      final json = jsonDecode(textResult) as Map<String, dynamic>;

      return {
        'titulo': (json['titulo'] as String?) ?? 'Momento especial',
        'descricao': (json['descricao'] as String?) ?? '',
        'categoria': (json['categoria'] as String?) ?? 'momentos',
      };
    } catch (_) {
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // SPRINT J — CURADOR CONTEXTUAL: próxima pergunta adaptativa
  // ════════════════════════════════════════════════════════════════════════
  //
  // Diferente dos métodos anteriores (`gerarPerguntas`/`gerarPerguntas
  // Contextuais`) que geram um LOTE de perguntas fixas de uma só vez,
  // este método recebe o HISTÓRICO COMPLETO da conversa e devolve
  // APENAS a PRÓXIMA pergunta, totalmente contextualizada.
  //
  // Características:
  //   - Lê todas as mensagens anteriores e lembra do que o usuário já
  //     disse (pessoas, lugares, datas, sentimentos).
  //   - Adapta a próxima pergunta em função da última resposta.
  //   - Pode sinalizar finalização quando entender que já tem material
  //     suficiente.
  //   - 1 chamada da OpenAI por turno (decidido com o usuário).
  //   - Modelo: gpt-4o-mini (default `_model`).
  //
  // Retorna um `CuradorRespostaIA` com a pergunta sugerida + flag
  // `deveEncerrar` (caso a IA sinalize "já temos material suficiente").
  Future<CuradorRespostaIA?> proximaPerguntaAdaptativa({
    required String contextoInicial,
    String? titulo,
    DateTime? dataMemoria,
    String? categoria,
    List<Map<String, String>> pessoas = const [],
    required List<CuradorMensagemDTO> historico,
  }) async {
    if (!isConfigured) return null;

    // Monta o prompt de sistema REESCRITO para o modo contextual.
    // Diferente do `_systemPrompt` original, este é explícito sobre:
    //   - não repetir perguntas
    //   - usar histórico
    //   - quando encerrar
    const sysPrompt =
        'Você é a Curadora de Memórias da aEterna. '
        'Seu papel é conduzir uma conversa gentil e calorosa para preservar '
        'uma história de família. '
        'Você NÃO é psicóloga, terapeuta, coach ou chatbot corporativo. '
        'Você é como uma pessoa da família que genuinamente se importa em '
        'preservar o que o usuário viveu. '
        '\n\n'
        'REGRAS OBRIGATÓRIAS (quebre qualquer outra para obedecê-las): '
        '1. NUNCA repita uma pergunta já feita — leia todo o histórico antes '
        'de perguntar. '
        '2. NUNCA pergunte algo que o usuário já disse explicitamente '
        '(pessoas presentes, local, data, etc.). '
        '3. Use o histórico para aprofundar a conversa de forma natural — '
        'pergunte sobre o que ele disse, não sobre o que você acha '
        'relevante. '
        '4. Mantenha a conversa curta (3-8 minutos no total) — após '
        'aproximadamente 4-6 perguntas substanciais, considere encerrar. '
        '5. Quando achar que tem material suficiente, pergunte '
        'explicitamente: "Acho que já conseguimos preservar muito bem essa '
        'lembrança. Gostaria de acrescentar mais algum detalhe?" '
        '6. Suas perguntas devem ser curtas (uma linha), acolhedoras e '
        'nunca prolixas. '
        '7. Respeite o limite: objetivo 3-8 minutos total, então NUNCA '
        'gere mais do que 8 perguntas. '
        '8. Quando o usuário disser "não" à pergunta de encerramento, OU '
        'disser tchau/adeus/termina/encerrar/ok/pronto/fim, '
        'finalize com UMA despedida gentil (1 linha) e ENCERRAR: sim. '
        'NUNCA continue a conversa só com despedidas — isso é loop. '
        '\n\n'
        'FORMATO DE RESPOSTA (responda EXATAMENTE assim, nada mais): '
        'PERGUNTA: <sua próxima pergunta aqui> '
        'ENCERRAR: <sim/não> '
        '\n\n'
        'Exemplo: '
        'PERGUNTA: Esse lugar tinha algum cheiro ou som que ficou na sua memória? '
        'ENCERRAR: não ';

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sysPrompt},
    ];

    // Mensagem de sistema adicional com metadados estruturados.
    final meta = StringBuffer();
    if (titulo != null && titulo.isNotEmpty) {
      meta.writeln('Título: "$titulo"');
    }
    meta.writeln('Memória inicial:');
    meta.writeln(contextoInicial);
    meta.writeln();
    if (categoria != null) {
      meta.writeln('Categoria: $categoria');
    }
    if (dataMemoria != null) {
      final dataStr = '${dataMemoria.day.toString().padLeft(2, '0')}/${dataMemoria.month.toString().padLeft(2, '0')}/${dataMemoria.year}';
      meta.writeln('Data já cadastrada: $dataStr');
      meta.writeln('RECO: NUNCA pergunte a data do evento.');
    }
    if (pessoas.isNotEmpty) {
      meta.writeln('Pessoas já cadastradas:');
      for (final p in pessoas) {
        meta.writeln('- ${p["nome"]} (${p["parentesco"]})');
      }
      meta.writeln('RECO: NUNCA pergunte quem participou ou os nomes dessas pessoas.');
    }
    if (meta.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': meta.toString(),
      });
    }

    // Adiciona todo o histórico (filtrando mensagens do tipo
    // `finalizacao`/`fechamento` que são meta-instruções, não fala real).
    for (final m in historico) {
      // Mensagens de finalizacao/fechamento são UI-only, não devem
      // ser enviadas ao LLM.
      if (m.tipo == CuradorMensagemTipo.finalizacao.name ||
          m.tipo == CuradorMensagemTipo.fechamento.name) {
        continue;
      }
      messages.add({'role': m.role, 'content': m.conteudo});
    }

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': messages,
              'temperature': 0.7,
              'max_tokens': 200,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) return null;
      final texto = choices[0]['message']['content'] as String;

      // Parse do formato "PERGUNTA: ... \n ENCERRAR: sim/não"
      String pergunta = texto.trim();
      bool deveEncerrar = false;
      final encerrarMatch = RegExp(r'ENCERRAR:\s*(sim|não|nao)', caseSensitive: false).firstMatch(texto);
      if (encerrarMatch != null) {
        deveEncerrar = encerrarMatch.group(1)!.toLowerCase().startsWith('sim');
        // Remove o "ENCERRAR: ..." da pergunta
        pergunta = texto
            .replaceAll(RegExp(r'ENCERRAR:.*', caseSensitive: false), '')
            .replaceAll(RegExp(r'PERGUNTA:', caseSensitive: false), '')
            .trim();
      }
      // Limpa prefixos comuns
      pergunta = pergunta
          .replaceAll(RegExp(r'^\d+[\.\)]\s*'), '')
          .replaceAll(RegExp(r'^(PERGUNTA:|ENCERRAR:)\s*', caseSensitive: false), '')
          .trim();

      if (pergunta.isEmpty) return null;
      return CuradorRespostaIA(pergunta: pergunta, deveEncerrar: deveEncerrar);
    } catch (_) {
      return null;
    }
  }

  Future<String?> responderComoCurador({
    required String nome,
    required String parentesco,
    required String biografia,
    required List<String> memoriasEContribuicoes,
    required List<Map<String, String>> historicoConversa,
  }) async {
    if (!isConfigured) {
      return "Olá, sou o curador de memórias de $nome. (Chave OpenAI não configurada. Ative as chaves para conversar com a IA!)";
    }

    final buffer = StringBuffer();
    buffer.writeln('Você é o Curador de Memórias e Guardião do Legado de $nome ($parentesco).');
    buffer.writeln('Seu papel é conversar de forma acolhedora, sensível, empática e respeitosa com familiares, amigos ou visitantes.');
    buffer.writeln('Responda sempre na primeira pessoa do Curador ("Eu sou o curador de..."). Nunca finja ser a pessoa falecida diretamente, mas fale sobre ela com imenso carinho e profundo conhecimento de sua vida.');
    buffer.writeln();
    buffer.writeln('Biografia de $nome:');
    buffer.writeln(biografia);
    buffer.writeln();
    
    if (memoriasEContribuicoes.isNotEmpty) {
      buffer.writeln('Recordações e histórias compartilhadas sobre $nome:');
      for (final story in memoriasEContribuicoes) {
        buffer.writeln('- $story');
      }
      buffer.writeln();
    }
    
    buffer.writeln('REGRAS DE CONDUTA:');
    buffer.writeln('1. NUNCA invente fatos, datas ou relacionamentos que não constem na biografia, nas recordações fornecidas OU no histórico desta conversa.');
    buffer.writeln('2. Fatos que familiares já contaram nesta conversa (histórico) são recordações guardadas — use-os com confiança quando perguntarem de novo.');
    buffer.writeln('3. Caso lhe perguntem algo ainda não documentado nem falado na conversa, responda com sensibilidade: "Infelizmente não temos essa recordação guardada, mas adoraria ouvir se você tiver essa lembrança para registrar."');
    buffer.writeln('4. Mantenha as respostas curtas (máximo 2 parágrafos), calorosas e humanizadas.');

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': buffer.toString(),
      },
    ];

    for (final msg in historicoConversa) {
      messages.add({
        'role': msg['role']!,
        'content': msg['content']!,
      });
    }

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': messages,
              'temperature': 0.7,
              'max_tokens': 400,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return "Desculpe, tive um contratempo temporário para acessar a memória de $nome. Por favor, tente novamente.";
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) return null;

      return choices[0]['message']['content'] as String;
    } catch (e) {
      return "Ocorreu um erro de conexão com o curador: $e";
    }
  }

  List<String> _parseToStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  static const _systemPrompt =
      'Você é a Curadora de Memórias da aEterna. '
      'Seu papel é entrevistar o usuário sobre suas memórias mais valiosas '
      'para transformá-las em um legado escrito rico e poético. '
      'Sua postura é sensível, calorosa e compreensiva. '
      'Gere perguntas curtas, poéticas e de profunda conexão emocional. '
      'NUNCA aja como um assistente corporativo, chatbot ou robô. '
      'NUNCA responda perguntas, ensine ou comente. Apenas faça as perguntas. '
      'NUNCA pergunte coisas que o usuário já declarou explicitamente (como quem participou se os nomes já estão listados, ou quando aconteceu se a data já está definida). '
      'Foque em extrair sentimentos, detalhes sensoriais, conselhos repetidos, traços de personalidade e o significado profundo desse instante para as próximas gerações.';
}
