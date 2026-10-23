'use strict';
// Builds the release zip: dist/Pathwise-<version>.zip holding the Pathwise/
// folder as players install it, with LICENSE and THIRD_PARTY.md inside it
// (the GPL asks that the licence travels with every copy). Nothing is uploaded.
//
//   node tools/pack.js            build the zip
//   node tools/pack.js --list     print what would go in, build nothing
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

// Every file of the addon folder, sorted, skipping dotfiles; then the
// licence files from the repository root.
function entries() {
	const out = [];
	(function walk(dir, rel) {
		for (const name of fs.readdirSync(dir).sort()) {
			if (name.startsWith('.')) continue;
			const full = path.join(dir, name);
			const r = rel ? `${rel}/${name}` : name;
			if (fs.statSync(full).isDirectory()) walk(full, r);
			else out.push({ name: `Pathwise/${r}`, file: full });
		}
	})(ADDON, '');
	for (const name of ['LICENSE', 'THIRD_PARTY.md']) out.push({ name: `Pathwise/${name}`, file: path.join(ROOT, name) });
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
	const v = version();
	const list = entries();
	if (process.argv.includes('--list')) {
		for (const e of list) console.log(e.name);
		console.log(`${list.length} files, version ${v}`);
		return;
	}
	const out = path.join(ROOT, 'dist', `Pathwise-${v}.zip`);
	fs.mkdirSync(path.dirname(out), { recursive: true });
	const buf = zip(list);
	fs.writeFileSync(out, buf);
	console.log(`wrote ${path.relative(ROOT, out)}: ${list.length} files, ${(buf.length / 1024).toFixed(0)} KB`);
}

if (require.main === module) main();
module.exports = { version, entries, zip, crc32 };
