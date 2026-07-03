import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pessoa.dart';
import '../theme/app_theme.dart';
import 'nova_pessoa_screen.dart';

class PessoaDetalheScreen extends StatefulWidget {
  const PessoaDetalheScreen({
    required this.pessoa,
    required this.onAbrirMemoria,
    this.titulosMemorias = const {},
    super.key,
  });

  final Pessoa pessoa;
  final void Function(int memoriaId) onAbrirMemoria;
  final Map<int, String> titulosMemorias;

  @override
  State<PessoaDetalheScreen> createState() => _PessoaDetalheScreenState();
}

class _PessoaDetalheScreenState extends State<PessoaDetalheScreen> {
  Pessoa? _pessoa;
  List<int> _memoriasViculadas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _pessoa = widget.pessoa;
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final todas = await PessoaRepository.listar();
      final atualizada = todas.firstWhere(
        (p) => p.id == widget.pessoa.id,
        orElse: () => widget.pessoa,
      );
      final vinculos = await PessoaRepository.listarVinculos();
      final ids = vinculos.entries
          .where((e) => e.value.contains(widget.pessoa.id))
          .map((e) => e.key)
          .toList();
      if (mounted) {
        setState(() {
          _pessoa = atualizada;
          _memoriasViculadas = ids;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao carregar dados.')),
        );
      }
    }
  }

  Future<void> _editar() async {
    final alterou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NovaPessoaScreen(pessoa: _pessoa),
      ),
    );
    if (alterou == true && mounted) _carregar();
  }

  Future<void> _excluir() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir pessoa'),
        content: Text('Tem certeza que deseja excluir ${widget.pessoa.nome}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmou == true && mounted) {
      try {
        await PessoaRepository.remover(widget.pessoa.id);
        if (mounted) Navigator.of(context).pop();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível excluir ${widget.pessoa.nome}.'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pessoa = _pessoa ?? widget.pessoa;

    return Scaffold(
      appBar: AppBar(
        title: Text(pessoa.nome),
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: _editar,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: _excluir,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: const Color(0xFFF0EAF5),
                          backgroundImage: pessoa.fotoBytes != null
                              ? MemoryImage(pessoa.fotoBytes!)
                              : null,
                          child: pessoa.fotoBytes == null
                              ? const Icon(Icons.person,
                                  size: 52, color: AppColors.roxo)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        pessoa.nome,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (pessoa.apelido != null &&
                          pessoa.apelido!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          pessoa.apelido!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF7A7280),
                            fontSize: 16,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0x26D4A84F),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            pessoa.parentesco,
                            style: const TextStyle(
                              color: AppColors.dourado,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (pessoa.dataNascimento != null) ...[
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cake_outlined,
                                size: 16, color: AppColors.verdeApoio),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('dd/MM/yyyy')
                                  .format(pessoa.dataNascimento!),
                              style: const TextStyle(
                                color: Color(0xFF817987),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (pessoa.email != null && pessoa.email!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.email_outlined,
                                size: 16, color: AppColors.dourado),
                            const SizedBox(width: 6),
                            Text(
                              pessoa.email!,
                              style: const TextStyle(
                                color: Color(0xFF817987),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (pessoa.telefone != null && pessoa.telefone!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.phone_outlined,
                                size: 16, color: AppColors.dourado),
                            const SizedBox(width: 6),
                            Text(
                              pessoa.telefone!,
                              style: const TextStyle(
                                color: Color(0xFF817987),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          const Icon(Icons.auto_stories_outlined,
                              size: 18, color: AppColors.dourado),
                          const SizedBox(width: 8),
                          Text(
                            _memoriasViculadas.isEmpty
                                ? 'Nenhuma memória vinculada'
                                : '${_memoriasViculadas.length} ${_memoriasViculadas.length == 1 ? 'memória' : 'memórias'}',
                            style: const TextStyle(
                              color: AppColors.roxo,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_memoriasViculadas.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.borda),
                          ),
                          child: const Text(
                            'As memórias que você vincular a esta pessoa aparecerão aqui.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF7A7280),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        )
                      else
                        ..._memoriasViculadas.map(
                          (id) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () => widget.onAbrirMemoria(id),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: AppColors.borda),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.auto_stories_outlined,
                                          size: 20, color: AppColors.roxo),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          widget.titulosMemorias[id] ?? 'Memória',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.roxo,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: Color(0xFF9B949D)),
                                    ],
                                  ),
                                ),
                              ),
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
