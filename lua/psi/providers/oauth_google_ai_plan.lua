-- Port of Pi #12614's Google AI Ultra OAuth flow (manual loopback URL paste).
-- Node supplies P-256 and HTTPS for this optional provider only. No client
-- identity ships with psi; secrets and signing keys enter Node over stdin.
local storage = require("psi.auth_storage")
local prelude = require("psi.prelude")
local sched = require("psi.sched")
local M = {}
local PROVIDER = "google-ai-plan"
local flow

local helper = [=[
const { readFileSync } = require('node:fs');
const { createHash, createPrivateKey, generateKeyPairSync, randomBytes, randomInt, sign } = require('node:crypto');
const authorize = 'https://accounts.google.com/o/oauth2/v2/auth';
const token = 'https://oauth2.googleapis.com/token';
const scope = 'https://www.googleapis.com/auth/generative-language.peruserquota';
const hash = s => createHash('sha256').update(s).digest('base64url');
const random = () => randomBytes(32).toString('base64url');
const encode = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const present = s => typeof s === 'string' && s.length > 0 && !/[\r\n]/.test(s);
const now = () => Math.floor(Date.now() / 1000);
const expired = 'Google sign-in expired or was revoked. Run /login google-ai-plan again.';

async function main({ action, client, secret, session, input, entry }) {
  if (action === 'begin') {
    const verifier = random(), nonce = random(), state = random();
    const key = generateKeyPairSync('ec', { namedCurve: 'P-256' }).privateKey.export({ format: 'jwk' });
    const redirect = `http://127.0.0.1:${randomInt(49152, 65536)}/oauth2callback`;
    const query = new URLSearchParams({ client_id: client, redirect_uri: redirect, response_type: 'code',
      scope: `openid email profile ${scope}`, code_challenge: hash(verifier), code_challenge_method: 'S256',
      state, nonce, access_type: 'offline' });
    return { verifier, nonce, state, key, redirect, url: `${authorize}?${query}`, expires: now() + 600 };
  }
  const login = action === 'finish';
  let code, key, proofNonce, iat;
  if (login) {
    if (now() >= session.expires) return { error: 'Login expired. Start again with /login google-ai-plan.' };
    let url;
    try { url = new URL(input); } catch { return { error: 'Paste the full redirect URL, not just the code.' }; }
    if (`${url.origin}${url.pathname}` !== session.redirect || url.searchParams.get('state') !== session.state)
      return { error: 'Google OAuth redirect or state mismatch.' };
    if (url.searchParams.has('error')) return { error: 'Google declined or canceled sign-in.' };
    code = url.searchParams.get('code');
    if (!present(code)) return { error: 'Google OAuth redirect is missing a code.' };
    key = session.key;
  } else {
    key = entry.key;
    proofNonce = entry.dpop_nonce;
  }
  const { kty, crv, x, y } = key;
  const signingKey = createPrivateKey({ key, format: 'jwk' });
  let nonceRetried = false;
  for (let attempt = 0; attempt < 3; attempt++) {
    const proof = `${encode({ typ: 'dpop+jwt', alg: 'ES256', jwk: { kty, crv, x, y } })}.${encode({
      jti: login ? hash(code) : random(), htm: 'POST', htu: token, iat: iat ?? now(),
      ...(proofNonce ? { nonce: proofNonce } : {}) })}`;
    const signature = sign('sha256', Buffer.from(proof), { key: signingKey, dsaEncoding: 'ieee-p1363' });
    const params = login ? { grant_type: 'authorization_code', code, code_verifier: session.verifier,
      redirect_uri: session.redirect } : { grant_type: 'refresh_token', refresh_token: entry.refresh };
    const response = await fetch(token, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: { Accept: 'application/json', DPoP: `${proof}.${signature.toString('base64url')}` },
      body: new URLSearchParams({ ...params, client_id: client, client_secret: secret }) });
    const body = await response.json();
    const nonce = response.headers.get('DPoP-Nonce');
    if (response.ok && present(body.access_token)) {
      if (login) {
        if (!present(body.refresh_token) || !body.scope?.split(/\s+/).includes(scope))
          return { error: 'Google did not grant offline access to the AI Ultra plan.' };
        // OIDC permits relying on TLS for an ID token received directly from the token endpoint.
        let claims;
        try { claims = JSON.parse(Buffer.from(body.id_token.split('.')[1], 'base64url')); } catch { claims = {}; }
        if (!['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss) ||
          claims.aud !== client || claims.nonce !== session.nonce || !(claims.exp > now() - 60))
          return { error: 'Google returned an ID token that failed validation.' };
      }
      const expiresIn = Number(body.expires_in);
      return { type: 'oauth', access: body.access_token, refresh: body.refresh_token || entry?.refresh,
        expires: (now() + (expiresIn > 0 && Number.isFinite(expiresIn) ? expiresIn : 3599)) * 1000,
        key, client, dpop_nonce: login ? undefined : (nonce ?? proofNonce) };
    }
    if (!login && !nonceRetried && body.error === 'use_dpop_nonce' && nonce && nonce !== proofNonce) {
      nonceRetried = true;
      proofNonce = nonce;
    } else if (!login && !iat && body.error === 'invalid_dpop_proof' && Number.isFinite(Date.parse(response.headers.get('date')))) {
      iat = Math.floor(Date.parse(response.headers.get('date')) / 1000);
    } else {
      if (!login && ['invalid_grant', 'unauthorized_client'].includes(body.error)) return { error: expired };
      return { error: `Google token request failed (HTTP ${response.status}). Check Psi's client approval and sign-in.` };
    }
  }
}
Promise.resolve().then(() => main(JSON.parse(readFileSync(0, 'utf8')))).then(
  r => process.stdout.write(JSON.stringify(r || { error: 'Google rejected the DPoP proof.' })),
  () => process.stdout.write(JSON.stringify({ error: 'Google OAuth request failed. Check Node.js and network access.' }))
);
]=]

