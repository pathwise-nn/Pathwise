'use strict';
// The Forever client's tables as CSV from wago.tools (product "wowf"),
// cached in data/sources/wago/<build>/ (not committed).

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');

// A CSV line into fields ("quoted, with commas" and "" escapes).
function splitCsv(line) {
	const out = [];
	let cur = '';
	let q = false;
	for (let i = 0; i < line.length; i++) {
		const c = line[i];
		if (q) {
			if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; }
			else if (c === '"') q = false;
			else cur += c;
		} else if (c === '"') q = true;
		else if (c === ',') { out.push(cur); cur = ''; }
		else cur += c;
	}
	out.push(cur);
	return out;
}

function parseCsv(text) {
	const lines = text.split(/\r?\n/).filter((l) => l.length > 0);
	const head = splitCsv(lines[0]);
	return lines.slice(1).map((l) => {
		const f = splitCsv(l);
		const row = {};
		head.forEach((h, i) => { row[h] = f[i]; });
		return row;
	});
}

async function table(build, name) {
	const dir = path.join(ROOT, 'data', 'sources', 'wago', build);
	const file = path.join(dir, `${name}.csv`);
	if (!fs.existsSync(file)) {
		fs.mkdirSync(dir, { recursive: true });
		const url = `https://wago.tools/db2/${name}/csv?build=${build}`;
		console.log(`downloading ${url}`);
		const r = await fetch(url);
		if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
		fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
	}
	return parseCsv(fs.readFileSync(file, 'utf8'));
}

module.exports = { splitCsv, parseCsv, table };
