function textResult(value) {
  return { content: [{ type: 'text', text: typeof value === 'string' ? value : JSON.stringify(value, null, 2) }] };
}

function imageResult(value) {
  if (!value || !value.imageBase64) return textResult(value);
  const summary = { ...value };
  delete summary.imageBase64;
  return {
    content: [
      { type: 'text', text: JSON.stringify(summary, null, 2) },
      { type: 'image', data: value.imageBase64, mimeType: value.mimeType || 'image/png' }
    ]
  };
}

function tool(name, description, properties = {}, required = []) {
  return { name, description, inputSchema: { type: 'object', properties, required, additionalProperties: false } };
}

module.exports = { imageResult, textResult, tool };
