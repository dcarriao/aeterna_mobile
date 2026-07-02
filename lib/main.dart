import 'package:flutter/material.dart';

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
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  await LegacyCuratorService.initialize();
  runApp(const AeternaApp());
}

class AeternaApp extends StatefulWidget {
  const AeternaApp({super.key});

  @override
  State<AeternaApp> createState() => _AeternaAppState();
}

class _AeternaAppState extends State<AeternaApp> {
  final _service = SupabaseService.instance;
  final List<Memoria> _memorias = [];
  bool _mostrarOnboarding = true;
  bool _entrou = false;
  bool _carregandoMemorias = false;
  String? _usuarioFotoUrl;

  @override
  void initState() {
    super.initState();
    _verificarOnboarding();
    _carregarMemorias();
    _carregarUsuario();
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
      }
    } catch (_) {
      // A tela continua disponível e oferece nova tentativa em Minha História.
    } finally {
      if (mounted) setState(() => _carregandoMemorias = false);
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
            onLogout: () {
              setState(() {
                _entrou = false;
                _memorias.clear(); // Limpa cache local de memórias
                _usuarioFotoUrl = null; // Limpa cache local da foto
              });
              Navigator.of(context).popUntil((route) => route.isFirst);
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
    _carregarUsuario();
    _carregarMemorias();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
