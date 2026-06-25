import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memoria.dart';
import '../models/pessoa.dart';
import '../theme/app_theme.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    required this.memorias,
    required this.onAbrirMemoria,
    required this.onCriarMemoria,
    super.key,
  });

  final List<Memoria> memorias;
  final void Function(Memoria memoria) onAbrirMemoria;
  final VoidCallback onCriarMemoria;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<Pessoa> _pessoas = [];
  Map<int, List<int>> _vinculos = {};
  int? _pessoaFiltroId;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    final pessoas = await PessoaRepository.listar();
    final vinculos = await PessoaRepository.listarVinculos();
    if (mounted) {
      setState(() {
        _pessoas = pessoas;
        _vinculos = vinculos;
        _carregando = false;
      });
    }
  }

  List<Memoria> get _memoriasFiltradas {
    final todas = widget.memorias;
    if (_pessoaFiltroId == null) return todas;

    return todas.where((m) {
      final ids = m.pessoasIds ?? _vinculos[m.id ?? -1];
      return ids != null && ids.contains(_pessoaFiltroId);
    }).toList();
  }

  Map<int, List<Memoria>> get _agrupadoPorAno {
    final mapa = <int, List<Memoria>>{};
    for (final m in _memoriasFiltradas) {
      final ano = m.criadaEm.year;
      mapa.putIfAbsent(ano, () => []).add(m);
    }
    return mapa;
  }

  int? get _anoMaisAntigo {
    if (_memoriasFiltradas.isEmpty) return null;
    return _memoriasFiltradas
        .map((m) => m.criadaEm.year)
        .reduce((a, b) => a < b ? a : b);
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
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Linha do Tempo')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Linha do Tempo')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: widget.memorias.isEmpty
                ? _EstadoVazio(onCriar: widget.onCriarMemoria)
                : Column(
                    children: [
                      const SizedBox(height: 12),
                      _StatsBar(
                        totalMemorias: _memoriasFiltradas.length,
                        totalPessoas: _pessoas.length,
                        anoMaisAntigo: _anoMaisAntigo,
                      ),
                      if (_pessoas.isNotEmpty) _buildFiltro(),
                      Expanded(child: _buildTimeline()),
                    ],
                  ),
          ),
        ),
      ),
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
              value: _pessoaFiltroId,
              isExpanded: true,
              underline: const SizedBox(),
              hint: const Text(
                'Todas as pessoas',
                style: TextStyle(color: AppColors.textoSuave, fontSize: 14),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todas as pessoas'),
                ),
                ..._pessoas.map(
                  (p) => DropdownMenuItem<int?>(
                    value: p.id,
                    child: Text(p.nome),
                  ),
                ),
              ],
              onChanged: (id) => setState(() => _pessoaFiltroId = id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final anos = _agrupadoPorAno.keys.toList()..sort((a, b) => b.compareTo(a));

    if (_memoriasFiltradas.isEmpty && _pessoaFiltroId != null) {
      final pessoa = _pessoaPorId(_pessoaFiltroId!);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Nenhuma memória com ${pessoa?.nome ?? 'esta pessoa'}.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF7A7280), fontSize: 15),
          ),
        ),
      );
    }

    final apenasUma = _memoriasFiltradas.length == 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (apenasUma) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EAF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 18, color: AppColors.dourado),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Todo legado começa com uma história.',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ...anos.map((ano) {
          final memorias = _agrupadoPorAno[ano]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AnoHeader(ano: ano),
              const SizedBox(height: 8),
              ...List.generate(memorias.length, (i) {
                final memoria = memorias[i];
                final ids = memoria.pessoasIds ??
                    _vinculos[memoria.id ?? -1] ??
                    [];
                final pessoasVinculadas = ids
                    .map((id) => _pessoaPorId(id))
                    .whereType<Pessoa>()
                    .toList();

                return _TimelineEvent(
                  memoria: memoria,
                  pessoas: pessoasVinculadas,
                  isLast: i == memorias.length - 1,
                  onTap: () => widget.onAbrirMemoria(memoria),
                );
              }),
              const SizedBox(height: 12),
            ],
          );
        }),
      ],
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.totalMemorias,
    required this.totalPessoas,
    required this.anoMaisAntigo,
  });

  final int totalMemorias;
  final int totalPessoas;
  final int? anoMaisAntigo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.auto_stories_outlined,
              value: '$totalMemorias',
              label: totalMemorias == 1 ? 'memória' : 'memórias',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.people_outline,
              value: '$totalPessoas',
              label: totalPessoas == 1 ? 'pessoa' : 'pessoas',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.calendar_today_outlined,
              value: anoMaisAntigo != null ? '$anoMaisAntigo' : '-',
              label: 'mais antigo',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borda),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.dourado),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.roxo,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7A7280),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnoHeader extends StatelessWidget {
  const _AnoHeader({required this.ano});

  final int ano;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
      child: Text(
        '$ano',
        style: const TextStyle(
          color: AppColors.roxo,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({
    required this.memoria,
    required this.pessoas,
    required this.isLast,
    required this.onTap,
  });

  final Memoria memoria;
  final List<Pessoa> pessoas;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                const SizedBox(height: 18),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.dourado,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40D4A84F),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: const Color(0xFFE2D8C8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onTap,
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
                            const Icon(Icons.calendar_today_outlined,
                                size: 14, color: AppColors.dourado),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('dd/MM/yyyy')
                                  .format(memoria.criadaEm),
                              style: const TextStyle(
                                color: Color(0xFF817987),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          memoria.titulo,
                          style: const TextStyle(
                            color: AppColors.roxo,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          memoria.contexto,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF625B67),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        if (memoria.foto != null) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Image.memory(
                                memoria.foto!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                        if (pessoas.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: pessoas
                                .map(
                                  (p) => Chip(
                                    avatar: CircleAvatar(
                                      radius: 10,
                                      backgroundColor:
                                          const Color(0xFFF0EAF5),
                                      backgroundImage: p.fotoBytes != null
                                          ? MemoryImage(p.fotoBytes!)
                                          : null,
                                      child: p.fotoBytes == null
                                          ? const Icon(Icons.person,
                                              size: 10,
                                              color: AppColors.roxo)
                                          : null,
                                    ),
                                    label: Text(
                                      p.nome,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    labelPadding: EdgeInsets.zero,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onCriar});

  final VoidCallback onCriar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timeline_outlined,
              size: 58, color: AppColors.dourado),
          const SizedBox(height: 20),
          const Text(
            'Sua linha do tempo ainda está começando',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cada memória registrada ajuda a contar a história da sua família.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF746D78),
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCriar,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Criar memória'),
          ),
        ],
      ),
    );
  }
}
