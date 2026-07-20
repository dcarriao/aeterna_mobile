import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase/supabase.dart';

import '../models/memoria.dart';
import '../models/pessoa.dart';
import '../theme/app_theme.dart';
import 'curador_screen.dart';

import '../models/detected_moment.dart';
import '../models/media_group.dart';
import '../models/pending_memory.dart';
import '../services/curador_sessao_service.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../services/media_suggestion_service.dart';
import '../services/memory_relationship_service.dart';
import 'package:photo_manager/photo_manager.dart';

class NovaMemoriaScreen extends StatefulWidget {
  const NovaMemoriaScreen({
    required this.onSalvar,
    this.memoria,
    this.onEditar,
    this.sugestaoGrupo,
    this.sugestaoPending,
    this.sugestaoMomento,
    this.fotoBytes,
    this.fotoNome,
    this.videoBytes,
    this.videoNome,
    super.key,
  });

  final Future<Memoria> Function(MemoriaRascunho rascunho) onSalvar;
  final Memoria? memoria;
  final Future<Memoria?> Function(MemoriaRascunho rascunho)? onEditar;
  final MediaGroup? sugestaoGrupo;
  final PendingMemory? sugestaoPending;
  final DetectedMoment? sugestaoMomento;
  final Uint8List? fotoBytes;
  final String? fotoNome;
  // Sprint S.9.1 — vídeo compartilhado via Share Extension iOS
  final Uint8List? videoBytes;
  final String? videoNome;

  bool get _editando => memoria != null;

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
  String? _fotoUrlExistente;
  bool _fotoRemovida = false;

  Uint8List? _videoBytes;
  String? _nomeVideo;
  String? _videoUrlExistente;
  bool _videoRemovido = false;

  String _categoria = 'momentos';
  List<int> _pessoasSelecionadas = [];
  List<Pessoa> _todasPessoas = [];
  bool _salvando = false;
  DateTime? _dataMemoria = DateTime.now();
  bool _dataMemoriaFoiAlterada = false;
  bool _isCompartilhada = false;
  List<int> _familiaresSelecionados = [];

  @override
  void initState() {
    super.initState();
    _carregarPessoas();
    final m = widget.memoria;
    if (m != null) {
      _tituloController.text = m.titulo;
      _contextoController.text = m.contexto;
      const categoriasValidas = [
        'momentos',
        'familia',
        'aprendizados',
        'viagens',
        'tradicoes'
      ];
      _categoria =
          categoriasValidas.contains(m.categoria) ? m.categoria : 'momentos';
      _dataMemoria = m.dataMemoria ?? m.criadaEm;
      _dataMemoriaFoiAlterada = m.dataMemoria != null;
      _isCompartilhada = m.isCompartilhada;
      _pessoasSelecionadas = List<int>.from(m.pessoasIds ?? []);
      _familiaresSelecionados = List<int>.from(m.familiaresIds ?? []);
      _foto = m.foto;
      _fotoUrlExistente = m.fotoUrl;
      _carregarVideoExistente(m.id!);
    } else {
      final grupo = widget.sugestaoGrupo;
      final pending = widget.sugestaoPending;
      final momento = widget.sugestaoMomento;
      if (widget.fotoBytes != null) {
        _foto = widget.fotoBytes;
        _nomeArquivo = widget.fotoNome ?? 'foto.jpg';
      } else if (widget.videoBytes != null) {
        // Sprint S.9.1 — vídeo compartilhado via Share Extension iOS
        _videoBytes = widget.videoBytes;
        _nomeVideo = widget.videoNome ?? 'video.mp4';
      } else if (grupo != null) {
        _dataMemoria = grupo.data;
        _dataMemoriaFoiAlterada = true;
        _carregarMidiasDoGrupo(grupo);
      } else if (pending != null) {
        _dataMemoria = pending.data;
        _dataMemoriaFoiAlterada = true;
        _carregarMidiasDoPendente(pending);
      } else if (momento != null) {
        _dataMemoria = momento.inicio;
        _dataMemoriaFoiAlterada = true;
        _carregarMidiasDoMomento(momento);
      }
    }
  }

