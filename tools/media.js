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

// Map markers' badge: a solid disc with a soft half-opaque rim, tinted dark
// under a glyph so it stands out on the light parchment of the world map.
T['pin-disc'] = () => {
	const c = canvas(32);
	paint(c, disc(16, 16, 15.5), 1, 0.45);
	paint(c, disc(16, 16, 14), 1);
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
// The guide window's resize grip: three diagonal lines in the bottom-right corner.
T['glyph-resize'] = () => {
	const c = canvas(32);
	paint(c, stroke([[27, 11], [11, 27]], 2.2));
	paint(c, stroke([[27, 18], [18, 27]], 2.2));
	paint(c, stroke([[27, 25], [25, 27]], 2.2));
	return c;
};
T['glyph-back'] = () => { const c = canvas(32); paint(c, stroke([[19, 9], [12, 16], [19, 23]], 2.4)); return c; };
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
// Dungeons: a gate (an arch with a doorway).
T['glyph-dungeon'] = () => {
	const c = canvas(32);
	const arch = [[7, 27], [7, 14]];
	for (let k = 0; k <= 12; k++) {
		const a = Math.PI - (k * Math.PI) / 12;
		arch.push([16 + 9 * Math.cos(a), 14 - 9 * Math.sin(a)]);
	}
	arch.push([25, 27]);
	paint(c, stroke(arch, 2.4));
	paint(c, stroke([[4, 27], [28, 27]], 2.4));
	paint(c, stroke([[16, 27], [16, 18]], 2));
	return c;
};

// Gear: the upgrade arrow (a bold chevron up with a stem).
T['glyph-upgrade'] = () => {
	const c = canvas(32);
	paint(c, polygon([[16, 4], [27, 16], [21, 16], [21, 28], [11, 28], [11, 16], [5, 16]]), 1);
	paint(c, stroke([[16, 4], [27, 16], [21, 16], [21, 28], [11, 28], [11, 16], [5, 16]], 1.6, true), 0.35, 0.9);
	return c;
};

// Gear: best for your level (a five-pointed star).
T['glyph-best'] = () => {
	const c = canvas(32);
	const pts = [];
	for (let k = 0; k < 10; k++) {
		const a = -Math.PI / 2 + (k * Math.PI) / 5;
		const r = k % 2 === 0 ? 13 : 5.5;
		pts.push([16 + r * Math.cos(a), 17 + r * Math.sin(a)]);
	}
	paint(c, polygon(pts), 1);
	paint(c, stroke(pts, 1.4, true), 0.35, 0.9);
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

// Bags: a coin (can be sold), a quest mark, a lock (kept), sort lines, search.
T['glyph-coin'] = () => {
	const c = canvas(32);
	paint(c, ring(16, 16, 10, 2.6));
	paint(c, stroke([[16, 10], [16, 22]], 2.2));
	return c;
};
T['glyph-quest'] = () => {
	const c = canvas(32);
	paint(c, stroke([[16, 5], [16, 19]], 4));
	paint(c, ring(16, 26, 1.6, 3.2));
	return c;
};
T['glyph-lock'] = () => {
	const c = canvas(32);
	paint(c, polygon([[8, 15], [24, 15], [24, 28], [8, 28]]), 1);
	const arch = [];
	for (let k = 0; k <= 12; k++) {
		const a = Math.PI - (k * Math.PI) / 12;
		arch.push([16 + 6 * Math.cos(a), 15 - 7 * Math.sin(a)]);
	}
	paint(c, stroke(arch, 2.4));
	return c;
};
T['glyph-sort'] = () => {
	const c = canvas(32);
	paint(c, stroke([[7, 10], [25, 10]], 2.4));
	paint(c, stroke([[7, 16], [20, 16]], 2.4));
	paint(c, stroke([[7, 22], [14, 22]], 2.4));
	return c;
};
T['glyph-bag'] = () => {
	const c = canvas(32);
	paint(c, polygon([[7, 12], [25, 12], [27, 28], [5, 28]]), 1);
	const arch = [];
	for (let k = 0; k <= 12; k++) {
		const a = Math.PI - (k * Math.PI) / 12;
		arch.push([16 + 5 * Math.cos(a), 12 - 6 * Math.sin(a)]);
	}
	paint(c, stroke(arch, 2.2));
	return c;
};
// Sync: two arrows chasing round a circle.
T['glyph-sync'] = () => {
	const c = canvas(32);
	const arc = (from, to) => {
		const pts = [];
		for (let k = 0; k <= 12; k++) {
			const a = from + ((to - from) * k) / 12;
			pts.push([16 + 9 * Math.cos(a), 16 - 9 * Math.sin(a)]);
		}
		return pts;
	};
	const deg = (d) => (d * Math.PI) / 180;
	paint(c, stroke(arc(deg(160), deg(20)), 2.4)); // over the top, left to right
	paint(c, stroke(arc(deg(-20), deg(-160)), 2.4)); // under, right to left
	// Arrowheads at the ends: right end points down, left end points up.
	const head = (d, dir) => {
		const x = 16 + 9 * Math.cos(deg(d)), y = 16 - 9 * Math.sin(deg(d));
		return polygon([[x - 4.5, y], [x + 4.5, y], [x, y + 5 * dir]]);
	};
	paint(c, head(20, 1));
	paint(c, head(200, -1));
	return c;
};
// Turn in: a question mark (the hook and the dot), next to glyph-quest's "!".
T['glyph-turnin'] = () => {
	const c = canvas(32);
	const hook = [];
	for (let k = 0; k <= 14; k++) {
		const a = Math.PI - (k * 1.45 * Math.PI) / 14; // from the left, over the top, round to lower right
		hook.push([16 + 6.5 * Math.cos(a), 11 - 6.5 * Math.sin(a)]);
	}
	hook.push([16, 18.5], [16, 21]);
	paint(c, stroke(hook, 3.6));
	paint(c, disc(16, 26.5, 2.4));
	return c;
};
// Talk to: a speech bubble with a tail at the lower left.
T['glyph-talk'] = () => {
	const c = canvas(32);
	const pts = [];
	for (let k = 0; k < 32; k++) {
		const a = (k * 2 * Math.PI) / 32;
		pts.push([16 + 11 * Math.cos(a), 14 - 8 * Math.sin(a)]);
	}
	paint(c, stroke(pts, 2.4, true));
	paint(c, polygon([[9, 19], [14, 21], [7, 27]]), 1);
	return c;
};
// Kill or complete: crosshairs, a ring and four ticks.
T['glyph-kill'] = () => {
	const c = canvas(32);
	paint(c, ring(16, 16, 8, 2.4));
	paint(c, stroke([[16, 3], [16, 10]], 2.4));
	paint(c, stroke([[16, 22], [16, 29]], 2.4));
	paint(c, stroke([[3, 16], [10, 16]], 2.4));
	paint(c, stroke([[22, 16], [29, 16]], 2.4));
	return c;
};
// Go to: a map pin, a round head narrowing to a point.
T['glyph-goto'] = () => {
	const c = canvas(32);
	const pts = [];
	for (let k = 0; k <= 20; k++) {
		const a = Math.PI * (-0.2 + (1.4 * k) / 20);
		pts.push([16 + 8 * Math.cos(a), 13 - 8 * Math.sin(a)]);
	}
	pts.push([16, 29]);
	paint(c, polygon(pts), 1);
	return c;
};
T['glyph-search'] = () => {
	const c = canvas(32);
	paint(c, ring(14, 14, 7, 2.4));
	paint(c, stroke([[19, 19], [26, 26]], 2.8));
	return c;
};

// --- the Signature Hub's pieces (v2) ---

// Rounded corners: the top-left quarter of a disc (fill) and of a 1 px ring
// (line), 32 px drawn for an 8 px corner so they stay sharp when scaled
// down. Theme.Round flips them for the other three corners.
T['corner'] = () => {
	const c = canvas(32);
	paint(c, disc(32, 32, 32));
	return c;
};
T['corner-line'] = () => {
	const c = canvas(32);
	paint(c, ring(32, 32, 30, 4));
	return c;
};
// A heraldic shield, filled and its edge, tinted by faction.
function shieldPoints(inset) {
	const pts = [[6 + inset, 4 + inset], [58 - inset, 4 + inset], [58 - inset, 30]];
	for (let k = 0; k <= 16; k++) {
		const a = (k * Math.PI) / 16;
		pts.push([32 + (26 - inset) * Math.cos(a), 30 + (30 - inset) * Math.sin(a)]);
	}
	pts.push([6 + inset, 30]);
	return pts;
}
T['crest'] = () => {
	const c = canvas(64);
	paint(c, polygon(shieldPoints(0)));
	return c;
};
T['crest-edge'] = () => {
	const c = canvas(64);
	paint(c, stroke(shieldPoints(1.5), 3, true));
	return c;
};
// A checkbox (rounded square outline), its fill, and its tick.
function roundSquare(half, r) {
	return (x, y) => {
		const dx = Math.max(0, Math.abs(x - 16) - (half - r)), dy = Math.max(0, Math.abs(y - 16) - (half - r));
		return Math.hypot(dx, dy) <= r;
	};
}
T['box'] = () => {
	const c = canvas(32);
	const outer = roundSquare(12, 5), inner = roundSquare(9.6, 2.6);
	paint(c, (x, y) => outer(x, y) && !inner(x, y));
	return c;
};
T['box-fill'] = () => {
	const c = canvas(32);
	paint(c, roundSquare(12, 5));
	return c;
};
T['check'] = () => {
	const c = canvas(32);
	paint(c, stroke([[9, 16.5], [14, 21.5], [23.5, 11]], 3.2));
	return c;
};
T['glyph-star'] = () => {
	const c = canvas(32);
	const pts = [];
	for (let k = 0; k < 10; k++) {
		const a = -Math.PI / 2 + (k * Math.PI) / 5;
		const r = k % 2 === 0 ? 12 : 5.2;
		pts.push([16 + r * Math.cos(a), 17 + r * Math.sin(a)]);
	}
	paint(c, stroke(pts, 2.2, true));
	return c;
};
T['glyph-info'] = () => {
	const c = canvas(32);
	paint(c, ring(16, 16, 11, 2.4));
	paint(c, stroke([[16, 14], [16, 22]], 2.6));
	paint(c, disc(16, 10, 1.7));
	return c;
};
T['glyph-grid'] = () => {
	const c = canvas(32);
	for (const [x, y] of [[6, 6], [18, 6], [6, 18], [18, 18]]) {
		paint(c, stroke([[x, y], [x + 8, y], [x + 8, y + 8], [x, y + 8]], 2.2, true));
	}
	return c;
};
T['glyph-chevron'] = () => {
	const c = canvas(32);
	paint(c, stroke([[12, 8], [20, 16], [12, 24]], 2.8));
	return c;
};
// The compass: a ring with a needle, for the toggle and the hub's menu.
T['glyph-compass'] = () => {
	const c = canvas(32);
	paint(c, ring(16, 16, 11, 2.4));
	paint(c, polygon([[20.5, 11.5], [17.5, 17.5], [11.5, 20.5], [14.5, 14.5]]));
	return c;
};
// A small downward caret: the compass strip's target mark.
T['caret'] = () => {
	const c = canvas(32);
	paint(c, polygon([[6, 8], [26, 8], [16, 24]]));
	return c;
};
// The hub's menu: book (leveling), list (routes).
T['glyph-book'] = () => {
	const c = canvas(32);
	paint(c, stroke([[4, 8], [13, 8], [16, 11], [16, 26], [13, 23], [4, 23]], 2.2, true));
	paint(c, stroke([[28, 8], [19, 8], [16, 11], [16, 26], [19, 23], [28, 23]], 2.2, true));
	return c;
};
T['glyph-list'] = () => {
	const c = canvas(32);
	paint(c, stroke([[6, 9], [26, 9]], 2.4));
	paint(c, stroke([[6, 16], [26, 16]], 2.4));
	paint(c, stroke([[6, 23], [19, 23]], 2.4));
	return c;
};
// The pin: a push-pin, tilted, that anchors a window in place.
T['glyph-pin'] = () => {
	const c = canvas(32);
	const rot = (pts) => pts.map(([x, y]) => {
		const a = Math.PI / 4, cx = 16, cy = 16;
		const dx = x - cx, dy = y - cy;
		return [cx + dx * Math.cos(a) - dy * Math.sin(a), cy + dx * Math.sin(a) + dy * Math.cos(a)];
	});
	paint(c, stroke(rot([[11, 5], [21, 5]]), 2.6));
	paint(c, stroke(rot([[13, 5], [13, 13], [9, 18], [23, 18], [19, 13], [19, 5]]), 2.4, true));
	paint(c, stroke(rot([[16, 18], [16, 28]]), 2.4));
	return c;
};

// --- the Pathwise emblem (from the addon's logo) ---
// A compass star: long points up and down, shorter barbed ones to the
// sides, a ring with small spikes between them; inside, a four-point star
// and a path winding down from it. Two layers so the theme can colour
// them: logo-body (the metal) and logo-glow (the star and the path).
// `icon` is both, coloured (silver and Pathwise blue), for the addon list.
function kite(cx, cy, tip, back, half, notch) {
	// A point from (cx, cy) out to `tip`: widest `half` at `back`, its base
	// pulled in to `notch`. tip/back/notch are [x, y].
	return polygon([tip, [back[0] + half[0], back[1] + half[1]], notch, [back[0] - half[0], back[1] - half[1]]]);
}
function emblemBody(c, S) {
	const k = S / 128, P = (x, y) => [x * k, y * k];
	// The ring and a thin inner ring.
	paint(c, ring(64 * k, 64 * k, 33 * k, 7 * k));
	paint(c, ring(64 * k, 64 * k, 25.5 * k, 1.6 * k), 1, 0.8);
	// Four main points: long up and down, shorter to the sides.
	paint(c, kite(64, 64, P(64, 2), P(64, 40), P(9, 0), P(64, 50)));
	paint(c, kite(64, 64, P(64, 126), P(64, 88), P(9, 0), P(64, 78)));
	paint(c, kite(64, 64, P(8, 64), P(30, 64), P(0, 8), P(34, 64)));
	paint(c, kite(64, 64, P(120, 64), P(98, 64), P(0, 8), P(94, 64)));
	// Barbs on the side points, curling back toward the ring.
	paint(c, polygon([P(24, 64), P(30, 55), P(33, 60)]));
	paint(c, polygon([P(104, 64), P(98, 55), P(95, 60)]));
	// Small spikes between the points, outside the ring.
	for (const d of [45, 135, 225, 315]) {
		const a = (d * Math.PI) / 180, ca = Math.cos(a), sa = Math.sin(a);
		const tip = P(64 + 50 * ca, 64 + 50 * sa);
		const l = P(64 + 38 * ca - 4 * sa, 64 + 38 * sa + 4 * ca), r = P(64 + 38 * ca + 4 * sa, 64 + 38 * sa - 4 * ca);
		paint(c, polygon([tip, l, r]));
	}
	return c;
}
function emblemGlow(c, S) {
	const k = S / 128, P = (x, y) => [x * k, y * k];
	// Gems set in the long points.
	paint(c, kite(64, 64, P(64, 14), P(64, 34), P(3.6, 0), P(64, 42)));
	paint(c, kite(64, 64, P(64, 114), P(64, 94), P(3.6, 0), P(64, 86)));
	// The star at the heart.
	const star = [];
	for (let i = 0; i < 8; i++) {
		const a = -Math.PI / 2 + (i * Math.PI) / 4, r = i % 2 === 0 ? 14 : 3.4;
		star.push(P(64 + r * Math.cos(a), 58 + r * Math.sin(a)));
	}
	paint(c, polygon(star));
	// The path, winding down from the star to the lower point.
	const pts = [];
	for (let t = 0; t <= 1.0001; t += 0.05) {
		const y = 66 + t * 24, x = 64 + 7 * Math.sin(t * Math.PI * 1.6) * (1 - 0.3 * t);
		pts.push(P(x, y));
	}
	paint(c, stroke(pts, 5.2 * k));
	return c;
}
T['logo-body'] = () => emblemBody(canvas(128), 128);
T['logo-glow'] = () => emblemGlow(canvas(128), 128);
// The addon list's icon and the minimap button's mark: both layers in colour.
function colourise(c, rgb) {
	for (let i = 0; i < c.size * c.size; i++) {
		c.px[i * 4] *= rgb[0]; c.px[i * 4 + 1] *= rgb[1]; c.px[i * 4 + 2] *= rgb[2];
	}
	return c;
}
function over(dst, src) {
	for (let i = 0; i < dst.size * dst.size; i++) {
		const sa = src.px[i * 4 + 3], da = dst.px[i * 4 + 3], oa = sa + da * (1 - sa);
		for (let ch = 0; ch < 3; ch++) {
			dst.px[i * 4 + ch] = oa ? (src.px[i * 4 + ch] * sa + dst.px[i * 4 + ch] * da * (1 - sa)) / oa : 0;
		}
		dst.px[i * 4 + 3] = oa;
	}
	return dst;
}
T['icon'] = () => {
	const body = colourise(emblemBody(canvas(64), 64), [0.85, 0.88, 0.92]);
	const glow = colourise(emblemGlow(canvas(64), 64), [0.4, 0.84, 1]);
	return over(body, glow);
};

// --- class and profession marks, faction crests (v2) ---
// Pathwise's own drawings: the hub shows the game's own icons where the
// game has them, and these where it has not (and in the preview).

// Clears a shape out of what is painted (holes: eyes, a gear's hub).
function erase(c, shape) {
	const { size, px } = c;
	for (let y = 0; y < size; y++) {
		for (let x = 0; x < size; x++) {
			let hit = 0;
			for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) if (shape(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)) hit++;
			if (hit) px[(y * size + x) * 4 + 3] *= 1 - hit / (SS * SS);
		}
	}
}
const rect = (x0, y0, x1, y1) => (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
function arcPts(cx, cy, r, a0, a1, n = 24, ry = r) {
	const out = [];
	for (let i = 0; i <= n; i++) {
		const a = ((a0 + ((a1 - a0) * i) / n) * Math.PI) / 180;
		out.push([cx + r * Math.cos(a), cy + ry * Math.sin(a)]);
	}
	return out;
}
const C64 = (draw) => () => { const c = canvas(64); draw(c); return c; };

// Classes.
T['class-warrior'] = C64((c) => {
	paint(c, polygon([[50, 8], [54, 12], [24, 44], [18, 42], [20, 38]]));
	paint(c, stroke([[13, 37], [27, 51]], 5));
	paint(c, stroke([[11, 53], [19, 45]], 4.5));
	paint(c, disc(9, 55, 3.6));
});
T['class-paladin'] = C64((c) => {
	paint(c, polygon([[12, 9], [52, 9], [52, 30], ...arcPts(32, 30, 20, 0, 180, 18, 28).slice(1, -1), [12, 30]]));
	erase(c, rect(28.5, 15, 35.5, 48));
	erase(c, rect(19, 23, 45, 30));
});
T['class-hunter'] = C64((c) => {
	paint(c, stroke(arcPts(44, 32, 24, 128, 232, 24), 4.2));
	paint(c, stroke([[29.3, 13], [29.3, 51]], 1.8));
	paint(c, stroke([[10, 32], [50, 32]], 3));
	paint(c, polygon([[58, 32], [48, 25.5], [48, 38.5]]));
	paint(c, polygon([[8, 26], [14, 32], [8, 38], [12, 32]]));
});
function dagger(c, flip) {
	const f = ([x, y]) => (flip ? [64 - x, y] : [x, y]);
	paint(c, polygon([[52, 6], [55, 9], [30, 38], [25, 33]].map(f)));
	paint(c, stroke([[20, 31], [32, 43]].map(f), 4));
	paint(c, stroke([[17, 47], [26, 38]].map(f), 4.5));
	paint(c, disc(...f([15, 49]), 3.2));
}
T['class-rogue'] = C64((c) => { dagger(c, false); dagger(c, true); });
T['class-priest'] = C64((c) => {
	paint(c, disc(32, 32, 10));
	for (let i = 0; i < 8; i++) {
		const a = (i * Math.PI) / 4;
		paint(c, stroke([[32 + 15 * Math.cos(a), 32 + 15 * Math.sin(a)], [32 + (i % 2 ? 22 : 27) * Math.cos(a), 32 + (i % 2 ? 22 : 27) * Math.sin(a)]], 3.6));
	}
	erase(c, disc(32, 32, 5));
});
function flame(cx, cy, w, h) {
	const pts = [];
	for (let i = 0; i <= 40; i++) {
		const t = i / 40, a = t * 2 * Math.PI;
		const r = w * (1 - Math.cos(a)) / 2;
		pts.push([cx + Math.sin(a) * r * 0.9 * (1 + 0.25 * Math.sin(a * 2)), cy - h * (1 + Math.cos(a)) / 2 + h * 0.35]);
	}
	return polygon(pts);
}
function drop(cx, cy, r, top) {
	return polygon([[cx, top], ...arcPts(cx, cy, r, -60, 240, 30)]);
}
T['class-mage'] = C64((c) => {
	paint(c, drop(32, 40, 17, 3));
	erase(c, drop(32, 46, 8, 26));
});
T['class-warlock'] = C64((c) => {
	paint(c, disc(32, 27, 19));
	paint(c, rect(21, 34, 43, 52));
	erase(c, disc(24.5, 28, 5.5));
	erase(c, disc(39.5, 28, 5.5));
	erase(c, polygon([[32, 34], [28.5, 41], [35.5, 41]]));
	for (const x of [26.5, 32, 37.5]) erase(c, rect(x - 1.1, 45, x + 1.1, 52));
});
T['class-druid'] = C64((c) => {
	paint(c, (x, y) => ((x - 32) / 13) ** 2 + ((y - 42) / 11) ** 2 <= 1);
	paint(c, disc(15.5, 26, 5.5));
	paint(c, disc(25.5, 16.5, 6));
	paint(c, disc(38.5, 16.5, 6));
	paint(c, disc(48.5, 26, 5.5));
});
T['class-shaman'] = C64((c) => {
	paint(c, polygon([[38, 4], [16, 36], [29, 36], [22, 60], [48, 24], [34, 24], [44, 4]]));
});

// Professions.
T['prof-alchemy'] = C64((c) => {
	paint(c, disc(32, 42, 17));
	paint(c, rect(26.5, 12, 37.5, 30));
	paint(c, stroke([[23, 11], [41, 11]], 5));
	erase(c, (x, y) => Math.hypot(x - 32, y - 42) <= 12.5 && y < 38);
	erase(c, disc(26, 46, 2.4));
});
T['prof-blacksmithing'] = C64((c) => {
	paint(c, polygon([[6, 17], [46, 17], [60, 13], [54, 24], [44, 26], [38, 35], [44, 44], [20, 44], [26, 35], [22, 26], [10, 26]]));
	paint(c, rect(14, 44, 50, 52));
});
T['prof-enchanting'] = C64((c) => {
	paint(c, polygon([[32, 3], [48, 26], [32, 61], [16, 26]]));
	erase(c, stroke([[16, 26], [48, 26]], 1.6));
	erase(c, stroke([[32, 3], [26, 26], [32, 61]], 1.4));
	erase(c, stroke([[32, 3], [38, 26], [32, 61]], 1.4));
});
T['prof-engineering'] = C64((c) => {
	paint(c, disc(32, 32, 19));
	for (let i = 0; i < 8; i++) {
		const a = (i * Math.PI) / 4, ca = Math.cos(a), sa = Math.sin(a);
		const pt = (r, o) => [32 + r * ca - o * sa, 32 + r * sa + o * ca];
		paint(c, polygon([pt(16, -5), pt(27, -4), pt(27, 4), pt(16, 5)]));
	}
	erase(c, disc(32, 32, 8));
});
T['prof-herbalism'] = C64((c) => {
	const leaf = [...arcPts(44, 48, 36, 180, 270, 20), ...arcPts(20, 16, 36, 0, 90, 20)];
	paint(c, polygon(leaf));
	erase(c, stroke([[14, 52], [46, 14]], 2));
	paint(c, stroke([[6, 60], [16, 50]], 3));
});
T['prof-leatherworking'] = C64((c) => {
	paint(c, polygon([[10, 8], [24, 15], [40, 15], [54, 8], [49, 25], [56, 40], [44, 56], [32, 49], [20, 56], [8, 40], [15, 25]]));
	for (let y = 20; y <= 46; y += 6) erase(c, rect(31, y, 33, y + 3));
});
T['prof-mining'] = C64((c) => {
	paint(c, stroke(arcPts(32, 40, 26, 205, 335, 26, 26), 5.2));
	paint(c, polygon([[6, 29], [10, 26], [12, 33]]));
	paint(c, polygon([[58, 29], [54, 26], [52, 33]]));
	paint(c, stroke([[32, 15], [32, 60]], 5.5));
});
T['prof-skinning'] = C64((c) => {
	paint(c, polygon([[18, 44], [26, 26], [40, 12], [56, 6], [46, 22], [32, 36], [24, 46]]));
	paint(c, stroke([[19, 45], [8, 58]], 6));
});
T['prof-tailoring'] = C64((c) => {
	paint(c, polygon([[52, 9], [55, 12], [14, 54], [11, 53]]));
	erase(c, disc(49.6, 13.4, 1.6));
	paint(c, stroke([[50, 13], [58, 26], [48, 38], [32, 36], [24, 44], [26, 58]], 2));
});
T['prof-cooking'] = C64((c) => {
	paint(c, polygon([[10, 30], ...arcPts(32, 30, 22, 0, 180, 24, 22).reverse(), [54, 30]]));
	paint(c, stroke([[5, 30], [59, 30]], 4));
	for (const x of [22, 32, 42]) paint(c, stroke([[x, 22], [x - 3, 17], [x, 12], [x - 3, 7]], 2.4));
});
T['prof-first-aid'] = C64((c) => {
	paint(c, rect(25, 8, 39, 56));
	paint(c, rect(8, 25, 56, 39));
});
T['prof-fishing'] = C64((c) => {
	paint(c, ring(36, 8, 3.4, 2.4));
	paint(c, stroke([[36, 11], [36, 40], ...arcPts(26, 40, 10, 0, 160, 16).slice(1)], 3.6));
	paint(c, polygon([[16, 36], [14, 26], [21, 33]]));
});

// Faction crests, Pathwise-made after the factions' emblems: each a fill
// (the faction's colour), an edge (gold for the Alliance, dark iron for the
// Horde) and a mark (the Pathwise star with its winding path), tinted in game.
function shieldOutline(inset) {
	const i = inset;
	return [[10 + i, 18 + i], ...arcPts(32, 30, 22 - i, 210, 330, 12, 15).map(([x, y]) => [x, y - 2 + i]), [54 - i, 18 + i],
		[54 - i, 30], ...arcPts(32, 30, 22 - i, 0, 180, 22, 31 - i).slice(1, -1), [10 + i, 30]];
}
function flameSpike(x, y, h, lean, w = 3.2) {
	// A flame-like spike rising from (x, y), leaning `lean` to one side.
	return polygon([[x - w, y], [x + lean * 0.4, y - h * 0.55], [x + lean, y - h], [x + lean * 0.2, y - h * 0.45], [x + w, y]]);
}
T['crest-alliance'] = C64((c) => paint(c, polygon(shieldOutline(1))));
T['crest-alliance-edge'] = C64((c) => {
	paint(c, stroke(shieldOutline(2.2), 4, true));
	// Flames along the top, tallest in the middle.
	paint(c, flameSpike(32, 15, 14, 0, 4));
	paint(c, flameSpike(23, 16, 11, -4));
	paint(c, flameSpike(41, 16, 11, 4));
	paint(c, flameSpike(14, 19, 9, -5));
	paint(c, flameSpike(50, 19, 9, 5));
	// Flicks at the shoulders and above the point.
	paint(c, polygon([[9, 24], [2, 20], [5, 27], [9, 31]]));
	paint(c, polygon([[55, 24], [62, 20], [59, 27], [55, 31]]));
	paint(c, polygon([[16, 46], [8, 48], [14, 52], [19, 50]]));
	paint(c, polygon([[48, 46], [56, 48], [50, 52], [45, 50]]));
});
function pathwiseMark(c, cy, r) {
	const star = [];
	for (let k = 0; k < 8; k++) {
		const a = -Math.PI / 2 + (k * Math.PI) / 4, rr = k % 2 === 0 ? r : r * 0.28;
		star.push([32 + rr * Math.cos(a), cy + rr * Math.sin(a)]);
	}
	paint(c, polygon(star));
	const path = [];
	for (let t = 0; t <= 1.0001; t += 0.05) path.push([32 + 4.5 * Math.sin(t * Math.PI * 1.7) * (1 - 0.3 * t), cy + r * 0.9 + t * r * 1.5]);
	paint(c, stroke(path, 3.2));
}
T['crest-alliance-mark'] = C64((c) => {
	pathwiseMark(c, 29, 10);
	paint(c, stroke(arcPts(32, 29, 14, 205, 335, 16), 2.2)); // a helm's arch over the star
});
// Horde: an open, spiked arch on two blades.
function hordeArch(c, grow) {
	const g = grow || 0;
	paint(c, stroke(arcPts(32, 27, 17, 128, 412, 40), 10 + g));
	// Spikes along the top and sides.
	for (const d of [-90, -55, -125, -20, -160]) {
		const a = (d * Math.PI) / 180, ca = Math.cos(a), sa = Math.sin(a);
		const base = 21 + g / 2, tip = (d === -90 ? 31 : 29) + g;
		const at = (r, o) => [32 + r * ca - o * sa, 27 + r * sa + o * ca];
		paint(c, polygon([at(base, -5 - g / 2), at(tip, d < -90 ? -1.5 : 1.5), at(base, 5 + g / 2)]));
	}
	// Side prongs.
	paint(c, polygon([[12 - g, 30], [1 - g, 26 - g], [6, 36], [14, 38]]));
	paint(c, polygon([[52 + g, 30], [63 + g, 26 - g], [58, 36], [50, 38]]));
	// The two blades, down and out.
	paint(c, polygon([[18 - g, 40], [24 + g, 40], [24, 50], [21, 62 + g], [15 - g, 49]]));
	paint(c, polygon([[46 + g, 40], [40 - g, 40], [40, 50], [43, 62 + g], [49 + g, 49]]));
}
T['crest-horde'] = C64((c) => hordeArch(c, 0));
T['crest-horde-edge'] = C64((c) => {
	hordeArch(c, 2.2);
	const inner = canvas(64);
	hordeArch(inner, 0);
	for (let k = 0; k < 64 * 64; k++) c.px[k * 4 + 3] = Math.max(0, c.px[k * 4 + 3] - inner.px[k * 4 + 3]);
});
T['crest-horde-mark'] = C64((c) => pathwiseMark(c, 24, 9));
T['crest-star'] = C64((c) => pathwiseMark(c, 26, 12));

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
