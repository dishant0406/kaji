const { tool } = require('./codegraph-results');

const stringSchema = description => ({ type: 'string', description });
const numberSchema = description => ({ type: 'number', description });

const tools = [
  tool('code_graph_status', 'Check whether a Kaji CodeGraph exists for a project.', {
    project_path: stringSchema('Optional repository path used to select the graph')
  }),
  tool('code_graph_projects', 'List Kaji CodeGraph projects known to this machine.'),
  tool('code_graph_report', 'Read the Kaji CodeGraph GRAPH_REPORT.md for a project.', {
    project_path: stringSchema('Optional repository path used to select the graph'),
    max_lines: numberSchema('Maximum report lines, default 160')
  }),
  tool('code_graph_search', 'Search Kaji CodeGraph nodes by symbol, file, or architectural term.', {
    query: stringSchema('Symbol, file, or architectural term'),
    project_path: stringSchema('Optional repository path used to select the graph'),
    limit: numberSchema('Maximum nodes, default 20')
  }, ['query']),
  tool('code_graph_neighbors', 'Show incoming and outgoing graph edges for a node.', {
    id: stringSchema('Node id'),
    label: stringSchema('Node label'),
    path: stringSchema('Source file path'),
    project_path: stringSchema('Optional repository path used to select the graph'),
    limit: numberSchema('Maximum edges, default 40')
  }),
  tool('code_graph_path', 'Find a shortest relationship path between two graph nodes.', {
    from_id: stringSchema('Source node id'),
    from_label: stringSchema('Source node label'),
    from_path: stringSchema('Source file path'),
    to_id: stringSchema('Target node id'),
    to_label: stringSchema('Target node label'),
    to_path: stringSchema('Target file path'),
    project_path: stringSchema('Optional repository path used to select the graph'),
    max_depth: numberSchema('Maximum path depth, default 4')
  }),
  tool('code_graph_hotspots', 'List high-degree CodeGraph nodes that are likely architecture entry points.', {
    project_path: stringSchema('Optional repository path used to select the graph'),
    limit: numberSchema('Maximum nodes, default 20')
  })
];

module.exports = { tools };
