import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';

import 'models/memoria.dart';
import 'models/pessoa.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/memoria_detalhe_screen.dart';
import 'screens/minha_historia_screen.dart';
import 'screens/nova_memoria_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/perfil_screen.dart';
import 'services/legacy_curator_service.dart';
import 'screens/compartilhadas_screen.dart';
import 'screens/pessoas_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/memoriais_screen.dart';
import 'services/supabase_service.dart';
import 'services/curator_invitation_service.dart';
import 'services/memory_growth_invitation_service.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sprint R.4 — Firebase DEVE ser inicializado antes de qualquer
  // outro serviço que dependa de plataforma (ex: Supabase usa
  // `firebase_messaging` via method channel em alguns cenários).
  await PushNotificationService.instance.initialize();
  await SupabaseService.initialize();
  await LegacyCuratorService.initialize();
  await CuratorInvitationService.instance.inicializar();
  // Sprint I — Curador de Memórias Contínuas: inicializa o canal
  // de notificação próprio e agenda o job do Workmanager.
  await MemoryGrowthInvitationService.instance.inicializar();
  await MemoryGrowthInvitationService.instance.registrarVerificacaoPeriodica();
  runApp(const AeternaApp());
}

// Sprint S.9.1 — dados de mídia recebidos da Share Extension iOS.
// Armazenados em memória durante o cold-start até o Navigator estar pronto.
class _PendingShare {
  final Uint8List bytes;
  final String filename;
  final bool isVideo;
  _PendingShare({
    required this.bytes,
    required this.filename,
    required this.isVideo,
  });
}

class AeternaApp extends StatefulWidget {
  const AeternaApp({super.key});

  @override
  State<AeternaApp> createState() => _AeternaAppState();
}