local function configured()
  local client, secret =
    os.getenv("PSI_GOOGLE_AI_PLAN_CLIENT_ID"), os.getenv("PSI_GOOGLE_AI_PLAN_CLIENT_SECRET")
  if client and client ~= "" and secret and secret ~= "" then
    return client, secret
  end
end

local function request(args)
  args.client, args.secret = configured()
  if not args.client then
    return nil,
      "Set PSI_GOOGLE_AI_PLAN_CLIENT_ID and PSI_GOOGLE_AI_PLAN_CLIENT_SECRET for an approved Psi Desktop client"
  end
  if not psi.process_begin_stdio_argv then
    return nil, "Google AI Ultra login requires process support and Node.js 22 or newer"
  end
  local handle = psi.process_begin_stdio_argv({ "node", "-e", helper })
  if not handle then
    return nil, "Google AI Ultra requires Node.js 22 or newer on PATH"
  end
  local written = psi.process_write(handle, psi.json_encode(args))
  if written and psi.process_close_stdin(handle) then
    local poll = sched.in_coroutine() and sched.proc_poll or psi.process_poll
    repeat
      if psi.is_aborted() then
        psi.process_terminate(handle)
        break
      end
      local _, done = poll(handle, 50)
      if done then
        break
      end
    until false
  else
    psi.process_terminate(handle)
  end
  local result = psi.process_finish(handle)
  local response = written
    and result.status == 0
    and not result.truncated
    and prelude.safe_json_decode(result.output, nil)
  if type(response) ~= "table" then
    return nil, "Google OAuth helper failed; check that Node.js 22 or newer is on PATH"
  end
  if response.error then
    return nil, response.error
  end
  return response
end

function M.begin_login()
  local err
  flow, err = request({ action = "begin" })
  return flow and { url = flow.url, require_redirect_url = true } or nil, err
end

function M.finish_login(input)
  if not flow then
    return false, "No pending login. Run /login google-ai-plan first."
  end
  local session = flow
  flow = nil
  local entry, err = request({ action = "finish", session = session, input = input })
  if not entry then
    return false, err
  end
  local ok, write_err = storage.set(PROVIDER, entry)
  return ok, ok and "Signed in to Google AI Ultra" or write_err
end

local function stored()
  local client = configured()
  local entry = client and storage.get(PROVIDER)
  return type(entry) == "table"
      and entry.type == "oauth"
      and entry.client == client
      and type(entry.refresh) == "string"
      and type(entry.key) == "table"
      and entry
    or nil
end

function M.has_credentials()
  return stored() ~= nil
end

function M.credentials()
  local entry = stored()
  if not entry then
    return nil, "Run /login google-ai-plan first"
  end
  if
    type(entry.access) == "string"
    and not entry.access:find("[\r\n]")
    and (tonumber(entry.expires) or 0) > (os.time() + 300) * 1000
  then
    return entry
  end
  local updated, err = request({ action = "refresh", entry = entry })
  if not updated then
    return nil, err
  end
  local ok, write_err = storage.set(PROVIDER, updated)
  if not ok then
    return nil, write_err
  end
  return updated
end

return M
