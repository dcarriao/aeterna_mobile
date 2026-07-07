import 'package:flutter/material.dart';

import '../models/memoria.dart';
import '../models/pessoa.dart';
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
  final _searchCtrl = TextEditingController();
  String _termoBusca = '';
  Map<int, List<String>> _pessoasPorMemoria = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _termoBusca = _searchCtrl.text.trim().toLowerCase());
    });
    _carregarPessoas();
  }

  @override
  void didUpdateWidget(MinhaHistoriaScreen old) {
    super.didUpdateWidget(old);
    if (old.memorias != widget.memorias && _termoBusca.isEmpty) {
      _carregarPessoas();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarPessoas() async {
    try {
      final pessoas = await PessoaRepository.listar();
      final vinculos = await PessoaRepository.listarVinculos();
      final map = <int, List<String>>{};
      for (final v in vinculos.entries) {
        final memoriaId = v.key;
        final pessoaIds = v.value;
        final nomes = pessoaIds
            .map((cid) => pessoas.where((p) => p.id == cid))
            .expand((p) => p)
            .map((p) => '${p.nome} ${p.apelido ?? ''}'.trim().toLowerCase())
            .toList();
        if (nomes.isNotEmpty) map[memoriaId] = nomes;
      }
      if (mounted) setState(() => _pessoasPorMemoria = map);
    } catch (_) {}

  }

  List<Memoria> get _memoriasFiltradas {
    if (_termoBusca.isEmpty) return widget.memorias;
    return widget.memorias.where((m) {
      if (m.titulo.toLowerCase().contains(_termoBusca)) return true;
      if (m.contexto.toLowerCase().contains(_termoBusca)) return true;
      final nomes = _pessoasPorMemoria[m.id];
      if (nomes != null) {
        for (final n in nomes) {
          if (n.contains(_termoBusca)) return true;
        }
      }
      return false;
    }).toList();
  }

  Future<void> _registrar() async {
    if (_registrando) return;
    setState(() => _registrando = true);
    try {
      await widget.onRegistrar();
      if (mounted) setState(() {});
      _carregarPessoas();
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  Future<void> _atualizar() async {
    setState(() => _atualizando = true);
    try {
      await widget.onAtualizar();
      _carregarPessoas();
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
    final filtradas = _memoriasFiltradas;
    final temResultados = filtradas.isNotEmpty;
    final temBusca = _termoBusca.isNotEmpty;

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
                // Busca
                if (widget.memorias.length >= 2 || temBusca)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      temBusca ? 8 : 0,
                      20,
                      temBusca ? 4 : 0,
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar histórias...',
                        prefixIcon: const Icon(Icons.search_outlined,
                            color: AppColors.dourado, size: 20),
                        suffixIcon: temBusca
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFEDE8DC)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFEDE8DC)),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: widget.carregando && widget.memorias.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : widget.memorias.isEmpty
                      ? _EstadoVazio(onRegistrar: _registrar)
                      : !temResultados && temBusca
                      ? _EstadoSemResultados(
                          termo: _termoBusca,
                          onLimpar: () => _searchCtrl.clear(),
                        )
                      : RefreshIndicator(
                          onRefresh: _atualizar,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                            itemCount: filtradas.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              return MemoryCard(
                                memoria: filtradas[index],
                                onLer: () =>
                                    widget.onAbrirDetalhe(filtradas[index]),
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

class _EstadoSemResultados extends StatelessWidget {
  const _EstadoSemResultados({required this.termo, required this.onLimpar});

  final String termo;
  final VoidCallback onLimpar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_outlined, size: 52,
              color: Color(0xFFB0A8B8)),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma história encontrada',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nenhuma história corresponde a "$termo".',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF7A7280), fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onLimpar,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Limpar busca'),
          ),
        ],
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
