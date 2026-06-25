import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase/supabase.dart';

import '../models/memoria.dart';
import '../models/pessoa.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'curador_screen.dart';

class NovaMemoriaScreen extends StatefulWidget {
  const NovaMemoriaScreen({required this.onSalvar, super.key});

  final Future<Memoria> Function(MemoriaRascunho rascunho) onSalvar;

  @override
  State<NovaMemoriaScreen> createState() => _NovaMemoriaScreenState();
}

class _NovaMemoriaScreenState extends State<NovaMemoriaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tituloController = TextEditingController();
  final _contextoController = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _foto;
  String? _nomeArquivo;
  String _categoria = 'momentos';
  List<int> _pessoasSelecionadas = [];
  List<Pessoa> _todasPessoas = [];
  bool _salvando = false;
  DateTime? _dataMemoria;
  bool _dataMemoriaFoiAlterada = false;
  bool _isCompartilhada = false;
  List<int> _familiaresSelecionados = [];

  @override
  void initState() {
    super.initState();
    _carregarPessoas();
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _contextoController.dispose();
    super.dispose();
  }

  Future<void> _capturarFoto(ImageSource origem) async {
    try {
      final imagem = await _picker.pickImage(
        source: origem,
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (imagem == null) return;

      final bytes = await imagem.readAsBytes();
      if (!mounted) return;
      setState(() {
        _foto = bytes;
        _nomeArquivo = imagem.name;
      });
    } catch (_) {
      if (!mounted) return;
      final mensagem = origem == ImageSource.camera
          ? 'Câmera disponível no app mobile. Escolha uma foto da galeria por enquanto.'
          : 'Não foi possível abrir a galeria. Tente novamente.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensagem)));
    }
  }

  Future<void> _tirarFoto() => _capturarFoto(ImageSource.camera);

  Future<void> _escolherDaGaleria() => _capturarFoto(ImageSource.gallery);

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    try {
      final memoria = await widget.onSalvar(
        MemoriaRascunho(
          titulo: _tituloController.text.trim(),
          contexto: _contextoController.text.trim(),
          categoria: _categoria,
          foto: _foto,
          nomeArquivo: _nomeArquivo,
          pessoasIds: _pessoasSelecionadas.isEmpty
              ? null
              : List<int>.from(_pessoasSelecionadas),
          isCompartilhada: _isCompartilhada,
          familiaresIds: _familiaresSelecionados.isEmpty
              ? null
              : List<int>.from(_familiaresSelecionados),
          dataMemoria: _dataMemoria,
        ),
      );
      if (_pessoasSelecionadas.isNotEmpty && memoria.id != null) {
        await PessoaRepository.salvarVinculo(
          memoria.id!,
          _pessoasSelecionadas,
        );
      }
      if (_isCompartilhada && memoria.id != null) {
        await PessoaRepository.salvarCompartilhamento(
          memoria.id!,
          _familiaresSelecionados,
        );
      }
      if (_dataMemoriaFoiAlterada &&
          _dataMemoria != null &&
          memoria.id != null) {
        await _salvarDataMemoria(memoria.id!, _dataMemoria!);
      }
      if (mounted) Navigator.of(context).pop(memoria);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemDeErro(erro)),
          action: SnackBarAction(label: 'Tentar novamente', onPressed: _salvar),
        ),
    );
  }
}

  Future<void> _escolherDataMemoria() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataMemoria ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() { _dataMemoria = data; _dataMemoriaFoiAlterada = true; });
    }
  }

  Future<void> _salvarDataMemoria(int memoriaId, DateTime data) async {
    await PessoaRepository.salvarDataMemoria(memoriaId, data);
  }

  Future<void> _carregarPessoas() async {
    _todasPessoas = await PessoaRepository.listar();
    if (mounted) setState(() {});
  }

  Future<void> _abrirSelecaoPessoas() async {
    if (!mounted) return;
    final selecionadas = Set<int>.from(_pessoasSelecionadas);

    if (!mounted) return;
    final resultado = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _PessoaPickerSheet(
          selecionadas: selecionadas,
          titulo: 'Quem participou?',
        );
      },
    );

    if (resultado != null && mounted) {
      setState(() => _pessoasSelecionadas = resultado);
    }
  }

  Future<void> _abrirSelecaoFamiliares() async {
    if (!mounted) return;
    final selecionados = Set<int>.from(_familiaresSelecionados);

    if (!mounted) return;
    final resultado = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _PessoaPickerSheet(
          selecionadas: selecionados,
          titulo: 'Selecionar familiares',
        );
      },
    );

    if (resultado != null && mounted) {
      setState(() => _familiaresSelecionados = resultado);
    }
  }

  Future<void> _abrirCurador() async {
    final contexto = _contextoController.text.trim();
    if (contexto.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escreva um pouco sobre este momento antes de aprofundar.'),
        ),
      );
      return;
    }

    final resultado = await Navigator.of(context).push<CuradorResultado>(
      MaterialPageRoute(
        builder: (_) => CuradorScreen(
          titulo: _tituloController.text.trim(),
          contextoOriginal: contexto,
          pessoas: _pessoasSelecionadas
              .map((id) {
                final p = _todasPessoas.firstWhere(
                  (p) => p.id == id,
                  orElse: () => Pessoa(
                    nome: '',
                    parentesco: 'Outro',
                  ),
                );
                return {
                  'nome': p.nome,
                  'parentesco': p.parentesco,
                };
              })
              .where((m) => m['nome']!.isNotEmpty)
              .toList(),
        ),
      ),
    );

    if (resultado == null || !mounted) return;
    _contextoController.text = resultado.contextoEnriquecido;
  }

  String _mensagemDeErro(Object erro) {
    if (erro is SupabaseConfigurationException) {
      return 'Configure a chave pública do Supabase para salvar na aEterna.';
    }
    if (erro is PostgrestException && erro.code == '42501') {
      return 'O Supabase bloqueou a gravação. Configure as políticas RLS do MVP.';
    }
    if (erro is StorageException &&
        (erro.statusCode == '400' || erro.statusCode == '403')) {
      return 'O Supabase bloqueou o envio da foto. Configure a política do bucket fotos.';
    }
    return 'Não foi possível salvar agora. Verifique a conexão e tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar momento')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const Text(
                    'Guarde este instante',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Conte o que esse momento significou para você.',
                    style: TextStyle(
                      color: AppColors.textoSuave,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _FotoEscolhida(
                    foto: _foto,
                    onRemover: () => setState(() {
                      _foto = null;
                      _nomeArquivo = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final botoes = [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _tirarFoto,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tirar foto'),
                          ),
                        ),
                        const SizedBox(width: 12, height: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _escolherDaGaleria,
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
                    controller: _tituloController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      hintText: 'Dê um nome a este momento',
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return 'Escreva um título.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _salvando ? null : _escolherDataMemoria,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data da memória',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        _dataMemoria != null
                            ? '${_dataMemoria!.day.toString().padLeft(2, '0')}/'
                                '${_dataMemoria!.month.toString().padLeft(2, '0')}/'
                                '${_dataMemoria!.year}'
                            : 'Toque para selecionar',
                        style: TextStyle(
                          color: _dataMemoria != null
                              ? AppColors.roxo
                              : const Color(0xFF9B949D),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _categoria,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'momentos',
                        child: Text('Momentos'),
                      ),
                      DropdownMenuItem(
                        value: 'familia',
                        child: Text('Família'),
                      ),
                      DropdownMenuItem(
                        value: 'aprendizados',
                        child: Text('Aprendizados'),
                      ),
                      DropdownMenuItem(
                        value: 'viagens',
                        child: Text('Viagens'),
                      ),
                      DropdownMenuItem(
                        value: 'tradicoes',
                        child: Text('Tradições'),
                      ),
                    ],
                    onChanged: (valor) {
                      if (valor != null) setState(() => _categoria = valor);
                    },
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    value: _isCompartilhada,
                    onChanged: _salvando
                        ? null
                        : (valor) {
                            setState(() {
                              _isCompartilhada = valor;
                              if (!valor) _familiaresSelecionados.clear();
                            });
                          },
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Compartilhar com familiares',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    secondary: const Icon(Icons.share_outlined,
                        color: AppColors.dourado),
                  ),
                  if (_isCompartilhada) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._familiaresSelecionados.map((id) {
                          final pessoa = _todasPessoas.firstWhere(
                            (p) => p.id == id,
                            orElse: () => Pessoa(
                              nome: 'Desconhecido',
                              parentesco: 'Outro',
                            ),
                          );
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor:
                                  const Color(0xFFF0EAF5),
                              backgroundImage: pessoa.fotoBytes != null
                                  ? MemoryImage(pessoa.fotoBytes!)
                                  : null,
                              child: pessoa.fotoBytes == null
                                  ? const Icon(Icons.person,
                                      size: 14, color: AppColors.roxo)
                                  : null,
                            ),
                            label: Text(pessoa.nome),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setState(() => _familiaresSelecionados
                                  .remove(id));
                            },
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: Text(
                            _familiaresSelecionados.isEmpty
                                ? 'Selecionar familiares'
                                : 'Adicionar mais',
                          ),
                          onPressed: _abrirSelecaoFamiliares,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Quem participou deste momento?',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._pessoasSelecionadas.map((id) {
                        final pessoa = _todasPessoas.firstWhere(
                          (p) => p.id == id,
                          orElse: () => Pessoa(
                            nome: 'Desconhecido',
                            parentesco: 'Outro',
                          ),
                        );
                        return Chip(
                          avatar: CircleAvatar(
                            backgroundColor: const Color(0xFFF0EAF5),
                            backgroundImage: pessoa.fotoBytes != null
                                ? MemoryImage(pessoa.fotoBytes!)
                                : null,
                            child: pessoa.fotoBase64 == null
                                ? const Icon(Icons.person,
                                    size: 14, color: AppColors.roxo)
                                : null,
                          ),
                          label: Text(pessoa.nome),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() => _pessoasSelecionadas.remove(id));
                          },
                        );
                      }),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(
                          _pessoasSelecionadas.isEmpty
                              ? 'Adicionar pessoas'
                              : 'Adicionar mais',
                        ),
                        onPressed: _abrirSelecaoPessoas,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _contextoController,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'O que aconteceu?',
                      alignLabelWithHint: true,
                      hintText:
                          'Quem estava com você? Por que este momento foi especial?',
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().length < 5) {
                        return 'Conte um pouco sobre este momento.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _salvando ? null : _abrirCurador,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Aprofundar esta história'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.favorite_outline),
                    label: Text(_salvando ? 'Salvando...' : 'Salvar memória'),
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

