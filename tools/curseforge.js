'use strict';
// Uploads the release zips (tools/pack.js: dist/<Addon>-<version>.zip, one
// per CurseForge project) through CurseForge's upload API
// (https://support.curseforge.com/en/support/solutions/articles/9000197321).
//
//   node tools/curseforge.js upload --dry-run   print what would be sent; send nothing
//   node tools/curseforge.js upload             upload every zip that has a project
//   node tools/curseforge.js versions           list CurseForge's game versions
//
// Settings come from the environment (in GitHub: the repository's secrets
// and variables), never from this file:
//   CF_API_KEY            the CurseForge API token (a secret; never printed)
//   CF_PROJECT_<ADDON>    optional: an addon's CurseForge project id, the folder
//                         name in capitals (CF_PROJECT_PATHWISEUI...), for one
//                         not in PROJECTS below. An addon without one is skipped.
//   CF_GAME_VERSIONS      optional: CurseForge game version ids, comma-separated.
//                         Without it, the game version named like the TOCs'
//                         client (CF_GAME_VERSION_NAME, default 1.60.1) is used.
//   CF_SINCE              optional: a git ref (the last release's tag); addons
//                         whose folder did not change since it (a new "## Version:"
//                         line alone does not count) are not uploaded.
//   CF_ONLY               optional: addon folders, comma-separated
//                         (PathwiseUI,Pathwise_Heal); the others are not uploaded.
//
// The release type follows the version: 1.2.0 is a release, 1.2.0-beta.1 a
// beta, anything else with a dash (1.2.0-dev) an alpha. The changelog is
// that version's section of CHANGELOG.md (tools/version.js writes it).

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { version } = require('./pack.js');

const ROOT = path.resolve(__dirname, '..');
const API = 'https://wow.curseforge.com/api';
const ADDONS = ['Pathwise', 'Pathwise_Gear', 'Pathwise_Bags', 'PathwiseUI', 'Pathwise_Heal', 'Pathwise_Encounters'];
// The CurseForge projects (public ids; CF_PROJECT_<ADDON> overrides one).
// Pathwise_Encounters has no project yet: it is skipped until it gets one
// here or in CF_PROJECT_PATHWISE_ENCOUNTERS.
const PROJECTS = { Pathwise: '1783619', Pathwise_Gear: '1784186', Pathwise_Bags: '1784179', PathwiseUI: '1785205', Pathwise_Heal: '1785207' };

function fail(msg) {
	console.error(msg);
	process.exit(1);
}

function token() {
	const t = process.env.CF_API_KEY;
	if (!t) fail('CF_API_KEY is not set (in GitHub: Settings > Secrets and variables > Actions).');
	return t;
}

function releaseType(v) {
	if (!v.includes('-')) return 'release';
	return /-beta/i.test(v) ? 'beta' : 'alpha';
}

// The text under "## <v> (date)" in CHANGELOG.md, up to the next "## ".
function changelogFor(v) {
	const log = fs.readFileSync(path.join(ROOT, 'CHANGELOG.md'), 'utf8');
	const lines = log.split(/\r?\n/);
	const start = lines.findIndex((l) => l.startsWith(`## ${v} `) || l === `## ${v}`);
	if (start < 0) fail(`CHANGELOG.md has no "## ${v}" section: run node tools/version.js ${v} first.`);
	const out = [];
	for (let i = start + 1; i < lines.length && !lines[i].startsWith('## '); i++) out.push(lines[i]);
	return out.join('\n').trim();
}

async function allVersions() {
	const res = await fetch(`${API}/game/versions`, { headers: { 'X-Api-Token': token() } });
	if (!res.ok) fail(`CurseForge answered ${res.status} ${res.statusText}`);
	return res.json();
}

// The game version ids to tag the files with.
async function gameVersions() {
	const given = (process.env.CF_GAME_VERSIONS || '').split(',').map((s) => s.trim()).filter(Boolean);
	if (given.length) {
		const ids = given.map(Number);
		if (ids.some((n) => !Number.isInteger(n))) fail('CF_GAME_VERSIONS must be numbers, comma-separated.');
		return ids;
	}
	const name = process.env.CF_GAME_VERSION_NAME || '1.60.1';
	const matches = (await allVersions()).filter((g) => g.name === name);
	if (matches.length !== 1) {
		fail(`found ${matches.length} CurseForge game versions named "${name}": set CF_GAME_VERSIONS to the right id (node tools/curseforge.js versions lists them).`);
	}
	return [matches[0].id];
}

