import 'package:flutter/material.dart';

import '../models/mensagem_futuro.dart';
import '../services/mensagem_futuro_service.dart';
import '../theme/app_theme.dart';

class MensagensFuturoScreen extends StatefulWidget {
  const MensagensFuturoScreen({super.key});

  @override
  State<MensagensFuturoScreen> createState() => _MensagensFuturoScreenState();
}

class _MensagensFuturoScreenState extends State<MensagensFuturoScreen> {
  List<MensagemFuturo> _itens = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final lista = await MensagemFuturoService.instance.listar();
    if (mounted) setState(() { _itens = lista; _carregando = false; });
  }

  Future<void> _criar() async {
    final criada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _CriarMensagemFuturoScreen()),
    );
    if (criada == true) _carregar();
  }

  Future<void> _confirmarRemover(MensagemFuturo msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover mensagem'),
        content: Text('Remover "${msg.titulo}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && msg.id != null) {
      await MensagemFuturoService.instance.remover(msg.id!);
      _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Mensagens para o Futuro'),
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
                          Icon(Icons.mail_outline, size: 64, color: AppColors.dourado.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          const Text(
                            'Nenhuma mensagem ainda',
                            style: TextStyle(color: AppColors.roxo, fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Escreva uma mensagem para alguém ler no futuro.',
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
                    itemBuilder: (_, i) => _MensagemCard(
                      mensagem: _itens[i],
                      onRemover: () => _confirmarRemover(_itens[i]),
                    ),
                  ),
      ),
    );
  }
}

class _MensagemCard extends StatelessWidget {
  const _MensagemCard({required this.mensagem, required this.onRemover});
  final MensagemFuturo mensagem;
  final VoidCallback onRemover;

  String _formatarData(DateTime? dt) {
    if (dt == null) return 'Sem data';
    final agora = DateTime.now();
    if (dt.isAfter(agora)) return 'Agendada para ${dt.day}/${dt.month}/${dt.year}';
    return 'Enviada em ${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final agora = DateTime.now();
    final vencida = mensagem.dataAgendamento != null && mensagem.dataAgendamento!.isBefore(agora);
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
                vencida ? Icons.mark_email_read_outlined : Icons.schedule_send_outlined,
                size: 18,
                color: vencida ? AppColors.verdeApoio : AppColors.dourado,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mensagem.titulo,
                  style: const TextStyle(color: AppColors.roxo, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB0A8B8)),
                onPressed: onRemover,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mensagem.conteudo,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF625B67), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            _formatarData(mensagem.dataAgendamento),
            style: TextStyle(
              color: vencida ? AppColors.verdeApoio : const Color(0xFF7A7280),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CriarMensagemFuturoScreen extends StatefulWidget {
  const _CriarMensagemFuturoScreen();
  @override
  State<_CriarMensagemFuturoScreen> createState() => _CriarMensagemFuturoScreenState();
}

class _CriarMensagemFuturoScreenState extends State<_CriarMensagemFuturoScreen> {
  final _tituloCtrl = TextEditingController();
  final _conteudoCtrl = TextEditingController();
  DateTime? _dataAgendamento;
  bool _salvando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _conteudoCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_tituloCtrl.text.trim().isEmpty || _conteudoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha título e conteúdo')),
      );
      return;
    }
    setState(() => _salvando = true);
    final msg = MensagemFuturo(
      titulo: _tituloCtrl.text.trim(),
      conteudo: _conteudoCtrl.text.trim(),
      dataAgendamento: _dataAgendamento ?? DateTime.now().add(const Duration(days: 1)),
    );
    await MensagemFuturoService.instance.criar(msg);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Nova mensagem'),
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
            TextField(
              controller: _conteudoCtrl,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Conteúdo',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _dataAgendamento == null
                    ? 'Data de entrega'
                    : '${_dataAgendamento!.day}/${_dataAgendamento!.month}/${_dataAgendamento!.year}',
                style: TextStyle(
                  color: _dataAgendamento == null ? const Color(0xFF7A7280) : AppColors.roxo,
                ),
              ),
              trailing: const Icon(Icons.calendar_today, color: AppColors.dourado),
              onTap: () async {
                final data = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                );
                if (data != null) setState(() => _dataAgendamento = data);
              },
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
                  : const Text('Salvar mensagem'),
            ),
          ],
        ),
      ),
    );
  }
}
