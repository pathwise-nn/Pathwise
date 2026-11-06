'use strict';
// Rebuilds Pathwise_Loot/Data/Loot.lua (npm run loot).
//
//   node tools/data/loot.js [build]      (default: the newest Forever build)
//
// 1. Downloads the Forever client's tables Map, Difficulty, DungeonEncounter, ItemSparse
//    and Item as CSV from wago.tools (product "wowf") into
//    data/sources/wago/<build>/ (not committed), unless already there.
// 2. Runs tools/data/loot.lua with them and QuestieDB's Forever data in
//    data/sources/questiedb (docs/DATA.md says how to get it).

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const PRODUCT = 'wowf';
const TABLES = ['Map', 'Difficulty', 'DungeonEncounter', 'ItemSparse', 'Item'];

async function newestBuild() {
	const r = await fetch('https://wago.tools/api/builds');
	if (!r.ok) throw new Error(`wago.tools builds: HTTP ${r.status}`);
	const list = (await r.json())[PRODUCT];
	if (!list || !list.length) throw new Error(`wago.tools lists no ${PRODUCT} build`);
	return list[0].version;
}

async function download(build, name) {
	const dir = path.join(ROOT, 'data', 'sources', 'wago', build);
	const file = path.join(dir, `${name}.csv`);
	if (fs.existsSync(file) && fs.statSync(file).size > 0) return;
	fs.mkdirSync(dir, { recursive: true });
	const url = `https://wago.tools/db2/${name}/csv?build=${build}`;
	console.log(`downloading ${url}`);
	const r = await fetch(url);
	const body = Buffer.from(await r.arrayBuffer());
	if (!r.ok || body.subarray(0, 1).toString() === '{') throw new Error(`${url}: HTTP ${r.status} ${body.toString().slice(0, 80)}`);
	fs.writeFileSync(file, body);
}

async function main() {
	const build = process.argv[2] || await newestBuild();
	for (const t of TABLES) await download(build, t);
	const qdb = path.join(ROOT, 'data', 'sources', 'questiedb');
	if (!fs.existsSync(qdb)) throw new Error('data/sources/questiedb is missing: see docs/DATA.md');
	execFileSync('lua5.1', ['tools/data/loot.lua', qdb, path.join(ROOT, 'data', 'sources', 'wago', build)], { cwd: ROOT, stdio: 'inherit' });
}

main().catch((e) => { console.error(e.message); process.exit(1); });
