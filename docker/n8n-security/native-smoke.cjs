const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const { createRequire } = require('node:module');
const root = '/usr/local/lib/node_modules/n8n';
const requireN8n = createRequire(`${root}/package.json`);
assert.equal(process.version, 'v26.12.1');
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
assert.match(execFileSync('brotli', ['--version'], { encoding: 'utf8' }), /1\.2\.1/);
const encoded = execFileSync('brotli', ['-c'], { input: 'shared-library roundtrip' });
assert.equal(execFileSync('brotli', ['-d', '-c'], { input: encoded }).toString(), 'shared-library roundtrip');
assert.equal(fs.realpathSync('/usr/lib/libbrotlidec.so.1'), '/usr/lib/libbrotlidec.so.1.2.1');
assert.equal(fs.existsSync('/usr/lib/libbrotlidec.so.1.2.0'), false);
assert.match(fs.readFileSync('/usr/local/share/runtime-security/brotli.txt', 'utf8'), /db24a98/);
for (const [command, version] of [['git', /2\.54\.0/], ['corepack', /0\.36\.0/], ['yarn', /1\.22\.22/]]) {
  assert.match(execFileSync(command, ['--version'], { encoding: 'utf8' }), version);
}
console.log('patched shared Brotli and vendor helper commands passed');
