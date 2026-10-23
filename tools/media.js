'use strict';
// Draws Pathwise's textures (Pathwise/Media/*.tga) from geometry: the
// Signature arrow, its glow, the arrived mark, the header icon, objective
// dots and the icon-button glyphs. White shapes on transparency, so the addon
// tints them with SetVertexColor. Run: node tools/media.js
// No dependencies: a small anti-aliased rasteriser (4x4 supersampling) and an
// uncompressed 32-bit TGA writer. Sizes are powers of two, as the client wants.

const fs = require('node:fs');
const path = require('node:path');

const OUT = path.join(__dirname, '..', 'Pathwise', 'Media');
const SS = 4; // supersamples per axis

// --- shapes: each returns coverage test (x, y) -> bool in pixel space ---

function polygon(points) {
	return (x, y) => {
		let inside = false;
		for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
			const [xi, yi] = points[i];
			const [xj, yj] = points[j];
			if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
		}
		return inside;
	};
}

function segDist(px, py, ax, ay, bx, by) {
	const dx = bx - ax, dy = by - ay;
	const len = dx * dx + dy * dy;
	let t = len ? ((px - ax) * dx + (py - ay) * dy) / len : 0;
	t = Math.max(0, Math.min(1, t));
	const cx = ax + t * dx, cy = ay + t * dy;
	return Math.hypot(px - cx, py - cy);
}

function stroke(points, width, closed = false) {
	const segs = [];
	for (let i = 0; i < points.length - 1; i++) segs.push([points[i], points[i + 1]]);
	if (closed) segs.push([points[points.length - 1], points[0]]);
	return (x, y) => segs.some(([a, b]) => segDist(x, y, a[0], a[1], b[0], b[1]) <= width / 2);
}

function disc(cx, cy, r) {
	return (x, y) => Math.hypot(x - cx, y - cy) <= r;
}

function ring(cx, cy, r, width) {
	return (x, y) => Math.abs(Math.hypot(x - cx, y - cy) - r) <= width / 2;
}

// --- canvas ---

function canvas(size) {
	return { size, px: new Float32Array(size * size * 4) }; // premultiplied-free RGBA 0..1
}

// Paint a shape with grey level `v` (0..1) and opacity `a`, anti-aliased.
function paint(c, shape, v = 1, a = 1) {
	const { size, px } = c;
	for (let y = 0; y < size; y++) {
		for (let x = 0; x < size; x++) {
			let hit = 0;
			for (let sy = 0; sy < SS; sy++) {
				for (let sx = 0; sx < SS; sx++) {
					if (shape(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)) hit++;
				}
			}
			if (!hit) continue;
			const sa = (a * hit) / (SS * SS);
			const i = (y * size + x) * 4;
			const da = px[i + 3];
			const oa = sa + da * (1 - sa);
			const blend = (s, d) => (oa ? (s * sa + d * da * (1 - sa)) / oa : 0);
			px[i] = blend(v, px[i]);
			px[i + 1] = blend(v, px[i + 1]);
			px[i + 2] = blend(v, px[i + 2]);
			px[i + 3] = oa;
		}
	}
}

// Soft glow: a box blur of the alpha, several passes, at strength `a`.
function blurAlpha(c, radius, passes, a) {
	const { size, px } = c;
	let alpha = new Float32Array(size * size);
	for (let i = 0; i < size * size; i++) alpha[i] = px[i * 4 + 3];
	for (let p = 0; p < passes; p++) {
		for (const horizontal of [true, false]) {
			const next = new Float32Array(size * size);
			for (let y = 0; y < size; y++) {
				for (let x = 0; x < size; x++) {
					let sum = 0, n = 0;
					for (let k = -radius; k <= radius; k++) {
						const xx = horizontal ? x + k : x, yy = horizontal ? y : y + k;
						if (xx < 0 || yy < 0 || xx >= size || yy >= size) { n++; continue; }
						sum += alpha[yy * size + xx];
						n++;
					}
					next[y * size + x] = sum / n;
				}
			}
			alpha = next;
		}
	}
	for (let i = 0; i < size * size; i++) {
		px[i * 4] = px[i * 4 + 1] = px[i * 4 + 2] = 1;
		px[i * 4 + 3] = Math.min(1, alpha[i] * a);
	}
}

function tga(c) {
	const { size, px } = c;
	const header = Buffer.alloc(18);
	header[2] = 2; // uncompressed true-colour
	header.writeUInt16LE(size, 12);
	header.writeUInt16LE(size, 14);
	header[16] = 32;
	header[17] = 0x28; // 8 alpha bits, top-left origin
	const body = Buffer.alloc(size * size * 4);
	for (let i = 0; i < size * size; i++) {
		const to = (v) => Math.round(Math.max(0, Math.min(1, v)) * 255);
		body[i * 4] = to(px[i * 4 + 2]);
		body[i * 4 + 1] = to(px[i * 4 + 1]);
		body[i * 4 + 2] = to(px[i * 4]);
		body[i * 4 + 3] = to(px[i * 4 + 3]);
	}
	return Buffer.concat([header, body]);
}

// --- the textures ---

const T = {};

// The dart: two facets (left lighter) and a thin light edge. Points up.
function dartShape(c, s) {
	const tip = [32 * s, 6 * s], right = [50 * s, 56 * s], notch = [32 * s, 44 * s], left = [14 * s, 56 * s];
	paint(c, polygon([tip, notch, left]), 1);
	paint(c, polygon([tip, right, notch]), 0.66);
	paint(c, stroke([tip, right, notch, left], 1.3 * s, true), 1, 0.9);
}

