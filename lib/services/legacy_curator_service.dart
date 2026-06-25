import 'dart:convert';

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
    List<Map<String, String>> pessoas,
  ) async {
    if (!isConfigured) return null;

    final buffer = StringBuffer();
    buffer.writeln('Memória: "$titulo"');
    buffer.writeln();
    buffer.writeln('Conteúdo:');
    buffer.writeln(contextoOriginal);
    buffer.writeln();

    if (pessoas.isNotEmpty) {
      buffer.writeln('Pessoas mencionadas:');
      for (final p in pessoas) {
        buffer.writeln('- ${p["nome"]} (${p["parentesco"]})');
      }
      buffer.writeln();
    }

    buffer.writeln(
      'Gere 3 a 5 perguntas curtas e profundas para entrevistar o autor sobre '
      'esta memória. Foque em valores, aprendizados, traços de personalidade '
      'e impacto emocional das pessoas citadas. Não repita "quando aconteceu", '
      '"onde foi" ou "quem estava presente". Responda apenas com as perguntas, '
      'uma por linha, sem numeração.',
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

  List<String> _parseToStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  static const _systemPrompt =
      'Você é um Entrevistador de Legado Familiar. '
      'Seu objetivo é descobrir valores, aprendizados, traços de personalidade '
      'e impacto emocional das pessoas citadas nas memórias. '
      'Nunca aja como assistente genérico. '
      'Nunca responda dúvidas. '
      'Nunca ensine. '
      'Apenas entreviste. '
      'Faça perguntas curtas, profundas e específicas. '
      'Foque em quem a pessoa era, não apenas no que aconteceu.';
}