function projectVar(addon) { return `CF_PROJECT_${addon.toUpperCase()}`; }

// Whether an addon's folder changed since a git ref (true without one). A
// TOC whose only change is its "## Version:" line does not count: a release
// bumps every addon's version, and an addon with nothing else new is not
// uploaded.
function changedSince(addon, ref, cwd = ROOT) {
	if (!ref) return true;
	let diff;
	try {
		diff = execFileSync('git', ['diff', '-U0', '--no-color', '--no-ext-diff', ref, 'HEAD', '--', `${addon}/`],
			{ cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
	} catch {
		return true;
	}
	let file = null;
	for (const line of diff.split(/\r?\n/)) {
		const header = line.match(/^diff --git a\/.* b\/(.*)$/);
		if (header) { file = header[1]; continue; }
		if (/^(index |--- |\+\+\+ |@@ )/.test(line) || line === '') continue;
		// A changed line, a new, deleted or renamed file, or a binary change.
		const versionLine = /\.toc$/i.test(file || '') && /^[+-]## Version:/.test(line);
		if (!versionLine) return true;
	}
	return false;
}

// What to upload: { addon, project, file, name }, and why others are skipped.
function plan(v) {
	const out = [];
	const skipped = [];
	const only = (process.env.CF_ONLY || '').split(',').map((a) => a.trim()).filter(Boolean);
	for (const a of only) if (!ADDONS.includes(a)) fail(`CF_ONLY: no addon "${a}" (${ADDONS.join(', ')})`);
	for (const addon of ADDONS) {
		if (!fs.existsSync(path.join(ROOT, addon))) continue;
		if (only.length && !only.includes(addon)) { skipped.push(`${addon}: not in CF_ONLY`); continue; }
		const project = process.env[projectVar(addon)] || PROJECTS[addon];
		const file = path.join(ROOT, 'dist', `${addon}-${v}.zip`);
		if (!project) skipped.push(`${addon}: no ${projectVar(addon)}`);
		else if (!/^\d+$/.test(project)) skipped.push(`${addon}: ${projectVar(addon)} is not a number`);
		else if (!changedSince(addon, process.env.CF_SINCE)) skipped.push(`${addon}: unchanged since ${process.env.CF_SINCE}`);
		else if (!fs.existsSync(file)) skipped.push(`${addon}: ${path.relative(ROOT, file)} not built (node tools/pack.js)`);
		else out.push({ addon, project, file, name: `${addon.replace(/_/g, ' ').replace('PathwiseUI', 'Pathwise UI')} ${v}` });
	}
	return { out, skipped };
}

async function upload(dryRun) {
	const v = version();
	const changelog = changelogFor(v);
	const { out, skipped } = plan(v);
	for (const s of skipped) console.log(`skip ${s}`);
	if (out.length === 0) fail('nothing to upload.');
	const ids = dryRun && !process.env.CF_API_KEY ? ['(looked up at upload)'] : await gameVersions();
	for (const u of out) {
		const meta = { displayName: u.name, changelog, changelogType: 'markdown', releaseType: releaseType(v), gameVersions: ids };
		if (dryRun) {
			console.log(`would upload ${path.relative(ROOT, u.file)} to project ${u.project} as "${u.name}" (${meta.releaseType}), game versions ${ids.join(', ')}`);
			continue;
		}
		const form = new FormData();
		form.append('metadata', JSON.stringify(meta));
		form.append('file', new Blob([fs.readFileSync(u.file)], { type: 'application/zip' }), path.basename(u.file));
		const res = await fetch(`${API}/projects/${u.project}/upload-file`, { method: 'POST', headers: { 'X-Api-Token': token() }, body: form });
		const text = await res.text();
		if (!res.ok) fail(`${u.addon}: upload failed: ${res.status} ${res.statusText} ${text}`);
		console.log(`uploaded ${u.name} (${meta.releaseType}): ${text}`);
	}
}

async function versions() {
	for (const g of await allVersions()) console.log(`${g.id}\t${g.name}\t(type ${g.gameVersionTypeID})`);
}

function main() {
	const cmd = process.argv[2];
	if (cmd === 'versions') versions();
	else if (cmd === 'upload') upload(process.argv.includes('--dry-run'));
	else fail('usage: node tools/curseforge.js upload [--dry-run] | versions');
}

if (require.main === module) main();
module.exports = { changedSince };
