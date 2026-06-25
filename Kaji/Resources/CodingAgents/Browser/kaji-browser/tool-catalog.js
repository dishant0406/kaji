const { tool } = require('./results');

const availabilityTools = [
  tool('kaji_browser_accessible', 'Check whether Kaji Browser is reachable before using browser tools.'),
  tool('kaji_browser_status', 'Return Kaji embedded WebKit browser broker status.'),
  tool('kaji_browser_session', 'Return the Kaji WebKit browser session values known to this MCP wrapper.')
];

const nativeTools = [
  tool('kaji_browser_open_panel', 'Open the Kaji Browser side panel for the active workspace.'),
  tool('kaji_browser_close_panel', 'Close the Kaji Browser side panel for the active workspace.'),
  tool('kaji_browser_current', 'Return the active Kaji browser tab and tab list.'),
  tool('kaji_browser_navigate', 'Navigate the active Kaji browser tab.', { url: stringSchema('URL or search query') }, ['url']),
  tool('kaji_browser_new_tab', 'Open a new Kaji browser tab.', { url: stringSchema('Optional URL or search query') }),
  tool('kaji_browser_back', 'Go back in the active Kaji browser tab.'),
  tool('kaji_browser_forward', 'Go forward in the active Kaji browser tab.'),
  tool('kaji_browser_reload', 'Reload the active Kaji browser tab.'),
  tool('kaji_browser_close', 'Close the active Kaji browser tab.', { index: numberSchema('Optional tab index') }),
  tool('kaji_browser_tabs', 'List, create, close, or select Kaji browser tabs.', { action: stringSchema('list, new, close, or select'), index: numberSchema('Tab index'), id: stringSchema('Tab id'), url: stringSchema('Optional URL for new tab') }, ['action']),
  tool('kaji_browser_resize', 'Resize the active Kaji browser viewport.', { width: numberSchema('Width in pixels'), height: numberSchema('Height in pixels') }, ['width', 'height']),
  tool('kaji_browser_read_page', 'Read text and metadata from the active Kaji browser tab.'),
  tool('kaji_browser_screenshot', 'Capture a visible PNG screenshot of the active Kaji browser tab.', screenshotSchema()),
  tool('kaji_browser_eval', 'Evaluate JavaScript in the active Kaji browser tab.', { script: stringSchema('JavaScript expression or IIFE') }, ['script']),
  tool('kaji_browser_snapshot', 'Return interactive element refs and selectors from the active Kaji browser tab.', { target: stringSchema('Optional element target'), depth: numberSchema('Tree depth'), boxes: boolSchema('Include bounding boxes') }),
  tool('kaji_browser_click', 'Click an element by selector, target ref, or point.', targetSchema({ button: stringSchema('left, right, or middle'), doubleClick: boolSchema('Double click'), x: numberSchema('X coordinate'), y: numberSchema('Y coordinate') })),
  tool('kaji_browser_hover', 'Hover an element by selector or target ref.', targetSchema()),
  tool('kaji_browser_drag', 'Drag between two snapshot targets.', { startTarget: stringSchema('Source target'), startSelector: stringSchema('Source selector'), endTarget: stringSchema('Drop target'), endSelector: stringSchema('Drop selector') }),
  tool('kaji_browser_fill', 'Fill an input, textarea, select-like field, or contenteditable by selector or target.', targetSchema({ text: stringSchema('Text to enter') }), ['text']),
  tool('kaji_browser_fill_form', 'Fill multiple form fields by target or selector.', { fields: arraySchema('Fields to fill') }, ['fields']),
  tool('kaji_browser_type', 'Type text into a field by selector or target.', targetSchema({ text: stringSchema('Text to type'), submit: boolSchema('Press Enter after typing'), slowly: boolSchema('Type key by key') }), ['text']),
  tool('kaji_browser_press_key', 'Press a keyboard key in the active page.', { key: stringSchema('Key name, such as Enter or Meta+A') }, ['key']),
  tool('kaji_browser_select_option', 'Select option values in a dropdown.', targetSchema({ values: arraySchema('Option values') }), ['values']),
  tool('kaji_browser_wait', 'Wait for text, text disappearance, element, or time.', waitSchema()),
  tool('kaji_browser_get_text', 'Read text from an element by CSS selector.', { selector: stringSchema('CSS selector') }),
  tool('kaji_browser_get_html', 'Read outer HTML from an element by CSS selector.', { selector: stringSchema('CSS selector') }),
  tool('kaji_browser_storage_get', 'Read localStorage or sessionStorage.', { type: stringSchema('local or session'), key: stringSchema('Optional storage key') }),
  tool('kaji_browser_console_messages', 'Return console messages captured by the native WebKit bridge.', { level: stringSchema('error, warning, info, debug, or log'), all: boolSchema('Return all messages since page load') }),
  tool('kaji_browser_network_requests', 'Return requests observed by the WebKit bridge.', { static: boolSchema('Include static resources when observable'), filter: stringSchema('URL regexp filter') }),
  tool('kaji_browser_network_request', 'Return one observed network request.', { number: numberSchema('Request number'), part: stringSchema('Optional response part') }, ['number']),
  tool('kaji_browser_handle_dialog', 'Handle the pending JavaScript dialog.', { accept: boolSchema('Accept the dialog'), promptText: stringSchema('Prompt text') }, ['accept']),
  tool('kaji_browser_file_upload', 'Upload project files into a file input.', targetSchema({ paths: arraySchema('File paths') }), ['paths']),
  tool('kaji_browser_drop', 'Drop MIME data onto an element.', targetSchema({ data: arraySchema('MIME data') }))
];

function targetSchema(extra = {}) {
  return { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), ref: stringSchema('Snapshot target'), selector: stringSchema('CSS selector'), ...extra };
}

function screenshotSchema() {
  return { filename: stringSchema('Output filename'), fullPage: boolSchema('Capture full page'), type: stringSchema('png or jpeg'), element: stringSchema('Element description'), target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector') };
}

function waitSchema() {
  return { text: stringSchema('Text to wait for'), textGone: stringSchema('Text to disappear'), time: numberSchema('Seconds to wait'), target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector'), timeoutMs: numberSchema('Timeout milliseconds') };
}

function stringSchema(description) {
  return { type: 'string', description };
}

function numberSchema(description) {
  return { type: 'number', description };
}

function boolSchema(description) {
  return { type: 'boolean', description };
}

function arraySchema(description) {
  return { type: 'array', description, items: {} };
}

module.exports = { availabilityTools, nativeTools };
