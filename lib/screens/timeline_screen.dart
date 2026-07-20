import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memoria.dart';
import '../models/pessoa.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_card.dart';

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
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 44),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 20),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EAF5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.timeline_outlined,
                color: AppColors.roxo, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: widget.memorias.isEmpty
                ? _EstadoVazio(onCriar: widget.onCriarMemoria)
                : Column(
                    children: [
                      _StatsBar(
                        totalMemorias: _memoriasFiltradas.length,
                        totalPessoas:
                            _pessoas.where((p) => !p.isPet).length,
                        totalPets: _pessoas.where((p) => p.isPet).length,
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEDE8DC)),
        ),
        child: Row(
          children: [
            const Icon(Icons.filter_list_outlined,
                size: 18, color: AppColors.dourado),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButton<int?>(
                value: _pessoaFiltroId,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: Colors.white,
                hint: const Text(
                  'Filtrar por pessoa',
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
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
          memorias.sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AnoHeader(ano: ano),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
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
    required this.totalPets,
    required this.anoMaisAntigo,
  });

  final int totalMemorias;
  final int totalPessoas;
  final int totalPets;
  final int? anoMaisAntigo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Linha do Tempo',
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Reviva sua história em ordem cronológica.',
            style: TextStyle(
              color: AppColors.textoSuave,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 20),
          Row(
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
              if (totalPets > 0) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon: Icons.pets_outlined,
                    value: '$totalPets',
                    label: totalPets == 1 ? 'pet' : 'pets',
                  ),
                ),
              ],
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
        border: Border.all(color: const Color(0xFFEDE8DC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x042B1747),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.dourado),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.roxo,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7A7280),
              fontSize: 11,
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
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 4),
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
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.dourado,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x30D4A84F),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: const Color(0xFFEDE8DC),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEDE8DC)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x062B1747),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (memoria.foto != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(15)),
                          child: SizedBox(
                            height: 180,
                            width: double.infinity,
                            child: Image.memory(
                              memoria.foto!,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                            ),
                          ),
                        )
                      else if (memoria.fotoUrl != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(15)),
                          child: SizedBox(
                            height: 180,
                            width: double.infinity,
                            child: Image.network(
                              memoria.fotoUrl!,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                        )
                      else if (memoria.temVideo && memoria.videoUrl != null)
                        VideoFramePreview(
                            url: memoria.videoUrl!, height: 180)
                      else if (memoria.temVideo)
                        Container(
                          height: 180,
                          width: double.infinity,
                          color: const Color(0xFF2B1747),
                          child: const Center(
                            child: Icon(Icons.videocam_outlined,
                                color: Colors.white38, size: 32),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_today_outlined,
                                    size: 13, color: AppColors.dourado),
                                const SizedBox(width: 6),
                                Text(
                                  DateFormat('dd/MM/yyyy')
                                      .format(memoria.criadaEm),
                                  style: const TextStyle(
                                    color: Color(0xFF817987),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              memoria.titulo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.roxo,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              memoria.contexto,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF625B67),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
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
                                          style: const TextStyle(fontSize: 11),
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
                    ],
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
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0x26D4A84F),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timeline_outlined,
                size: 32, color: AppColors.dourado),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sua linha do tempo começará com a primeira memória.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cada memória registrada ajuda a contar a história da sua família.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFF746D78), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCriar,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.roxo,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('Nova memória'),
          ),
        ],
      ),
    );
  }
}
