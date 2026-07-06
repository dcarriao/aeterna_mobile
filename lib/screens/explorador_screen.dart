import 'package:flutter/material.dart';

import '../models/memoria.dart';
import '../services/memory_relationship_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_card.dart';
import 'conexoes_descobertas_screen.dart';
import 'memoria_detalhe_screen.dart';

class ExploradorScreen extends StatefulWidget {
  const ExploradorScreen({super.key});

  @override
  State<ExploradorScreen> createState() => _ExploradorScreenState();
}

class _ExploradorScreenState extends State<ExploradorScreen> {
  List<Memoria> _memorias = [];
  bool _carregando = true;
  String? _categoriaSelecionada;
  int _conexoesPendentes = 0;
  bool _carregandoConexoes = true;

  static const _categorias = [
    'momentos',
    'familia',
    'aprendizados',
    'viagens',
    'tradicoes',
  ];

  static const _rotuloCategoria = {
    'momentos': 'Momentos',
    'familia': 'Família',
    'aprendizados': 'Aprendizados',
    'viagens': 'Viagens',
    'tradicoes': 'Tradições',
  };

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final memorias = await SupabaseService.instance.listarMemorias();
    if (mounted) setState(() { _memorias = memorias; _carregando = false; });
    _carregarConexoes();
  }

  Future<void> _carregarConexoes() async {
    try {
      final pendentes =
          await MemoryRelationshipService.instance.listarPendentesDoUsuario();
      if (mounted) {
        setState(() {
          _conexoesPendentes = pendentes.length;
          _carregandoConexoes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregandoConexoes = false);
    }
  }

  List<Memoria> get _memoriasFiltradas {
    if (_categoriaSelecionada == null) return _memorias;
    return _memorias
        .where((m) => m.categoria == _categoriaSelecionada)
        .toList();
  }

  String? get _categoriaMaisComum {
    if (_memorias.isEmpty) return null;
    final contagem = <String, int>{};
    for (final m in _memorias) {
      contagem[m.categoria] = (contagem[m.categoria] ?? 0) + 1;
    }
    return contagem.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String get _sugestao {
    final cat = _categoriaMaisComum;
    if (cat != null && cat != 'momentos') {
      return 'Que tal revisitar as histórias sobre ${_rotuloCategoria[cat]?.toLowerCase() ?? cat}?';
    }
    if (_memorias.length >= 3) {
      return 'Navegue pelas suas histórias e redescubra momentos especiais.';
    }
    if (_memorias.isNotEmpty) {
      return 'Explore as histórias que você já registrou.';
    }
    return 'Comece registrando memórias para explorá-las aqui.';
  }

  IconData _iconeCategoria(String cat) => switch (cat) {
        'familia' => Icons.people_outline,
        'aprendizados' => Icons.auto_stories_outlined,
        'viagens' => Icons.flight_outlined,
        'tradicoes' => Icons.redeem_outlined,
        _ => Icons.explore_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final filtradas = _memoriasFiltradas;
    final selecionando = _categoriaSelecionada != null;

    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Explorador'),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _memorias.isEmpty
                ? _EstadoVazio()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    children: [
                      // Sugestão
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEDE8DC)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline,
                                color: AppColors.dourado, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _sugestao,
                                style: const TextStyle(
                                  color: AppColors.roxo,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Categorias
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 10),
                        child: Text(
                          'Explorar por categoria',
                          style: TextStyle(
                            color: AppColors.roxo,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _categorias.map((cat) {
                            final count = _memorias
                                .where((m) => m.categoria == cat)
                                .length;
                            final selecionada = _categoriaSelecionada == cat;
                            return Padding(
                              padding:
                                  const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(
                                  '${_rotuloCategoria[cat]} ($count)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selecionada
                                        ? Colors.white
                                        : AppColors.roxo,
                                  ),
                                ),
                                avatar: Icon(
                                  _iconeCategoria(cat),
                                  size: 16,
                                  color: selecionada
                                      ? Colors.white
                                      : AppColors.dourado,
                                ),
                                selected: selecionada,
                                onSelected: (val) {
                                  setState(() =>
                                      _categoriaSelecionada =
                                          val ? cat : null);
                                },
                                selectedColor: AppColors.roxo,
                                backgroundColor: Colors.white,
                                checkmarkColor: Colors.white,
                                side: BorderSide(
                                  color: selecionada
                                      ? AppColors.roxo
                                      : const Color(0xFFEDE8DC),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Conexões (só quando sem filtro)
                      if (!selecionando &&
                          !_carregandoConexoes &&
                          _conexoesPendentes > 0) ...[
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _abrirConexoes(),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFEDE8DC)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF0E0),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.link_outlined,
                                    color: AppColors.dourado,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Conexões entre histórias',
                                        style: TextStyle(
                                          color: AppColors.roxo,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$_conexoesPendentes conexões para explorar',
                                        style: const TextStyle(
                                          color: Color(0xFF7A7280),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: Color(0xFFB0A8B8)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Título da lista
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          selecionando
                              ? '${_rotuloCategoria[_categoriaSelecionada]} (${filtradas.length})'
                              : 'Todas as histórias (${_memorias.length})',
                          style: const TextStyle(
                            color: AppColors.roxo,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                      // Lista
                      ...filtradas.map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: MemoryCard(
                              memoria: m,
                              onLer: () => _abrirDetalhe(m),
                            ),
                          )),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _abrirDetalhe(Memoria m) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoriaDetalheScreen(
          memoria: m,
          memoriasConhecidas: _memorias,
          onAbrirMemoria: (mem) => _abrirDetalhe(mem),
        ),
      ),
    );
  }

  void _abrirConexoes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConexoesDescobertasScreen(
          memorias: _memorias,
          onAbrirMemoria: (mem) => _abrirDetalhe(mem),
        ),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.explore_outlined, size: 58,
              color: Color(0xFFB0A8B8)),
          const SizedBox(height: 20),
          const Text(
            'Nada para explorar ainda',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Registre memórias para explorá-las aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF7A7280), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
