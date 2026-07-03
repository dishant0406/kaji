function search(graph, query, limit) {
  const terms = normalizeTerms(query);
  return nodes(graph).map(node => ({ node, score: scoreNode(node, terms) }))
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score || degree(b.node) - degree(a.node))
    .slice(0, limit)
    .map(item => item.node);
}

function neighbors(graph, selector, limit) {
  const node = findNode(graph, selector);
  if (!node) return null;
  const items = edges(graph).filter(edge => edge.source === node.id || edge.target === node.id).slice(0, limit);
  const byID = nodeMap(graph);
  return { node, edges: items.map(edge => ({ edge, source: byID.get(edge.source), target: byID.get(edge.target) })) };
}

function shortestPath(graph, from, to, maxDepth) {
  const source = findNode(graph, from);
  const target = findNode(graph, to);
  if (!source || !target) return null;
  const byID = nodeMap(graph);
  const adjacency = buildAdjacency(graph);
  const queue = [{ id: source.id, path: [] }];
  const visited = new Set([source.id]);
  while (queue.length > 0) {
    const current = queue.shift();
    if (current.id === target.id) return { source, target, steps: current.path.map(step => ({ edge: step.edge, node: byID.get(step.id) })) };
    if (current.path.length >= maxDepth) continue;
    for (const next of adjacency.get(current.id) || []) {
      if (visited.has(next.id)) continue;
      visited.add(next.id);
      queue.push({ id: next.id, path: current.path.concat(next) });
    }
  }
  return { source, target, steps: null };
}

function hotspots(graph, limit) {
  return nodes(graph).slice().sort((a, b) => degree(b) - degree(a)).slice(0, limit);
}

function findNode(graph, selector = {}) {
  const id = clean(selector.id);
  if (id) return nodes(graph).find(node => node.id === id) || null;
  const path = clean(selector.path);
  const label = clean(selector.label);
  if (path) return nodes(graph).find(node => clean(nodePath(node)) === path) || null;
  if (!label) return null;
  return search(graph, label, 1)[0] || null;
}

function buildAdjacency(graph) {
  const adjacency = new Map();
  for (const edge of edges(graph)) {
    add(adjacency, edge.source, edge.target, edge);
    add(adjacency, edge.target, edge.source, edge);
  }
  return adjacency;
}

function add(adjacency, source, target, edge) {
  if (!source || !target) return;
  if (!adjacency.has(source)) adjacency.set(source, []);
  adjacency.get(source).push({ id: target, edge });
}

function nodeMap(graph) {
  return new Map(nodes(graph).map(node => [node.id, node]));
}

function scoreNode(node, terms) {
  const haystack = [node.id, node.label, nodePath(node), nodeType(node)].join(' ').toLowerCase();
  return terms.reduce((sum, term) => sum + (haystack.includes(term) ? term.length : 0), 0);
}

function normalizeTerms(query) {
  return clean(query).toLowerCase().split(/[^a-z0-9_./-]+/).filter(term => term.length > 1);
}

function nodes(graph) {
  return Array.isArray(graph.nodes) ? graph.nodes : [];
}

function edges(graph) {
  return Array.isArray(graph.edges) ? graph.edges : [];
}

function degree(node) {
  return Number(node && node.degree) || 0;
}

function nodePath(node) {
  return node && (node.source_file || node.sourceFile) || '';
}

function nodeType(node) {
  return node && (node.file_type || node.fileType) || '';
}

function clean(value) {
  return typeof value === 'string' ? value.trim() : '';
}

module.exports = { search, neighbors, shortestPath, hotspots, findNode };
