import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../curador/perguntas.dart';

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
