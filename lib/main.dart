import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'screens/pets_screen.dart';
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
  // Push APNs/FCM só depois da UI — nunca await MethodChannel antes de runApp
  // (unawaited com delay curto dentro de initialize() causou tela branca).
  PushNotificationService.instance.agendarAposUi();
  // Fallback de entrega: após compartilhar memória, o app invoca send-push
  // se o Database Webhook não existir. Nunca no caminho antes do runApp.
  PessoaRepository.setPushDispatch(
    (ids) => PushNotificationService.instance.dispararPendentesParaPessoas(ids),
  );
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
  // Canal unificado: Android (MainActivity.kt) e iOS (AppDelegate.swift)
  // respondem a 'getSharedImage' com o caminho da imagem pendente.
  static const _shareChannel = MethodChannel('com.aeterna.app/share');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verificarOnboarding();
    _carregarSessao();
    _configurarDeepLinks();
    // Delay + retries: canal iOS / escrita da Share Extension podem
    // não estar prontos no primeiro frame do initState.
    Future.delayed(const Duration(milliseconds: 400), () {
      _verificarCompartilhamentoPendente(tentativas: 4);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verificarCompartilhamentoPendente(tentativas: 4);
    }
  }

  /// Verifica compartilhamento pendente no Android (Intent) e no iOS (App Group).
  /// Em ambas as plataformas a native side consome a pendência ao retornar o path.
  Future<void> _verificarCompartilhamentoPendente({int tentativas = 1}) async {
    for (var i = 0; i < tentativas; i++) {
      try {
        final String? path = await _shareChannel
            .invokeMethod<String>('getSharedImage')
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        print(
            '[FLUTTER_SHARE] tent=${i + 1}/$tentativas payload=${path != null && path.isNotEmpty} path=$path');
        if (path != null && path.isNotEmpty) {
          PushNotificationService.registrarDiagnostico('share: pendencia_lida');
          await _processarImagemCompartilhada(path);
          return;
        }
      } catch (e) {
        print('[FLUTTER_SHARE] erro=$e');
        PushNotificationService.registrarDiagnostico('share: erro=$e');
        return;
      }
      if (i < tentativas - 1) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }
    PushNotificationService.registrarDiagnostico('share: sem_pendencia');
  }

  Future<void> _processarImagemCompartilhada(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        print('[FLUTTER_SHARE] arquivo inexistente path=$path');
        PushNotificationService.registrarDiagnostico(
            'share: arquivo_inexistente');
        return;
      }
      final bytes = await file.readAsBytes();
      final filename = path.split('/').last;
      final lower = filename.toLowerCase();
      final isVideo = lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.m4v');
      final nav = _navigatorKey.currentState;
      if (nav == null) {
        // Navigator ainda não pronto — tenta de novo em breve.
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final resultado =
          await _navigatorKey.currentState?.push<Memoria>(
        MaterialPageRoute(
          builder: (_) => NovaMemoriaScreen(
            onSalvar: _service.salvarMemoriaComFoto,
            fotoBytes: isVideo ? null : bytes,
            fotoNome: isVideo ? null : filename,
            videoBytes: isVideo ? bytes : null,
            videoNome: isVideo ? filename : null,
          ),
        ),
      );
      if (resultado != null && mounted) {
        setState(() => _memorias.insert(0, resultado));
      }
    } catch (e) {
      print('[Share] Erro ao carregar imagem compartilhada: $e');
      PushNotificationService.registrarDiagnostico('share: processar_erro=$e');
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

    // Ler session_pessoa_id (pessoas.id). NUNCA usar session_user_id como
    // pessoas.id direto — podia ser contatos.id / usuarios.id legado.
    final sessionPessoaId = prefs.getInt('session_pessoa_id');
    final sessionUserId = prefs.getInt('session_user_id');
    final email = prefs.getString('session_user_email');

    int? uid = sessionPessoaId;
    if (uid != null && uid > 0) {
      // Valida que ainda é pessoa humana (evita sessão corrompida).
      try {
        final p = await PessoaRepository.obterPorId(uid);
        if (p == null || p.isPet) {
          print('[SESSAO] session_pessoa_id=$uid invalido — limpando');
          uid = null;
          await prefs.remove('session_pessoa_id');
        }
      } catch (_) {
        uid = null;
      }
    }

    // Só mapeia session_user_id via _legacy_usuario_id — nunca assume que
    // o número legado é o pessoas.id atual.
    if ((uid == null || uid <= 0) &&
        sessionUserId != null &&
        sessionUserId > 0) {
      try {
        final rows = await PessoaRepository.supabaseClient
            .from('pessoas')
            .select('id')
            .eq('_legacy_usuario_id', sessionUserId)
            .limit(1);
        if (rows.isNotEmpty) {
          uid = (rows.first['id'] as num).toInt();
          await prefs.setInt('session_pessoa_id', uid);
          await prefs.remove('session_user_id');
        } else {
          print('[SESSAO] session_user_id=$sessionUserId sem mapeamento — descartando');
          await prefs.remove('session_user_id');
        }
      } catch (_) {
        await prefs.remove('session_user_id');
      }
    }

    if (uid != null && uid > 0) {
      PessoaRepository.usuarioId = uid;
      PessoaRepository.legadoUsuarioId = null;
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
    // Fallback: buscar por email (sessões antigas sem session_pessoa_id)
    if (email != null && email.isNotEmpty) {
      final uidByEmail = await PessoaRepository.obterUsuarioIdPorEmail(email);
      if (uidByEmail != null) {
        PessoaRepository.usuarioId = uidByEmail;
        PessoaRepository.legadoUsuarioId = null;
        PessoaRepository.usuarioEmail = email;
        SupabaseService.usuarioId = uidByEmail;
        await prefs.setInt('session_pessoa_id', uidByEmail);
        await prefs.remove('session_user_id');
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
    // Sessão expirou / inválida
    await prefs.setBool('is_logged_in', false);
    await prefs.remove('session_user_email');
    await prefs.remove('session_pessoa_id');
    await prefs.remove('session_user_id');
    _carregarUsuario();
    _carregarMemorias();
  }

  Future<void> _carregarUsuario() async {
    // S.9.3.1 (Item 3) — o avatar da sessão vem SEMPRE da pessoa
    // autenticada canônica (pessoas.id = usuarioId), nunca da "última
    // pessoa editada".
    final dados = await PessoaRepository.obterUsuario();
    print('[LOGIN_AVATAR] pessoa_id=${PessoaRepository.usuarioId}');
    print('[LOGIN_AVATAR] foto_perfil=${dados?['foto_perfil']}');
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
          videoUrl: m.videoUrl,
          temVideo: m.temVideo,
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
          final prev = _memorias[index];
          // Nunca perder videoUrl/temVideo ao voltar do detalhe (rebuild
          // incompleto no detalhe corrompia o cache da Home/Timeline).
          _memorias[index] = Memoria(
            id: resultado.id,
            titulo: resultado.titulo,
            contexto: resultado.contexto,
            categoria: resultado.categoria,
            criadaEm: resultado.criadaEm,
            foto: resultado.foto ?? prev.foto,
            fotoUrl: resultado.fotoUrl ?? prev.fotoUrl,
            video: resultado.video ?? prev.video,
            videoUrl: resultado.videoUrl ?? prev.videoUrl,
            temVideo: resultado.temVideo ||
                prev.temVideo ||
                (resultado.videoUrl ?? prev.videoUrl) != null,
            pessoasIds: resultado.pessoasIds ?? prev.pessoasIds,
            isCompartilhada: resultado.isCompartilhada,
            familiaresIds: resultado.familiaresIds ?? prev.familiaresIds,
            dataMemoria: resultado.dataMemoria ?? prev.dataMemoria,
            donoUsuarioId: resultado.donoUsuarioId ?? prev.donoUsuarioId,
            compartilhadaPorNome:
                resultado.compartilhadaPorNome ?? prev.compartilhadaPorNome,
          );
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

  void _abrirPets(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PetsScreen(
          titulosMemorias: {
            for (final m in _memorias.where((m) => m.id != null))
              m.id!: m.titulo,
          },
          onAbrirMemoria: (memoriaId) => _abrirMemoriaPorId(context, memoriaId),
        ),
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
          onAbrirMemoria: (memoriaId) => _abrirMemoriaPorId(context, memoriaId),
        ),
      ),
    );
  }

  /// Abre memória pelo id do perfil/pet. NÃO usa `orElse: first` — isso
  /// abria "Gol no Morumbi" (primeira da Home) quando o id do pet não
  /// estava em `_memorias` e ainda corrompia o cache ao voltar.
  Future<void> _abrirMemoriaPorId(BuildContext context, int memoriaId) async {
    Memoria? memoria;
    for (final m in _memorias) {
      if (m.id == memoriaId) {
        memoria = m;
        break;
      }
    }
    memoria ??= await PessoaRepository.obterMemoriaPorId(memoriaId);
    if (!context.mounted) return;
    if (memoria == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir esta memória.')),
      );
      return;
    }
    await _abrirDetalhe(context, memoria);
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
    await prefs.remove('session_pessoa_id');
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
      // S.9.3.2 — datas/calendários em português (público 40+ sem 2º idioma)
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
                    onPets: () => _abrirPets(context),
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
