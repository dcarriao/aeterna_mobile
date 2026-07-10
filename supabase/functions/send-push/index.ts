// ============================================================================
// supabase/functions/send-push/index.ts
// Sprint S.9.2 — Push Notifications Transacionais
// ============================================================================
// Recebe evento do trigger PostgreSQL (via pg_net.http_post) ou chamada direta.
// Fluxo:
//   1. Valida payload
//   2. Verifica idempotência em `notificacoes` (ON CONFLICT DO NOTHING)
//   3. Busca tokens ativos em `push_dispositivos` para pessoa_id
//   4. Obtém access_token via Google Service Account JWT (OAuth2 RS256)
//   5. Chama FCM HTTP v1 API para cada token
//   6. Atualiza `notificacoes` com resultado
//   7. Desativa tokens inválidos (NOT_REGISTERED)
//
// Payload esperado (enviado pelos triggers):
// {
//   tipo          : string   — tipo do evento (convite_familiar_recebido | ...)
//   pessoa_id     : number   — destinatário (pessoas.id)
//   titulo        : string   — título da notificação
//   corpo         : string   — corpo da notificação
//   dados         : object   — payload de rota para o Flutter (sem dados sensíveis)
//   conteudo_id   : number | null — para idempotência
//   conteudo_tipo : string | null — para idempotência
// }
//
// Secrets necessários (Supabase → Edge Functions → Secrets):
//   FIREBASE_SERVICE_ACCOUNT_JSON — JSON da Service Account do Firebase
//   SUPABASE_URL                  — injetado automaticamente pelo Supabase
//   SUPABASE_SERVICE_ROLE_KEY     — injetado automaticamente pelo Supabase
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface PushPayload {
  tipo: string;
  pessoa_id: number;
  titulo: string;
  corpo: string;
  dados?: Record<string, unknown>;
  conteudo_id?: number | null;
  conteudo_tipo?: string | null;
}

interface ServiceAccountKey {
  type: string;
  project_id: string;
  private_key_id: string;
  private_key: string;
  client_email: string;
  token_uri: string;
}

interface FcmResult {
  token: string;
  success: boolean;
  error?: string;
  errorCode?: string;
}

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const FCM_PROJECT_ID = 'aeterna-94450';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const FCM_ENDPOINT = `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`;

