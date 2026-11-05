'use strict';
// tools/curseforge.js: which addons a release uploads. Run: node --test tests/
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { changedSince } = require('../tools/curseforge.js');

// A throwaway repository: two addons released as v1, then changed.
function repo() {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pathwise-cf-'));
	const git = (...args) => execFileSync('git', args, { cwd: dir, stdio: 'ignore' });
	const write = (file, text) => {
		fs.mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
		fs.writeFileSync(path.join(dir, file), text);
	};
	git('init', '-q');
	git('config', 'user.email', 'test@example.invalid');
	git('config', 'user.name', 'test');
	git('config', 'core.autocrlf', 'false');
	for (const a of ['A', 'B']) {
		write(`${a}/${a}.toc`, `## Interface: 16001\n## Title: ${a}\n## Version: 0.1.0\n\nCore.lua\n`);
		write(`${a}/Core.lua`, 'local x = 1\n');
	}
	git('add', '-A');
	git('commit', '-qm', 'one');
	git('tag', 'v1');
	return { dir, git, write };
}

test('a version bump alone is not a change; code or other TOC lines are', () => {
	const r = repo();
	try {
		for (const a of ['A', 'B']) r.write(`${a}/${a}.toc`, `## Interface: 16001\n## Title: ${a}\n## Version: 0.1.1\n\nCore.lua\n`);
		r.write('A/Core.lua', 'local x = 2\n');
		r.git('add', '-A');
		r.git('commit', '-qm', 'two');
		assert.strictEqual(changedSince('A', 'v1', r.dir), true, 'A: its code changed');
		assert.strictEqual(changedSince('B', 'v1', r.dir), false, 'B: only its version');
		// Any other TOC line counts.
		r.write('B/B.toc', `## Interface: 16002\n## Title: B\n## Version: 0.1.1\n\nCore.lua\n`);
		r.git('commit', '-qam', 'three');
		assert.strictEqual(changedSince('B', 'v1', r.dir), true, 'B: its interface changed');
		assert.strictEqual(changedSince('B', undefined, r.dir), true, 'no ref: everything');
	} finally {
		fs.rmSync(r.dir, { recursive: true, force: true });
	}
});
