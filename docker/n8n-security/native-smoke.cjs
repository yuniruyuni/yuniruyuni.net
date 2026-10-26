const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const { createRequire } = require('node:module');
const root = '/usr/local/lib/node_modules/n8n';
const requireN8n = createRequire(`${root}/package.json`);
assert.equal(process.version, 'v26.12.1');
assert.equal(requireN8n('./package.json').version, '2.45.3');
console.log(JSON.stringify({ node: process.version, modules: process.versions.modules, openssl: process.versions.openssl }));
const ivm = requireN8n('isolated-vm');
const isolate = new ivm.Isolate({ memoryLimit: 16 });
const context = isolate.createContextSync();
assert.equal(context.evalSync('21 * 2'), 42);
isolate.dispose();
console.log('isolated-vm execution passed');
const sqlite3 = requireN8n('sqlite3');
const db = new sqlite3.Database(':memory:');
db.get('SELECT 21 * 2 AS answer', (error, row) => {
  assert.ifError(error);
  assert.equal(row.answer, 42);
  db.close();
  console.log('sqlite3 query passed');
});
const pnpm = `${root}/node_modules/.pnpm`;
const kafkaDir = fs.readdirSync(pnpm).find(name => name.startsWith('@confluentinc+kafka-javascript@'));
const kafka = require(`${pnpm}/${kafkaDir}/node_modules/@confluentinc/kafka-javascript`);
assert.ok(kafka.KafkaJS || kafka.Kafka || kafka.Producer);
console.log('Kafka native binding load passed');
for (const [prefix, relative] of [
  ['@sentry+node-cpu-profiler@', '@sentry/node-cpu-profiler/lib/sentry_cpu_profiler-linux-x64-musl-147.node'],
  ['@sentry+node-native-stacktrace@', '@sentry/node-native-stacktrace/lib/stack-trace-linux-x64-musl-147.node'],
  ['snowflake-sdk@', 'snowflake-sdk/dist/lib/minicore/binaries/sf_mini_core_0.0.1.linux-x64-musl.node'],
]) {
  const directory = fs.readdirSync(pnpm).find(name => name.startsWith(prefix));
  require(`${pnpm}/${directory}/node_modules/${relative}`);
  console.log(`${prefix} musl binding load passed`);
}
const zlib = require('node:zlib');
assert.equal(zlib.brotliDecompressSync(zlib.brotliCompressSync('roundtrip')).toString(), 'roundtrip');
console.log('patched Node Brotli roundtrip passed');
// The transient CLI used for the build-time shared-library roundtrip is absent
// from the final image; the official runtime's command set is preserved.
assert.equal(fs.realpathSync('/usr/lib/libbrotlidec.so.1'), '/usr/lib/libbrotlidec.so.1.2.1');
assert.equal(fs.existsSync('/usr/lib/libbrotlidec.so.1.2.0'), false);
assert.match(fs.readFileSync('/lib/apk/db/installed', 'utf8'), /P:brotli-libs\nV:1\.2\.1-r0\n/);
assert.ok(fs.readFileSync('/usr/lib/libbrotlidec.so.1').includes(Buffer.from('BLOCK_SWITCH\0')));
assert.match(fs.readFileSync('/usr/local/share/runtime-security/brotli.txt', 'utf8'), /db24a98/);
for (const target of ['/usr/lib/libcurl.so.4', '/usr/libexec/git-core/git-remote-http']) {
  assert.match(execFileSync('/lib/ld-musl-x86_64.so.1', ['--list', target], { encoding: 'utf8' }), /libbrotlidec\.so\.1 => \/usr\/lib\/libbrotlidec\.so\.1/);
}
for (const [command, version] of [['git', /2\.55\.0/], ['corepack', /0\.36\.0/], ['yarn', /1\.22\.22/], ['npm', /11\.21\.1/]]) {
  assert.match(execFileSync(command, ['--version'], { encoding: 'utf8' }), version);
}
for (const temporary of ['/tmp/apk.static', '/tmp/brotli', '/tmp/security-packages', '/tmp/alpine-keys']) assert.equal(fs.existsSync(temporary), false);
console.log('patched shared Brotli package, libcurl/Git linkage and unchanged official helpers passed');
