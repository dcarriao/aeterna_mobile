// lib/services/push_notification_service.dart
// Sprint S.9.2 — Push Notifications Transacionais
//
// Mudanças em relação ao Sprint R.4:
//   - RPC corrigida: upsert_device_token(p_usuario_id) → upsert_push_dispositivo(p_pessoa_id)
//     (a FK era para usuarios.id; agora aponta para pessoas.id — correto desde Sprint S.3)
//   - desativarDispositivoAtual(): chamado no logout para marcar ativo=false
//   - Foreground: exibe notificação local via flutter_local_notifications
//   - Toque na notificação: navega para a rota correta via callback (_navigationCallback)
//   - Logs: [PUSH_TOKEN] e [PUSH_OPEN] para rastreamento

import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import '../models/pessoa.dart';

/// Callback invocado quando o usuário toca numa notificação push.
/// Recebe o [data] do payload FCM (campo `data`, nunca `notification`).
typedef PushNavigationCallback = void Function(Map<String, dynamic> data);

/// Canal Android para notificações transacionais do aEterna.
const _androidChannel = AndroidNotificationChannel(
  'aeterna_transacional',
  'Notificações aEterna',
  description: 'Convites, compartilhamentos e atualizações de memórias.',
  importance: Importance.high,
  playSound: true,
);

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  static const _shareChannel = MethodChannel('com.aeterna.app/share');

  bool _inicializado = false;
  bool _obtendoToken = false;

  /// S.9.4c — trilha de diagnóstico visível na tela Perfil (iPhone sem
  /// Mac não tem Console; isto substitui).
  static final List<String> diagnostico = [];
  static void _diag(String m) {
    diagnostico.add('${DateTime.now().toIso8601String().substring(11, 19)} $m');
    if (diagnostico.length > 30) diagnostico.removeAt(0);
    print('[PUSH_IOS] $m');
  }

  /// S.9.4c — sink público de diagnóstico. Permite que outros serviços
  /// (ex.: falha da consulta de vídeos em lote) registrem no MESMO painel
  /// visível do Perfil, sem expor _diag.
  static void registrarDiagnostico(String m) => _diag(m);

  String? _currentToken;
  PushNavigationCallback? _navigationCallback;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  bool get isInitialized => _inicializado;
  String? get currentToken => _currentToken;

  /// Registra o callback de navegação.
  /// Deve ser chamado por main.dart logo após initialize().
  void setNavigationCallback(PushNavigationCallback callback) {
    _navigationCallback = callback;
  }

  /// Inicializa Firebase, flutter_local_notifications e listeners de FCM.
  /// Deve ser chamado o mais cedo possível em main() — antes de runApp().
  /// NÃO aguarda token APNs/FCM (nem MethodChannel) — isso roda em background
  /// após marcar pronto, para não bloquear runApp() (tela branca).
  Future<void> initialize() async {
    if (_inicializado) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final messaging = FirebaseMessaging.instance;

      // iOS: exibe alertas e sons em foreground (padrão FCM suprime no iOS)
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Solicita permissão (iOS pede dialog; Android 13+ já declarado no manifest)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('[PUSH_TOKEN] Permissão: ${settings.authorizationStatus}');
      _diag('permission=${settings.authorizationStatus}');

      // Inicializa flutter_local_notifications (necessário para foreground Android
      // e para roteamento ao tocar em notificação recebida em foreground)
      await _inicializarLocalNotifications();

      // Escuta renovação de token
      messaging.onTokenRefresh.listen((token) async {
        print('[PUSH_TOKEN] Token FCM renovado: ...${token.substring(token.length - 8)}');
        _currentToken = token;
        await _salvarTokenSeLogado();
      });

      // Mensagem recebida com app em FOREGROUND
      FirebaseMessaging.onMessage.listen(_onMessage);

      // App aberto ao tocar em notificação (app estava em BACKGROUND)
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      // Notificação que abriu o app a partir do estado TERMINADO.
      // Timeout: nunca bloquear runApp se o plugin não responder.
      try {
        final initialMessage = await messaging
            .getInitialMessage()
            .timeout(const Duration(seconds: 2));
        if (initialMessage != null) {
          print(
              '[PUSH_OPEN] App iniciado via notificação: tipo=${initialMessage.data['tipo']}');
          _invocarCallback(initialMessage.data);
        }
      } on TimeoutException {
        _diag('getInitialMessage timeout');
      }

      _inicializado = true;
      print('[PUSH_TOKEN] Serviço inicializado com sucesso');
      // NÃO chamar MethodChannel / APNs wait aqui.
      // main() ainda tem awaits (Supabase etc.) antes de runApp(); um
      // unawaited com delay curto (ex. 300ms) dispara o canal ANTES da UI
      // e pode travar em tela branca. Token: agendarAposUi() pós-runApp.
    } catch (e) {
      print('[PUSH_TOKEN] Erro ao inicializar: $e');
    }
  }

  /// Agenda obtenção de token APNs/FCM DEPOIS de runApp().
  /// Chamar de main() logo após runApp — sem await. Nunca no initialize().
  void agendarAposUi({Duration delay = const Duration(seconds: 3)}) {
    Future.delayed(delay, () {
      unawaited(_obterTokenAposRegistro());
    });
  }

  /// Solicita registro APNs nativo → espera token APNs → obtém FCM → persiste.
  Future<void> _obterTokenAposRegistro() async {
    if (_obtendoToken) return;
    _obtendoToken = true;
    try {
      if (Platform.isIOS) {
        await _solicitarRegistroPushIos();
        final apns = await _aguardarApnsToken(maxSegundos: 20);
        _diag('apns_token=${apns == null ? 'NULL' : 'ok'}');
        if (apns == null) {
          _diag('fcm_token=NULL (sem APNs)');
          return;
        }
      }

      _currentToken = await FirebaseMessaging.instance.getToken();
      if (_currentToken != null) {
        print(
            '[PUSH_TOKEN] Token FCM obtido: ...${_currentToken!.substring(_currentToken!.length - 8)}');
        _diag(
            'fcm_token=...${_currentToken!.substring(_currentToken!.length - 8)}');
        await _salvarTokenSeLogado();
      } else {
        _diag('fcm_token=NULL');
      }
    } catch (e) {
      _diag('obterToken erro: $e');
    } finally {
      _obtendoToken = false;
    }
  }

  /// Pede ao AppDelegate que chame registerForRemoteNotifications.
  /// Timeout obrigatório — nunca travar se o canal não responder.
  /// Só chamar depois da UI (agendarAposUi / salvarTokenParaUsuario).
  Future<void> _solicitarRegistroPushIos() async {
    try {
      await _shareChannel
          .invokeMethod('requestPushRegistration')
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      _diag('requestPushRegistration=ok');
    } catch (e) {
      _diag('requestPushRegistration erro: $e');
    }
  }

  /// Espera o token APNs ficar disponível (até [maxSegundos]).
  Future<String?> _aguardarApnsToken({int maxSegundos = 20}) async {
    final messaging = FirebaseMessaging.instance;
    String? apns = await messaging.getAPNSToken();
    for (var i = 0; apns == null && i < maxSegundos; i++) {
      await Future.delayed(const Duration(seconds: 1));
      apns = await messaging.getAPNSToken();
      if (i % 5 == 4) {
        _diag('apns(tent ${i + 1})=${apns == null ? 'NULL' : 'ok'}');
      }
    }
    return apns;
  }

  /// Importa linhas de diagnóstico nativo (getPushDiag).
  /// Chamar SÓ ao abrir o painel no Perfil — nunca no startup.
  Future<void> importarDiagnosticoNativo() async {
    if (!Platform.isIOS) return;
    try {
      final linhas = await _shareChannel
          .invokeMethod<List<dynamic>>('getPushDiag')
          .timeout(const Duration(seconds: 2), onTimeout: () => <dynamic>[]);
      if (linhas != null) {
        for (final l in linhas) {
          final s = 'iOS: $l';
          if (!diagnostico.contains(s)) diagnostico.add(s);
        }
        while (diagnostico.length > 30) {
          diagnostico.removeAt(0);
        }
      }
    } catch (e) {
      _diag('getPushDiag erro: $e');
    }
  }

  /// Probe se o container do App Group é acessível.
  /// Chamar SÓ ao abrir o painel no Perfil — nunca no startup.
  Future<void> probeAppGroup() async {
    if (!Platform.isIOS) return;
    try {
      final ok = await _shareChannel
          .invokeMethod<bool>('probeAppGroup')
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      _diag(ok == true ? 'share: app_group=ok' : 'share: app_group=NULL');
    } catch (e) {
      _diag('share: app_group erro=$e');
    }
  }

  /// Inicializa flutter_local_notifications e cria o canal Android.
  Future<void> _inicializarLocalNotifications() async {
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initIOS = DarwinInitializationSettings(
      requestAlertPermission: false, // permissão já pedida via FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: initAndroid,
      iOS: initIOS,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Usuário tocou em notificação local (foreground)
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          // payload é "tipo|route|conteudo_id" — ver _onMessage()
          final parts = payload.split('|');
          final data = <String, dynamic>{
            'tipo': parts.isNotEmpty ? parts[0] : '',
            'route': parts.length > 1 ? parts[1] : '',
            'conteudo_id': parts.length > 2 ? parts[2] : '',
          };
          print('[PUSH_OPEN] Toque em notificação local: tipo=${data['tipo']}');
          _invocarCallback(data);
        }
      },
    );

    // Cria canal Android (idempotente — sem efeito se já existir)
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  /// Salva o token para o usuário atualmente logado.
  /// Chamado após login, restore de sessão e token refresh.
  Future<void> salvarTokenParaUsuario() async {
    // Mesma ordem do init: registrar APNs → esperar token → FCM → persistir.
    if (_currentToken == null) {
      await _obterTokenAposRegistro();
    }
    if (_currentToken != null) {
      await _salvarToken(_currentToken!);
    } else {
      _diag('persistido=false (sem token após retries)');
    }
  }

  /// Desativa o dispositivo atual no banco ao fazer logout.
  /// Evita receber pushes para outra conta no mesmo dispositivo.
  Future<void> desativarDispositivoAtual() async {
    final token = _currentToken;
    final pessoaId = PessoaRepository.usuarioId;

    if (token == null || pessoaId <= 0) return;
    if (!PessoaRepository.isConfigured) return;

    try {
      await PessoaRepository.supabaseClient.rpc(
        'desativar_dispositivo',
        params: {
          'p_pessoa_id': pessoaId,
          'p_token': token,
        },
      );
      print('[PUSH_TOKEN] Dispositivo desativado para pessoa_id=$pessoaId');
    } catch (e) {
      print('[PUSH_TOKEN] Erro ao desativar dispositivo: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Privado
  // ---------------------------------------------------------------------------

  Future<void> _salvarTokenSeLogado() async {
    if (_currentToken == null) return;
    final uid = PessoaRepository.usuarioId;
    if (uid <= 0) return;
    await _salvarToken(_currentToken!);
  }

  Future<void> _salvarToken(String token) async {
    if (!PessoaRepository.isConfigured) return;
    final pessoaId = PessoaRepository.usuarioId;
    if (pessoaId <= 0) return;

    try {
      final plataforma = Platform.isIOS ? 'ios' : 'android';
      // S.9.2: RPC corrigida — p_pessoa_id (pessoas.id), não p_usuario_id
      await PessoaRepository.supabaseClient.rpc(
        'upsert_push_dispositivo',
        params: {
          'p_pessoa_id': pessoaId,
          'p_token': token,
          'p_plataforma': plataforma,
        },
      );
      print(
          '[PUSH_TOKEN] Token salvo/atualizado para pessoa_id=$pessoaId plataforma=$plataforma');
      _diag('persistido=true pessoa=$pessoaId');
    } catch (e) {
      print('[PUSH_TOKEN] Erro ao salvar token: $e');
      _diag('persistido=false erro=$e');
    }
  }

  /// App em FOREGROUND: exibe notificação local (FCM não exibe banner automaticamente).
  void _onMessage(RemoteMessage message) {
    final notif = message.notification;
    final titulo = notif?.title ?? message.data['titulo'] as String? ?? 'aEterna';
    final corpo = notif?.body ?? message.data['corpo'] as String? ?? '';
    final tipo = message.data['tipo'] as String? ?? '';
    final route = message.data['route'] as String? ?? '';
    final cid = message.data['conteudo_id'] as String? ?? '';

    print('[PUSH_OPEN] Mensagem em foreground: tipo=$tipo');

    // Payload simples para recuperar a rota ao tocar
    final payload = '$tipo|$route|$cid';

    _localNotifications.show(
      message.hashCode,
      titulo,
      corpo,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// App em BACKGROUND e tocado pelo usuário: navega para a rota correta.
  void _onMessageOpenedApp(RemoteMessage message) {
    final tipo = message.data['tipo'] as String? ?? '';
    print('[PUSH_OPEN] App aberto via notificação: tipo=$tipo');
    _invocarCallback(message.data);
  }

  void _invocarCallback(Map<String, dynamic> data) {
    if (_navigationCallback != null) {
      _navigationCallback!(data);
    } else {
      // Callback ainda não registrado (race condition na inicialização)
      // main.dart chama setNavigationCallback() logo após initialize()
      print(
          '[PUSH_OPEN] Callback de navegação ainda não registrado — tipo=${data['tipo']}');
    }
  }
}
