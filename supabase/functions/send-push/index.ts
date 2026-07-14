// supabase/functions/send-push/index.ts
// Sprint S.9.2 — Push Notifications Transacionais
//
// Duas formas de chamada:
//   A) Database Webhook (INSERT em `notificacoes`):
//      { type: "INSERT", table: "notificacoes", record: { ... }, schema: "public" }
//   B) Dispatch direto (app / teste SQL):
//      { notificacao_id: <bigint> }
//
// Fluxo:
//   1. Resolve a linha em `notificacoes`
//   2. Busca tokens ativos em push_dispositivos para o pessoa_id
//   3. Obtém access_token do FCM via OAuth2 JWT (RS256) com FIREBASE_SERVICE_ACCOUNT_JSON
//   4. Envia mensagem FCM HTTP v1 para cada token (APNs priority 10)
//   5. Atualiza notificacoes (enviada, enviada_at, tentativas, erro_envio)
//   6. Desativa tokens inválidos via RPC desativar_token_invalido

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const FCM_PROJECT_ID = 'aeterna-94450';
const FCM_SCOPE      = 'https://www.googleapis.com/auth/firebase.messaging';
const FCM_ENDPOINT   = `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`;

const INVALID_TOKEN_CODES = new Set([
  'NOT_REGISTERED',
  'INVALID_ARGUMENT',
  'UNREGISTERED',
]);

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface WebhookPayload {
  type?:   'INSERT' | 'UPDATE' | 'DELETE';
  table?:  string;
  schema?: string;
  record?: NotificacaoRecord;
  notificacao_id?: number;
}

interface NotificacaoRecord {
  id:            number;
  pessoa_id:     number;
  tipo:          string;
  titulo:        string;
  corpo:         string;
  dados:         Record<string, unknown> | null;
  conteudo_id:   number | null;
  conteudo_tipo: string | null;
  enviada:       boolean;
  tentativas:    number;
  erro_envio?:   string | null;
}

