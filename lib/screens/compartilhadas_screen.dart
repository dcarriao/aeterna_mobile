import 'package:flutter/material.dart';

import '../models/memoria.dart';
import '../models/pessoa.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_card.dart';

class CompartilhadasScreen extends StatefulWidget {
  const CompartilhadasScreen({
    required this.memorias,
    required this.onAbrirMemoria,
    required this.onCompartilhar,
    this.memoriasRecebidas = const [],
    super.key,
  });

  final List<Memoria> memorias;
  final void Function(Memoria memoria) onAbrirMemoria;
  final VoidCallback onCompartilhar;

  /// Memórias que OUTRAS contas compartilharam com o usuário logado
  /// (Bug 1 — antes não existia distinção entre "compartilhei" e
  /// "compartilharam comigo").
  final List<Memoria> memoriasRecebidas;

  @override
  State<CompartilhadasScreen> createState() => _CompartilhadasScreenState();
}

class _CompartilhadasScreenState extends State<CompartilhadasScreen> {
  List<Pessoa> _pessoas = [];
  Map<int, List<int>> _compartilhamentos = {};
  int? _familiarFiltroId;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final pessoas = await PessoaRepository.listar();
    final comp = await PessoaRepository.listarCompartilhamentos();
    if (mounted) {
      setState(() {
        _pessoas = pessoas;
        _compartilhamentos = comp;
        _carregando = false;
      });
    }
  }

  List<Memoria> get _memoriasFiltradas {
    final ids = _compartilhamentos.keys.toSet();
    final todas = widget.memorias.where((m) => ids.contains(m.id)).toList();

    if (_familiarFiltroId == null) return todas;

    return todas.where((m) {
      final familiares = m.familiaresIds ?? _compartilhamentos[m.id] ?? [];
      return familiares.contains(_familiarFiltroId);
    }).toList();
  }

  Pessoa? _pessoaPorId(int id) {
    try {
      return _pessoas.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Compartilhadas'),
          bottom: const TabBar(
            labelColor: AppColors.roxo,
            unselectedLabelColor: AppColors.textoSuave,
            indicatorColor: AppColors.dourado,
            tabs: [
              Tab(text: 'Você compartilhou'),
              Tab(text: 'Compartilharam com você'),
            ],
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: TabBarView(
                children: [
                  _buildAbaVoceCompartilhou(),
                  _buildAbaRecebidas(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAbaVoceCompartilhou() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    final compartilhadas = _compartilhamentos.keys.toSet();
    final memorias = _memoriasFiltradas;

    if (widget.memorias.every((m) => !compartilhadas.contains(m.id))) {
      return _EstadoVazio(onCompartilhar: widget.onCompartilhar);
    }

    return Column(
      children: [
        if (_pessoas.isNotEmpty) _buildFiltro(),
        Expanded(
          child: memorias.isEmpty
              ? Center(
                  child: Text(
                    'Nenhuma memória compartilhada com este familiar.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF7A7280),
                      fontSize: 15,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  itemCount: memorias.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final m = memorias[index];
                    final ids = m.familiaresIds ??
                        _compartilhamentos[m.id] ??
                        [];
                    final nomes = ids
                        .map((id) => _pessoaPorId(id)?.nome)
                        .whereType<String>()
                        .take(3)
                        .toList();

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => widget.onAbrirMemoria(m),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.borda),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.share_outlined,
                                      size: 16, color: AppColors.dourado),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${ids.length} ${ids.length == 1 ? 'familiar' : 'familiares'}',
                                    style: const TextStyle(
                                      color: AppColors.dourado,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                m.titulo,
                                style: const TextStyle(
                                  color: AppColors.roxo,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                m.contexto,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF625B67),
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                              if (nomes.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Com ${nomes.join(', ')}',
                                  style: const TextStyle(
                                    color: Color(0xFF7A7280),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAbaRecebidas() {
    final recebidas = widget.memoriasRecebidas;

    if (recebidas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined,
                size: 58, color: AppColors.dourado),
            const SizedBox(height: 20),
            const Text(
              'Ninguém compartilhou memórias com você ainda.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.roxo,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Quando um familiar compartilhar uma memória com o seu '
              'e-mail de cadastro, ela aparecerá aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF746D78),
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: recebidas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final m = recebidas[index];
        return MemoryCard(
          memoria: m,
          compartilhadaPorNome: m.compartilhadaPorNome,
          onLer: () => widget.onAbrirMemoria(m),
        );
      },
    );
  }

  Widget _buildFiltro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          const Icon(Icons.filter_list_outlined,
              size: 18, color: AppColors.textoSuave),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<int?>(
              value: _familiarFiltroId,
              isExpanded: true,
              underline: const SizedBox(),
              hint: const Text(
                'Todos os familiares',
                style: TextStyle(color: AppColors.textoSuave, fontSize: 14),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todos os familiares'),
                ),
                ..._pessoas.map(
                  (p) => DropdownMenuItem<int?>(
                    value: p.id,
                    child: Text(p.nome),
                  ),
                ),
              ],
              onChanged: (id) => setState(() => _familiarFiltroId = id),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onCompartilhar});

  final VoidCallback onCompartilhar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline,
              size: 58, color: AppColors.dourado),
          const SizedBox(height: 20),
          const Text(
            'As melhores histórias merecem ser compartilhadas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Compartilhe memórias importantes com as pessoas que '
            'fazem parte da sua história.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF746D78),
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCompartilhar,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartilhar primeira memória'),
          ),
        ],
      ),
    );
  }
}