class _AeternaAppState extends State<AeternaApp> with WidgetsBindingObserver {
  final _service = SupabaseService.instance;
  final List<Memoria> _memorias = [];
  final List<Memoria> _memoriasRecebidas = [];
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _mostrarOnboarding = true;
  bool _entrou = false;
  bool _carregandoMemorias = false;
  String? _usuarioFotoUrl;
  late final AppLinks _appLinks;
  static const _androidShareChannel = MethodChannel('com.aeterna.app/share');
  // Sprint S.9.1 — mídia pendente da Share Extension (cold-start race condition)
  _PendingShare? _pendingShare;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verificarOnboarding();
    _carregarSessao();
    _configurarDeepLinks();
    _verificarCompartilhamentoAndroid();
    // Sprint S.9.2 — registra callback de navegação para pushes
    PushNotificationService.instance.setNavigationCallback(_navegarViaPush);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verificarCompartilhamentoAndroid();
    }
  }

  Future<void> _verificarCompartilhamentoAndroid() async {
    try {
      final String? path = await _androidShareChannel.invokeMethod('getSharedImage');
      if (path != null && path.isNotEmpty) {
        _processarImagemAndroid(path);
      }
    } catch (e) {
      print('[AndroidShare] Erro ao verificar compartilhamento: $e');
    }
  }

  Future<void> _processarImagemAndroid(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final filename = path.split('/').last;
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => NovaMemoriaScreen(
              onSalvar: _service.salvarMemoriaComFoto,
              fotoBytes: bytes,
              fotoNome: filename,
            ),
          ),
        );
      }
    } catch (e) {
      print('[AndroidShare] Erro ao carregar imagem compartilhada: $e');
    }
  }

  void _configurarDeepLinks() {
    _appLinks = AppLinks();
    _appLinks.uriLinkStream.listen((uri) {
      _processarLinkCompartilhamento(uri);
    });
    _appLinks.getInitialAppLink().then((uri) {
      if (uri != null) {
        _processarLinkCompartilhamento(uri);
      }
    });
  }

  // Sprint S.9.1 — processa deep link da Share Extension iOS.
  // Suporta dois formatos:
  //   aeterna://share?manifest=<encoded_path>  (novo — preferencial)
  //   aeterna://share?image=<encoded_path>     (legado — mantido por compatibilidade)
  Future<void> _processarLinkCompartilhamento(Uri uri) async {
    print('[FLUTTER_SHARE] Deep link recebido: $uri');
    if (uri.scheme != 'aeterna' || uri.host != 'share') return;

    final manifestPath = uri.queryParameters['manifest'];
    if (manifestPath != null && manifestPath.isNotEmpty) {
      await _processarManifest(manifestPath);
      return;
    }

    // Legado: ?image=<path>
    final imagePath = uri.queryParameters['image'];
    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        final file = File(imagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final filename = imagePath.split('/').last;
          _agendarNavegacaoShare(_PendingShare(
            bytes: bytes,
            filename: filename,
            isVideo: false,
          ));
        }
      } catch (e) {
        print('[FLUTTER_SHARE] Erro ao processar imagem legada: $e');
      }
    }
  }

  // Lê o manifest.json escrito pela Share Extension, extrai mídia e agenda navegação.
  Future<void> _processarManifest(String manifestPath) async {
    try {
      final manifestFile = File(manifestPath);
      if (!await manifestFile.exists()) {
        print('[FLUTTER_SHARE] manifest.json não encontrado: $manifestPath');
        return;
      }

      final content = await manifestFile.readAsString();
      final Map<String, dynamic> manifest = jsonDecode(content) as Map<String, dynamic>;
      final shareId   = manifest['share_id']   as String? ?? '';
      final filePath  = manifest['file_path']  as String? ?? '';
      final mediaType = manifest['media_type'] as String? ?? 'image';

      print('[FLUTTER_SHARE] Manifest lido — share_id=$shareId media_type=$mediaType');

      // Dedup: evita processar o mesmo compartilhamento duas vezes
      final prefs = await SharedPreferences.getInstance();
      final lastShareId = prefs.getString('last_share_id') ?? '';
      if (shareId.isNotEmpty && shareId == lastShareId) {
        print('[FLUTTER_SHARE] share_id duplicado — ignorando');
        return;
      }
      if (shareId.isNotEmpty) {
        await prefs.setString('last_share_id', shareId);
      }

      final mediaFile = File(filePath);
      if (!await mediaFile.exists()) {
        print('[FLUTTER_SHARE] Arquivo de mídia não encontrado: $filePath');
        return;
      }

      final bytes    = await mediaFile.readAsBytes();
      final filename = filePath.split('/').last;
      final isVideo  = mediaType == 'video';

      // Limpa arquivos temporários do container
      try {
        await manifestFile.delete();
        await mediaFile.delete();
      } catch (_) {}

      print('[FLUTTER_SHARE] Mídia carregada (${bytes.length} bytes) isVideo=$isVideo');
      _agendarNavegacaoShare(_PendingShare(
        bytes: bytes,
        filename: filename,
        isVideo: isVideo,
      ));
    } catch (e) {
      print('[FLUTTER_SHARE] Erro ao processar manifest: $e');
    }
  }

  // Agenda navegação para NovaMemoriaScreen com retry por frame até o Navigator estar pronto.
  void _agendarNavegacaoShare(_PendingShare share) {
    _pendingShare = share;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tentarNavegacaoPendente());
  }

  // Chamado em cada frame até conseguir navegar (resolve race condition de cold-start).
  void _tentarNavegacaoPendente() {
    final share = _pendingShare;
    if (share == null) return;

    final nav = _navigatorKey.currentState;
    if (nav == null || !_entrou) {
      // Navigator ainda não está pronto ou usuário não está logado — tentar no próximo frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _tentarNavegacaoPendente());
      return;
    }

    _pendingShare = null;
    _navegarParaNovaMemoria(share);
  }

  void _navegarParaNovaMemoria(_PendingShare share) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => NovaMemoriaScreen(
          onSalvar: _service.salvarMemoriaComFoto,
          fotoBytes: share.isVideo ? null : share.bytes,
          fotoNome:  share.isVideo ? null : share.filename,
          videoBytes: share.isVideo ? share.bytes : null,
          videoNome:  share.isVideo ? share.filename : null,
        ),
      ),
    );
  }

  Future<void> _carregarSessao() async {
    final prefs = await SharedPreferences.getInstance();
    final logado = prefs.getBool('is_logged_in') ?? false;
    if (!logado) {
      _carregarUsuario();
      _carregarMemorias();
      return;
    }

    // Ler session_pessoa_id (novo nome) com fallback para session_user_id (legado)
    final sessionPessoaId = prefs.getInt('session_pessoa_id');
    final sessionUserId = prefs.getInt('session_user_id');
    final email = prefs.getString('session_user_email');

    // Se só temos o ID legado (session_user_id), mapear para o novo pessoas.id
    int? uid = sessionPessoaId;
    if (uid == null && sessionUserId != null && sessionUserId > 0) {
      try {
        final rows = await PessoaRepository.supabaseClient
            .from('pessoas')
            .select('id')
            .eq('_legacy_usuario_id', sessionUserId)
            .limit(1);
        if (rows.isNotEmpty) {
          uid = (rows.first['id'] as num).toInt();
          await prefs.setInt('session_pessoa_id', uid);
        }
      } catch (_) {}
      // Se não achou mapeamento, usar o legado como fallback
      uid ??= sessionUserId;
    }

    if (uid != null && uid > 0) {
      PessoaRepository.usuarioId = uid;
      SupabaseService.usuarioId = uid;
      if (email != null) PessoaRepository.usuarioEmail = email;
      // Sprint R.4 — associa o token FCM ao usuário restaurado
      PushNotificationService.instance.salvarTokenParaUsuario();
      if (mounted) {
        setState(() => _entrou = true);
        _carregarUsuario();
        _carregarMemorias();
        // Sprint S.9.1 — tenta navegar para mídia pendente da Share Extension
        WidgetsBinding.instance.addPostFrameCallback((_) => _tentarNavegacaoPendente());
      }
      return;
    }
    // Fallback: buscar por email (sessões antigas sem session_user_id)
    if (email != null && email.isNotEmpty) {
      final uidByEmail = await PessoaRepository.obterUsuarioIdPorEmail(email);
      if (uidByEmail != null) {
        PessoaRepository.usuarioId = uidByEmail;
        PessoaRepository.usuarioEmail = email;
        SupabaseService.usuarioId = uidByEmail;
        await prefs.setInt('session_pessoa_id', uidByEmail);
        // Sprint R.4 — associa o token FCM ao usuário restaurado
        PushNotificationService.instance.salvarTokenParaUsuario();
        if (mounted) {
          setState(() => _entrou = true);
          _carregarUsuario();
          _carregarMemorias();
          // Sprint S.9.1 — tenta navegar para mídia pendente da Share Extension
          WidgetsBinding.instance.addPostFrameCallback((_) => _tentarNavegacaoPendente());
        }
        return;
      }
    }
    // Sessão expirou
    await prefs.setBool('is_logged_in', false);
    await prefs.remove('session_user_email');
    await prefs.remove('session_pessoa_id');
    await prefs.remove('session_user_id');
    _carregarUsuario();
    _carregarMemorias();
  }

  Future<void> _carregarUsuario() async {
    final dados = await PessoaRepository.obterUsuario();
    if (mounted && dados != null) {
      setState(() {
        _usuarioFotoUrl = dados['foto_perfil'] as String?;
      });
    }
  }

  Future<void> _verificarOnboarding() async {
    final jaVisto = await OnboardingScreen.jaVisto();
    if (mounted) setState(() => _mostrarOnboarding = !jaVisto);
  }

  Future<void> _carregarVinculosMemorias() async {
    final vinculos = await PessoaRepository.listarVinculos();
    final compartilhamentos =
        await PessoaRepository.listarCompartilhamentos();
    final datas = await PessoaRepository.carregarDatasMemorias();
    for (var i = 0; i < _memorias.length; i++) {
      final m = _memorias[i];
      final ids = vinculos[m.id ?? -1];
      final famIds = compartilhamentos[m.id ?? -1];
      final hasPessoas = ids != null && ids.isNotEmpty;
      final hasFamiliares = famIds != null && famIds.isNotEmpty;

      final dataCustomizada = datas[m.id];
      if (hasPessoas || hasFamiliares || dataCustomizada != null) {
        _memorias[i] = Memoria(
          titulo: m.titulo,
          contexto: m.contexto,
          categoria: m.categoria,
          criadaEm: dataCustomizada ?? m.criadaEm,
          id: m.id,
          foto: m.foto,
          fotoUrl: m.fotoUrl,
          pessoasIds: hasPessoas ? ids : null,
          isCompartilhada: hasFamiliares,
          familiaresIds: hasFamiliares ? famIds : null,
          dataMemoria: dataCustomizada,
        );
      }
    }
  }

  Future<void> _carregarMemorias() async {
    if (!_service.isConfigured || _carregandoMemorias) return;

    setState(() => _carregandoMemorias = true);
    try {
      final memorias = await _service.listarMemorias();
      if (mounted) {
        setState(() => _memorias.replaceRange(0, _memorias.length, memorias));
        _carregarVinculosMemorias();
        _carregarMemoriasRecebidas();
      }
    } catch (_) {
      // A tela continua disponível e oferece nova tentativa em Minha História.
    } finally {
      if (mounted) setState(() => _carregandoMemorias = false);
    }
  }

  // Bug 1: memórias que OUTRAS contas (ex: Darlan) compartilharam com o
  // usuário logado (ex: Alice), vinculadas por e-mail do contato.
  Future<void> _carregarMemoriasRecebidas() async {
    if (!_service.isConfigured) return;
    try {
      final vinculos = await PessoaRepository.listarMemoriasCompartilhadasComigo();
      final recebidas = await _service.listarMemoriasRecebidas(vinculos);
      if (mounted) {
        setState(() {
          _memoriasRecebidas
            ..clear()
            ..addAll(recebidas);
        });
      }
    } catch (_) {
      // Silencioso: a aba Compartilhadas continua funcional sem esta parte.
    }
  }

  Future<void> _abrirNovaMemoria(BuildContext context) async {
    final memoria = await Navigator.of(context).push<Memoria>(
      MaterialPageRoute(
        builder: (_) =>
            NovaMemoriaScreen(onSalvar: _service.salvarMemoriaComFoto),
      ),
    );

    if (memoria == null || !context.mounted) return;
    setState(() => _memorias.insert(0, memoria));
    _mostrarSucesso(context);
  }

  void _mostrarSucesso(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Memória salva com sucesso',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Mais uma história preservada para sua família.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _abrirDetalhe(BuildContext context, Memoria memoria) async {
    final resultado = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => MemoriaDetalheScreen(
          memoria: memoria,
          somenteLeitura: memoria.isRecebidaDeOutraConta,
          memoriasConhecidas: _memorias,
          onAbrirMemoria: (m) => _abrirDetalhe(context, m),
        ),
      ),
    );

    if (resultado == 'deletada' && context.mounted) {
      setState(() {
        _memorias.removeWhere((m) => m.id == memoria.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('História excluída com sucesso.')),
      );
    } else if (resultado is Memoria && context.mounted) {
      setState(() {
        final index = _memorias.indexWhere((m) => m.id == resultado.id);
        if (index >= 0) {
          _memorias[index] = resultado;
        }
      });
    }
  }

  void _abri