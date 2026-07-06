import 'package:flutter/material.dart';

import '../models/cofre_item.dart';
import '../services/cofre_service.dart';
import '../theme/app_theme.dart';

class CofreScreen extends StatefulWidget {
  const CofreScreen({super.key});

  @override
  State<CofreScreen> createState() => _CofreScreenState();
}

class _CofreScreenState extends State<CofreScreen> {
  List<CofreItem> _itens = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final lista = await CofreService.instance.listar();
      if (mounted) setState(() { _itens = lista; _carregando = false; });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _criar() async {
    final criado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _CriarCofreItemScreen()),
    );
    if (criado == true) _carregar();
  }

  Future<void> _confirmarRemover(CofreItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover item'),
        content: Text('Remover "${item.titulo}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && item.id != null) {
      await CofreService.instance.remover(item.id!);
      _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Cofre'),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.roxo,
        foregroundColor: Colors.white,
        onPressed: _criar,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _itens.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 64, color: AppColors.dourado.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          const Text(
                            'Cofre vazio',
                            style: TextStyle(color: AppColors.roxo, fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Guarde documentos e anotações importantes aqui.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF7A7280), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: _itens.length,
                    itemBuilder: (_, i) => _CofreItemCard(
                      item: _itens[i],
                      onRemover: () => _confirmarRemover(_itens[i]),
                    ),
                  ),
      ),
    );
  }
}

class _CofreItemCard extends StatelessWidget {
  const _CofreItemCard({required this.item, required this.onRemover});
  final CofreItem item;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE8DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                item.tipo == 'documento' ? Icons.description_outlined : Icons.notes_outlined,
                size: 18,
                color: AppColors.dourado,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.titulo,
                  style: const TextStyle(color: AppColors.roxo, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB0A8B8)),
                onPressed: onRemover,
              ),
            ],
          ),
          if (item.conteudo != null && item.conteudo!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.conteudo!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF625B67), fontSize: 13, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            item.tipo == 'documento' ? 'Documento' : 'Anotação',
            style: const TextStyle(color: Color(0xFF7A7280), fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CriarCofreItemScreen extends StatefulWidget {
  const _CriarCofreItemScreen();
  @override
  State<_CriarCofreItemScreen> createState() => _CriarCofreItemScreenState();
}

class _CriarCofreItemScreenState extends State<_CriarCofreItemScreen> {
  final _tituloCtrl = TextEditingController();
  final _conteudoCtrl = TextEditingController();
  String _tipo = 'texto';
  bool _salvando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _conteudoCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_tituloCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha o título')),
      );
      return;
    }
    setState(() => _salvando = true);
    final item = CofreItem(
      titulo: _tituloCtrl.text.trim(),
      tipo: _tipo,
      conteudo: _conteudoCtrl.text.trim().isEmpty ? null : _conteudoCtrl.text.trim(),
    );
    await CofreService.instance.criar(item);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Novo item'),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _tituloCtrl,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'texto', label: Text('Anotação'), icon: Icon(Icons.notes_outlined)),
                ButtonSegment(value: 'documento', label: Text('Documento'), icon: Icon(Icons.description_outlined)),
              ],
              selected: {_tipo},
              onSelectionChanged: (v) => setState(() => _tipo = v.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _conteudoCtrl,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: _tipo == 'documento' ? 'Conteúdo do documento' : 'Conteúdo da anotação',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.roxo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _salvando
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                  : const Text('Salvar no Cofre'),
            ),
          ],
        ),
      ),
    );
  }
}
