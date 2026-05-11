const { tool } = require('./results');

const tools = [
  tool('browser_close', 'Close the page.'),
  tool('browser_resize', 'Resize the browser window.', { width: numberSchema('Width in pixels'), height: numberSchema('Height in pixels') }, ['width', 'height']),
  tool('browser_console_messages', 'Returns all console messages.', { level: stringSchema('error, warning, info, or debug'), all: boolSchema('Return all messages since session start') }),
  tool('browser_handle_dialog', 'Handle a browser dialog.', { accept: boolSchema('Accept dialog'), promptText: stringSchema('Prompt text') }, ['accept']),
  tool('browser_evaluate', 'Evaluate JavaScript expression on page or element.', { function: stringSchema('JavaScript function to evaluate'), element: stringSchema('Element description'), target: stringSchema('Snapshot target') }, ['function']),
  tool('browser_file_upload', 'Upload one or multiple files.', { paths: arraySchema('File paths to upload') }, ['paths']),
  tool('browser_drop', 'Drop files or MIME data onto an element.', { target: stringSchema('Snapshot target'), paths: arraySchema('File paths'), data: arraySchema('MIME data') }),
  tool('browser_fill_form', 'Fill multiple form fields.', { fields: arraySchema('Fields to fill') }, ['fields']),
  tool('browser_press_key', 'Press a key on the keyboard.', { key: stringSchema('Key name, such as Enter or ArrowLeft') }, ['key']),
  tool('browser_type', 'Type text into editable element.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), text: stringSchema('Text to type'), submit: boolSchema('Press Enter after typing'), slowly: boolSchema('Type key by key') }, ['text']),
  tool('browser_navigate', 'Navigate to a URL.', { url: stringSchema('URL to navigate to') }, ['url']),
  tool('browser_navigate_back', 'Go back to the previous page in history.'),
  tool('browser_navigate_forward', 'Go forward to the next page in history.'),
  tool('browser_reload', 'Reload the current page.'),
  tool('browser_network_requests', 'Returns a numbered list of network requests.', { static: boolSchema('Include static resources'), filter: stringSchema('URL regexp filter') }),
  tool('browser_network_request', 'Returns full details of one network request.', { number: numberSchema('Request number'), part: stringSchema('Optional part') }, ['number']),
  tool('browser_take_screenshot', 'Take a screenshot of the current page.', { filename: stringSchema('Output filename'), fullPage: boolSchema('Capture full page'), type: stringSchema('png or jpeg'), element: stringSchema('Element description'), target: stringSchema('Snapshot target') }),
  tool('browser_snapshot', 'Capture accessibility snapshot of the current page.', { target: stringSchema('Optional element target'), filename: stringSchema('Save snapshot to file'), depth: numberSchema('Tree depth'), boxes: boolSchema('Include bounding boxes') }),
  tool('browser_click', 'Perform click on a web page.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), button: stringSchema('left, right, or middle'), doubleClick: boolSchema('Double click') }),
  tool('browser_drag', 'Perform drag and drop between two elements.', { startElement: stringSchema('Source element'), startTarget: stringSchema('Source target'), endElement: stringSchema('Target element'), endTarget: stringSchema('Drop target') }, ['startTarget', 'endTarget']),
  tool('browser_hover', 'Hover over element on page.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target') }),
  tool('browser_select_option', 'Select an option in a dropdown.', { element: stringSchema('Element description'), target: stringSchema('Snapshot target'), values: arraySchema('Option values') }, ['values']),
  tool('browser_tabs', 'List, create, close, or select a browser tab.', { action: stringSchema('list, new, close, or select'), index: numberSchema('Tab index') }, ['action']),
  tool('browser_wait_for', 'Wait for text to appear or disappear or a specified time to pass.', { text: stringSchema('Text to wait for'), textGone: stringSchema('Text to disappear'), time: numberSchema('Seconds to wait') })
];

function stringSchema(description) { return { type: 'string', description }; }
function numberSchema(description) { return { type: 'number', description }; }
function boolSchema(description) { return { type: 'boolean', description }; }
function arraySchema(description) { return { type: 'array', description, items: {} }; }

module.exports = { tools };
