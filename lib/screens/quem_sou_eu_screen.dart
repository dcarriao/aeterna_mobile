import 'package:flutter/material.dart';

import '../models/quem_sou_eu.dart';
import '../services/quem_sou_eu_service.dart';
import '../theme/app_theme.dart';

class QuemSouEuScreen extends StatefulWidget {
  const QuemSouEuScreen({super.key});

  @override
  State<QuemSouEuScreen> createState() => _QuemSouEuScreenState();
}

class _QuemSouEuScreenState extends State<QuemSouEuScreen> {
  List<QuemSouEuRegistro> _registros = [];
  bool _carregando = true;

  static const _perguntasPadrao = [
    'O que mais importa para mim?',
    'Como eu quero ser lembrado?',
    'O que me faz feliz?',
    'Qual é o meu maior sonho?',
    'O que aprendi com os desafios da vida?',
    'O que eu diria para as próximas gerações?',
    'Quais valores guiam minhas decisões?',
    'O que eu mais admiro nas pessoas?',
    'Qual momento da minha vida foi mais marcante?',
    'O que eu ainda quero viver?',
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final lista = await QuemSouEuService.instance.listar();
      if (mounted) setState(() { _registros = lista; _carregando = false; });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  QuemSouEuRegistro? _buscarRegistro(String pergunta) {
    try {
      return _registros.firstWhere((r) => r.perguntaChave == pergunta);
    } catch (_) {
      return null;
    }
  }

  Future<void> _editarResposta(String pergunta, String? respostaAtual) async {
    final ctrl = TextEditingController(text: respostaAtual);
    final salva = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pergunta, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escreva sua resposta...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (salva == true && ctrl.text.trim().isNotEmpty) {
      final reg = QuemSouEuRegistro(
        id: _buscarRegistro(pergunta)?.id,
        perguntaChave: pergunta,
        resposta: ctrl.text.trim(),
      );
      await QuemSouEuService.instance.salvar(reg);
      _carregar();
    }
    ctrl.dispose();
  }

  Future<void> _confirmarLimpar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar respostas'),
        content: const Text('Remover todas as suas respostas?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpar tudo', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      for (final r in _registros) {
        if (r.id != null) await QuemSouEuService.instance.remover(r.id!);
      }
      _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final respostasCount = _registros.length;
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Quem Sou Eu'),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
        actions: [
          if (respostasCount > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFB0A8B8)),
              tooltip: 'Limpar respostas',
              onPressed: _confirmarLimpar,
            ),
        ],
      ),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  const Text(
                    'Registre quem você é para o Curador conhecer melhor sua história.',
                    style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$respostasCount de ${_perguntasPadrao.length} respondidas',
                    style: const TextStyle(color: AppColors.dourado, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  ..._perguntasPadrao.map((pergunta) {
                    final reg = _buscarRegistro(pergunta);
                    return _PerguntaCard(
                      pergunta: pergunta,
                      resposta: reg?.resposta,
                      onEditar: () => _editarResposta(pergunta, reg?.resposta),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

class _PerguntaCard extends StatelessWidget {
  const _PerguntaCard({
    required this.pergunta,
    this.resposta,
    required this.onEditar,
  });

  final String pergunta;
  final String? resposta;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final temResposta = resposta != null && resposta!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: temResposta ? const Color(0xFFE8E0D0) : const Color(0xFFEDE8DC),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEditar,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  temResposta ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                  size: 16,
                  color: temResposta ? AppColors.verdeApoio : const Color(0xFFB0A8B8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pergunta,
                    style: const TextStyle(
                      color: AppColors.roxo,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 16, color: AppColors.dourado),
              ],
            ),
            if (temResposta) ...[
              const SizedBox(height: 8),
              Text(
                resposta!,
                style: const TextStyle(color: Color(0xFF625B67), fontSize: 13, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
