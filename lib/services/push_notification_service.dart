import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';
import '../models/pessoa.dart';

/// Sprint R.4 — Firebase Cloud Messaging integration.
///
/// Inicializa o Firebase, solicita permissão (iOS), captura o token
/// FCM e o persiste no Supabase vinculado ao usuário logado.
///
/// O token é armazenado em memória durante a inicialização e só é
/// persistido no Supabase quando um usuário estiver logado (método
/// [salvarTokenParaUsuario]).
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  bool _inicializado = false;
  String? _currentToken;

  bool get isInitialized => _inicializado;
  String? get currentToken => _currentToken;

  /// Inicializa o Firebase e configura listeners de FCM.
  /// Deve ser chamado o mais cedo possível em main().
  Future<void> initialize() async {
    if (_inicializado) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final messaging = FirebaseMessaging.instance;

      // Solicita permissão (iOS)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('[PushNotification] Permissão: ${settings.authorizationStatus}');

      // Captura o token atual
      _currentToken = await messaging.getToken();
      if (_currentToken != null) {
        print('[PushNotification] Token FCM obtido');
        // Tenta salvar imediatamente se já houver usuário logado
        await _salvarTokenSeLogado();
      }

      // Escuta renovação de token
      messaging.onTokenRefresh.listen((token) async {
        _currentToken = token;
        print('[PushNotification] Token FCM renovado');
        await _salvarTokenSeLogado();
      });

      // Escuta mensagens em primeiro plano
      FirebaseMessaging.onMessage.listen(_onMessage);

      // Escuta quando o app abre a partir de uma notificação
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      // Verifica notificação que abriu o app a partir do estado terminado
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _onMessageOpenedApp(initialMessage);
      }

      _inicializado = true;
      print('[PushNotification] Firebase inicializado com sucesso');
    } catch (e) {
      print('[PushNotification] Erro ao inicializar: $e');
    }
  }

  /// Salva o token para o usuário atualmente logado.
  /// Deve ser chamado sempre que um usuário fizer login.
  Future<void> salvarTokenParaUsuario() async {
    if (_currentToken == null) {
      // Tenta obter o token novamente
      try {
        final messaging = FirebaseMessaging.instance;
        _currentToken = await messaging.getToken();
      } catch (_) {
        return;
      }
    }
    if (_currentToken != null) {
      await _salvarToken(_currentToken!);
    }
  }

  /// Persiste o token no Supabase, se houver usuário logado.
  Future<void> _salvarTokenSeLogado() async {
    if (_currentToken == null) return;
    final uid = PessoaRepository.usuarioId;
    if (uid <= 0) return;
    await _salvarToken(_currentToken!);
  }

  Future<void> _salvarToken(String token) async {
    if (!PessoaRepository.isConfigured) return;
    final uid = PessoaRepository.usuarioId;
    if (uid <= 0) return;
    try {
      final plataforma = Platform.isIOS ? 'ios' : 'android';
      await PessoaRepository.supabaseClient.rpc(
        'upsert_device_token',
        params: {
          'p_usuario_id': uid,
          'p_token': token,
          'p_plataforma': plataforma,
        },
      );
      print('[PushNotification] Token salvo no Supabase para usuário $uid');
    } catch (e) {
      print('[PushNotification] Erro ao salvar token: $e');
    }
  }

  void _onMessage(RemoteMessage message) {
    print('[PushNotification] Mensagem recebida em primeiro plano: ${message.messageId}');
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    print('[PushNotification] App aberto por notificação: ${message.messageId}');
  }
}