T.arrow = () => { const c = canvas(64); dartShape(c, 1); return c; };

T['arrow-glow'] = () => {
	const c = canvas(64);
	// The dart, scaled down to sit inside the glow's margin, then blurred.
	const s = 0.82, o = 32 * (1 - s);
	paint(c, polygon([[32, 6 * s + o], [50 * s + o, 56 * s + o], [32, 44 * s + o], [14 * s + o, 56 * s + o]]), 1);
	blurAlpha(c, 3, 3, 0.9);
	return c;
};

// Arrived: a thin four-point compass star with a centre dot.
T.arrived = () => {
	const c = canvas(64);
	paint(c, stroke([[32, 6], [40, 32], [32, 58], [24, 32]], 2, true), 1);
	paint(c, stroke([[6, 32], [32, 26], [58, 32], [32, 38]], 1.4, true), 1, 0.5);
	paint(c, disc(32, 32, 3.5), 1);
	return c;
};

// The header icon: ring, ice needle north-south, grey east-west. Coloured.
T.icon = () => {
	const c = canvas(32);
	const ice = (shape, a = 1) => {
		paint(c, shape, 1, a);
	};
	// Drawn white here and coloured below: ring silver, needle ice.
	paint(c, ring(16, 16, 12.5, 1.4), 0.66);
	paint(c, polygon([[16, 4], [19, 16], [16, 28], [13, 16]]), 1);
	paint(c, polygon([[4, 16], [16, 14.5], [28, 16], [16, 17.5]]), 0.6, 0.7);
	// Colour pass: the needle ice (#66D7FF), the rest silver-grey (#9AAFC0).
	const { px } = c;
	for (let y = 0; y < 32; y++) {
		for (let x = 0; x < 32; x++) {
			const i = (y * 32 + x) * 4;
			if (!px[i + 3]) continue;
			const needle = polygon([[16, 4], [19, 16], [16, 28], [13, 16]])(x + 0.5, y + 0.5);
			const col = needle ? [0x66, 0xd7, 0xff] : [0x9a, 0xaf, 0xc0];
			px[i] = col[0] / 255; px[i + 1] = col[1] / 255; px[i + 2] = col[2] / 255;
		}
	}
	void ice;
	return c;
};

// Objective markers: an open ring; a disc with a dark check cut in.
T['dot-open'] = () => { const c = canvas(32); paint(c, ring(16, 16, 11, 3), 1); return c; };
T['dot-done'] = () => {
	const c = canvas(32);
	paint(c, disc(16, 16, 13), 1);
	paint(c, stroke([[10, 16.5], [14.5, 21], [22.5, 12]], 3.2), 0.06);
	return c;
};

// The slider's handle: a disc with a thin darker ring, so it reads on the fill.
T.thumb = () => {
	const c = canvas(32);
	paint(c, disc(16, 16, 12), 1);
	paint(c, ring(16, 16, 12, 2), 0.55);
	return c;
};

// Glyphs, 32 px drawn for a 16 px button.
T['glyph-close'] = () => { const c = canvas(32); paint(c, stroke([[10, 10], [22, 22]], 2.4)); paint(c, stroke([[22, 10], [10, 22]], 2.4)); return c; };
T['glyph-collapse'] = () => { const c = canvas(32); paint(c, stroke([[9, 19], [16, 12], [23, 19]], 2.4)); return c; };
T['glyph-expand'] = () => { const c = canvas(32); paint(c, stroke([[9, 13], [16, 20], [23, 13]], 2.4)); return c; };
T['glyph-flag'] = () => {
	const c = canvas(32);
	paint(c, stroke([[10, 26], [10, 6]], 2.2));
	paint(c, stroke([[10, 7], [24, 7], [20.5, 12], [24, 17], [10, 17]], 2.2));
	return c;
};
T['glyph-zones'] = () => {
	// A folded map: three panels.
	const c = canvas(32);
	paint(c, stroke([[6, 9], [12, 6], [20, 9], [26, 6], [26, 23], [20, 26], [12, 23], [6, 26]], 2.2, true));
	paint(c, stroke([[12, 6], [12, 23]], 2));
	paint(c, stroke([[20, 9], [20, 26]], 2));
	return c;
};
// Professions: a hammer.
T['glyph-prof'] = () => {
	const c = canvas(32);
	paint(c, stroke([[9, 25], [19, 15]], 2.6));
	paint(c, polygon([[15, 8], [23, 16], [26, 13], [18, 5]]), 1);
	return c;
};
T['glyph-settings'] = () => {
	const c = canvas(32);
	paint(c, ring(16, 16, 5, 2.4));
	for (let k = 0; k < 8; k++) {
		const a = (k * Math.PI) / 4;
		paint(c, stroke([[16 + Math.cos(a) * 8.5, 16 + Math.sin(a) * 8.5], [16 + Math.cos(a) * 12, 16 + Math.sin(a) * 12]], 2.6));
	}
	return c;
};

function main() {
	const only = process.argv.slice(2);
	fs.mkdirSync(OUT, { recursive: true });
	for (const [name, draw] of Object.entries(T)) {
		if (only.length && !only.includes(name)) continue;
		const file = path.join(OUT, `${name}.tga`);
		fs.writeFileSync(file, tga(draw()));
		console.log(`wrote ${path.relative(process.cwd(), file)}`);
	}
}

if (require.main === module) main();
module.exports = { T, tga, canvas, paint, polygon };
