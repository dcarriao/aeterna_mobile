import 'dart:io';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verificarOnboarding();
    _carregarSessao();
    _configurarDeepLinks();
    _verificarCompartilhamentoAndroid();
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

  Future<void> _processarLinkCompartilhamento(Uri uri) async {
    print('[DeepLink] Recebido deep link: $uri');
    if (uri.scheme == 'aeterna' && uri.host == 'share') {
      final imagePath = uri.queryParameters['image'];
      if (imagePath != null && imagePath.isNotEmpty) {
        try {
          final file = File(imagePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final filename = imagePath.split('/').last;
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
          print('[DeepLink] Erro ao processar imagem: $e');
        }
      }
    }
  }

  Future<void> _carregarSessao() async {
    final prefs = await SharedPreferences.getInstance();
    final logado = prefs.getBool('is_logged_in') ?? false;
    if (!logado) {
      _carregarUsuario();
      _carregarMemorias();
      return;
    }

    final uid = prefs.getInt('session_user_id');
    final email = prefs.getString('session_user_email');
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
        await prefs.setInt('session_user_id', uidByEmail);
        // Sprint R.4 — associa o token FCM ao usuário restaurado
        PushNotificationService.instance.salvarTokenParaUsuario();
        if (mounted) {
          setState(() => _entrou = true);
          _carregarUsuario();
          _carregarMemorias();
        }
        return;
      }
    }
    // Sessão expirou
    await prefs.setBool('is_logged_in', false);
    await prefs.remove('session_user_email');
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

  void _abrirTimeline(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TimelineScreen(
          memorias: _memorias,
          onCriarMemoria: () => _abrirNovaMemoria(context),
          onAbrirMemoria: (memoria) => _abrirDetalhe(context, memoria),
        ),
      ),
    );
  }

  void _abrirCompartilhadas(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CompartilhadasScreen(
          memorias: _memorias,
          memoriasRecebidas: _memoriasRecebidas,
          onAbrirMemoria: (memoria) => _abrirDetalhe(context, memoria),
          onCompartilhar: () => _abrirNovaMemoria(context),
        ),
      ),
    );
  }

  void _abrirMemoriais(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const MemoriaisScreen(),
      ),
    );
  }

  void _abrirPessoas(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PessoasScreen(
          titulosMemorias: {
            for (final m in _memorias.where((m) => m.id != null))
              m.id!: m.titulo,
          },
          onAbrirMemoria: (memoriaId) {
            final memoria = _memorias.firstWhere(
              (m) => m.id == memoriaId,
              orElse: () => _memorias.first,
            );
            _abrirDetalhe(context, memoria);
          },
        ),
      ),
    );
  }

  void _abrirPerfil(BuildContext context) async {
    final totalPessoas = (await PessoaRepository.listar()).length;
    if (context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PerfilScreen(
            totalMemorias: _memorias.length,
            totalPessoas: totalPessoas,
            onLogout: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('is_logged_in', false);
              await prefs.remove('session_user_email');
              await prefs.remove('session_user_id');
              if (mounted) {
                setState(() {
                  _entrou = false;
                  _memorias.clear(); // Limpa cache local de memórias
                  _memoriasRecebidas.clear(); // Limpa cache de recebidas
                  _usuarioFotoUrl = null; // Limpa cache local da foto
                });
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ),
      );
      _carregarUsuario();
    }
  }

  void _abrirMinhaHistoria(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MinhaHistoriaScreen(
          memorias: _memorias,
          carregando: _carregandoMemorias,
          supabaseConfigurado: _service.isConfigured,
          onRegistrar: () async {
            await _abrirNovaMemoria(context);
          },
          onAbrirDetalhe: (memoria) => _abrirDetalhe(context, memoria),
          onAtualizar: _carregarMemorias,
        ),
      ),
    );
  }

  void _efetuarLogin() {
    setState(() {
      _entrou = true;
    });
    // Sprint R.4 — associa o token FCM ao usuário que acabou de logar
    PushNotificationService.instance.salvarTokenParaUsuario();
    _carregarUsuario();
    _carregarMemorias();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'aEterna',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _mostrarOnboarding
          ? OnboardingScreen(
              onComecar: () => setState(() => _mostrarOnboarding = false),
            )
          : _entrou
              ? Builder(
                  builder: (context) => HomeScreen(
                    memorias: _memorias,
                    fotoUrl: _usuarioFotoUrl,
                    onRegistrar: () => _abrirNovaMemoria(context),
                    onMinhaHistoria: () => _abrirMinhaHistoria(context),
                    onAbrirMemoria: (memoria) => _abrirDetalhe(context, memoria),
                    onPessoas: () => _abrirPessoas(context),
                    onTimeline: () => _abrirTimeline(context),
                    onCompartilhadas: () => _abrirCompartilhadas(context),
                    onPerfil: () => _abrirPerfil(context),
                    onMemoriais: () => _abrirMemoriais(context),
                  ),
                )
              : LoginScreen(onEntrar: _efetuarLogin),
    );
  }
}
