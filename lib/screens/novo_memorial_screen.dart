import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/memorial.dart';
import '../models/pessoa.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class NovoMemorialScreen extends StatefulWidget {
  const NovoMemorialScreen({super.key});

  @override
  State<NovoMemorialScreen> createState() => _NovoMemorialScreenState();
}

class _NovoMemorialScreenState extends State<NovoMemorialScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _parentescoController = TextEditingController();
  final _biografiaController = TextEditingController();
  final _picker = ImagePicker();

  DateTime? _dataNascimento;
  DateTime? _dataFalecimento;
  Uint8List? _fotoBytes;
  bool _salvando = false;

  List<Pessoa> _pessoasDisponiveis = [];
  Pessoa? _pessoaSelecionada;
  bool _carregandoPessoas = false;

  @override
  void initState() {
    super.initState();
    _carregarPessoas();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _parentescoController.dispose();
    _biografiaController.dispose();
    super.dispose();
  }

  Future<void> _carregarPessoas() async {
    setState(() => _carregandoPessoas = true);
    try {
      final lista = await PessoaRepository.listar();
      if (mounted) {
        setState(() {
          _pessoasDisponiveis = lista;
          _carregandoPessoas = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregandoPessoas = false);
    }
  }

  Future<void> _capturarFoto(ImageSource origem) async {
    try {
      final imagem = await _picker.pickImage(
        source: origem,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (imagem == null) return;

      final bytes = await imagem.readAsBytes();
      if (!mounted) return;
      setState(() {
        _fotoBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar a foto.')),
      );
    }
  }

  Future<void> _escolherDataNascimento() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataNascimento ?? DateTime(1950),
      firstDate: DateTime(1850),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() => _dataNascimento = data);
    }
  }

  Future<void> _escolherDataFalecimento() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataFalecimento ?? DateTime.now(),
      firstDate: _dataNascimento ?? DateTime(1850),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() => _dataFalecimento = data);
    }
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '';
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dataNascimento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, informe a data de nascimento.')),
      );
      return;
    }
    if (_dataFalecimento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, informe a data de falecimento.')),
      );
      return;
    }

    if (_dataFalecimento!.isBefore(_dataNascimento!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A data de falecimento não pode ser anterior à data de nascimento.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final memorial = Memorial(
        nome: _nomeController.text.trim(),
        parentesco: _parentescoController.text.trim(),
        dataNascimento: _dataNascimento!,
        dataFalecimento: _dataFalecimento!,
        biografia: _biografiaController.text.trim(),
        fotoBytes: _fotoBytes,
        contatoId: _pessoaSelecionada?.id,
        usuarioId: SupabaseService.usuarioId,
        createdAt: DateTime.now(),
      );

      await SupabaseService.instance.salvarMemorial(memorial);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar memorial: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Novo Memorial',
            style: TextStyle(
                color: AppColors.roxo,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _salvando
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.roxo),
                  )
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        const Text(
                          'Preste uma Homenagem',
                          style: TextStyle(
                              color: AppColors.roxo,
                              fontSize: 24,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Registre o legado de um ente querido que partiu para preservar suas melhores recordações.',
                          style: TextStyle(
                              color: Color(0xFF7A7280), fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 24),

                        // Link com Pessoa do App
                        if (_pessoasDisponiveis.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borda),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Vincular a uma pessoa já cadastrada (Opcional):',
                                  style: TextStyle(
                                    color: AppColors.roxo,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonHideUnderline(
                                  child: DropdownButtonFormField<Pessoa>(
                                    value: _pessoaSelecionada,
                                    hint: const Text('Selecione uma pessoa', style: TextStyle(fontSize: 14)),
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      contentPadding: EdgeInsets.zero,
                                      filled: false,
                                      border: InputBorder.none,
                                    ),
                                    items: _pessoasDisponiveis.map((p) {
                                      return DropdownMenuItem<Pessoa>(
                                        value: p,
                                        child: Text('${p.nome} (${p.parentesco})', style: const TextStyle(fontSize: 14)),
                                      );
                                    }).toList(),
                                    onChanged: (pessoa) {
                                      if (pessoa != null) {
                                        setState(() {
                                          _pessoaSelecionada = pessoa;
                                          _nomeController.text = p.nome;
                                          _parentescoController.text = p.parentesco;
                                          _dataNascimento = p.dataNascimento;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Foto de Perfil do Homenageado
                        Center(
                          child: Stack(
                            children: [
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(55),
                                  border: Border.all(color: AppColors.borda, width: 3),
                                  image: _fotoBytes != null
                                      ? DecorationImage(
                                          image: MemoryImage(_fotoBytes!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: _fotoBytes == null
                                    ? const Icon(Icons.favorite_outline,
                                        color: AppColors.dourado, size: 44)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: AppColors.roxo,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                                    onPressed: () => _mostrarOpcoesFoto(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Form Fields
                        TextFormField(
                          controller: _nomeController,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(fontSize: 15, color: AppColors.roxo, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            labelText: 'Nome Completo',
                            hintText: 'Nome do ente querido',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Por favor, informe o nome.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _parentescoController,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(fontSize: 15, color: AppColors.roxo, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            labelText: 'Grau de Parentesco / Relação',
                            hintText: 'Ex: Avó, Pai, Amigo',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Por favor, informe o parentesco.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Datas de Nascimento e Falecimento (Lado a Lado)
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _escolherDataNascimento,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.borda),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Nascimento',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF9B949D), fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _dataNascimento == null ? 'Selecionar' : _formatarData(_dataNascimento),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _dataNascimento == null ? const Color(0xFFC4BCC7) : AppColors.roxo,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: _escolherDataFalecimento,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.borda),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Falecimento',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF9B949D), fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _dataFalecimento == null ? 'Selecionar' : _formatarData(_dataFalecimento),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _dataFalecimento == null ? const Color(0xFFC4BCC7) : AppColors.roxo,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _biografiaController,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(fontSize: 14, color: AppColors.roxo, height: 1.4),
                          decoration: const InputDecoration(
                            labelText: 'Biografia / Homenagem Inicial',
                            hintText: 'Escreva um breve resumo da história, valores e legado deixados por esta pessoa...',
                            alignLabelWithHint: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Por favor, escreva uma biografia.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),

                        FilledButton(
                          onPressed: _salvar,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.roxo,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Salvar Memorial',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _mostrarOpcoesFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.roxo),
                title: const Text('Tirar Foto', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.of(context).pop();
                  _capturarFoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.roxo),
                title: const Text('Escolher da Galeria', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.of(context).pop();
                  _capturarFoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
