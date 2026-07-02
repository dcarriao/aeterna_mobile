import 'package:flutter/material.dart';
import '../models/memorial.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'novo_memorial_screen.dart';
import 'memorial_detalhe_screen.dart';

class MemoriaisScreen extends StatefulWidget {
  const MemoriaisScreen({super.key});

  @override
  State<MemoriaisScreen> createState() => _MemoriaisScreenState();
}

class _MemoriaisScreenState extends State<MemoriaisScreen> {
  final _service = SupabaseService.instance;
  List<Memorial> _memoriais = [];
  bool _carregando = false;

  @override
  void initState() {
    super.initState();
    _carregarMemoriais();
  }

  Future<void> _carregarMemoriais() async {
    if (!_service.isConfigured) return;
    setState(() => _carregando = true);
    try {
      final lista = await _service.listarMemoriais();
      if (mounted) {
        setState(() {
          _memoriais = lista;
        });
      }
    } catch (e) {
      print('Erro ao carregar memoriais: $e');
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _abrirNovoMemorial() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NovoMemorialScreen()),
    );
    if (result == true) {
      _carregarMemoriais();
    }
  }

  void _abrirDetalhe(Memorial memorial) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MemorialDetalheScreen(memorial: memorial)),
    );
    if (result == true) {
      _carregarMemoriais();
    }
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Memoriais',
            style: TextStyle(
                color: AppColors.roxo,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.roxo),
                  )
                : _memoriais.isEmpty
                    ? _buildEstadoVazio()
                    : RefreshIndicator(
                        onRefresh: _carregarMemoriais,
                        color: AppColors.roxo,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          itemCount: _memoriais.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Homenagens',
                                      style: TextStyle(
                                          color: AppColors.roxo,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800),
                                    ),
                                    FilledButton.icon(
                                      onPressed: _abrirNovoMemorial,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.roxo,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Criar'),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final memorial = _memoriais[index - 1];
                            return _buildCardMemorial(memorial);
                          },
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardMemorial(Memorial memorial) {
    final periodo = '${_formatarData(memorial.dataNascimento)} - ${_formatarData(memorial.dataFalecimento)}';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _abrirDetalhe(memorial),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EAF5),
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(color: AppColors.borda, width: 2),
                      image: memorial.fotoUrl != null && memorial.fotoUrl!.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(memorial.fotoUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: memorial.fotoUrl == null || memorial.fotoUrl!.isEmpty
                        ? const Icon(Icons.favorite_outline,
                            color: AppColors.roxo, size: 28)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memorial.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.roxo,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          memorial.parentesco,
                          style: const TextStyle(
                            color: AppColors.dourado,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 12, color: Color(0xFF9B949D)),
                            const SizedBox(width: 6),
                            Text(
                              periodo,
                              style: const TextStyle(
                                color: Color(0xFF9B949D),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 14, color: AppColors.borda),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEstadoVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0x16D4A84F),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_outline,
                  size: 40, color: AppColors.dourado),
            ),
            const SizedBox(height: 24),
            const Text(
              'Espaço Memorial',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.roxo,
                  fontSize: 22,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'Preste homenagem a entes queridos que partiram. Crie um memorial interativo com biografia, fotos e permita que familiares contribuam.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF7A7280), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _abrirNovoMemorial,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.roxo,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Criar Memorial'),
            ),
          ],
        ),
      ),
    );
  }
}
