'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { scan, query } = require('../copilot/modules/analyzers/typescript/analyze.cjs');
const modulePath = process.env.SDD_TEST_TYPESCRIPT;

test('portable TypeScript workspace: symbols, aliases, imports, warm cache and incremental diagnostics', { skip: !modulePath }, () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'sdd-ts-'));
  const root = path.join(temp, 'renamed', 'client');
  const out = path.join(temp, 'agent-state');
  function put(file, text) { const full = path.join(root, file); fs.mkdirSync(path.dirname(full), { recursive: true }); fs.writeFileSync(full, text); }
  try {
    put('package.json', JSON.stringify({ name: 'portable-client', devDependencies: { typescript: '*' }, scripts: { test: 'node --test' } }));
    put(path.join('node_modules', 'typescript', 'index.js'), `module.exports = require(${JSON.stringify(modulePath)});`);
    put('angular.json', JSON.stringify({ version: 1, projects: { portal: { root: '', sourceRoot: 'src', projectType: 'application' } } }));
    put('tsconfig.json', JSON.stringify({ compilerOptions: { strict: true, target: 'es2022', module: 'commonjs', baseUrl: '.', paths: { '@core/*': ['src/*'] } }, include: ['src/**/*.ts'] }));
    put(path.join('src', 'service.ts'), 'export class CatalogService { run(value: number): number { return value + 1; } }');
    put(path.join('src', 'consumer.ts'), "import { CatalogService } from '@core/service'; export function consume() { return new CatalogService().run(1); }");
    put(path.join('src', 'metadata.ts'), "function Injectable(options: unknown) { return (target: Function) => {}; } class HttpClient { get(url: string) { return url; } } @Injectable({providedIn:'root'}) export class CatalogApi { constructor(private http: HttpClient) {} load() { return this.http.get('/api/catalog'); } } export const routes = [{path:'catalog', component:CatalogApi}];");
    const cold = scan(root, out);
    assert.throws(() => scan(root, path.join(root, 'cache')), /outside/);
    assert.equal(cold.summary.status, 'SCANNED');
    assert.equal(cold.index.projects[0].name, 'portal');
    assert.equal(cold.index.documents.length, 3);
    assert.equal(cold.index.documents.flatMap(d => d.diagnostics).length, 0);
    const match = query(cold.index, 'CatalogService');
    assert.equal(match.candidates.length, 1);
    const method = cold.index.documents.flatMap(d => d.symbols).find(s => s.name === 'run');
    assert.ok(cold.index.documents.flatMap(d => d.calls).some(c => c.to === method.id));
    assert.equal(cold.index.documents.find(d => d.path.endsWith('consumer.ts')).imports[0].target, 'src/service.ts');
    const metadata = cold.index.documents.find(d => d.path.endsWith('metadata.ts'));
    assert.equal(metadata.http.length, 1);
    assert.ok(metadata.providers.some(p => p.property === 'providedIn'));
    assert.ok(metadata.routes.some(p => p.property === 'path'));
    assert.equal(metadata.decorators.length, 1);
    assert.equal(scan(root, out).summary.status, 'UP_TO_DATE');
    put(path.join('src', 'service.ts'), 'export class CatalogService { run(value: string): string { return value; } }');
    const incremental = scan(root, out);
    assert.equal(incremental.summary.changedDocuments, 1);
    assert.equal(incremental.summary.revalidatedDocuments, 3);
    assert.ok(incremental.index.documents.find(d => d.path.endsWith('consumer.ts')).diagnostics.some(d => d.code === 2345));
    assert.equal(scan(root, path.join(temp, 'fresh')).index.documents.flatMap(d => d.diagnostics).length,
      incremental.index.documents.flatMap(d => d.diagnostics).length);
    execFileSync('git', ['-C', root, 'init', '--quiet', '--initial-branch=fixture']);
    const helper = path.join(__dirname, '..', 'copilot', 'modules', 'investigate', 'scripts', 'akzo.ps1');
    const environment = { ...process.env, AKZO_AGENT_HOME: path.join(temp, 'isolated-state') };
    const invoke = command => JSON.parse(execFileSync('powershell', ['-NoProfile', '-File', helper, command, '-Repo', root],
      { env: environment, encoding: 'utf8', timeout: 120000 }));
    const architecture = invoke('arch');
    assert.equal(architecture.analysis, 'typescript-semantic');
    assert.equal(architecture.coverage.documents, 3);
    const affected = invoke('affected');
    assert.equal(affected.language, 'typescript');
    assert.equal(affected.workingDirectory, root);
    const review = invoke('review');
    assert.equal(review.language, 'typescript');
    assert.ok(review.findings.some(d => d.rule === 'TS2345'));
    assert.match(review.verification, /independent statuses/);
    fs.unlinkSync(path.join(root, 'src', 'consumer.ts'));
    assert.equal(scan(root, out).summary.removedDocuments, 1);
    put('tsconfig.json', '{');
    assert.throws(() => scan(root, out), /expected/);
  } finally { fs.rmSync(temp, { recursive: true, force: true }); }
});
