'use strict';
// tools/data/recipebook.js: the checks on data/professions/*.json, and that
// data/recipebook.lua was rebuilt from the JSON. Run: node --test tests/
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { check } = require('../tools/data/recipebook.js');

const ROOT = path.resolve(__dirname, '..');

// A tiny client: two Alchemy recipes, one Tailoring one, two items, a zone.
function db() {
	return {
		abilities: new Map([[7183, [{ line: 171 }]], [2331, [{ line: 171 }]], [2963, [{ line: 197 }]]]),
		items: new Map([[765, { name: 'Silverleaf' }], [2447, { name: 'Peacebloom' }]]),
		itemIds: new Set([765, 2447, 5444]),
		zones: new Map([['Durotar', 1411]]),
		spellNames: new Map([[13617, 'Enchant Gloves - Herbalism']]),
	};
}

function book(steps, extra = {}) {
	return { key: 'alchemy', line: 171, ranks: [{ rank: 'Apprentice', cap: 75 }], steps, ...extra };
}

test('a good plan passes', () => {
	assert.deepStrictEqual(check(book([
		{ from: 1, to: 60, make: [[7183, 45]], or: [[2331, null]] },
		{ from: 60, to: 300, any: [[2331, 10, 'H'], [7183, 5]], nodes: [765], zones: { H: ['Durotar'] } },
	], { tools: [5444] }), db()), []);
});

test('a spell of another profession, an unknown item or zone, a bad count', () => {
	const errors = check(book([
		{ from: 1, to: 300, make: [[2963, 30], [7183, 0]], nodes: [99999], zones: { AH: ['Atlantis'], X: [] } },
	]), db());
	assert.ok(errors.some((e) => e.includes('spell 2963 is not a alchemy recipe')), errors.join('\n'));
	assert.ok(errors.some((e) => e.includes('make entry [7183,0]')), errors.join('\n'));
	assert.ok(errors.some((e) => e.includes('item 99999')), errors.join('\n'));
	assert.ok(errors.some((e) => e.includes('zone "Atlantis"')), errors.join('\n'));
	assert.ok(errors.some((e) => e.includes('zones side X')), errors.join('\n'));
});

test('a gap, a plan short of 300, a faction left without a range', () => {
	const gap = check(book([{ from: 1, to: 50, make: [[7183, 1]] }, { from: 60, to: 300, make: [[7183, 1]] }]), db());
	assert.ok(gap.some((e) => e.includes('gap or overlap at 50/60')), gap.join('\n'));
	const short = check(book([{ from: 1, to: 250, make: [[7183, 1]] }]), db());
	assert.ok(short.some((e) => e.includes('not 1-300')), short.join('\n'));
	const horde = check(book([
		{ from: 1, to: 75, faction: 'H', make: [[7183, 1]] },
		{ from: 75, to: 300, make: [[7183, 1]] },
	]), db());
	assert.ok(horde.some((e) => e.startsWith('alchemy (A): the plan runs 75-300')), horde.join('\n'));
});

test('another path only has to be continuous itself', () => {
	assert.deepStrictEqual(check(book([
		{ from: 1, to: 300, make: [[7183, 1]] },
		{ path: 'Dust', from: 70, to: 100, make: [[2331, 1]] },
		{ path: 'Dust', from: 100, to: 150, make: [[2331, 1]] },
	]), db()), []);
	const broken = check(book([
		{ from: 1, to: 300, make: [[7183, 1]] },
		{ path: 'Dust', from: 70, to: 100, make: [[2331, 1]] },
		{ path: 'Dust', from: 110, to: 150, make: [[2331, 1]] },
	]), db());
	assert.ok(broken.some((e) => e.includes('(Dust)')), broken.join('\n'));
});

test('data/recipebook.lua holds every recipe the JSON names (the tool was rerun)', () => {
	const lua = fs.readFileSync(path.join(ROOT, 'data', 'recipebook.lua'), 'utf8');
	const have = new Set([...lua.matchAll(/^\[(\d+)\]=\{"/gm)].map((m) => Number(m[1])));
	const dir = path.join(ROOT, 'data', 'professions');
	const files = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
	assert.strictEqual(files.length, 12);
	for (const f of files) {
		const b = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
		assert.strictEqual(`${b.key}.json`, f);
		assert.ok(lua.includes(`key="${b.key}"`), `${b.key} in data/recipebook.lua`);
		const spells = [...(b.extra || [])];
		for (const s of b.steps) for (const k of ['make', 'any', 'or']) for (const e of s[k] || []) spells.push(e[0]);
		for (const id of spells) assert.ok(have.has(id), `${f}: spell ${id} missing from data/recipebook.lua: rerun node tools/data/recipebook.js`);
	}
});
