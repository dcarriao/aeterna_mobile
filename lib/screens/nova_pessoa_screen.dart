import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/pessoa.dart';
import '../theme/app_theme.dart';

class NovaPessoaScreen extends StatefulWidget {
  const NovaPessoaScreen({this.pessoa, super.key});

  final Pessoa? pessoa;

  @override
  State<NovaPessoaScreen> createState() => _NovaPessoaScreenState();
}

class _NovaPessoaScreenState extends State<NovaPessoaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _apelidoController = TextEditingController();
  final _picker = ImagePicker();

  String _parentesco = 'Outro';
  DateTime? _dataNascimento;
  String? _fotoBase64;
  Uint8List? _fotoBytes;
  bool _salvando = false;

  bool get _editando => widget.pessoa != null;

  @override
  void initState() {
    super.initState();
    if (widget.pessoa != null) {
      final p = widget.pessoa!;
      _nomeController.text = p.nome;
      _apelidoController.text = p.apelido ?? '';
      _parentesco = p.parentesco;
      _dataNascimento = p.dataNascimento;
      _fotoBase64 = p.fotoBase64;
      _fotoBytes = p.fotoBytes;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _apelidoController.dispose();
    super.dispose();
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
        _fotoBase64 = base64Encode(bytes);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar a foto.')),
      );
    }
  }

  Future<void> _escolherData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataNascimento ?? DateTime(1960),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() => _dataNascimento = data);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    try {
      final pessoa = Pessoa(
        id: widget.pessoa?.id,
        nome: _nomeController.text.trim(),
        apelido: _apelidoController.text.trim().isEmpty
            ? null
            : _apelidoController.text.trim(),
        parentesco: _parentesco,
        dataNascimento: _dataNascimento,
        fotoBase64: _fotoBase64,
        createdAt: widget.pessoa?.createdAt,
      );
      print('[NovaPessoaScreen] _salvar() -> chamando PessoaRepository.salvar(${pessoa.nome}) isUpdate=$_editando');
      await PessoaRepository.salvar(pessoa, isUpdate: _editando);
      print('[NovaPessoaScreen] _salvar() -> salvar concluido, pop(true)');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      print('[NovaPessoaScreen] _salvar() ERRO: $e');
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar a pessoa.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar pessoa' : 'Nova pessoa'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (!_editando) ...[
                    const Text(
                      'Quem faz parte da sua história?',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Cadastre alguém importante para sua família.',
                      style: TextStyle(
                        color: AppColors.textoSuave,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  _FotoPessoa(
                    fotoBytes: _fotoBytes,
                    onRemover: () => setState(() {
                      _fotoBytes = null;
                      _fotoBase64 = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final botoes = [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _capturarFoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tirar foto'),
                          ),
                        ),
                        const SizedBox(width: 12, height: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _capturarFoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galeria'),
                          ),
                        ),
                      ];

                      if (constraints.maxWidth < 390) {
                        return Column(
                          children: botoes.map((item) {
                            return item is Expanded ? item.child : item;
                          }).toList(),
                        );
                      }
                      return Row(children: botoes);
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nomeController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      hintText: 'Nome completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return 'Informe o nome.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _apelidoController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Apelido',
                      hintText: 'Como você chama essa pessoa?',
                      prefixIcon: Icon(Icons.favorite_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _parentesco,
                    decoration: const InputDecoration(
                      labelText: 'Parentesco',
                      prefixIcon: Icon(Icons.family_restroom_outlined),
                    ),
                    items: parentescos
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (valor) {
                      if (valor != null) setState(() => _parentesco = valor);
                    },
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Selecione o parentesco.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _escolherData,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data de nascimento',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      child: Text(
                        _dataNascimento != null
                            ? '${_dataNascimento!.day.toString().padLeft(2, '0')}/'
                                '${_dataNascimento!.month.toString().padLeft(2, '0')}/'
                                '${_dataNascimento!.year}'
                            : 'Toque para selecionar',
                        style: TextStyle(
                          color: _dataNascimento != null
                              ? AppColors.roxo
                              : const Color(0xFF9B949D),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_outlined),
                    label: Text(
                      _salvando
                          ? 'Salvando...'
                          : _editando
                              ? 'Salvar alterações'
                              : 'Salvar pessoa',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FotoPessoa extends StatelessWidget {
  const _FotoPessoa({required this.fotoBytes, required this.onRemover});

  final Uint8List? fotoBytes;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    if (fotoBytes != null) {
      return Stack(
        children: [
          Center(
            child: ClipOval(
              child: SizedBox(
                width: 140,
                height: 140,
                child: Image.memory(fotoBytes!, fit: BoxFit.cover),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filled(
              tooltip: 'Remover foto',
              onPressed: onRemover,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      );
    }

    return const SizedBox(
      height: 160,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 42, color: AppColors.dourado),
          SizedBox(height: 12),
          Text(
            'Adicione uma foto',
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Use a câmera ou escolha uma imagem',
            style: TextStyle(color: Color(0xFF7A7280)),
          ),
        ],
      ),
    );
  }
}
