#!/bin/sh
set -eu
export N8N_DIAGNOSTICS_ENABLED=false N8N_VERSION_NOTIFICATIONS_ENABLED=false N8N_TEMPLATES_ENABLED=false N8N_SECURE_COOKIE=false
# Isolated, disposable data only. This key is a public fixture, never production.
export N8N_ENCRYPTION_KEY=public-local-test-fixture-not-production
node -e 'require("http").createServer((req,res)=>{res.setHeader("Content-Type","application/json");res.end(JSON.stringify({runtimeSmoke:true}));}).listen(18081,"127.0.0.1")' &
upstream=$!
trap 'kill "$upstream" "${server:-}" 2>/dev/null || true' EXIT
n8n import:workflow --input=/tests/workflow-smoke.json >/tmp/import.log 2>&1
n8n import:credentials --input=/tests/credential-smoke.json >/tmp/credentials-import.log 2>&1
n8n export:credentials --all --decrypted --output=/tmp/credential-roundtrip.json >/tmp/credentials-export.log 2>&1
node -e 'const a=require("/tmp/credential-roundtrip.json");if(a.length!==1||a[0].data.value!=="public-local-fixture")process.exit(1);console.log("synthetic encrypted credential roundtrip passed")'
n8n execute --id=securityRuntimeSmoke --rawOutput >/tmp/execute.log 2>&1
grep -q '"runtimeSmoke":true' /tmp/execute.log || grep -q '"runtimeSmoke": true' /tmp/execute.log
echo 'manual trigger -> Code -> HTTP request -> JSON workflow passed'
n8n publish:workflow --id=securityWebhookSmoke >/tmp/activate.log 2>&1
n8n start >/tmp/start.log 2>&1 &
server=$!
for attempt in $(seq 1 60); do
  if node -e 'fetch("http://127.0.0.1:5678/healthz/readiness").then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))'; then break; fi
  sleep 1
done
# Readiness can precede registration of published workflows. Retry only a 404
# during this bounded startup window; other errors still fail immediately.
node <<'JS'
(async () => {
  for (let attempt = 0; attempt < 40; attempt++) {
    const response = await fetch('http://127.0.0.1:5678/webhook/security-runtime-smoke', { signal: AbortSignal.timeout(2000) });
    await response.arrayBuffer();
    if (response.ok) { console.log('active webhook HTTP ' + response.status); return; }
    if (response.status !== 404) throw new Error('webhook status ' + response.status);
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error('published webhook did not register within 20 seconds');
})().catch(error => { console.error(error.message); process.exit(1); });
JS
echo 'isolated n8n start, SQLite migrations, workflow activation and webhook passed'
