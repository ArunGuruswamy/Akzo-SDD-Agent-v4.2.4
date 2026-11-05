'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const schema = 1;
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const ignored = new Set(['node_modules', '.git', 'dist', '.angular', 'coverage', 'bin', 'obj']);

function scan(root, out) {
  const started = performance.now();
  root = fs.realpathSync(root);
  const cacheRelative = path.relative(root, path.resolve(out));
  if (!cacheRelative || (!cacheRelative.startsWith(`..${path.sep}`) && cacheRelative !== '..' && !path.isAbsolute(cacheRelative)))
    throw new Error('Architecture cache must be outside the analyzed workspace.');
  const localRequire = createRequire(path.join(root, 'package.json'));
  const ts = localRequire('typescript');
  const compilerHash = hash(fs.readFileSync(localRequire.resolve('typescript')));
  const files = [];
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.isSymbolicLink() || ignored.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.(ts|tsx|json)$/.test(entry.name)) files.push(full);
    }
  }
  walk(root);
  const relative = full => path.relative(root, full).split(path.sep).join('/');
  const inputs = files.filter(f => /\.(ts|tsx)$/.test(f) ||
    /(?:tsconfig[^\\/]*|angular|package|package-lock)\.json$/.test(f));
  const fingerprint = hash(JSON.stringify(inputs.sort().map(f => [relative(f), hash(fs.readFileSync(f))])) +
    ts.version + compilerHash + schema + hash(fs.readFileSync(__filename)));
  const target = path.join(out, 'index.json');
  let prior;
  if (fs.existsSync(target)) {
    prior = JSON.parse(fs.readFileSync(target, 'utf8'));
    const dependenciesCurrent = (prior.dependencyInputs || []).every(d =>
      fs.existsSync(d.path) && hash(fs.readFileSync(d.path)) === d.hash);
    if (prior.root === root && prior.schema === schema && prior.fingerprint === fingerprint && dependenciesCurrent)
      return { index: prior, summary: { status: 'UP_TO_DATE', elapsedMs: Math.round(performance.now() - started), changedDocuments: 0 } };
  }
  const packageFile = path.join(root, 'package.json');
  const pkg = fs.existsSync(packageFile) ? JSON.parse(fs.readFileSync(packageFile, 'utf8')) : {};
  const angularFile = path.join(root, 'angular.json');
  const angular = fs.existsSync(angularFile) ? JSON.parse(fs.readFileSync(angularFile, 'utf8')) : {};
  const configs = files.filter(f => /[\\/]tsconfig[^\\/]*\.json$/.test(f))
    .sort((a, b) => b.split(path.sep).length - a.split(path.sep).length || a.localeCompare(b));
  const programs = [];
  const diagnostics = [];
  for (const config of configs) {
    const normalizedConfig = config.split(path.sep).join('/');
    const read = ts.readConfigFile(normalizedConfig, ts.sys.readFile);
    if (read.error) throw new Error(ts.flattenDiagnosticMessageText(read.error.messageText, '\n'));
    const parsed = ts.parseJsonConfigFileContent(read.config, ts.sys, path.dirname(config), { noEmit: true }, normalizedConfig);
    diagnostics.push(...parsed.errors.map(d => ({ config: relative(config), message: ts.flattenDiagnosticMessageText(d.messageText, '\n') })));
    if (parsed.fileNames.length) programs.push({ config: relative(config),
      rootNames: parsed.fileNames, options: parsed.options, projectReferences: parsed.projectReferences });
  }
  if (!programs.length) programs.push({ config: '',
    rootNames: files.filter(f => /\.(ts|tsx)$/.test(f)), options: { noEmit: true, experimentalDecorators: true,
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.Latest } });
  const documents = [];
  const seen = new Set();
  const dependencyFiles = new Set();
  for (const { config, ...inputs } of programs) {
    if (inputs.rootNames.every(file => seen.has(relative(file)))) continue;
    const program = ts.createProgram(inputs);
    const checker = program.getTypeChecker();
    function symbolId(symbol) {
      if (!symbol) return null;
      if (symbol.flags & ts.SymbolFlags.Alias) symbol = checker.getAliasedSymbol(symbol);
      const declaration = symbol.valueDeclaration || symbol.declarations?.[0];
      if (!declaration) return null;
      const source = declaration.getSourceFile();
      return `${relative(source.fileName)}:${source.getLineAndCharacterOfPosition(declaration.getStart()).line + 1}:${symbol.getName()}`;
    }
    for (const source of program.getSourceFiles()) {
      const rel = relative(source.fileName);
      if (source.isDeclarationFile || rel.startsWith('../') || rel.split('/').some(p => ignored.has(p)))
        dependencyFiles.add(source.fileName);
      if (rel.startsWith('../') || path.isAbsolute(rel) || rel.split('/').some(p => ignored.has(p)) ||
        source.isDeclarationFile || seen.has(rel)) continue;
      seen.add(rel);
      const doc = { path: rel, config, hash: hash(source.text), symbols: [], imports: [], calls: [], decorators: [],
        providers: [], routes: [], http: [], diagnostics: [] };
      const at = node => source.getLineAndCharacterOfPosition(node.getStart()).line + 1;
      function visit(node, container) {
        const declaration = ts.isClassDeclaration(node) || ts.isInterfaceDeclaration(node) || ts.isFunctionDeclaration(node) ||
          ts.isMethodDeclaration(node) || ts.isEnumDeclaration(node) || ts.isTypeAliasDeclaration(node);
        if (declaration && node.name) {
          const id = symbolId(checker.getSymbolAtLocation(node.name));
          doc.symbols.push({ id, name: node.name.getText(source), kind: ts.SyntaxKind[node.kind], line: at(node),
            container: container || null, bases: node.heritageClauses?.flatMap(h => h.types.map(t => t.getText(source))) || [] });
          container = id;
        }
        if (ts.isImportDeclaration(node)) {
          const resolved = ts.resolveModuleName(node.moduleSpecifier.text, source.fileName, program.getCompilerOptions(), ts.sys).resolvedModule;
          doc.imports.push({ module: node.moduleSpecifier.text, target: resolved ? relative(resolved.resolvedFileName) : null, line: at(node) });
        }
        if (ts.isDecorator(node)) doc.decorators.push({ text: node.expression.getText(source).slice(0, 1000), line: at(node) });
        if (ts.isCallExpression(node)) {
          const signature = checker.getResolvedSignature(node);
          const to = signature?.declaration?.name ? symbolId(checker.getSymbolAtLocation(signature.declaration.name)) : null;
          doc.calls.push({ from: container || `${rel}:module`, to, text: node.expression.getText(source), line: at(node) });
          if (ts.isPropertyAccessExpression(node.expression) && /^(get|post|put|delete|patch)$/.test(node.expression.name.text)) {
            const receiverType = checker.typeToString(checker.getTypeAtLocation(node.expression.expression));
            if (receiverType === 'HttpClient') doc.http.push({ method: node.expression.name.text, url: node.arguments[0]?.getText(source),
              line: at(node), basis: 'resolved HttpClient type; URL expression is not evaluated' });
          }
          if (node.expression.getText(source) === 'inject')
            doc.providers.push({ token: node.arguments[0]?.getText(source), line: at(node), basis: 'inject call' });
        }
        if (ts.isPropertyAssignment(node)) {
          const name = node.name.getText(source).replace(/^['"]|['"]$/g, '');
          if (['providers', 'providedIn', 'provide', 'useClass', 'useFactory', 'useExisting'].includes(name))
            doc.providers.push({ property: name, value: node.initializer.getText(source).slice(0, 500), line: at(node), basis: 'source metadata, not runtime registration' });
          if (['path', 'loadChildren', 'loadComponent', 'component'].includes(name))
            doc.routes.push({ property: name, value: node.initializer.getText(source), line: at(node), basis: 'source metadata, not evaluated route' });
        }
        ts.forEachChild(node, child => visit(child, container));
      }
      visit(source);
      doc.diagnostics = program.getSyntacticDiagnostics(source).concat(program.getSemanticDiagnostics(source))
        .map(d => ({ code: d.code, line: d.start === undefined ? null : source.getLineAndCharacterOfPosition(d.start).line + 1,
          message: ts.flattenDiagnosticMessageText(d.messageText, '\n') }));
      documents.push(doc);
    }
  }
  const index = { schema, root, fingerprint, tool: `TypeScript ${ts.version}`, scannedAt: new Date().toISOString(),
    frameworks: Object.keys({ ...pkg.dependencies, ...pkg.devDependencies }).filter(k => /angular|react|vue|jest|typescript/.test(k)),
    dependencies: { ...pkg.dependencies, ...pkg.devDependencies }, scripts: pkg.scripts || {},
    projects: Object.entries(angular.projects || {}).map(([name, project]) => ({ name, ...project })),
    configs: configs.map(relative), documents, diagnostics,
    dependencyInputs: [...dependencyFiles].sort().map(file => ({ path: file, hash: hash(fs.readFileSync(file)) })) };
  fs.mkdirSync(out, { recursive: true });
  const pending = `${target}.${crypto.randomUUID()}`;
  try { fs.writeFileSync(pending, JSON.stringify(index)); fs.renameSync(pending, target); }
  finally { if (fs.existsSync(pending)) fs.unlinkSync(pending); }
  const previous = new Map((prior?.root === root ? prior.documents : []).map(d => [d.path, d.hash]));
  return { index, summary: { status: 'SCANNED', elapsedMs: Math.round(performance.now() - started),
    changedDocuments: documents.filter(d => previous.get(d.path) !== d.hash).length,
    revalidatedDocuments: documents.length, removedDocuments: [...previous.keys()].filter(p => !seen.has(p)).length } };
}

function query(index, terms, max = 8) {
  const words = terms.toLowerCase().match(/[a-z0-9]+/g) || [];
  const entries = index.documents.flatMap(doc => doc.symbols.map(symbol => ({ doc, symbol })));
  const exact = entries.some(e => e.symbol.name.toLowerCase() === terms.toLowerCase());
  const candidates = entries.filter(e => !exact || e.symbol.name.toLowerCase() === terms.toLowerCase()).map(({ doc, symbol }) => ({
    id: symbol.id, name: symbol.name, kind: symbol.kind, at: `${doc.path}:${symbol.line}`, bases: symbol.bases,
    score: words.filter(w => symbol.name.toLowerCase().includes(w)).length * 3 + words.filter(w => doc.path.toLowerCase().includes(w)).length,
    imports: doc.imports.slice(0, 8), decorators: doc.decorators.slice(0, 5), providers: doc.providers.slice(0, 5),
    routes: doc.routes.slice(0, 5), http: doc.http.slice(0, 5), diagnostics: doc.diagnostics.slice(0, 5),
    callers: index.documents.flatMap(d => d.calls.filter(c => c.to === symbol.id).map(c => ({ ...c, at: `${d.path}:${c.line}` }))).slice(0, 8)
  })).filter(c => c.score > 0).sort((a, b) => b.score - a.score || a.at.localeCompare(b.at)).slice(0, Math.min(8, Math.max(1, max)));
  return { status: 'ARCHITECTURE', analysis: 'typescript-semantic', candidates, coverage: { documents: index.documents.length,
    diagnostics: index.documents.reduce((n, d) => n + d.diagnostics.length, index.diagnostics.length) },
    limitations: ['Angular templates are not compiled', 'Dynamic routes and provider factories are source evidence only',
      'Changed input revalidates all programs to prevent stale cross-file edges; compiler watch reuse is not implemented',
      'Cross-repository HTTP links require contract evidence; matching names alone are candidates'] };
}

if (require.main === module) {
  try {
    const command = process.argv[2];
    const args = {};
    for (let i = 3; i < process.argv.length; i += 2) args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
    if (!['scan', 'query'].includes(command) || !args.root || !args.out) throw new Error('scan|query --root <workspace> --out <cache> [--terms <requirement>]');
    const { index, summary } = scan(args.root, args.out);
    const result = command === 'query' ? { ...query(index, args.terms || '', Number(args.max) || 8), scan: summary } :
      { ...summary, analysis: 'typescript-semantic', projects: index.projects, configs: index.configs, frameworks: index.frameworks,
        coverage: { documents: index.documents.length, diagnostics: index.documents.reduce((n, d) => n + d.diagnostics.length, index.diagnostics.length) } };
    process.stdout.write(JSON.stringify(result));
  } catch (error) {
    process.stdout.write(JSON.stringify({ status: 'UNAVAILABLE', analysis: 'typescript', error: error.message }));
    process.exitCode = 1;
  }
}
module.exports = { scan, query };
