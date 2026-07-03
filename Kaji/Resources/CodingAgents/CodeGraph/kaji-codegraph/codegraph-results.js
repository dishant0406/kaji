function tool(name, description, properties = {}, required = []) {
  return {
    name,
    description,
    inputSchema: { type: 'object', properties, required, additionalProperties: false }
  };
}

function textResult(text, details) {
  const content = [{ type: 'text', text }];
  if (details !== undefined) content.push({ type: 'text', text: JSON.stringify(details, null, 2) });
  return { content };
}

function jsonResult(value) {
  return { content: [{ type: 'text', text: JSON.stringify(value, null, 2) }] };
}

function errorResult(code, message, recovery, details = {}) {
  return {
    isError: true,
    content: [{ type: 'text', text: JSON.stringify({ code, message, recovery, ...details }, null, 2) }]
  };
}

module.exports = { tool, textResult, jsonResult, errorResult };
