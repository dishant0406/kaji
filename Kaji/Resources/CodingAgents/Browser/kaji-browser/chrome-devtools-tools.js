const { tool } = require('./results');

const toolMap = new Map([
  ['browser_close', 'close_page'],
  ['browser_resize', 'resize_page'],
  ['browser_console_messages', 'list_console_messages'],
  ['browser_handle_dialog', 'handle_dialog'],
  ['browser_evaluate', 'evaluate_script'],
  ['browser_fill_form', 'fill_form'],
  ['browser_reload', 'navigate_page'],
  ['browser_press_key', 'press_key'],
  ['browser_type', 'type_text'],
  ['browser_navigate', 'navigate_page'],
  ['browser_navigate_back', 'navigate_page_history'],
  ['browser_navigate_forward', 'navigate_page_history'],
  ['browser_network_requests', 'list_network_requests'],
  ['browser_network_request', 'get_network_request'],
  ['browser_take_screenshot', 'take_screenshot'],
  ['browser_snapshot', 'take_snapshot'],
  ['browser_click', 'click'],
  ['browser_drag', 'drag'],
  ['browser_hover', 'hover'],
  ['browser_tabs', 'tabs'],
  ['browser_wait_for', 'wait_for']
]);

const tools = [
  tool('browser_close', 'Close the current page through Chrome DevTools MCP.'),
  tool('browser_resize', 'Resize the browser window through Chrome DevTools MCP.', { width: numberSchema('Width in pixels'), height: numberSchema('Height in pixels') }, ['width', 'height']),
  tool('browser_console_messages', 'Return console messages through Chrome DevTools MCP.', { level: stringSchema('error, warning, info, or debug'), all: boolSchema('Return all messages since session start') }),
  tool('browser_handle_dialog', 'Handle a browser dialog through Chrome DevTools MCP.', { accept: boolSchema('Accept dialog'), promptText: stringSchema('Prompt text') }, ['accept']),
  tool('browser_evaluate', 'Evaluate JavaScript on the current page through Chrome DevTools MCP.', { function: stringSchema('JavaScript function or expression'), element: stringSchema('Element description'), target: stringSchema('Snapshot target') }, ['function']),
  tool('browser_fill_form', 'Fill multiple form fields through Chrome DevTools MCP.', { fields: arraySchema('Fields to fill') }, ['fields']),
  tool('browser_reload', 'Reload the current page through Chrome DevTools MCP.'),
  tool('browser_press_key', 'Press a keyboard key through Chrome DevTools MCP.', { key: stringSchema('Key name, such as Enter or ArrowLeft') }, ['key']),
  tool('browser_type', 'Type text through Chrome DevTools MCP.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), text: stringSchema('Text to type'), submit: boolSchema('Press Enter after typing'), slowly: boolSchema('Type key by key') }, ['text']),
  tool('browser_navigate', 'Navigate to a URL through Chrome DevTools MCP.', { url: stringSchema('URL to navigate to') }, ['url']),
  tool('browser_navigate_back', 'Go back through Chrome DevTools MCP.'),
  tool('browser_navigate_forward', 'Go forward through Chrome DevTools MCP.'),
  tool('browser_network_requests', 'Return network requests through Chrome DevTools MCP.', { static: boolSchema('Include static resources'), filter: stringSchema('URL regexp filter') }),
  tool('browser_network_request', 'Return one network request through Chrome DevTools MCP.', { number: numberSchema('Request number'), part: stringSchema('Optional part') }, ['number']),
  tool('browser_take_screenshot', 'Take a screenshot through Chrome DevTools MCP.', { filename: stringSchema('Output filename'), fullPage: boolSchema('Capture full page'), type: stringSchema('png or jpeg'), element: stringSchema('Element description'), target: stringSchema('Snapshot target') }),
  tool('browser_snapshot', 'Capture a page snapshot through Chrome DevTools MCP.', { target: stringSchema('Optional element target'), filename: stringSchema('Save snapshot to file'), depth: numberSchema('Tree depth'), boxes: boolSchema('Include bounding boxes') }),
  tool('browser_click', 'Click on the page through Chrome DevTools MCP.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), button: stringSchema('left, right, or middle'), doubleClick: boolSchema('Double click'), x: numberSchema('X coordinate'), y: numberSchema('Y coordinate') }),
  tool('browser_drag', 'Drag between two elements through Chrome DevTools MCP.', { startElement: stringSchema('Source element'), startTarget: stringSchema('Source target'), endElement: stringSchema('Target element'), endTarget: stringSchema('Drop target') }, ['startTarget', 'endTarget']),
  tool('browser_hover', 'Hover over an element through Chrome DevTools MCP.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target') }),
  tool('browser_tabs', 'List, create, close, or select a browser tab through Chrome DevTools MCP.', { action: stringSchema('list, new, close, or select'), index: numberSchema('Tab index'), url: stringSchema('Optional URL for new tab') }, ['action']),
  tool('browser_wait_for', 'Wait for text or time through Chrome DevTools MCP.', { text: stringSchema('Text to wait for'), textGone: stringSchema('Text to disappear'), time: numberSchema('Seconds to wait') })
];

function providerToolName(name) {
  return toolMap.get(name) || '';
}

function stringSchema(description) { return { type: 'string', description }; }
function numberSchema(description) { return { type: 'number', description }; }
function boolSchema(description) { return { type: 'boolean', description }; }
function arraySchema(description) { return { type: 'array', description, items: {} }; }

module.exports = { providerToolName, tools };
