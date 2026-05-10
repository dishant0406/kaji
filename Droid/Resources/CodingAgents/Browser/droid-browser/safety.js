const blocked = new Set(['browser_run_code_unsafe', 'browser_file_upload', 'browser_drop']);

function isAllowed(name) {
  return process.env.DROID_BROWSER_ALLOW_UNSAFE_TOOLS === '1' || !blocked.has(name);
}

function filterTools(tools) {
  return tools.filter(tool => isAllowed(tool.name));
}

module.exports = { filterTools, isAllowed };
