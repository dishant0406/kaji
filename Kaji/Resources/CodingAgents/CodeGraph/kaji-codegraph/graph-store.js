const fs = require('fs');
const os = require('os');
const path = require('path');

function rootDirectory() {
  return process.env.KAJI_CODE_GRAPH_ROOT_DIR || path.join(os.homedir(), '.kaji', 'extensions', 'kajicodegraph');
}

function graphRecords() {
  const root = rootDirectory();
  const projects = path.join(root, 'projects');
  if (!fs.existsSync(projects)) return [];
  const records = [];
  for (const projectID of safeReadDir(projects)) {
    const projectDir = path.join(projects, projectID);
    for (const worktreeID of safeReadDir(projectDir)) {
      const directory = path.join(projectDir, worktreeID);
      const graphPath = path.join(directory, 'graphify-out', 'kaji-graph.json');
      const reportPath = path.join(directory, 'graphify-out', 'GRAPH_REPORT.md');
      if (!fs.existsSync(graphPath)) continue;
      const graph = readJSON(graphPath);
      records.push({ projectID, worktreeID, directory, graphPath, reportPath, graph });
    }
  }
  return records.sort((a, b) => projectPath(a).localeCompare(projectPath(b)));
}

function resolveRecord(args = {}) {
  const requestedPath = normalizePath(args.project_path || args.projectPath || process.env.KAJI_WORKTREE_PATH || process.cwd());
  const records = graphRecords();
  if (records.length === 0) return { records };
  let best = null;
  for (const record of records) {
    const candidate = normalizePath(projectPath(record));
    if (!candidate) continue;
    if (requestedPath === candidate || requestedPath.startsWith(`${candidate}${path.sep}`)) {
      if (!best || candidate.length > normalizePath(projectPath(best)).length) best = record;
    }
  }
  if (best) return { record: best, records };
  if (records.length === 1) return { record: records[0], records };
  return { records, requestedPath };
}

function readReport(record, maxLines) {
  if (!fs.existsSync(record.reportPath)) return null;
  return fs.readFileSync(record.reportPath, 'utf8').split(/\r?\n/).slice(0, maxLines).join('\n');
}

function projectSummaries() {
  return graphRecords().map(record => ({
    projectPath: projectPath(record),
    graphPath: record.graphPath,
    reportPath: record.reportPath,
    nodes: Array.isArray(record.graph.nodes) ? record.graph.nodes.length : 0,
    edges: Array.isArray(record.graph.edges) ? record.graph.edges.length : 0,
    communities: Array.isArray(record.graph.communities) ? record.graph.communities.length : 0,
    builtAt: record.graph.builtAt || record.graph.versionBuiltAt || null,
    git: record.graph.git || null
  }));
}

function safeReadDir(directory) {
  try { return fs.readdirSync(directory); } catch (_) { return []; }
}

function readJSON(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return {}; }
}

function normalizePath(value) {
  if (!value || typeof value !== 'string') return '';
  return path.resolve(value).replace(/[\/]+$/, '');
}

function projectPath(record) {
  if (!record.graph) return '';
  return record.graph.projectPath || record.graph.project_path || '';
}

module.exports = { rootDirectory, resolveRecord, projectSummaries, readReport };
