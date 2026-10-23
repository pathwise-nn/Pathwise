'use strict';
// Sets Pathwise's version everywhere it is written: the TOC's ## Version,
// package.json, and a new CHANGELOG.md section made from "Unreleased".
//
//   node tools/version.js 0.2.0
//
// It does not tag, commit or upload anything.

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const v = process.argv[2];
if (!/^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/.test(v || '')) {
	console.error('usage: node tools/version.js <major.minor.patch>   e.g. 0.2.0');
	process.exit(2);
}

const toc = path.join(ROOT, 'Pathwise', 'Pathwise.toc');
fs.writeFileSync(toc, fs.readFileSync(toc, 'utf8').replace(/^## Version:.*$/m, `## Version: ${v}`));

const pkgPath = path.join(ROOT, 'package.json');
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
pkg.version = v;
fs.writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);

const logPath = path.join(ROOT, 'CHANGELOG.md');
const log = fs.readFileSync(logPath, 'utf8');
const today = new Date().toISOString().slice(0, 10);
if (!log.includes('## Unreleased')) {
	console.error('CHANGELOG.md has no "## Unreleased" section to release');
	process.exit(1);
}
fs.writeFileSync(logPath, log.replace('## Unreleased', `## Unreleased\n\n## ${v} (${today})`));
console.log(`version ${v}: Pathwise.toc, package.json, CHANGELOG.md`);
