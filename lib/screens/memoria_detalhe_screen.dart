import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memoria.dart';
import '../models/pessoa.dart';
import '../theme/app_theme.dart';

class MemoriaDetalheScreen extends StatefulWidget {
  const MemoriaDetalheScreen({required this.memoria, super.key});

  final Memoria memoria;

  @override
  State<MemoriaDetalheScreen> createState() => _MemoriaDetalheScreenState();
}

class _MemoriaDetalheScreenState extends State<MemoriaDetalheScreen> {
  List<Pessoa> _familiares = [];

  @override
  void initState() {
    super.initState();
    _carregarFamiliares();
  }

  Future<void> _carregarFamiliares() async {
    if (!widget.memoria.isCompartilhada) return;

    final ids = widget.memoria.familiaresIds ??
        await PessoaRepository.obterFamiliaresDaMemoria(widget.memoria.id);

    if (ids.isEmpty) return;

    final todas = await PessoaRepository.listar();
    if (mounted) {
      setState(() {
        _familiares = todas.where((p) => ids.contains(p.id)).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final memoria = widget.memoria;

    return Scaffold(
      appBar: AppBar(title: const Text('Memória')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                if (memoria.foto != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.memory(memoria.foto!, fit: BoxFit.cover),
                    ),
                  )
                else if (memoria.fotoUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        memoria.fotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0EAF5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.roxo,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (memoria.foto != null || memoria.fotoUrl != null)
                  const SizedBox(height: 24),
                if (memoria.isCompartilhada) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x26D4A84F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.share_outlined,
                            size: 16, color: AppColors.dourado),
                        SizedBox(width: 6),
                        Text(
                          'Compartilhada',
                          style: TextStyle(
                            color: AppColors.dourado,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Text(
                  memoria.titulo,
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 15,
                      color: AppColors.dourado,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      DateFormat('dd/MM/yyyy').format(memoria.criadaEm),
                      style: const TextStyle(
                        color: Color(0xFF817987),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.label_outline,
                      size: 15,
                      color: AppColors.verdeApoio,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _categoriaLabel(memoria.categoria),
                      style: const TextStyle(
                        color: Color(0xFF817987),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  memoria.contexto,
                  style: const TextStyle(
                    color: Color(0xFF625B67),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
                if (_familiares.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Compartilhada com',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _familiares.map((f) {
                      return Chip(
                        avatar: CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFFF0EAF5),
                          backgroundImage: f.fotoBytes != null
                              ? MemoryImage(f.fotoBytes!)
                              : null,
                          child: f.fotoBytes == null
                              ? const Icon(Icons.person,
                                  size: 14, color: AppColors.roxo)
                              : null,
                        ),
                        label: Text(f.nome, style: const TextStyle(fontSize: 13)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _categoriaLabel(String categoria) {
    return switch (categoria) {
      'familia' => 'Família',
      'aprendizados' => 'Aprendizados',
      'viagens' => 'Viagens',
      'tradicoes' => 'Tradições',
      _ => 'Momentos',
    };
  }
}
