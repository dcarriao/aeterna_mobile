import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memoria.dart';
import '../models/memoria_relacionamento.dart';
import '../services/memory_relationship_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Sprint K — Esqueleto do "Mapa da Vida" da pessoa.
///
/// Visão cronológica de TODAS as memórias do usuário, agrupadas por
/// ano, com um marcador visual (linha conectora + ícone) nas memórias
/// que têm relações confirmadas com outras.
///
/// É a base para iterações futuras (e.g., visualização em grafo,
/// agrupamento por fase, tags automáticas). Esta sprint entrega o
/// "retrato cronológico + relações visíveis".
class MapaVidaScreen extends StatefulWidget {
  const MapaVidaScreen({
    required this.memorias,
    required this.onAbrirMemoria,
    super.key,
  });

  final List<Memoria> memorias;
  final void Function(Memoria) onAbrirMemoria;

  @override
  State<MapaVidaScreen> createState() => _MapaVidaScreenState();
}

class _MapaVidaScreenState extends State<MapaVidaScreen> {
  Set<int> _idsComRelacionamento = const {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final todas = <int>{};
    for (final m in widget.memorias) {
      if (m.id == null) continue;
      final rels = await MemoryRelationshipService.instance
          .listarRelacionamentosConfirmados(m.id!);
      for (final r in rels) {
        todas.add(r.memoriaOrigemId);
        todas.add(r.memoriaDestinoId);
      }
    }
    if (mounted) {
      setState(() {
        _idsComRelacionamento = todas;
        _carregando = false;
      });
    }
  }

  String _formatarMes(DateTime data) {
    const meses = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    return '${meses[data.month - 1]} ${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    final memorias = List<Memoria>.from(widget.memorias);
    memorias.sort((a, b) {
      final ad = a.dataMemoria ?? a.criadaEm;
      final bd = b.dataMemoria ?? b.criadaEm;
      return ad.compareTo(bd);
    });
    final grupos = <int, List<Memoria>>{};
    for (final m in memorias) {
      final d = m.dataMemoria ?? m.criadaEm;
      grupos.putIfAbsent(d.year, () => []).add(m);
    }
    final anos = grupos.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Mapa da Vida',
            style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: AppColors.roxo))
                : memorias.isEmpty
                    ? _vazio()
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                          itemCount: anos.length,
                          itemBuilder: (context, i) {
                            final ano = anos[i];
                            return _buildSecaoAno(ano, grupos[ano]!);
                          },
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _vazio() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline, size: 56, color: AppColors.dourado),
          SizedBox(height: 16),
          Text(
            'O Mapa da Vida começa com a primeira memória.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Crie memórias na Home e elas aparecerão aqui em ordem cronológica, com as conexões entre elas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF7A7280),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoAno(int ano, List<Memoria> memorias) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x1AD4A84F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$ano',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.dourado,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 1,
                  color: const Color(0x33D4A84F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...memorias.map((m) => _buildItem(m)),
        ],
      ),
    );
  }

  Widget _buildItem(Memoria m) {
    final d = m.dataMemoria ?? m.criadaEm;
    final temRel = m.id != null && _idsComRelacionamento.contains(m.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => widget.onAbrirMemoria(m),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: temRel
                    ? AppColors.dourado.withValues(alpha: 0.5)
                    : AppColors.borda,
                width: temRel ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: temRel ? AppColors.dourado : AppColors.roxo,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.titulo,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatarMes(d),
                        style: const TextStyle(
                          color: Color(0xFF7A7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (temRel)
                  const Icon(Icons.timeline, size: 16, color: AppColors.dourado),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: Color(0xFF9B949D), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
