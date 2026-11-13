'use strict';
// Builds the release zips, one per CurseForge project: dist/<Addon>-<version>.zip
// for Pathwise, Pathwise_Gear, Pathwise_Bags, PathwiseUI, Pathwise_Heal,
// Pathwise_Encounters, Pathwise_Loot and Pathwise_Insights, each holding its addon folder
// as players install it, with LICENSE and THIRD_PARTY.md inside it (the GPL
// asks that the licence travels with every copy). Nothing is uploaded.
//
//   node tools/pack.js                  build all eight zips
//   node tools/pack.js Pathwise_Gear    build only the zips named
//   node tools/pack.js --list           print what would go in, build nothing
//
// No dependencies: Node's zlib deflates, and the zip is written by hand
// (local headers, central directory, end record; no zip64, files < 4 GB).

const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const ROOT = path.resolve(__dirname, '..');
const ADDON = path.join(ROOT, 'Pathwise');

function version() {
	const toc = fs.readFileSync(path.join(ADDON, 'Pathwise.toc'), 'utf8');
	const m = toc.match(/^## Version:\s*(\S+)/m);
	if (!m) throw new Error('Pathwise.toc has no ## Version line');
	return m[1];
}

// The addons, each its own CurseForge project and zip. Gear needs Pathwise
// installed (## Dependencies in its TOC); Pathwise UI, Pathwise Heal,
// Pathwise Encounters, Pathwise Loot, Pathwise Insights and Pathwise Bags
// work on their own (## OptionalDeps).
const ADDONS = ['Pathwise', 'Pathwise_Gear', 'Pathwise_Bags', 'PathwiseUI', 'Pathwise_Heal', 'Pathwise_Encounters', 'Pathwise_Loot', 'Pathwise_Insights'];

// Every file of the addon folders asked for (all by default), sorted,
// skipping dotfiles; then the licence files from the repository root, in
// each folder.
function entries(addons = ADDONS) {
	const out = [];
	for (const addon of addons) {
		const dir0 = path.join(ROOT, addon);
		if (!fs.existsSync(dir0)) continue;
		(function walk(dir, rel) {
			for (const name of fs.readdirSync(dir).sort()) {
				if (name.startsWith('.')) continue;
				const full = path.join(dir, name);
				const r = rel ? `${rel}/${name}` : name;
				if (fs.statSync(full).isDirectory()) walk(full, r);
				else out.push({ name: `${addon}/${r}`, file: full });
			}
		})(dir0, '');
		for (const name of ['LICENSE', 'THIRD_PARTY.md']) out.push({ name: `${addon}/${name}`, file: path.join(ROOT, name) });
	}
	return out;
}

function crc32(buf) {
	if (zlib.crc32) return zlib.crc32(buf) >>> 0;
	let c, crc = 0xffffffff;
	for (let n = 0; n < buf.length; n++) {
		c = (crc ^ buf[n]) & 0xff;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		crc = (crc >>> 8) ^ c;
	}
	return (crc ^ 0xffffffff) >>> 0;
}

// DOS date and time of a JS date (zip timestamps).
function dos(d) {
	const time = (d.getHours() << 11) | (d.getMinutes() << 5) | Math.floor(d.getSeconds() / 2);
	const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
	return { time, date };
}

function zip(list) {
	const parts = [];
	const central = [];
	let offset = 0;
	const { time, date } = dos(new Date());
	for (const e of list) {
		const data = fs.readFileSync(e.file);
		const deflated = zlib.deflateRawSync(data, { level: 9 });
		const useDeflate = deflated.length < data.length;
		const body = useDeflate ? deflated : data;
		const name = Buffer.from(e.name, 'utf8');
		const crc = crc32(data);
		const local = Buffer.alloc(30);
		local.writeUInt32LE(0x04034b50, 0);
		local.writeUInt16LE(20, 4);
		local.writeUInt16LE(0x0800, 6); // UTF-8 names
		local.writeUInt16LE(useDeflate ? 8 : 0, 8);
		local.writeUInt16LE(time, 10);
		local.writeUInt16LE(date, 12);
		local.writeUInt32LE(crc, 14);
		local.writeUInt32LE(body.length, 18);
		local.writeUInt32LE(data.length, 22);
		local.writeUInt16LE(name.length, 26);
		local.writeUInt16LE(0, 28);
		parts.push(local, name, body);
		const c = Buffer.alloc(46);
		c.writeUInt32LE(0x02014b50, 0);
		c.writeUInt16LE(20, 4);
		c.writeUInt16LE(20, 6);
		c.writeUInt16LE(0x0800, 8);
		c.writeUInt16LE(useDeflate ? 8 : 0, 10);
		c.writeUInt16LE(time, 12);
		c.writeUInt16LE(date, 14);
		c.writeUInt32LE(crc, 16);
		c.writeUInt32LE(body.length, 20);
		c.writeUInt32LE(data.length, 24);
		c.writeUInt16LE(name.length, 28);
		c.writeUInt32LE(offset, 42);
		central.push(c, name);
		offset += local.length + name.length + body.length;
	}
	const cd = Buffer.concat(central);
	const end = Buffer.alloc(22);
	end.writeUInt32LE(0x06054b50, 0);
	end.writeUInt16LE(list.length, 8);
	end.writeUInt16LE(list.length, 10);
	end.writeUInt32LE(cd.length, 12);
	end.writeUInt32LE(offset, 16);
	return Buffer.concat([...parts, cd, end]);
}

function main() {
	// Pathwise Heal, Encounters, Loot, Insights and Bags carry copies of Pathwise UI's shared files: never ship stale ones.
	const kit = require('./kit');
	const stale = kit.plan().filter(([, to, want]) => !fs.existsSync(to) || !fs.readFileSync(to).equals(want));
	if (stale.length) {
		console.error(`${stale.length} stale copied kit file(s) (Pathwise_Heal, Pathwise_Encounters, Pathwise_Loot, Pathwise_Insights, Pathwise_Bags): run npm run kit first`);
		process.exit(1);
	}
	const v = version();
	const asked = process.argv.slice(2).filter((a) => !a.startsWith('--'));
	for (const a of asked) {
		if (!ADDONS.includes(a)) {
			console.error(`unknown addon ${a}: one of ${ADDONS.join(', ')}`);
			process.exit(2);
		}
	}
	const list = process.argv.includes('--list');
	for (const addon of asked.length ? asked : ADDONS) {
		const files = entries([addon]);
		if (list) {
			for (const e of files) console.log(e.name);
			console.log(`${addon}: ${files.length} files, version ${v}`);
			continue;
		}
		const out = path.join(ROOT, 'dist', `${addon}-${v}.zip`);
		fs.mkdirSync(path.dirname(out), { recursive: true });
		const buf = zip(files);
		fs.writeFileSync(out, buf);
		console.log(`wrote ${path.relative(ROOT, out)}: ${files.length} files, ${(buf.length / 1024).toFixed(0)} KB`);
	}
}

if (require.main === module) main();
module.exports = { ADDONS, version, entries, zip, crc32 };
