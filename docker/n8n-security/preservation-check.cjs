const assert = require('node:assert/strict');
const fs = require('node:fs');
const directory = process.argv[2];
const read = name => JSON.parse(fs.readFileSync(`${directory}/${name}`, 'utf8'));
const base = read('base.json');
const candidate = read('candidate.json');
const baseImage = read('base-inspect.json')[0];
const candidateImage = read('candidate-inspect.json')[0];
for (const key of ['User', 'Env', 'Entrypoint', 'Cmd', 'WorkingDir', 'ExposedPorts', 'Volumes', 'StopSignal', 'Healthcheck']) {
  assert.deepEqual(candidateImage.Config[key], baseImage.Config[key], `Official image configuration changed: ${key}`);
}
assert.deepEqual(candidateImage.RootFS.Layers.slice(0, baseImage.RootFS.Layers.length), baseImage.RootFS.Layers);
assert.equal(candidateImage.RootFS.Layers.length, baseImage.RootFS.Layers.length + 1);
const changed = Object.keys({ ...base.packages, ...candidate.packages }).filter(name => base.packages[name] !== candidate.packages[name]);
assert.deepEqual(changed, ['brotli-libs']);
assert.equal(candidate.packages['brotli-libs'], '1.2.1-r0');
for (const key of ['critical', 'trust', 'native', 'migrations']) assert.deepEqual(candidate[key], base[key], `Official ${key} files changed`);
console.log(JSON.stringify({ changedPackages: changed, nativeFilesPreserved: Object.keys(base.native).length, trustFilesPreserved: Object.keys(base.trust).length, addedLayers: 1 }));
