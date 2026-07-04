import 'package:flutter/material.dart';

import '../models/memoria.dart';
import '../models/memoria_relacionamento.dart';
import '../services/memory_relationship_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'mapa_vida_screen.dart';

/// Sprint K — Tela "Conexões descobertas".
/// Lista todas as relações PENDENTES do usuário, permitindo confirmar
/// ou ignorar. Após qualquer ação, faz `pop(true)` para que a Home
/// recarregue.
class ConexoesDescobertasScreen extends StatefulWidget {
  const ConexoesDescobertasScreen({this.memorias = const [], this.onAbrirMemoria, super.key});

  final List<Memoria> memorias;
  final void Function(Memoria)? onAbrirMemoria;

  @override
  State<ConexoesDescobertasScreen> createState() =>
      _ConexoesDescobertasScreenState();
}

class _ConexoesDescobertasScreenState extends State<ConexoesDescobertasScreen> {
  List<MemoriaRelacionamento> _pendentes = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final lista = await MemoryRelationshipService.instance
        .listarPendentesDoUsuario(limite: 50);
    if (mounted) {
      setState(() {
        _pendentes = lista;
        _carregando = false;
      });
    }
  }

  Future<void> _confirmar(int id) async {
    await MemoryRelationshipService.instance.confirmar(id);
    await _carregar();
  }

  Future<void> _ignorar(int id) async {
    await MemoryRelationshipService.instance.ignorar(id);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Conexões descobertas',
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
                : _pendentes.isEmpty
                    ? _vazio()
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                          itemCount: _pendentes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (_, i) =>
                              _buildCardConexao(_pendentes[i]),
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _vazio() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timeline_outlined, size: 56, color: AppColors.dourado),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma conexão pendente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quando você criar novas memórias, o Curador vai sugerir conexões automaticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF7A7280),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _abrirMapaVida(context),
            style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
            icon: const Icon(Icons.timeline, size: 18),
            label: const Text('Ver Mapa da Vida'),
          ),
        ],
      ),
    );
  }

  void _abrirMapaVida(BuildContext context) {
    if (widget.memorias.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => MapaVidaScreen(
        memorias: widget.memorias,
        onAbrirMemoria: widget.onAbrirMemoria ??
            (m) {
              Navigator.of(context).pop();
            },
      ),
    ));
  }

  Widget _buildCardConexao(MemoriaRelacionamento r) {
    final legendas = r.motivos.legendasHumanas;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.dourado.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_outlined, color: AppColors.dourado, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conexão ${r.score}%',
                  style: const TextStyle(
                    color: AppColors.dourado,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '"${r.tituloOrigem ?? 'Memória 1'}"',
            style: const TextStyle(
              color: AppColors.roxo,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.arrow_downward, size: 16, color: Color(0xFF7A7280)),
              const SizedBox(width: 4),
              const Text('faz parte de', style: TextStyle(color: Color(0xFF7A7280), fontSize: 12)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '"${r.tituloDestino ?? 'Memória 2'}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (legendas.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Relacionada porque:',
              style: TextStyle(
                color: Color(0xFF7A7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            ...legendas.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: AppColors.verdeApoio),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s,
                          style: const TextStyle(
                            color: Color(0xFF625B67),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _ignorar(r.id!),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7A7280),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Nunca sugerir'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => _ignorar(r.id!),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7A7280),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Agora não'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () => _confirmar(r.id!),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Conectar',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