interface PushDispositivo {
  token:      string;
  plataforma: string;
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

serve(async (req: Request) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    const payload: WebhookPayload = await req.json();

    const supabaseUrl        = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey     = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');

    if (!serviceAccountJson) {
      console.error('[PUSH] FIREBASE_SERVICE_ACCOUNT_JSON não configurado');
      return new Response(
        JSON.stringify({
          error: 'missing firebase config',
          hint: 'Supabase → Edge Functions → Secrets → FIREBASE_SERVICE_ACCOUNT_JSON (JSON da service account Firebase com private_key)',
        }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Resolve a notificação: webhook INSERT ou dispatch { notificacao_id }
    let notif: NotificacaoRecord | null = null;

    if (typeof payload.notificacao_id === 'number') {
      const { data, error } = await supabase
        .from('notificacoes')
        .select('id, pessoa_id, tipo, titulo, corpo, dados, conteudo_id, conteudo_tipo, enviada, tentativas, erro_envio')
        .eq('id', payload.notificacao_id)
        .maybeSingle();
      if (error) {
        console.error('[PUSH] Erro ao buscar notificacao_id:', error.message);
        return new Response('error fetching notification', { status: 500 });
      }
      notif = data as NotificacaoRecord | null;
      if (!notif) {
        return new Response('notification not found', { status: 404 });
      }
    } else if (payload.type === 'INSERT' && payload.table === 'notificacoes' && payload.record) {
      notif = payload.record;
    } else {
      return new Response('ignored', { status: 200 });
    }

    if (notif.enviada) {
      return new Response('already sent', { status: 200 });
    }

    return await processarNotificacao(supabase, serviceAccountJson, notif);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[PUSH] Erro inesperado:', msg);
    return new Response(`unexpected error: ${msg}`, { status: 500 });
  }
});

async function processarNotificacao(
  supabase: SupabaseClient,
  serviceAccountJson: string,
  notif: NotificacaoRecord,
): Promise<Response> {
  // 1. Busca tokens ativos para o destinatário
  const { data: dispositivos, error: errTokens } = await supabase
    .from('push_dispositivos')
    .select('token, plataforma')
    .eq('pessoa_id', notif.pessoa_id)
    .eq('ativo', true);

  if (errTokens) {
    console.error('[PUSH] Erro ao buscar tokens:', errTokens.message);
    await marcarErro(supabase, notif.id, errTokens.message, notif.tentativas);
    return new Response('error fetching tokens', { status: 500 });
  }

  if (!dispositivos || dispositivos.length === 0) {
    const msg = `nenhum token ativo para pessoa_id=${notif.pessoa_id}`;
    console.log(`[PUSH] ${msg}`);
    // NÃO marcar enviada — deixa pendente para retry quando o token chegar
    await marcarErro(supabase, notif.id, msg, notif.tentativas);
    return new Response(JSON.stringify({ enviou: false, erros: [msg] }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // 2. Obtém access_token do FCM
  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken(serviceAccountJson);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[PUSH] Erro ao obter token FCM:', msg);
    await marcarErro(supabase, notif.id, `FCM auth: ${msg}`, notif.tentativas);
    return new Response('fcm auth error', { status: 500 });
  }

  // 3. Envia para cada token
  const erros: string[] = [];
  let enviouPeloMenos = false;

  for (const disp of dispositivos as PushDispositivo[]) {
    const result = await enviarFcm(accessToken, disp.token, {
      titulo:        notif.titulo,
      corpo:         notif.corpo,
      dados:         notif.dados ?? {},
      notificacaoId: notif.id,
      tipo:          notif.tipo,
    });

    if (result.ok) {
      enviouPeloMenos = true;
      console.log(`[PUSH] Enviado para token ...${disp.token.slice(-8)} plat=${disp.plataforma}`);
    } else {
      console.warn(`[PUSH] Falha token ...${disp.token.slice(-8)}: ${result.error}`);
      erros.push(result.error ?? 'unknown');

      if (result.invalidToken) {
        await supabase.rpc('desativar_token_invalido', { p_token: disp.token });
        console.log(`[PUSH] Token inválido desativado: ...${disp.token.slice(-8)}`);
      }
    }
  }

  // 4. Atualiza notificacoes
  if (enviouPeloMenos) {
    await marcarEnviada(supabase, notif.id, notif.tentativas);
  } else {
    await marcarErro(supabase, notif.id, erros.join('; ') || 'todos tokens falharam', notif.tentativas);
  }

  return new Response(JSON.stringify({ enviou: enviouPeloMenos, erros }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// ---------------------------------------------------------------------------
// FCM HTTP v1 — envio por token
// ---------------------------------------------------------------------------

async function enviarFcm(
  accessToken: string,
  token: string,
  payload: {
    titulo: string;
    corpo:  string;
    dados:  Record<string, unknown>;
    notificacaoId: number;
    tipo: string;
  }
): Promise<{ ok: boolean; error?: string; invalidToken?: boolean }> {
  // FCM exige que todos os valores em `data` sejam strings
  const dataPayload: Record<string, string> = {
    notificacao_id: String(payload.notificacaoId),
    tipo: payload.tipo,
  };
  for (const [k, v] of Object.entries(payload.dados)) {
    dataPayload[k] = String(v);
  }

  const body = JSON.stringify({
    message: {
      token,
      notification: {
        title: payload.titulo,
        body:  payload.corpo,
      },
      data: dataPayload,
      android: {
        priority: 'high',
        notification: { channel_id: 'aeterna_transacional' },
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            alert: { title: payload.titulo, body: payload.corpo },
            sound: 'default',
            'content-available': 1,
          },
        },
      },
    },
  });

  const res = await fetch(FCM_ENDPOINT, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
    },
    body,
  });

  if (res.ok) return { ok: true };

  const errBody = await res.json().catch(() => ({}));
  const fcmCode = (
    errBody?.error?.details?.[0]?.errorCode as string | undefined
    ?? errBody?.error?.status as string | undefined
    ?? String(res.status)
  );

  console.warn('[PUSH] FCM HTTP error:', JSON.stringify(errBody));

  return {
    ok:           false,
    error:        fcmCode,
    invalidToken: INVALID_TOKEN_CODES.has(fcmCode),
  };
}

// ---------------------------------------------------------------------------
// OAuth2 — JWT RS256 → access_token do Google
// ---------------------------------------------------------------------------

async function getFcmAccessToken(serviceAccountJson: string): Promise<string> {
  const sa  = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);

  // Secrets às vezes preservam \n literal na private_key
  let privateKeyPem = String(sa.private_key ?? '');
  if (privateKeyPem.includes('\\n')) {
    privateKeyPem = privateKeyPem.replace(/\\n/g, '\n');
  }

  const header  = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss:   sa.client_email,
    scope: FCM_SCOPE,
    aud:   'https://oauth2.googleapis.com/token',
    iat:   now,
    exp:   now + 3600,
  };

  const encode = (obj: unknown) =>
    btoa(JSON.stringify(obj))
      .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

  const signingInput = `${encode(header)}.${encode(payload)}`;

  const pemBody = privateKeyPem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');

  const keyBytes = Uint8Array.from(atob(pemBody), c => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const signatureBytes = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const signature = btoa(String.fromCharCode(...new Uint8Array(signatureBytes)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

  const jwt = `${signingInput}.${signature}`;

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`Google token exchange falhou: ${err}`);
  }

  const { access_token } = await tokenRes.json();
  return access_token as string;
}

// ---------------------------------------------------------------------------
// Helpers de atualização em notificacoes
// ---------------------------------------------------------------------------

async function marcarEnviada(
  supabase: SupabaseClient,
  id: number,
  tentativasAtuais: number
): Promise<void> {
  await supabase
    .from('notificacoes')
    .update({
      enviada:    true,
      enviada_at: new Date().toISOString(),
      tentativas: tentativasAtuais + 1,
      erro_envio: null,
    })
    .eq('id', id);
}

async function marcarErro(
  supabase: SupabaseClient,
  id: number,
  erro: string,
  tentativasAtuais: number
): Promise<void> {
  await supabase
    .from('notificacoes')
    .update({
      tentativas: tentativasAtuais + 1,
      erro_envio: erro.slice(0, 500),
    })
    .eq('id', id);
}
