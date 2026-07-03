const store = require('./graph-store');
const query = require('./graph-query');
const { jsonResult, textResult, errorResult } = require('./codegraph-results');
const { tools } = require('./codegraph-tool-catalog');

function list() {
  return tools;
}

function call(name, args = {}) {
  if (name === 'code_graph_projects') return jsonResult({ root: store.rootDirectory(), projects: store.projectSummaries() });
  if (name === 'code_graph_status') return status(args);
  const resolved = selected(args);
  if (resolved.error) return resolved.error;
  if (name === 'code_graph_report') return report(resolved.record, args);
  if (name === 'code_graph_search') return search(resolved.record, args);
  if (name === 'code_graph_neighbors') return neighbors(resolved.record, args);
  if (name === 'code_graph_path') return pathResult(resolved.record, args);
  if (name === 'code_graph_hotspots') return hotspots(resolved.record, args);
  return null;
}

function status(args) {
  const resolved = store.resolveRecord(args);
  if (!resolved.record) {
    return jsonResult({ ready: false, root: store.rootDirectory(), requestedPath: resolved.requestedPath || null, projects: projectHints(resolved.records) });
  }
  return jsonResult({ ready: true, ...summary(resolved.record) });
}

function report(record, args) {
  const maxLines = boundedNumber(args.max_lines || args.maxLines, 160, 20, 1000);
  const body = store.readReport(record, maxLines);
  if (!body) return errorResult('report_missing', 'GRAPH_REPORT.md is missing for this CodeGraph.', 'Regenerate the CodeGraph from Kaji.');
  return textResult(body, summary(record));
}

function search(record, args) {
  const term = trim(args.query);
  if (!term) return errorResult('query_required', 'query is required.', 'Pass a symbol, file, or architectural term.');
  const nodes = query.search(record.graph, term, boundedNumber(args.limit, 20, 1, 100));
  return jsonResult({ query: term, projectPath: projectPath(record), nodes });
}

function neighbors(record, args) {
  const result = query.neighbors(record.graph, selector(args), boundedNumber(args.limit, 40, 1, 200));
  if (!result) return errorResult('node_not_found', 'No matching graph node was found.', 'Pass id, label, or path from code_graph_search.');
  return jsonResult({ projectPath: projectPath(record), ...result });
}

function pathResult(record, args) {
  const from = selector(args, 'from_');
  const to = selector(args, 'to_');
  if (!hasSelector(from) || !hasSelector(to)) {
    return errorResult('selectors_required', 'from_* and to_* selectors are required.', 'Pass node ids or labels from code_graph_search.');
  }
  const result = query.shortestPath(record.graph, from, to, boundedNumber(args.max_depth || args.maxDepth, 4, 1, 12));
  if (!result) return errorResult('node_not_found', 'No matching source or target node was found.', 'Search both endpoints before asking for a path.');
  return jsonResult({ projectPath: projectPath(record), ...result });
}

function hotspots(record, args) {
  return jsonResult({ projectPath: projectPath(record), nodes: query.hotspots(record.graph, boundedNumber(args.limit, 20, 1, 100)) });
}

function selected(args) {
  const resolved = store.resolveRecord(args);
  if (resolved.record) return { record: resolved.record };
  return { error: errorResult('graph_missing', 'No matching Kaji CodeGraph was found.', 'Generate a graph from Kaji or pass project_path.', { projects: projectHints(resolved.records) }) };
}

function selector(args, prefix = '') {
  return { id: args[`${prefix}id`] || args[camel(prefix, 'id')], label: args[`${prefix}label`] || args[camel(prefix, 'label')], path: args[`${prefix}path`] || args[camel(prefix, 'path')] };
}

function camel(prefix, suffix) {
  if (!prefix) return suffix;
  return prefix.replace(/_$/, '') + suffix[0].toUpperCase() + suffix.slice(1);
}

function summary(record) {
  return { projectPath: projectPath(record), graphPath: record.graphPath, reportPath: record.reportPath, nodes: count(record.graph.nodes), edges: count(record.graph.edges), communities: count(record.graph.communities), builtAt: record.graph.builtAt || record.graph.versionBuiltAt || null, git: record.graph.git || null };
}

function projectHints(records) {
  return (records || []).map(summary);
}

function boundedNumber(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(number)));
}

function count(value) {
  return Array.isArray(value) ? value.length : 0;
}

function projectPath(record) {
  if (!record.graph) return '';
  return record.graph.projectPath || record.graph.project_path || '';
}

function hasSelector(value) {
  return trim(value.id) || trim(value.label) || trim(value.path);
}

function trim(value) {
  return typeof value === 'string' ? value.trim() : '';
}

module.exports = { list, call };
