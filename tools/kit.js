'use strict';
// Pathwise Heal, Pathwise Encounters and Pathwise Loot stand alone, so each carries its own
// copy of the files it shares with Pathwise UI: the core (settings, events),
// theme, motion, widgets, move mode, options window and minimap button, plus
// their media. Pathwise UI's are the originals; this copies them into each
// addon's Kit/ and Media/. Each addon runs its copy in its own namespace,
// told who it is by its Identity.lua, so they never clash.
//
//   node tools/kit.js           copy (npm run kit)
//   node tools/kit.js --check   exit 1 if any copy differs (the tests do this too)

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const FROM = path.join(ROOT, 'PathwiseUI');
const TARGETS = ['Pathwise_Heal', 'Pathwise_Encounters', 'Pathwise_Loot'];
const FILES = ['Core.lua', 'Theme.lua', 'Anim.lua', 'Widgets.lua', 'Movers.lua', 'Options.lua', 'Minimap.lua'];
const HEADER = (name) => `-- COPIED from PathwiseUI/${name} by tools/kit.js: do not edit here.\n-- Edit PathwiseUI/${name}, then run npm run kit.\n`;

// Every copy: [from, to, expected bytes].
function plan() {
	const out = [];
	for (const target of TARGETS) {
		const TO = path.join(ROOT, target);
		for (const name of FILES) {
			const src = fs.readFileSync(path.join(FROM, name));
			out.push([path.join(FROM, name), path.join(TO, 'Kit', name), Buffer.concat([Buffer.from(HEADER(name)), src])]);
		}
		(function walk(dir, rel) {
			for (const name of fs.readdirSync(dir).sort()) {
				const full = path.join(dir, name);
				const r = path.join(rel, name);
				if (fs.statSync(full).isDirectory()) walk(full, r);
				else out.push([full, path.join(TO, 'Media', r), fs.readFileSync(full)]);
			}
		})(path.join(FROM, 'Media'), '');
	}
	return out;
}

function main() {
	const check = process.argv.includes('--check');
	let differ = 0;
	for (const [from, to, want] of plan()) {
		const have = fs.existsSync(to) ? fs.readFileSync(to) : null;
		if (have && have.equals(want)) continue;
		differ++;
		if (check) console.error(`differs: ${path.relative(ROOT, to)} (from ${path.relative(ROOT, from)})`);
		else { fs.mkdirSync(path.dirname(to), { recursive: true }); fs.writeFileSync(to, want); console.log(`wrote ${path.relative(ROOT, to)}`); }
	}
	if (check && differ) { console.error(`${differ} file(s) differ: run npm run kit`); process.exit(1); }
	if (!check) console.log(differ ? `${differ} file(s) copied` : 'the copies are up to date');
}

if (require.main === module) main();
module.exports = { plan, FILES, TARGETS };