  Future<void> _carregarMidiasDoMomento(DetectedMoment momento) async {
    if (momento.fotos.isNotEmpty) {
      final file = await momento.fotos.first.file;
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _foto = bytes;
            _nomeArquivo = file.path.split('/').last;
          });
        }
      }
    }
    if (momento.videos.isNotEmpty) {
      final file = await momento.videos.first.file;
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _videoBytes = bytes;
            _nomeVideo = file.path.split('/').last;
          });
        }
      }
    }
  }

  Future<void> _carregarMidiasDoPendente(PendingMemory pending) async {
    if (pending.fotos.isNotEmpty) {
      final file = await pending.fotos.first.file;
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _foto = bytes;
            _nomeArquivo = file.path.split('/').last;
          });
        }
      }
    }
    if (pending.videos.isNotEmpty) {
      final file = await pending.videos.first.file;
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _videoBytes = bytes;
            _nomeVideo = file.path.split('/').last;
          });
        }
      }
    }
  }

  Future<void> _carregarMidiasDoGrupo(MediaGroup grupo) async {
    for (final midia in grupo.midias) {
      final file = await midia.asset.file;
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          if (midia.tipo == AssetType.image) {
            _foto = bytes;
            _nomeArquivo = file.path.split('/').last;
          } else if (midia.tipo == AssetType.video) {
            _videoBytes = bytes;
            _nomeVideo = file.path.split('/').last;
          }
        });
      }
    }
  }

  Future<void> _carregarVideoExistente(int memoriaId) async {
    final url = await PessoaRepository.obterVideoDaMemoria(memoriaId);
    if (mounted && url != null) {
      setState(() {
        _videoUrlExistente = url;
      });
    }
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _contextoController.dispose();
    super.dispose();
  }

  Future<void> _carregarPessoas() async {
    print('[NovaMemoriaScreen] _carregarPessoas() iniciando');
    _todasPessoas = await PessoaRepository.listar();
    print(
        '[NovaMemoriaScreen] _carregarPessoas() -> ${_todasPessoas.length} pessoas carregadas');
    if (mounted) setState(() {});
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
        _fotoRemovida = false;
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

  Future<void> _capturarVideo() async {
    try {
      final video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null) return;

      final bytes = await video.readAsBytes();
      if (!mounted) return;
      setState(() {
        _videoBytes = bytes;
        _nomeVideo = video.name;
        _videoRemovido = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar o vídeo.')),
      );
    }
  }

  Future<void> _tirarFoto() => _capturarFoto(ImageSource.camera);

  Future<void> _escolherDaGaleria() => _capturarFoto(ImageSource.gallery);

  void _abrirOpcoesFoto() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_outlined, color: AppColors.roxo),
              title: const Text('Tirar foto',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                _tirarFoto();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: AppColors.roxo),
              title: const Text('Escolher da Galeria',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                _escolherDaGaleria();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _escolherDataMemoria() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataMemoria ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (data != null && mounted) {
      setState(() {
        _dataMemoria = data;
        _dataMemoriaFoiAlterada = true;
      });
    }
  }

  Future<void> _salvarDataMemoria(int memoriaId, DateTime data) async {
    await PessoaRepository.salvarDataMemoria(memoriaId, data);
  }

  // S.9.3.1 (Item 10) — seletores separados: pessoas ≠ pets.
  // Participação (quem aparece na memória) aceita humanos E pets, mas em
  // seletores distintos. Compartilhamento (permissões) aceita SOMENTE
  // humanos: pet não recebe permissão, push, nem autentica.
  Future<void> _abrirSelecaoPessoas() async {
    if (!mounted) return;
    // Mantém no set apenas os já selecionados do mesmo filtro
    final selecionadas = Set<int>.from(_pessoasSelecionadas);

    final resultado = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return PessoaPickerSheet(
          selecionadas: selecionadas,
          titulo: 'Quem participou?',
          filtro: PessoaPickerFiltro.humanos,
        );
      },
    );

    if (resultado != null && mounted) {
      // Preserva pets já selecionados (gerenciados pelo outro seletor)
      final petsJaSelecionados = _pessoasSelecionadas
          .where((id) => _todasPessoas.any((p) => p.id == id && p.isPet))
          .toList();
      setState(() =>
          _pessoasSelecionadas = [...resultado, ...petsJaSelecionados]);
      _carregarPessoas();
    }
  }

  /// S.9.3.1 (Item 10) — seletor exclusivo de pets como participantes.
  Future<void> _abrirSelecaoPets() async {
    if (!mounted) return;
    final selecionados = Set<int>.from(_pessoasSelecionadas);

    final resultado = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return PessoaPickerSheet(
          selecionadas: selecionados,
          titulo: 'Quais pets participaram?',
          filtro: PessoaPickerFiltro.pets,
        );
      },
    );

    if (resultado != null && mounted) {
      // Preserva humanos já selecionados (gerenciados pelo outro seletor)
      final humanosJaSelecionados = _pessoasSelecionadas
          .where((id) => !_todasPessoas.any((p) => p.id == id && p.isPet))
          .toList();
      setState(() =>
          _pessoasSelecionadas = [...humanosJaSelecionados, ...resultado]);
      _carregarPessoas();
    }
  }

  Future<void> _abrirSelecaoFamiliares() async {
    if (!mounted) return;
    final selecionados = Set<int>.from(_familiaresSelecionados);

    final resultado = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return PessoaPickerSheet(
          selecionadas: selecionados,
          titulo: 'Selecionar pessoas',
          // Compartilhamento: pet NUNCA é destinatário de permissão.
          filtro: PessoaPickerFiltro.humanos,
        );
      },
    );

    if (resultado != null && mounted) {
      setState(() => _familiaresSelecionados = resultado);
      _carregarPessoas();
    }
  }

  Future<void> _abrirCurador() async {
    final contexto = _contextoController.text.trim();
    final isProativo = widget.sugestaoGrupo != null || widget.sugestaoPending != null || widget.sugestaoMomento != null;

    if (!isProativo && contexto.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Escreva um pouco sobre este momento antes de aprofundar.'),
        ),
      );
      return;
    }

    // Sprint J — Se já existe sessão ativa do Curador Contextual para
    // o usuário, retoma automaticamente (a Home também oferece a opção
    // de "continuar"). Isso garante que o Curador tenha memória de
    // contexto da conversa anterior.
    final sessaoAtiva =
        await CuradorSessaoService.instance.obterSessaoAtiva();
    if (sessaoAtiva != null && !isProativo) {
      final retomar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Você tem uma conversa em andamento',
              style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold)),
          content: const Text(
            'Deseja continuar de onde parou? O Curador vai lembrar do que você já contou.',
            style: TextStyle(color: Color(0xFF625B67), fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Começar nova',
                  style: TextStyle(color: Color(0xFF7A7280))),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
              child: const Text('Continuar conversa'),
            ),
          ],
        ),
      );
      if (retomar == true) {
        // Cancelar a sessão atual antes de criar uma nova (para não
        // conflitar com a UNIQUE index de 1 sessão em_andamento).
        await CuradorSessaoService.instance.cancelarSessao(sessaoAtiva.id!);
      } else {
        await CuradorSessaoService.instance.cancelarSessao(sessaoAtiva.id!);
      }
    }

    final resultado = await Navigator.of(context).push<CuradorResultado>(
      MaterialPageRoute(
        builder: (_) => CuradorScreen(
          titulo: _tituloController.text.trim(),
          contextoOriginal: contexto,
          dataMemoria: _dataMemoria,
          categoria: _categoria,
          isProativo: isProativo,
          proativoMediaBytes: _foto ?? _videoBytes,
          proativoMediaIsVideo: _videoBytes != null,
          proativoFotosCount: widget.sugestaoGrupo?.totalFotos ?? widget.sugestaoPending?.quantidadeFotos ?? widget.sugestaoMomento?.quantidadeFotos ?? 0,
          proativoVideosCount: widget.sugestaoGrupo?.totalVideos ?? widget.sugestaoPending?.quantidadeVideos ?? widget.sugestaoMomento?.quantidadeVideos ?? 0,
          pendingMemory: widget.sugestaoPending,
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

  /// Regra de produto (Darlan, S.9.3.2): todo PARTICIPANTE humano recebe
  /// o compartilhamento automaticamente (quem estava no balão vê a foto);
  /// compartilhados extras não precisam ser participantes; pet participa
  /// mas nunca recebe permissão/push.
  List<int> _compartilhadosEfetivos() {
    final humanosParticipantes = _pessoasSelecionadas.where((id) {
      final p = _todasPessoas.where((x) => x.id == id).firstOrNull;
      return p == null || !p.isPet;
    });
    return <int>{..._familiaresSelecionados, ...humanosParticipantes}.toList();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_salvando) return;

    setState(() => _salvando = true);
    try {
      await _executarSalvar().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw TimeoutException(
            'O salvamento demorou demais. Verifique a conexão e tente de novo.',
          );
        },
      );
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

  Future<void> _executarSalvar() async {
      if (widget._editando && widget.onEditar != null) {
        final m = widget.memoria!;
        final rascunho = MemoriaRascunho(
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
        );

        await PessoaRepository.atualizarMemoria(
          memoriaId: m.id!,
          titulo: rascunho.titulo,
          contexto: rascunho.contexto,
          categoria: rascunho.categoria,
          dataEvento: _dataMemoria,
          isCompartilhada: _isCompartilhada,
        );

        await PessoaRepository.salvarVinculo(
          m.id!,
          _pessoasSelecionadas,
        );
        await PessoaRepository.salvarCompartilhamento(
          m.id!,
          _compartilhadosEfetivos(),
        );

        String? novaFotoUrl = m.fotoUrl;
        if (_fotoRemovida) {
          await PessoaRepository.removerFotosDaMemoria(m.id!);
          novaFotoUrl = null;
        } else if (_foto != null) {
          await PessoaRepository.removerFotosDaMemoria(m.id!);
          novaFotoUrl = await PessoaRepository.uploadFotoMemoria(
            memoriaId: m.id!,
            bytes: _foto!,
            nomeArquivo: _nomeArquivo ?? 'foto.jpg',
          );
        }

        String? novoVideoUrl = m.videoUrl;
        if (_videoRemovido) {
          await PessoaRepository.removerVideosDaMemoria(m.id!);
          novoVideoUrl = null;
        } else if (_videoBytes != null) {
          await PessoaRepository.removerVideosDaMemoria(m.id!);
          novoVideoUrl = await PessoaRepository.uploadVideoMemoria(
            memoriaId: m.id!,
            bytes: _videoBytes!,
            nomeArquivo: _nomeVideo ?? 'video.mp4',
          );
        }

        if (_dataMemoria != null) {
          await PessoaRepository.salvarDataMemoria(m.id!, _dataMemoria!);
        }

        if (mounted) {
          final atualizada = Memoria(
            titulo: rascunho.titulo,
            contexto: rascunho.contexto,
            categoria: rascunho.categoria,
            criadaEm: _dataMemoria ?? m.criadaEm,
            id: m.id,
            foto: _foto ?? (_fotoRemovida ? null : m.foto),
            fotoUrl: novaFotoUrl,
            pessoasIds: rascunho.pessoasIds,
            isCompartilhada: _isCompartilhada,
            familiaresIds: rascunho.familiaresIds,
            dataMemoria: _dataMemoria,
            video: _videoBytes ?? (_videoRemovido ? null : m.video),
            videoUrl: novoVideoUrl,
            temVideo: novoVideoUrl != null ||
                (_videoBytes != null) ||
                (m.temVideo && !_videoRemovido),
          );
          Navigator.of(context).pop(atualizada);
        }
        return;
      }

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
          video: _videoBytes,
          nomeVideo: _nomeVideo,
        ),
      );
      if (_pessoasSelecionadas.isNotEmpty && memoria.id != null) {
        await PessoaRepository.salvarVinculo(
          memoria.id!,
          _pessoasSelecionadas,
        );
      }
      if (memoria.id != null) {
        // participantes humanos entram SEMPRE no compartilhamento
        await PessoaRepository.salvarCompartilhamento(
          memoria.id!,
          _compartilhadosEfetivos(),
        );
      }
      if (memoria.id != null) {
        await PessoaRepository.atualizarVisibilidadeMemoria(
          memoria.id!,
          _isCompartilhada,
        );
      }
      if (_dataMemoria != null && memoria.id != null) {
        await _salvarDataMemoria(memoria.id!, _dataMemoria!);
      }

      String? criadoVideoUrl;
      if (_videoBytes != null && memoria.id != null) {
        criadoVideoUrl = await PessoaRepository.uploadVideoMemoria(
          memoriaId: memoria.id!,
          bytes: _videoBytes!,
          nomeArquivo: _nomeVideo ?? 'video.mp4',
        );
      }

      if (widget.sugestaoGrupo != null) {
        for (final m in widget.sugestaoGrupo!.midias) {
          await MediaSuggestionService.instance.registrarAssetComoUtilizado(m.id);
        }
      } else if (widget.sugestaoPending != null) {
        for (final f in widget.sugestaoPending!.fotos) {
          await MediaSuggestionService.instance.registrarAssetComoUtilizado(f.id);
        }
        for (final v in widget.sugestaoPending!.videos) {
          await MediaSuggestionService.instance.registrarAssetComoUtilizado(v.id);
        }
      } else if (widget.sugestaoMomento != null) {
        for (final f in widget.sugestaoMomento!.fotos) {
          await MediaSuggestionService.instance.registrarAssetComoUtilizado(f.id);
        }
        for (final v in widget.sugestaoMomento!.videos) {
          await MediaSuggestionService.instance.registrarAssetComoUtilizado(v.id);
        }
      }

      if (mounted) {
        final finalMemoria = Memoria(
          titulo: memoria.titulo,
          contexto: memoria.contexto,
          categoria: memoria.categoria,
          criadaEm: _dataMemoria ?? memoria.criadaEm, // Bug 5 Fix!
          id: memoria.id,
          foto: memoria.foto,
          fotoUrl: memoria.fotoUrl,
          pessoasIds: _pessoasSelecionadas.isEmpty ? null : _pessoasSelecionadas,
          isCompartilhada: _isCompartilhada,
          familiaresIds: _familiaresSelecionados.isEmpty ? null : _familiaresSelecionados,
          dataMemoria: _dataMemoria,
          video: _videoBytes,
          videoUrl: criadoVideoUrl,
          temVideo: criadoVideoUrl != null || _videoBytes != null,
        );
        // S.9.3.2 (Item 5) — CAUSA DA TELA PRETA: após este pop, a
        // execução CONTINUAVA e chegava ao pop() de fallback logo
        // abaixo — DOIS pops seguidos derrubavam também a tela de baixo
        // (restava rota nenhuma = tela preta). O hook roda antes e
        // encerramos aqui.
        // ignore: unawaited_futures
        MemoryRelationshipService.instance.aoSalvarMemoria(memoria.id!);
        Navigator.of(context).pop(finalMemoria);
        return;
      }

      // Sprint K — hook incremental: após salvar a memória, dispara o
      // cálculo de relações (sem O(n²) — só para esta memória).
      // Fire-and-forget: falha no relacionamento não impede a memória de
      // ter sido salva.
      // ignore: unawaited_futures
      MemoryRelationshipService.instance
          .aoSalvarMemoria(memoria.id!);

      if (!mounted) return;
      // Tenta devolver a versão completa (com id) ao caller. Se a
      // construção de finalMemoria não chegou a rodar, devolve só o
      // rascunho para que a navegação continue funcionando.
      Navigator.of(context).pop(memoria);
  }

  String _mensagemDeErro(Object erro) {
    if (erro is TimeoutException) {
      return erro.message ??
          'O salvamento demorou demais. Tente novamente.';
    }
    if (erro is PostgrestException && erro.code == '42501') {
      return 'O Supabase bloqueou a gravação. Configure as políticas RLS do MVP.';
    }
    if (erro is StorageException &&
        (erro.statusCode == '400' || erro.statusCode == '403')) {
      return 'O Supabase bloqueou o envio da foto. Configure a política do bucket fotos.';
    }
    // Mostra erro real para diagnóstico
    final msg = erro.toString();
    if (msg.contains('TimeoutException') || msg.contains('demorou demais')) {
      return 'O salvamento demorou demais. Verifique a conexão e tente de novo.';
    }
    if (msg.contains('unique') || msg.contains('duplicate')) {
      return 'Registro duplicado. Verifique se já existe.';
    }
    if (msg.contains('permission') || msg.contains('policy')) {
      return 'Permissão negada. Verifique as políticas RLS.';
    }
    if (msg.contains('foreign key') || msg.contains('violates')) {
      return 'Erro de referência. Verifique os dados vinculados.';
    }
    return 'Erro: $msg';
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.roxo,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPhotoHero() {
    final temFoto = _foto != null || (_fotoUrlExistente != null && !_fotoRemovida);
    return Center(
      child: Container(
        height: 240,
        width: double.infinity,
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_foto != null)
                Image.memory(
                  _foto!,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                )
              else if (_fotoUrlExistente != null && !_fotoRemovida)
                Image.network(
                  _fotoUrlExistente!,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                )
              else
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined,
                          size: 48, color: AppColors.dourado),
                      SizedBox(height: 12),
                      Text(
                        'Adicione uma foto',
                        style: TextStyle(
                          color: AppColors.roxo,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              // Botão de câmera sobreposto no canto inferior direito
              Positioned(
                bottom: 12,
                right: 12,
                child: FloatingActionButton.small(
                  heroTag: 'camera_btn',
                  onPressed: _salvando ? null : _abrirOpcoesFoto,
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.camera_alt_outlined, size: 18),
                ),
              ),
              // Botão de remover foto se houver
              if (temFoto)
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    radius: 18,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _foto = null;
                          _nomeArquivo = null;
                          _fotoRemovida = true;
                        });
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoHero() {
    final temVideo = _videoBytes != null || (_videoUrlExistente != null && !_videoRemovido);
    return Center(
      child: Container(
        height: 140,
        width: double.infinity,
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (temVideo)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.video_library_outlined, size: 40, color: AppColors.roxo),
                      const SizedBox(height: 8),
                      Text(
                        _nomeVideo ?? 'Vídeo da memória',
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_videoUrlExistente != null && _videoBytes == null)
                        const Text(
                          'Vídeo salvo no Supabase',
                          style: TextStyle(color: AppColors.textoSuave, fontSize: 11),
                        ),
                    ],
                  ),
                )
              else
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.video_call_outlined, size: 42, color: AppColors.dourado),
                      SizedBox(height: 8),
                      Text(
                        'Adicione um vídeo',
                        style: TextStyle(
                          color: AppColors.roxo,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              // Botão de câmera/vídeo sobreposto no canto inferior direito
              Positioned(
                bottom: 12,
                right: 12,
                child: FloatingActionButton.small(
                  heroTag: 'video_btn',
                  onPressed: _salvando ? null : _capturarVideo,
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.video_call_outlined, size: 18),
                ),
              ),
              // Botão de remover vídeo se houver
              if (temVideo)
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    radius: 18,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _videoBytes = null;
                          _nomeVideo = null;
                          _videoRemovido = true;
                        });
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 44),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  // ── HERO DE FOTO ──
                  _buildPhotoHero(),
                  const SizedBox(height: 16),
                  // ── HERO DE VÍDEO ──
                  _buildVideoHero(),
                  const SizedBox(height: 24),

                  // ── CAMPO TÍTULO ──
                  _buildFieldLabel('Título da memória'),
                  TextFormField(
                    controller: _tituloController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Dê um nome a este momento',
                      prefixIcon: Icon(Icons.title_outlined, color: AppColors.dourado, size: 20),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return 'Escreva um título.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── CAMPO DATA ──
                  _buildFieldLabel('Data da memória'),
                  InkWell(
                    onTap: _salvando ? null : _escolherDataMemoria,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.calendar_today_outlined, color: AppColors.dourado, size: 20),
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
                  const SizedBox(height: 20),

                  // ── CAMPO CATEGORIA ──
                  _buildFieldLabel('Categoria'),
                  DropdownButtonFormField<String>(
                    initialValue: _categoria,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.label_outline, color: AppColors.dourado, size: 20),
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

                  // ── SEÇÃO COMPARTILHAMENTO ──
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEDE8DC)),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _isCompartilhada,
                          onChanged: (valor) {
                            if (_salvando) return;
                            setState(() {
                              _isCompartilhada = valor;
                              if (!valor) _familiaresSelecionados.clear();
                            });
                          },
                          activeThumbColor: AppColors.roxo,
                          title: const Text(
                            'Compartilhar com familiares',
                            style: TextStyle(
                              color: AppColors.roxo,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          secondary: const Icon(Icons.share_outlined,
                              color: AppColors.dourado, size: 20),
                        ),
                        if (_isCompartilhada) ...[
                          const Divider(height: 1, color: Color(0xFFEDE8DC)),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ..._familiaresSelecionados.map((id) {
                                  final p = _todasPessoas.firstWhere(
                                    (p) => p.id == id,
                                    orElse: () => Pessoa(
                                      nome: 'Desconhecido',
                                      parentesco: 'Outro',
                                    ),
                                  );
                                  return Chip(
                                    avatar: CircleAvatar(
                                      backgroundColor: const Color(0xFFF0EAF5),
                                      backgroundImage: p.fotoBytes != null
                                          ? MemoryImage(p.fotoBytes!)
                                          : null,
                                      child: p.fotoBytes == null
                                          ? const Icon(Icons.person,
                                              size: 14, color: AppColors.roxo)
                                          : null,
                                    ),
                                    label: Text(p.nome, style: const TextStyle(fontSize: 12)),
                                    deleteIcon: const Icon(Icons.close, size: 14),
                                    onDeleted: () {
                                      setState(() => _familiaresSelecionados.remove(id));
                                    },
                                  );
                                }),
                                ActionChip(
                                  avatar: const Icon(Icons.add, size: 14),
                                  label: Text(
                                    _familiaresSelecionados.isEmpty
                                        ? 'Selecionar familiares'
                                        : 'Adicionar mais',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onPressed: _abrirSelecaoFamiliares,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── SEÇÃO PARTICIPANTES ──
                  _buildFieldLabel('Quem participou deste momento?'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEDE8DC)),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._pessoasSelecionadas.map((id) {
                          final p = _todasPessoas.firstWhere(
                            (p) => p.id == id,
                            orElse: () => Pessoa(
                              nome: 'Desconhecido',
                              parentesco: 'Outro',
                            ),
                          );
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: const Color(0xFFF0EAF5),
                              backgroundImage: p.fotoBytes != null
                                  ? MemoryImage(p.fotoBytes!)
                                  : null,
                              child: p.fotoBytes == null
                                  ? Icon(
                                      // S.9.3.1 — pata para pets
                                      p.isPet ? Icons.pets : Icons.person,
                                      size: 14,
                                      color: AppColors.roxo)
                                  : null,
                            ),
                            label: Text(p.nome, style: const TextStyle(fontSize: 12)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() => _pessoasSelecionadas.remove(id));
                            },
                          );
                        }),
                        // S.9.3.1 (Item 10) — seletores separados
                        ActionChip(
                          avatar: const Icon(Icons.person_add_alt,
                              size: 14),
                          label: const Text(
                            'Adicionar pessoas',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: _abrirSelecaoPessoas,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.pets, size: 14),
                          label: const Text(
                            'Adicionar pets',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: _abrirSelecaoPets,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── CAMPO CONTEXTO ──
                  _buildFieldLabel('O que aconteceu?'),
                  TextFormField(
                    controller: _contextoController,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 5,
                    maxLines: 12,
                    decoration: const InputDecoration(
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

                  // ── BOTÃO CURADOR ──
                  OutlinedButton.icon(
                    onPressed: _salvando ? null : _abrirCurador,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.roxo,
                      side: const BorderSide(color: AppColors.borda),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Aprofundar esta história'),
                  ),
                  const SizedBox(height: 28),

                  // ── BOTÃO SALVAR ──
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.roxo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _salvando
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.favorite_outline, size: 18),
                    label: Text(
                      _salvando
                          ? 'Salvando...'
                          : widget._editando
                              ? 'Salvar alterações'
                              : 'Salvar memória',
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

/// S.9.3.1 (Item 10) — filtro do seletor: humanos ou pets, nunca misturado.
enum PessoaPickerFiltro { humanos, pets }

class PessoaPickerSheet extends StatefulWidget {
  const PessoaPickerSheet({
    required this.selecionadas,
    required this.titulo,
    this.filtro = PessoaPickerFiltro.humanos,
    this.excluirIds = const {},
    this.excluirFalecido = false,
  });

  final Set<int> selecionadas;
  final String titulo;
  final PessoaPickerFiltro filtro;
  /// IDs ocultos do seletor (ex.: pessoa que o memorial representa).
  final Set<int> excluirIds;
  /// Memorial: falecido nunca é alvo de compartilhamento.
  final bool excluirFalecido;

  @override
  State<PessoaPickerSheet> createState() => _PessoaPickerSheetState();
}

class _PessoaPickerSheetState extends State<PessoaPickerSheet> {
  late final Set<int> _sel = Set<int>.from(widget.selecionadas);
  List<Map<String, dynamic>> _pessoas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    print('[PessoaPickerSheet] _carregar() iniciando filtro=${widget.filtro}');
    final todas = await PessoaRelacionamentoService.instance.listarContatos();
    // S.9.3.1 (Item 10) — separa humanos de pets pelo pessoas.tipo.
    final pessoas = todas.where((m) {
      final ehPet = (m['tipo'] as String?) == 'pet';
      final tipoOk =
          widget.filtro == PessoaPickerFiltro.pets ? ehPet : !ehPet;
      if (!tipoOk) return false;
      final id = m['pessoa_b_id'] as int;
      if (widget.excluirIds.contains(id)) return false;
      if (widget.excluirFalecido && (m['falecido'] as bool? ?? false)) {
        return false;
      }
      return true;
    }).toList();
    print('[PessoaPickerSheet] _carregar() -> ${pessoas.length} de ${todas.length}');
    if (mounted) {
      setState(() {
        _pessoas = pessoas;
        _carregando = false;
      });
    }
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_sel.length} ${_sel.length == 1 ? 'selecionada' : 'selecionadas'}',
                    style: const TextStyle(
                      color: Color(0xFF7A7280),
                      fontSize: 14,
                    ),
                  ),
                  if (_pessoas.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                            setState(() {
                                if (_sel.length == _pessoas.length) {
                                  _sel.clear();
                                } else {
                                  _sel.clear();
                                  _sel.addAll(_pessoas
                                      .map((m) => m['pessoa_b_id'] as int));
                                }
                              });
                      },
                      child: Text(
                        _sel.length == _pessoas.length ? 'Limpar Seleção' : 'Selecionar Todos',
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _pessoas.isEmpty
                    ? Center(
                        child: Text(
                          widget.filtro == PessoaPickerFiltro.pets
                              ? 'Nenhum pet cadastrado. Cadastre em Pets.'
                              : 'Nenhuma pessoa cadastrada. Cadastre em Pessoas.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF7A7280)),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        itemCount: _pessoas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (ctx, index) {
                          final r = _pessoas[index];
                          final pId = r['pessoa_b_id'] as int;
                          final nome = r['nome'] as String? ?? '';
                          final label = r['relacao_b_para_a'] as String? ?? '';
                          final sel = _sel.contains(pId);
                          return CheckboxListTile(
                            value: sel,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _sel.add(pId);
                                } else {
                                  _sel.remove(pId);
                                }
                              });
                            },
                            title: Text(
                              nome,
                              style: const TextStyle(
                                color: AppColors.roxo,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: label.isNotEmpty ? Text(label) : null,
                            secondary: CircleAvatar(
                              backgroundColor: const Color(0xFFF0EAF5),
                              child: Icon(
                                widget.filtro == PessoaPickerFiltro.pets
                                    ? Icons.pets
                                    : Icons.person,
                                color: AppColors.roxo,
                              ),
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
                    // Retorna somente ids visíveis neste filtro — ids do
                    // outro grupo (pré-selecionados) são preservados pelo
                    // chamador.
                    final visiveis = _pessoas
                        .map((m) => m['pessoa_b_id'] as int)
                        .toSet();
                    Navigator.of(ctx)
                        .pop(_sel.where(visiveis.contains).toList());
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
