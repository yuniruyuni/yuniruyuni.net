const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const hash = filename => crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
const hashes = filenames => Object.fromEntries(filenames.map(filename => [filename, hash(filename)]));
const packages = Object.fromEntries(
  fs.readFileSync('/lib/apk/db/installed', 'utf8').split('\n\n')
    .filter(record => /^P:/m.test(record))
    .map(record => [record.match(/^P:(.+)$/m)[1], record.match(/^V:(.+)$/m)[1]]),
);

function walk(directory, visit) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(filename, visit);
    else if (entry.isFile()) visit(filename);
  }
}

const native = {};
walk('/usr/local/lib/node_modules/n8n', filename => {
  if (filename.endsWith('.node')) native[filename] = hash(filename);
});
const critical = hashes([
  process.execPath, '/docker-entrypoint.sh', '/usr/bin/git', '/etc/passwd', '/etc/group',
  '/usr/share/node_modules/corepack/package.json', '/usr/share/node_modules/yarn/package.json',
  '/usr/local/lib/node_modules/n8n/package.json',
]);
const trust = hashes([
  '/etc/apk/repositories',
  ...fs.readdirSync('/etc/apk/keys').map(name => `/etc/apk/keys/${name}`),
]);
const dbRoot = '/usr/local/lib/node_modules/n8n/node_modules/.pnpm';
const migrations = {};
for (const directory of fs.readdirSync(dbRoot).filter(name => name.startsWith('@n8n+db@'))) {
  walk(path.join(dbRoot, directory, 'node_modules/@n8n/db/dist'), filename => {
    if (filename.includes('/migrations/') && !filename.endsWith('.map')) {
      migrations[filename.substring(filename.indexOf('/dist/'))] = hash(filename);
    }
  });
}
console.log(JSON.stringify({ packages, critical, trust, native, migrations }));