// Códigos FCM que indicam token inválido (deve desativar no banco)
const INVALID_TOKEN_CODES = new Set([
  'NOT_REGISTERED',
  'INVALID_ARGUMENT',
  'UNREGISTERED',
]);

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  // Só aceita POST
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  let payload: PushPayload;
  try {
    payload = await req.json() as PushPayload;
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Validação mínima
  if (!payload.tipo || !payload.pessoa_id || !payload.titulo || !payload.corpo) {
    console.error('[PUSH] Payload inválido:', JSON.stringify(payload));
    return new Response(JSON.stringify({ error: 'Missing required fields' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  console.log(`[PUSH_START] tipo=${payload.tipo} pessoa_id=${payload.pessoa_id}`);

  // Cliente Supabase com service role (acesso total, sem RLS)
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } }
  );

  // ---------------------------------------------------------------------------
  // 1. Idempotência: tenta inserir em notificacoes
  //    Se já existe (uq_notificacoes_evento_pessoa), retorna 200 sem reenviar
  // ---------------------------------------------------------------------------

  let notificacaoId: number | null = null;

  if (payload.conteudo_id != null && payload.conteudo_tipo != null) {
    const { data: notif, error: notifErr } = await supabase
      .from('notificacoes')
      .insert({
        pessoa_id:     payload.pessoa_id,
        tipo:          payload.tipo,
        titulo:        payload.titulo,
        corpo:         payload.corpo,
        dados:         payload.dados ?? {},
        conteudo_id:   payload.conteudo_id,
        conteudo_tipo: payload.conteudo_tipo,
        lida:          false,
        enviada:       false,
        tentativas:    0,
      })
      .select('id')
      .single();

    if (notifErr) {
      // Código 23505 = unique_violation → já enviado, idempotente
      if (notifErr.code === '23505') {
        console.log(`[PUSH_SKIP] Idempotência: tipo=${payload.tipo} conteudo_id=${payload.conteudo_id} pessoa_id=${payload.pessoa_id}`);
        return new Response(JSON.stringify({ skipped: true, reason: 'already_sent' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      console.error('[PUSH] Erro ao inserir notificacao:', notifErr);
      // Prossegue mesmo sem registro de auditoria (melhor do que não enviar)
    } else {
      notificacaoId = notif?.id ?? null;
    }
  } else {
    // Sem conteudo_id: insere sem idempotência (eventos de atualização contínua)
    const { data: notif } = await supabase
      .from('notificacoes')
      .insert({
        pessoa_id:  payload.pessoa_id,
        tipo:       payload.tipo,
        titulo:     payload.titulo,
        corpo:      payload.corpo,
        dados:      payload.dados ?? {},
        lida:       false,
        enviada:    false,
        tentativas: 0,
      })
      .select('id')
      .single();
    notificacaoId = notif?.id ?? null;
  }

  // ---------------------------------------------------------------------------
  // 2. Busca tokens ativos para esta pessoa
  // ---------------------------------------------------------------------------

  const { data: dispositivos, error: dispErr } = await supabase
    .from('push_dispositivos')
    .select('id, token, plataforma')
    .eq('pessoa_id', payload.pessoa_id)
    .eq('ativo', true);

  if (dispErr || !dispositivos || dispositivos.length === 0) {
    console.log(`[PUSH_SKIP] Nenhum dispositivo ativo para pessoa_id=${payload.pessoa_id}`);
    if (notificacaoId) {
      await supabase
        .from('notificacoes')
        .update({ erro_envio: 'Nenhum dispositivo ativo', tentativas: 1 })
        .eq('id', notificacaoId);
    }
    return new Response(JSON.stringify({ sent: 0, reason: 'no_active_devices' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  console.log(`[PUSH_DEVICES] ${dispositivos.length} dispositivo(s) ativo(s) para pessoa_id=${payload.pessoa_id}`);

  // ---------------------------------------------------------------------------
  // 3. Obtém access_token do Google OAuth2 via Service Account JWT
  // ---------------------------------------------------------------------------

  let accessToken: string;
  try {
    accessToken = await getGoogleAccessToken();
  } catch (err) {
    console.error('[PUSH] Falha ao obter access_token Google:', err);
    if (notificacaoId) {
      await supabase
        .from('notificacoes')
        .update({
          erro_envio: `OAuth2 falhou: ${String(err)}`,
          tentativas: 1,
        })
        .eq('id', notificacaoId);
    }
    return new Response(JSON.stringify({ error: 'OAuth2 failure', details: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ---------------------------------------------------------------------------
  // 4. Envia para cada token via FCM HTTP v1 API
  // ---------------------------------------------------------------------------

  // Dados de rota para o Flutter (sem dados sensíveis)
  const dadosFlutter: Record<string, string> = {
    tipo: payload.tipo,
    ...(payload.dados
      ? Object.fromEntries(
          Object.entries(payload.dados).map(([k, v]) => [k, String(v)])
        )
      : {}),
  };
  if (notificacaoId) {
    dadosFlutter['notificacao_id'] = String(notificacaoId);
  }

  const resultados: FcmResult[] = await Promise.all(
    dispositivos.map((d) =>
      enviarFcm(accessToken, d.token, payload.titulo, payload.corpo, dadosFlutter)
    )
  );

  // ---------------------------------------------------------------------------
  // 5. Atualiza notificacoes com resultado agregado
  // ---------------------------------------------------------------------------

  const sucessos = resultados.filter((r) => r.success).length;
  const erros    = resultados.filter((r) => !r.success);

  if (notificacaoId) {
    if (sucessos > 0) {
      await supabase
        .from('notificacoes')
        .update({
          enviada:    true,
          enviada_at: new Date().toISOString(),
          tentativas: 1,
          erro_envio: erros.length > 0
            ? `${erros.length} token(s) falharam: ${erros.map((e) => e.errorCode).join(', ')}`
            : null,
        })
        .eq('id', notificacaoId);
    } else {
      await supabase
        .from('notificacoes')
        .update({
          enviada:    false,
          tentativas: 1,
          erro_envio: erros.map((e) => `${e.token.slice(-8)}: ${e.errorCode}`).join('; '),
        })
        .eq('id', notificacaoId);
    }
  }

  // ---------------------------------------------------------------------------
  // 6. Desativa tokens inválidos
  // ---------------------------------------------------------------------------

  const tokensInvalidos = resultados
    .filter((r) => !r.success && r.errorCode && INVALID_TOKEN_CODES.has(r.errorCode))
    .map((r) => r.token);

  if (tokensInvalidos.length > 0) {
    console.log(`[PUSH_INVALID] Desativando ${tokensInvalidos.length} token(s) inválido(s)`);
    await supabase.rpc('desativar_token_invalido', { p_token: tokensInvalidos[0] });
    // Para múltiplos tokens inválidos, chama individualmente
    for (const token of tokensInvalidos.slice(1)) {
      await supabase.rpc('desativar_token_invalido', { p_token: token });
    }
  }

  console.log(`[PUSH_DONE] tipo=${payload.tipo} pessoa_id=${payload.pessoa_id} enviados=${sucessos}/${dispositivos.length}`);

  return new Response(
    JSON.stringify({
      sent:    sucessos,
      total:   dispositivos.length,
      failed:  erros.length,
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
});

// ---------------------------------------------------------------------------
// Google OAuth2: gera access_token a partir do Service Account JSON
// Usa RS256 JWT assinado com a private_key da Service Account.
// ---------------------------------------------------------------------------

async function getGoogleAccessToken(): Promise<string> {
  const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!saJson) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON não configurado');
  }

  const sa: ServiceAccountKey = JSON.parse(saJson);

  const now     = Math.floor(Date.now() / 1000);
  const expires = now + 3600; // 1 hora

  // Monta JWT header + payload
  const header  = { alg: 'RS256', typ: 'JWT' };
  const jwtBody = {
    iss  : sa.client_email,
    scope: FCM_SCOPE,
    aud  : sa.token_uri || 'https://oauth2.googleapis.com/token',
    iat  : now,
    exp  : expires,
  };

  const encode = (obj: object) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');

  const headerB64  = encode(header);
  const payloadB64 = encode(jwtBody);
  const toSign     = `${headerB64}.${payloadB64}`;

  // Importa a chave RSA privada no formato PEM
  const pemKey = sa.private_key;
  const binaryKey = pemToBinary(pemKey);
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );

  // Assina
  const encoder   = new TextEncoder();
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    encoder.encode(toSign)
  );

  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  const jwt = `${toSign}.${signatureB64}`;

  // Troca JWT por access_token
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion:  jwt,
    }),
  });

  if (!tokenRes.ok) {
    const errText = await tokenRes.text();
    throw new Error(`Google token exchange falhou (${tokenRes.status}): ${errText}`);
  }

  const tokenData = await tokenRes.json();
  return tokenData.access_token as string;
}

// Converte PEM RSA privada → ArrayBuffer (PKCS#8 DER)
function pemToBinary(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(b64);
  const bytes  = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// ---------------------------------------------------------------------------
// Envia uma mensagem FCM HTTP v1 para um token específico
// ---------------------------------------------------------------------------

async function enviarFcm(
  accessToken: string,
  token: string,
  titulo: string,
  corpo: string,
  dados: Record<string, string>
): Promise<FcmResult> {
  const message = {
    message: {
      token,
      // Notification: exibe na bandeja do sistema (background/encerrado)
      notification: {
        title: titulo,
        body:  corpo,
      },
      // Data: entregue ao app em foreground e background (usado para roteamento)
      data: dados,
      // Configurações específicas de plataforma
      apns: {
        payload: {
          aps: {
            sound: 'default',
            'content-available': 1,
          },
        },
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channel_id: 'aeterna_transacional',
        },
      },
    },
  };

  try {
    const res = await fetch(FCM_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify(message),
    });

    if (res.ok) {
      const data = await res.json();
      console.log(`[PUSH_FCM_OK] token=...${token.slice(-8)} name=${data?.name}`);
      return { token, success: true };
    }

    // Falha
    const errData = await res.json().catch(() => ({}));
    const fcmError = errData?.error;
    const errorCode: string =
      (fcmError?.details?.[0]?.errorCode as string) ??
      (fcmError?.status as string) ??
      String(res.status);

    console.warn(`[PUSH_FCM_ERR] token=...${token.slice(-8)} code=${errorCode} status=${res.status}`);
    return { token, success: false, error: fcmError?.message, errorCode };

  } catch (err) {
    console.error(`[PUSH_FCM_EXCEPTION] token=...${token.slice(-8)}`, err);
    return { token, success: false, error: String(err), errorCode: 'EXCEPTION' };
  }
}
