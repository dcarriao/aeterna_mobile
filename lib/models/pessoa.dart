import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Pessoa {
  Pessoa({
    required this.nome,
    required this.parentesco,
    this.apelido,
    this.dataNascimento,
    this.fotoBase64,
    DateTime? createdAt,
    int? id,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now();

  final int id;
  final String nome;
  final String? apelido;
  final String parentesco;
  final DateTime? dataNascimento;
  final String? fotoBase64;
  final DateTime createdAt;

  Uint8List? get fotoBytes =>
      fotoBase64 != null && fotoBase64!.isNotEmpty
          ? base64Decode(fotoBase64!)
          : null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'apelido': apelido,
      'parentesco': parentesco,
      'dataNascimento': dataNascimento?.toIso8601String(),
      'fotoBase64': fotoBase64,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Pessoa.fromMap(Map<String, dynamic> map) {
    return Pessoa(
      id: map['id'] as int?,
      nome: map['nome'] as String? ?? '',
      apelido: map['apelido'] as String?,
      parentesco: map['parentesco'] as String? ?? 'Outro',
      dataNascimento: map['dataNascimento'] != null
          ? DateTime.tryParse(map['dataNascimento'] as String)
          : null,
      fotoBase64: map['fotoBase64'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class PessoaRepository {
  PessoaRepository._();

  static const _pessoasKey = 'aeterna_pessoas';
  static const _vinculosKey = 'aeterna_vinculos';
  static const _compartilhadasKey = 'aeterna_compartilhadas';
  static const _datasMemoriasKey = 'aeterna_datas_memorias';

  static Future<List<Pessoa>> listar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pessoasKey);
    debugPrint('[PessoaRepository] listar: raw=${raw != null ? "${raw.length} chars" : "null"}');
    if (raw == null || raw.isEmpty) return [];

    final list = jsonDecode(raw) as List<dynamic>;
    debugPrint('[PessoaRepository] listar: ${list.length} pessoas carregadas');
    for (final item in list) {
      debugPrint('  -> ${(item as Map)['nome']} (${item['parentesco']})');
    }
    return list
        .map((item) => Pessoa.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> salvar(Pessoa pessoa) async {
    final pessoas = await listar();
    final index = pessoas.indexWhere((p) => p.id == pessoa.id);
    if (index >= 0) {
      pessoas[index] = pessoa;
    } else {
      pessoas.insert(0, pessoa);
    }
    await _persistir(pessoas);
  }

  static Future<void> remover(int pessoaId) async {
    final pessoas = await listar();
    pessoas.removeWhere((p) => p.id == pessoaId);
    await _persistir(pessoas);
  }

  static Future<void> _persistir(List<Pessoa> pessoas) async {
    final prefs = await SharedPreferences.getInstance();
    final list = pessoas.map((p) => p.toMap()).toList();
    await prefs.setString(_pessoasKey, jsonEncode(list));
  }

  static Future<Map<int, List<int>>> listarVinculos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_vinculosKey);
    if (raw == null || raw.isEmpty) return {};

    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map(
      (key, value) => MapEntry(
        int.parse(key),
        (value as List<dynamic>).cast<int>(),
      ),
    );
  }

  static Future<void> salvarVinculo(int memoriaId, List<int> pessoaIds) async {
    final vinculos = await listarVinculos();
    if (pessoaIds.isEmpty) {
      vinculos.remove(memoriaId);
    } else {
      vinculos[memoriaId] = pessoaIds;
    }
    final prefs = await SharedPreferences.getInstance();
    final map = vinculos.map((key, value) => MapEntry('$key', value));
    await prefs.setString(_vinculosKey, jsonEncode(map));
  }

  static Future<List<int>> obterPessoasDaMemoria(int? memoriaId) async {
    if (memoriaId == null) return [];
    final vinculos = await listarVinculos();
    return vinculos[memoriaId] ?? [];
  }

  static Future<Map<int, List<int>>> listarCompartilhamentos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_compartilhadasKey);
    if (raw == null || raw.isEmpty) return {};

    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map(
      (key, value) => MapEntry(
        int.parse(key),
        (value as List<dynamic>).cast<int>(),
      ),
    );
  }

  static Future<void> salvarDataMemoria(int memoriaId, DateTime data) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_datasMemoriasKey);
    final map = raw != null && raw.isNotEmpty
        ? jsonDecode(raw) as Map<String, dynamic>
        : <String, dynamic>{};
    map['$memoriaId'] = data.toIso8601String();
    await prefs.setString(_datasMemoriasKey, jsonEncode(map));
  }

  static Future<Map<int, DateTime>> carregarDatasMemorias() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_datasMemoriasKey);
    debugPrint('[PessoaRepository] carregarDatasMemorias: raw=${raw != null ? "${raw.length} chars" : "null"}');
    if (raw == null || raw.isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final result = <int, DateTime>{};
    for (final entry in map.entries) {
      final dt = DateTime.tryParse(entry.value as String);
      debugPrint('  -> memoria ${entry.key}: ${entry.value} -> $dt');
      if (dt != null) result[int.parse(entry.key)] = dt;
    }
    debugPrint('[PessoaRepository] carregarDatasMemorias: ${result.length} datas carregadas, sobreescrevendo ${result.values.map((d) => d.year)}');
    return result;
  }

  static Future<void> salvarCompartilhamento(
    int memoriaId,
    List<int> familiaresIds,
  ) async {
    final compartilhamentos = await listarCompartilhamentos();
    if (familiaresIds.isEmpty) {
      compartilhamentos.remove(memoriaId);
    } else {
      compartilhamentos[memoriaId] = familiaresIds;
    }
    final prefs = await SharedPreferences.getInstance();
    final map =
        compartilhamentos.map((key, value) => MapEntry('$key', value));
    await prefs.setString(_compartilhadasKey, jsonEncode(map));
  }

  static Future<List<int>> obterFamiliaresDaMemoria(int? memoriaId) async {
    if (memoriaId == null) return [];
    final compartilhamentos = await listarCompartilhamentos();
    return compartilhamentos[memoriaId] ?? [];
  }
}

const parentescos = [
  'Pai',
  'Mãe',
  'Avô',
  'Avó',
  'Bisavô',
  'Bisavó',
  'Irmão',
  'Irmã',
  'Filho',
  'Filha',
  'Tio',
  'Tia',
  'Primo',
  'Prima',
  'Amigo',
  'Outro',
];
