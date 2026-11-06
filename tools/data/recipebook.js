'use strict';
// The professions recipe book: the leveling plan per profession from
// data/professions/<key>.json (facts from wow-professions.com's Forever
// guides, written by hand), checked against the Forever client's own tables
// and filled in from them. Writes data/recipebook.lua, which
// tools/data/build.lua joins with QuestieDB (recipe sources, trainers, mobs).
//
//   node tools/data/recipebook.js [build]      (default: 1.60.1.70790)
//
// Every spell must be a recipe of its profession's skill line
// (SkillLineAbility), every item and zone must exist (ItemSparse, UiMap);
// the tool stops on the first file with an error and writes nothing.
// From the client: recipe names, reagents (SpellReagents), the item made
// (SpellEffect 24), yellow and grey (SkillLineAbility's
// TrivialSkillLineRankLow and High) and the recipe items that teach a spell
// (ItemEffect TriggerType 6, as tools/data/recipes.js). The JSON holds only
// the choices: which recipe for which skill range, how many, the rank
// trainers by name, the zones and mobs for gathering.

const fs = require('fs');
const path = require('path');
const { table } = require('./wago');

const ROOT = path.resolve(__dirname, '..', '..');
const DEFAULT_BUILD = '1.60.1.70790';
const FACTS = path.join(ROOT, 'data', 'professions');
const OUT = path.join(ROOT, 'data', 'recipebook.lua');
const ORDER = ['alchemy', 'blacksmithing', 'enchanting', 'engineering', 'leatherworking', 'tailoring',
	'herbalism', 'mining', 'skinning', 'cooking', 'first-aid', 'fishing'];

// Checks one profession's facts; returns a list of problems (empty when good).
function check(book, db) {
	const errors = [];
	const where = (s) => `${book.key} ${s.from}-${s.to}`;
	const spell = (id, ctx) => {
		const rows = db.abilities.get(id) || [];
		if (!rows.some((a) => a.line === book.line)) errors.push(`${ctx}: spell ${id} is not a ${book.key} recipe (SkillLineAbility)`);
	};
	const item = (id, ctx) => { if (!db.items.has(id) && !db.itemIds.has(id)) errors.push(`${ctx}: item ${id} is not in Item or ItemSparse`); };
	for (const r of book.ranks || []) {
		if (![75, 150, 225, 300].includes(r.cap)) errors.push(`${book.key} ${r.rank}: cap ${r.cap}`);
		if (r.book) item(r.book, `${book.key} ${r.rank} book`);
	}
	const paths = new Map();
	for (const s of book.steps || []) {
		if (!(s.from >= 1 && s.to <= 300 && s.from < s.to)) errors.push(`${where(s)}: bad range`);
		for (const k of ['make', 'any', 'or']) {
			for (const e of s[k] || []) {
				// [spell, count, faction]: count null when the guide gives none.
				if (!Array.isArray(e) || typeof e[0] !== 'number' || !(e[1] === null || (typeof e[1] === 'number' && e[1] >= 1))) errors.push(`${where(s)}: ${k} entry ${JSON.stringify(e)}`);
				else spell(e[0], where(s));
				if (e[2] !== undefined && e[2] !== 'A' && e[2] !== 'H') errors.push(`${where(s)}: faction ${e[2]}`);
			}
		}
		for (const n of s.nodes || []) item(n, where(s));
		for (const side of Object.keys(s.zones || {})) {
			if (side !== 'A' && side !== 'H' && side !== 'AH') errors.push(`${where(s)}: zones side ${side}`);
			for (const z of s.zones[side]) if (!db.zones.has(z)) errors.push(`${where(s)}: zone "${z}" is not in UiMap`);
		}
		if (s.faction !== undefined && s.faction !== 'A' && s.faction !== 'H') errors.push(`${where(s)}: faction ${s.faction}`);
		for (const n of s.mobs || []) if (!Number.isInteger(n)) errors.push(`${where(s)}: mob ${n}`);
		const p = s.path || '';
		if (!paths.has(p)) paths.set(p, []);
		paths.get(p).push(s);
	}
	for (const r of book.ranks || []) for (const n of r.needs || []) item(n, `${book.key} ${r.rank}`);
	// For each faction, the main plan runs from 1 to 300 with no gap; an
	// other path (a second way through a few ranges) only needs to be
	// continuous itself.
	for (const [p, steps] of paths) {
		for (const side of ['A', 'H']) {
			const sorted = steps.filter((s) => !s.faction || s.faction === side).sort((a, b) => a.from - b.from);
			if (p === '' && sorted.length && (sorted[0].from !== 1 || sorted[sorted.length - 1].to !== 300)) {
				errors.push(`${book.key} (${side}): the plan runs ${sorted[0].from}-${sorted[sorted.length - 1].to}, not 1-300`);
			}
			for (let i = 1; i < sorted.length; i++) {
				if (sorted[i].from !== sorted[i - 1].to) errors.push(`${book.key}${p ? ` (${p})` : ''} (${side}): gap or overlap at ${sorted[i - 1].to}/${sorted[i].from}`);
			}
		}
	}
	for (const id of book.extra || []) spell(id, `${book.key} extra`);
	// Recipe vendors the guide names that QuestieDB lacks: { [recipeItem]: [names] }.
	for (const [id, names] of Object.entries(book.sellers || {})) {
		item(Number(id), `${book.key} sellers`);
		if (!Array.isArray(names) || !names.every((n) => typeof n === 'string')) errors.push(`${book.key} sellers ${id}: names`);
	}
	for (const id of book.tools || []) item(id, `${book.key} tools`);
	for (const b of book.bonuses || []) {
		if (b.item) item(b.item, `${book.key} bonus`);
		if (b.spell && !db.spellNames.has(b.spell)) errors.push(`${book.key} bonus: spell ${b.spell} is not in SpellName`);
	}
	return errors;
}

