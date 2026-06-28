import 'package:flutter/material.dart';

import '../models/memoria.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_card.dart';

class MinhaHistoriaScreen extends StatefulWidget {
  const MinhaHistoriaScreen({
    required this.memorias,
    required this.carregando,
    required this.supabaseConfigurado,
    required this.onRegistrar,
    required this.onAbrirDetalhe,
    required this.onAtualizar,
    super.key,
  });

  final List<Memoria> memorias;
  final bool carregando;
  final bool supabaseConfigurado;
  final Future<void> Function() onRegistrar;
  final void Function(Memoria memoria) onAbrirDetalhe;
  final Future<void> Function() onAtualizar;

  @override
  State<MinhaHistoriaScreen> createState() => _MinhaHistoriaScreenState();
}

class _MinhaHistoriaScreenState extends State<MinhaHistoriaScreen> {
  bool _atualizando = false;

  bool _registrando = false;

  Future<void> _registrar() async {
    if (_registrando) return;
    setState(() => _registrando = true);
    try {
      await widget.onRegistrar();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  Future<void> _atualizar() async {
    setState(() => _atualizando = true);
    try {
      await widget.onAtualizar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar sua história.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _atualizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha História'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _atualizando ? null : _atualizar,
            icon: _atualizando
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Registrar momento',
        onPressed: _registrando ? null : _registrar,
        backgroundColor: AppColors.dourado,
        foregroundColor: AppColors.roxo,
        child: _registrando
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                if (!widget.supabaseConfigurado) const _ModoLocalBanner(),
                Expanded(
                  child: widget.carregando && widget.memorias.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : widget.memorias.isEmpty
                      ? _EstadoVazio(onRegistrar: _registrar)
                      : RefreshIndicator(
                          onRefresh: _atualizar,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                            itemCount: widget.memorias.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              return MemoryCard(
                                memoria: widget.memorias[index],
                                onLer: () =>
                                    widget.onAbrirDetalhe(widget.memorias[index]),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModoLocalBanner extends StatelessWidget {
  const _ModoLocalBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8D39B)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: AppColors.roxo),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Modo local. Configure a chave pública para sincronizar com a aEterna.',
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onRegistrar});

  final VoidCallback onRegistrar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.auto_stories_outlined,
            size: 58,
            color: AppColors.dourado,
          ),
          const SizedBox(height: 20),
          const Text(
            'Sua história começa aqui',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Registre memórias, aprendizados e momentos que merecem ser '
            'lembrados pelas próximas gerações.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF746D78),
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRegistrar,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Criar primeira memória'),
          ),
        ],
      ),
    );
  }
}