class _FotoEscolhida extends StatelessWidget {
  const _FotoEscolhida({required this.foto, required this.onRemover});

  final Uint8List? foto;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    if (foto != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.memory(foto!, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton.filled(
              tooltip: 'Remover foto',
              onPressed: onRemover,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      );
    }

    return Container(
      height: 210,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2D8C8)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 42, color: AppColors.dourado),
          SizedBox(height: 12),
          Text(
            'Adicione uma foto deste momento',
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

class _PessoaPickerSheet extends StatefulWidget {
  const _PessoaPickerSheet({
    required this.selecionadas,
    required this.titulo,
  });

  final Set<int> selecionadas;
  final String titulo;

  @override
  State<_PessoaPickerSheet> createState() => _PessoaPickerSheetState();
}

class _PessoaPickerSheetState extends State<_PessoaPickerSheet> {
  late final Set<int> _sel = Set<int>.from(widget.selecionadas);
  List<Pessoa> _pessoas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final pessoas = await PessoaRepository.listar();
    if (mounted) setState(() { _pessoas = pessoas; _carregando = false; });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (ctx, controller) {
        if (_carregando) {
          return const Center(child: CircularProgressIndicator());
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borda,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.titulo,
                style: const TextStyle(
                  color: AppColors.roxo,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_sel.length} ${_sel.length == 1 ? 'selecionada' : 'selecionadas'}',
                style: const TextStyle(
                  color: Color(0xFF7A7280),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _pessoas.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhuma pessoa cadastrada. Cadastre em Pessoas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF7A7280)),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        itemCount: _pessoas.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 4),
                        itemBuilder: (ctx, index) {
                          final p = _pessoas[index];
                          final sel = _sel.contains(p.id);
                          return CheckboxListTile(
                            value: sel,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _sel.add(p.id);
                                } else {
                                  _sel.remove(p.id);
                                }
                              });
                            },
                            title: Text(
                              p.nome,
                              style: const TextStyle(
                                color: AppColors.roxo,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(p.parentesco),
                            secondary: CircleAvatar(
                              backgroundColor:
                                  const Color(0xFFF0EAF5),
                              backgroundImage: p.fotoBytes != null
                                  ? MemoryImage(p.fotoBytes!)
                                  : null,
                              child: p.fotoBytes == null
                                  ? const Icon(Icons.person,
                                      color: AppColors.roxo)
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(_sel.toList());
                  },
                  child: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
