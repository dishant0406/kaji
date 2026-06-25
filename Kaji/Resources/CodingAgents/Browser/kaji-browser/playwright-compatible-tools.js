const { tool } = require('./results');

const tools = [
  tool('browser_close', 'Close the current Kaji WebKit browser page.', { index: numberSchema('Optional tab index') }),
  tool('browser_resize', 'Resize the active Kaji WebKit browser viewport.', { width: numberSchema('Width in pixels'), height: numberSchema('Height in pixels') }, ['width', 'height']),
  tool('browser_console_messages', 'Return console messages captured by the native WebKit bridge.', { level: stringSchema('error, warning, info, debug, or log'), all: boolSchema('Return all messages since page load') }),
  tool('browser_handle_dialog', 'Handle the pending JavaScript dialog.', { accept: boolSchema('Accept the dialog'), promptText: stringSchema('Prompt text') }, ['accept']),
  tool('browser_evaluate', 'Evaluate JavaScript in the active Kaji WebKit page.', { function: stringSchema('JavaScript expression or function'), element: stringSchema('Element description'), target: stringSchema('Snapshot target') }, ['function']),
  tool('browser_file_upload', 'Upload one or multiple project files into a file input.', { target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector'), paths: arraySchema('File paths') }, ['paths']),
  tool('browser_drop', 'Drop MIME data onto an element.', { target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector'), data: arraySchema('MIME data') }),
  tool('browser_fill_form', 'Fill multiple form fields by snapshot target or selector.', { fields: arraySchema('Fields to fill') }, ['fields']),
  tool('browser_press_key', 'Press a keyboard key in the active page.', { key: stringSchema('Key name, such as Enter or Meta+A') }, ['key']),
  tool('browser_type', 'Type text into an editable element.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector'), text: stringSchema('Text to type'), submit: boolSchema('Press Enter after typing'), slowly: boolSchema('Type key by key') }, ['text']),
  tool('browser_navigate', 'Navigate to a URL.', { url: stringSchema('URL to navigate to') }, ['url']),
  tool('browser_navigate_back', 'Go back to the previous page in history.'),
  tool('browser_navigate_forward', 'Go forward to the next page in history.'),
  tool('browser_reload', 'Reload the current page.'),
  tool('browser_network_requests', 'Return requests observed by the WebKit bridge.', { static: boolSchema('Include static resources when observable'), filter: stringSchema('URL regexp filter') }),
  tool('browser_network_request', 'Return one observed network request.', { number: numberSchema('Request number'), part: stringSchema('Optional response part') }, ['number']),
  tool('browser_take_screenshot', 'Take a page screenshot.', { filename: stringSchema('Output filename'), fullPage: boolSchema('Capture full page'), type: stringSchema('png or jpeg'), element: stringSchema('Element description'), target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector') }),
  tool('browser_snapshot', 'Capture a Playwright-compatible ref snapshot of the current page.', { target: stringSchema('Optional element target'), filename: stringSchema('Save snapshot to file'), depth: numberSchema('Tree depth'), boxes: boolSchema('Include bounding boxes') }),
  tool('browser_click', 'Click on the page by snapshot target, selector, or point.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector'), button: stringSchema('left, right, or middle'), doubleClick: boolSchema('Double click'), x: numberSchema('X coordinate'), y: numberSchema('Y coordinate') }),
  tool('browser_drag', 'Drag between two elements.', { startElement: stringSchema('Source element'), startTarget: stringSchema('Source target'), endElement: stringSchema('Target element'), endTarget: stringSchema('Drop target') }, ['startTarget', 'endTarget']),
  tool('browser_hover', 'Hover over an element.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector') }),
  tool('browser_select_option', 'Select option values in a dropdown.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector'), values: arraySchema('Option values') }, ['values']),
  tool('browser_tabs', 'List, create, close, or select a browser tab.', { action: stringSchema('list, new, close, or select'), index: numberSchema('Tab index'), id: stringSchema('Tab id'), url: stringSchema('Optional URL for new tab') }, ['action']),
  tool('browser_wait_for', 'Wait for text, text disappearance, element, or time.', { text: stringSchema('Text to wait for'), textGone: stringSchema('Text to disappear'), time: numberSchema('Seconds to wait'), target: stringSchema('Snapshot target'), selector: stringSchema('CSS selector'), timeoutMs: numberSchema('Timeout milliseconds') })
];

const actionNames = {
  browser_close: 'close',
  browser_resize: 'resize',
  browser_console_messages: 'console_messages',
  browser_handle_dialog: 'handle_dialog',
  browser_evaluate: 'eval',
  browser_file_upload: 'file_upload',
  browser_drop: 'drop',
  browser_fill_form: 'fill_form',
  browser_press_key: 'press_key',
  browser_type: 'type',
  browser_navigate: 'navigate',
  browser_navigate_back: 'back',
  browser_navigate_forward: 'forward',
  browser_reload: 'reload',
  browser_network_requests: 'network_requests',
  browser_network_request: 'network_request',
  browser_take_screenshot: 'screenshot',
  browser_snapshot: 'snapshot',
  browser_click: 'click',
  browser_drag: 'drag',
  browser_hover: 'hover',
  browser_select_option: 'select_option',
  browser_tabs: 'tabs',
  browser_wait_for: 'wait'
};

function actionName(name) {
  return actionNames[name];
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

module.exports = { actionName, tools };