const LUA_KEYWORDS = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in',
	'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);

function lua(v) {
	if (v === null || v === undefined) return 'nil';
	if (typeof v === 'number') return String(v);
	if (typeof v === 'boolean') return v ? 'true' : 'false';
	if (typeof v === 'string') return JSON.stringify(v);
	if (Array.isArray(v)) return `{${v.map(lua).join(',')}}`;
	const keys = Object.keys(v).filter((k) => v[k] !== undefined && v[k] !== null);
	return `{${keys.map((k) => `${/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(k) && !LUA_KEYWORDS.has(k) ? k : `[${JSON.stringify(k)}]`}=${lua(v[k])}`).join(',')}}`;
}

async function main() {
	const build = process.argv[2] || DEFAULT_BUILD;
	const db = { abilities: new Map(), items: new Map(), itemIds: new Set(), zones: new Map(), spellNames: new Map() };
	for (const r of await table(build, 'Item')) db.itemIds.add(Number(r.ID));
	for (const a of await table(build, 'SkillLineAbility')) {
		const id = Number(a.Spell);
		if (!db.abilities.has(id)) db.abilities.set(id, []);
		db.abilities.get(id).push({ line: Number(a.SkillLine), yellow: Number(a.TrivialSkillLineRankLow) || 0, grey: Number(a.TrivialSkillLineRankHigh) || 0, min: Number(a.MinSkillLineRank) || 0 });
	}
	for (const r of await table(build, 'ItemSparse')) db.items.set(Number(r.ID), { name: r.Display_lang, req: Number(r.RequiredSkillRank) || 0 });
	for (const r of await table(build, 'SpellName')) db.spellNames.set(Number(r.ID), r.Name_lang);
	// Zones (UiMap type 3); a name used twice keeps its lowest id.
	for (const r of await table(build, 'UiMap')) {
		if (Number(r.Type) !== 3) continue;
		const id = Number(r.ID);
		if (!db.zones.has(r.Name_lang) || id < db.zones.get(r.Name_lang)) db.zones.set(r.Name_lang, id);
	}
	const reagents = new Map();
	for (const r of await table(build, 'SpellReagents')) {
		const list = [];
		for (let i = 0; i < 8; i++) {
			const it = Number(r[`Reagent_${i}`]);
			const n = Number(r[`ReagentCount_${i}`]);
			if (it > 0 && n > 0) list.push([it, n]);
		}
		reagents.set(Number(r.SpellID), list);
	}
	const creates = new Map();
	for (const e of await table(build, 'SpellEffect')) {
		if (Number(e.DifficultyID) !== 0 || Number(e.Effect) !== 24) continue;
		const it = Number(e.EffectItemType);
		if (it > 0 && !creates.has(Number(e.SpellID))) creates.set(Number(e.SpellID), it);
	}
	const effectItems = new Map();
	for (const r of await table(build, 'ItemXItemEffect')) {
		const k = Number(r.ItemEffectID);
		if (!effectItems.has(k)) effectItems.set(k, []);
		effectItems.get(k).push(Number(r.ItemID));
	}
	const taughtBy = new Map();
	for (const r of await table(build, 'ItemEffect')) {
		if (Number(r.TriggerType) !== 6) continue;
		for (const it of effectItems.get(Number(r.ID)) || []) {
			const s = Number(r.SpellID);
			if (!taughtBy.has(s)) taughtBy.set(s, []);
			if (!taughtBy.get(s).includes(it)) taughtBy.get(s).push(it);
		}
	}

	const books = [];
	const problems = [];
	for (const key of ORDER) {
		const file = path.join(FACTS, `${key}.json`);
		if (!fs.existsSync(file)) { problems.push(`${key}: no ${path.relative(ROOT, file)}`); continue; }
		const book = JSON.parse(fs.readFileSync(file, 'utf8'));
		if (book.key !== key) problems.push(`${file}: key "${book.key}"`);
		problems.push(...check(book, db));
		books.push(book);
	}
	if (problems.length) {
		for (const p of problems) console.error(p);
		console.error(`${problems.length} problem(s): data/recipebook.lua not written`);
		process.exit(1);
	}

	// Spells and items the books use, with the client's facts.
	const spells = new Map();
	const items = new Map();
	const zoneNames = new Map();
	// An item only in Item (no ItemSparse row) gets its name from QuestieDB in build.lua.
	const useItem = (id) => { items.set(id, db.items.has(id) ? db.items.get(id).name : null); };
	const useSpell = (id, line) => {
		if (spells.has(id)) return;
		const a = (db.abilities.get(id) || []).find((x) => x.line === line);
		const teach = (taughtBy.get(id) || []).filter((it) => db.items.has(it)).sort((x, y) => x - y);
		// A recipe item names the skill it needs: the skill to learn it from it.
		const learn = teach.length ? db.items.get(teach[0]).req || null : null;
		const made = creates.get(id) || null;
		const rg = reagents.get(id) || [];
		spells.set(id, { name: db.spellNames.get(id) || `spell ${id}`, line, learn, yellow: a.yellow || null, grey: a.grey || null, made, reagents: rg, teach });
		if (made) useItem(made);
		for (const [it] of rg) useItem(it);
		for (const it of teach) useItem(it);
	};
	for (const b of books) {
		for (const s of b.steps) {
			for (const k of ['make', 'any', 'or']) for (const e of s[k] || []) useSpell(e[0], b.line);
			for (const n of s.nodes || []) useItem(n);
			if (s.zones) {
				for (const side of Object.keys(s.zones)) {
					s.zones[side] = s.zones[side].map((z) => { zoneNames.set(db.zones.get(z), z); return db.zones.get(z); });
				}
			}
			if (s.or) { s.alt = s.or; delete s.or; } // `or` is a Lua keyword
		}
		for (const id of b.extra || []) useSpell(id, b.line);
		for (const id of b.tools || []) useItem(id);
		for (const r of b.ranks) {
			if (r.book) useItem(r.book);
			for (const n of r.needs || []) useItem(n);
		}
		for (const x of b.bonuses || []) {
			if (x.item) useItem(x.item);
			if (x.spell) x.name = db.spellNames.get(x.spell);
		}
	}

	const out = [];
	out.push(`-- GENERATED by tools/data/recipebook.js from data/professions/*.json and the Forever client's`);
	out.push(`-- tables (build ${build}, via wago.tools). Do not edit by hand: change the JSON and rerun the tool.`);
	out.push('-- spells[id] = { name, skillLine, learn (from its recipe item), yellow, grey, itemMade, { {reagent, count}, ... }, { recipe items } }');
	out.push('-- items[id] = name (false: QuestieDB names it), zones[uiMap] = name');
	out.push(`return { build = ${JSON.stringify(build)},`);
	out.push('books = {');
	for (const b of books) {
		const { source, untestedFrom, key, line, ranks, steps, extra, tools, bonuses, notes } = b;
		const sellers = b.sellers ? Object.entries(b.sellers).map(([id, names]) => [Number(id), names]) : undefined;
		out.push(`${lua({ key, line, source, untestedFrom, ranks, steps, extra, tools, bonuses, notes, sellers })},`);
	}
	out.push('},');
	out.push('spells = {');
	for (const id of [...spells.keys()].sort((x, y) => x - y)) {
		const s = spells.get(id);
		out.push(`[${id}]=${lua([s.name, s.line, s.learn, s.yellow, s.grey, s.made, s.reagents, s.teach.length ? s.teach : null])},`);
	}
	out.push('},');
	out.push('items = {');
	for (const id of [...items.keys()].sort((x, y) => x - y)) out.push(`[${id}]=${items.get(id) == null ? 'false' : JSON.stringify(items.get(id))},`);
	out.push('},');
	out.push('zones = {');
	for (const id of [...zoneNames.keys()].sort((x, y) => x - y)) out.push(`[${id}]=${JSON.stringify(zoneNames.get(id))},`);
	out.push('} }');
	fs.writeFileSync(OUT, out.join('\n') + '\n');
	console.log(`wrote data/recipebook.lua: ${books.length} professions, ${spells.size} recipes, ${items.size} items (Forever build ${build})`);
}

if (require.main === module) main().catch((e) => { console.error(e.message); process.exit(1); });
module.exports = { check };
