'use strict';
// Photographs the preview pages (preview/*.html, made by
// tools/preview/preview.py) in headless Chromium: preview/<scene>.png.
// Run from the repository root: node tools/preview/shot.js [scene ...]

const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const DIR = path.join(process.cwd(), 'preview');

async function main() {
	const wanted = process.argv.slice(2);
	const pages = fs.readdirSync(DIR).filter((f) => f.endsWith('.html'))
		.filter((f) => !wanted.length || wanted.includes(path.basename(f, '.html')));
	const browser = await chromium.launch();
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 2 });
	for (const f of pages) {
		await page.goto('file://' + path.join(DIR, f));
		await page.evaluate(() => document.fonts.ready);
		const out = path.join(DIR, path.basename(f, '.html') + '.png');
		await page.screenshot({ path: out });
		console.log('wrote ' + path.relative(process.cwd(), out));
	}
	await browser.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
