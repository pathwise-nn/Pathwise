'use strict';
// Recipes of the Forever client: which profession teaches each recipe spell,
// at what skill, and which item it creates. Writes data/recipes.lua, read by
// tools/data/build.lua for Pathwise Gear's crafted gear.
//
//   node tools/data/recipes.js [build]      (default: the newest Forever build)
//
// Source: Blizzard's client tables, as CSV from wago.tools (product "wowf",
// the Forever client), cached in data/sources/wago/<build>/ (not committed):
//   SkillLineAbility  SkillLine, Spell, MinSkillLineRank, AcquireMethod,
//                     TrivialSkillLineRankLow (yellow)
//   SpellEffect       SpellID, DifficultyID, Effect (24 = create item), EffectItemType
// The method follows Polestar's profession tool (tools/lib/professions in
// Polestar, GPL-3.0; see THIRD_PARTY.md), with one change: Season of
// Discovery recipes are kept (players found some in Forever) and marked
// `sod`; build.lua keeps a recipe only when QuestieDB's Forever data knows the
// item it makes. AcquireMethod 3 is a spell nobody learns ("retired") and is
// left out, as Polestar does.

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PRODUCT = 'wowf';
const LINES = { 164: 'Blacksmithing', 165: 'Leatherworking', 197: 'Tailoring', 202: 'Engineering', 333: 'Enchanting', 171: 'Alchemy' };
const SOD_MIN = 400000;
const FOREVER_MIN = 1000000;

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

async function newestBuild() {
	const r = await fetch('https://wago.tools/api/builds');
	if (!r.ok) throw new Error(`wago.tools builds: HTTP ${r.status}`);
	const j = await r.json();
	const list = j[PRODUCT];
	if (!list || !list.length) throw new Error(`wago.tools lists no ${PRODUCT} build`);
	return list[0].version;
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

async function main() {
	const build = process.argv[2] || await newestBuild();
	const abilities = await table(build, 'SkillLineAbility');
	const effects = await table(build, 'SpellEffect');
	const itemRows = new Map((await table(build, 'Item')).map((r) => [Number(r.ID), r]));
	const sparse = new Map((await table(build, 'ItemSparse')).map((r) => [Number(r.ID), r]));
	// Recipe items: an item effect with TriggerType 6 teaches its SpellID
	// (Forever's recipe items; ItemXItemEffect names the item), as in Polestar.
	const effectItems = new Map();
	for (const r of await table(build, 'ItemXItemEffect')) {
		const k = Number(r.ItemEffectID);
		if (!effectItems.has(k)) effectItems.set(k, []);
		effectItems.get(k).push(Number(r.ItemID));
	}
	const taughtBy = new Map();
	for (const r of await table(build, 'ItemEffect')) {
		if (Number(r.TriggerType) !== 6) continue;
		const spell = Number(r.SpellID);
		for (const item of effectItems.get(Number(r.ID)) || []) {
			const it = itemRows.get(item);
			if (!it || Number(it.ClassID) !== 9) continue;
			if (!taughtBy.has(spell)) taughtBy.set(spell, []);
			if (!taughtBy.get(spell).includes(item)) taughtBy.get(spell).push(item);
		}
	}
	const creates = new Map();
	for (const e of effects) {
		if (Number(e.DifficultyID) !== 0 || Number(e.Effect) !== 24) continue;
		const item = Number(e.EffectItemType);
		if (item > 0 && !creates.has(Number(e.SpellID))) creates.set(Number(e.SpellID), item);
	}
	const recipes = new Map();
	const skipped = { retired: 0, noItem: 0 };
	for (const a of abilities) {
		const line = Number(a.SkillLine);
		if (!LINES[line]) continue;
		const spell = Number(a.Spell);
		if (recipes.has(spell)) continue;
		if (Number(a.AcquireMethod) === 3) { skipped.retired++; continue; }
		const item = creates.get(spell);
		if (!item) { skipped.noItem++; continue; }
		const min = Number(a.MinSkillLineRank) || 0;
		const yellow = Number(a.TrivialSkillLineRankLow) || 0;
		const it = itemRows.get(item);
		const sp = sparse.get(item);
		const teach = (taughtBy.get(spell) || []).sort((x, y) => x - y);
		// A recipe item names the skill it needs (RequiredSkillRank): the best
		// figure for when it can be learned; else the ability's own.
		const teachSkill = teach.length && sparse.get(teach[0]) ? Number(sparse.get(teach[0]).RequiredSkillRank) || 0 : 0;
		recipes.set(spell, {
			line, item,
			skill: Math.max(1, teachSkill || min || yellow),
			auto: Number(a.AcquireMethod) === 1,
			sod: spell >= SOD_MIN && spell < FOREVER_MIN,
			cls: it ? Number(it.ClassID) : null,
			sub: it ? Number(it.SubclassID) : null,
			req: sp ? Number(sp.RequiredLevel) || 0 : null,
			ilvl: sp ? Number(sp.ItemLevel) || 0 : null,
			bop: sp ? Number(sp.Bonding) === 1 : false,
			teach,
		});
	}
	const ids = [...recipes.keys()].sort((x, y) => x - y);
	const out = [];
	out.push(`-- GENERATED by tools/data/recipes.js from the Forever client's tables (build ${build},`);
	out.push('-- via wago.tools). Do not edit by hand: rerun the tool.');
	out.push('-- recipes[spell] = { skillLine, skill, createdItem, auto (known with the skill), sod (Season of Discovery spell),');
	out.push('--   item class, subclass, required level, item level, binds on pickup, { recipe items that teach it } }');
	out.push(`return { build = ${JSON.stringify(build)}, recipes = {`);
	const n = (v) => (v == null ? 'nil' : String(v));
	for (const id of ids) {
		const r = recipes.get(id);
		const teach = r.teach.length ? `{${r.teach.join(',')}}` : 'nil';
		out.push(`[${id}]={${r.line},${r.skill},${r.item},${r.auto ? 'true' : 'nil'},${r.sod ? 'true' : 'nil'},${n(r.cls)},${n(r.sub)},${n(r.req)},${n(r.ilvl)},${r.bop ? 'true' : 'nil'},${teach}},`);
	}
	out.push('} }');
	const file = path.join(ROOT, 'data', 'recipes.lua');
	fs.writeFileSync(file, out.join('\n') + '\n');
	const sod = ids.filter((id) => recipes.get(id).sod).length;
	console.log(`wrote data/recipes.lua: ${ids.length} recipes (${sod} Season of Discovery), build ${build}; left out ${skipped.retired} retired, ${skipped.noItem} that make no item`);
}

main().catch((e) => { console.error(e.message); process.exit(1); });
