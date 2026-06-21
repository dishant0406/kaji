import './style.css';
import * as monaco from 'monaco-editor';
import EditorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker';
import JsonWorker from 'monaco-editor/esm/vs/language/json/json.worker?worker';
import CssWorker from 'monaco-editor/esm/vs/language/css/css.worker?worker';
import HtmlWorker from 'monaco-editor/esm/vs/language/html/html.worker?worker';
import TsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker';

type BridgeMessage = {
  type: string;
  editorID: string;
  payload?: unknown;
};

type KajiCommand = {
  command: string;
  editorID: string;
  payload?: Record<string, unknown>;
};

type BridgeHost = {
  messageHandlers?: {
    kajiMonaco?: {
      postMessage: (message: BridgeMessage) => void;
    };
  };
};

type ModelEdit = {
  range: {
    startLineNumber: number;
    startColumn: number;
    endLineNumber: number;
    endColumn: number;
  };
  text: string;
};

type SearchMatch = {
  range: monaco.Range;
};

declare global {
  interface Window {
    webkit?: BridgeHost;
    MonacoEnvironment?: monaco.Environment;
    kajiMonacoReceive?: (command: KajiCommand) => void;
  }
}

window.MonacoEnvironment = {
  getWorker(_workerId: string, label: string) {
    if (label === 'json') return new JsonWorker();
    if (label === 'css' || label === 'scss' || label === 'less') return new CssWorker();
    if (label === 'html' || label === 'handlebars' || label === 'razor') return new HtmlWorker();
    if (label === 'typescript' || label === 'javascript') return new TsWorker();
    return new EditorWorker();
  }
};

const container = document.getElementById('editor');
if (!container) throw new Error('Missing editor container');

let editorID = new URLSearchParams(window.location.search).get('editorID') ?? 'default';
let model: monaco.editor.ITextModel | null = null;
const viewStates = new Map<string, monaco.editor.ICodeEditorViewState | null>();
let suppressChange = false;
let currentSearchNeedle = '';
let currentSearchCaseSensitive = false;
let currentSearchRegex = false;
let searchMatches: SearchMatch[] = [];
let currentSearchIndex = -1;
const editor = monaco.editor.create(container, {
  automaticLayout: true,
  minimap: { enabled: false },
  scrollBeyondLastLine: false,
  renderLineHighlight: 'line',
  fixedOverflowWidgets: true,
  wordBasedSuggestions: 'off',
  padding: { top: 4, bottom: 4 },
  scrollbar: {
    vertical: 'visible',
    horizontal: 'visible',
    useShadows: false
  }
});

function post(type: string, payload?: unknown) {
  window.webkit?.messageHandlers?.kajiMonaco?.postMessage({ type, editorID, payload });
}

function currentModel() {
  const value = editor.getModel();
  if (!value) throw new Error('No editor model is loaded');
  return value;
}

function saveCurrentViewState() {
  if (!model) return;
  viewStates.set(model.uri.toString(), editor.saveViewState());
}

function restoreViewState(uri: monaco.Uri) {
  const state = viewStates.get(uri.toString());
  if (state) editor.restoreViewState(state);
}

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function asNumber(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function asBoolean(value: unknown, fallback = false): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function commandPayload(command: KajiCommand): Record<string, unknown> {
  return command.payload ?? {};
}

function bindEditor(command: KajiCommand) {
  saveCurrentViewState();
  const payload = commandPayload(command);
  editorID = asString(payload.editorID, command.editorID || editorID);
  currentSearchNeedle = '';
  currentSearchCaseSensitive = false;
  currentSearchRegex = false;
  searchMatches = [];
  currentSearchIndex = -1;
  post('ready', { userAgent: navigator.userAgent, preloaded: true });
}

function setModel(payload: Record<string, unknown>) {
  const uri = monaco.Uri.parse(asString(payload.uri, `kaji://editor/${editorID}`));
  const uriString = uri.toString();
  const language = asString(payload.language, 'plaintext');
  const text = asString(payload.text);
  const readOnly = asBoolean(payload.readOnly);
  const backingStoreVersion = asNumber(payload.backingStoreVersion, -1);
  const existing = monaco.editor.getModel(uri);
  saveCurrentViewState();
  suppressChange = true;
  try {
    model = existing ?? monaco.editor.createModel(text, language, uri);
    if (existing && existing.getValue() !== text) existing.setValue(text);
    monaco.editor.setModelLanguage(model, language);
    editor.setModel(model);
    restoreViewState(uri);
    editor.updateOptions({ readOnly });
    const activeEditorID = editorID;
    const activeModel = model;
    setTimeout(() => {
      if (editorID !== activeEditorID || model !== activeModel) return;
      post('modelActivated', { uri: uriString, backingStoreVersion });
      postSearchState();
      postDiagnostics();
    }, 0);
  } finally {
    suppressChange = false;
  }
}

function appendText(payload: Record<string, unknown>) {
  const text = asString(payload.text);
  if (text.length === 0) return;
  const loaded = currentModel();
  const lastLine = loaded.getLineCount();
  const lastColumn = loaded.getLineMaxColumn(lastLine);
  suppressChange = true;
  try {
    editor.executeEdits('kaji-append', [{ range: new monaco.Range(lastLine, lastColumn, lastLine, lastColumn), text }]);
  } finally {
    suppressChange = false;
  }
}

function applyEdit(payload: Record<string, unknown>) {
  const rangePayload = payload.range as Record<string, unknown> | undefined;
  if (!rangePayload) return;
  const range = new monaco.Range(
    asNumber(rangePayload.startLineNumber, 1),
    asNumber(rangePayload.startColumn, 1),
    asNumber(rangePayload.endLineNumber, 1),
    asNumber(rangePayload.endColumn, 1)
  );
  editor.executeEdits('kaji-apply-edit', [{ range, text: asString(payload.text), forceMoveMarkers: true }]);
}

function applyInlineEdit(payload: Record<string, unknown>) {
  const selection = editor.getSelection();
  const text = asString(payload.text);
  if (!selection || selection.isEmpty()) {
    const position = editor.getPosition() ?? { lineNumber: 1, column: 1 };
    const range = new monaco.Range(position.lineNumber, position.column, position.lineNumber, position.column);
    editor.executeEdits('kaji-inline-edit', [{ range, text, forceMoveMarkers: true }]);
    return;
  }
  editor.executeEdits('kaji-inline-edit', [{ range: selection, text, forceMoveMarkers: true }]);
}

function updateOptions(payload: Record<string, unknown>) {
  editor.updateOptions({
    lineNumbers: asBoolean(payload.showsLineNumbers, true) ? 'on' : 'off',
    renderLineHighlight: asBoolean(payload.highlightsActiveLine, true) ? 'line' : 'none',
    renderWhitespace: asBoolean(payload.rendersWhitespace, false) ? 'all' : 'none',
    matchBrackets: asBoolean(payload.highlightsMatchingBrackets, true) ? 'always' : 'never',
    wordWrap: asBoolean(payload.wordWrapEnabled, false) ? 'on' : 'off',
    autoClosingBrackets: asBoolean(payload.autoClosesPairs, true) ? 'always' : 'never',
    autoClosingQuotes: asBoolean(payload.autoClosesPairs, true) ? 'always' : 'never',
    autoIndent: asBoolean(payload.autoIndentsNewLines, true) ? 'advanced' : 'none',
    tabSize: asNumber(payload.tabSize, 4),
    insertSpaces: true,
    guides: { indentation: asBoolean(payload.showsIndentGuides, true) },
    fontFamily: asString(payload.fontFamily, 'SF Mono'),
    fontSize: asNumber(payload.fontSize, 15),
    lineHeight: asNumber(payload.lineHeight, 21)
  });
}

function quickOutline() {
  editor.trigger('kaji', 'editor.action.quickOutline', {});
}

function postDiagnostics() {
  if (!model) return;
  const markers = monaco.editor.getModelMarkers({ resource: model.uri }).map((marker) => ({
    startLineNumber: marker.startLineNumber,
    startColumn: marker.startColumn,
    endLineNumber: marker.endLineNumber,
    endColumn: marker.endColumn,
    severity: marker.severity,
    message: marker.message,
    source: marker.source
  }));
  post('diagnosticsChanged', { diagnostics: markers });
}

function setTheme(payload: Record<string, unknown>) {
  const name = asString(payload.name, 'kaji-editor-theme');
  const base = asString(payload.base, 'vs-dark') === 'vs' ? 'vs' : 'vs-dark';
  const colors = typeof payload.colors === 'object' && payload.colors ? payload.colors as Record<string, string> : {};
  monaco.editor.defineTheme(name, { base, inherit: true, colors, rules: [] });
  monaco.editor.setTheme(name);
}

function revealLine(payload: Record<string, unknown>) {
  const line = Math.max(1, Math.floor(asNumber(payload.line, 1)));
  const column = Math.max(1, Math.floor(asNumber(payload.column, 1)));
  const position = { lineNumber: line, column };
  editor.setPosition(position);
  editor.revealPositionInCenter(position, monaco.editor.ScrollType.Smooth);
}

function setScrollTop(payload: Record<string, unknown>) {
  editor.setScrollTop(Math.max(0, asNumber(payload.scrollTop)));
}

function find(payload: Record<string, unknown>) {
  currentSearchNeedle = asString(payload.needle);
  currentSearchCaseSensitive = asBoolean(payload.caseSensitive);
  currentSearchRegex = asBoolean(payload.regex);
  refreshSearchMatches();
  if (searchMatches.length === 0) {
    currentSearchIndex = -1;
    postSearchState();
    return;
  }
  const direction = asString(payload.direction, 'next');
  currentSearchIndex = direction === 'previous'
    ? (currentSearchIndex <= 0 ? searchMatches.length - 1 : currentSearchIndex - 1)
    : (currentSearchIndex + 1) % searchMatches.length;
  revealSearchMatch();
  postSearchState();
}

function replaceCurrent(payload: Record<string, unknown>) {
  if (currentSearchIndex < 0 || currentSearchIndex >= searchMatches.length) return;
  const match = searchMatches[currentSearchIndex];
  if (!match) return;
  editor.executeEdits('kaji-replace-current', [{ range: match.range, text: asString(payload.replacement), forceMoveMarkers: true }]);
  refreshSearchMatches();
  if (searchMatches.length === 0) currentSearchIndex = -1;
  else currentSearchIndex = Math.min(currentSearchIndex, searchMatches.length - 1);
  revealSearchMatch();
  postSearchState();
}

function replaceAll(payload: Record<string, unknown>) {
  refreshSearchMatches();
  const replacement = asString(payload.replacement);
  const edits = searchMatches.map((match) => ({ range: match.range, text: replacement, forceMoveMarkers: true }));
  if (edits.length > 0) editor.executeEdits('kaji-replace-all', edits);
  refreshSearchMatches();
  currentSearchIndex = searchMatches.length > 0 ? 0 : -1;
  revealSearchMatch();
  postSearchState();
}

function refreshSearchMatches() {
  if (!model || currentSearchNeedle.length === 0) {
    searchMatches = [];
    return;
  }
  try {
    searchMatches = model.findMatches(currentSearchNeedle, false, currentSearchRegex, currentSearchCaseSensitive, null, false).map((match) => ({ range: match.range }));
  } catch {
    searchMatches = [];
    post('searchState', { count: 0, index: 0, invalidRegex: true });
  }
}

function revealSearchMatch() {
  if (currentSearchIndex < 0 || currentSearchIndex >= searchMatches.length) return;
  const match = searchMatches[currentSearchIndex];
  if (!match) return;
  editor.setSelection(match.range);
  editor.revealRangeInCenter(match.range, monaco.editor.ScrollType.Smooth);
}

function postSearchState() {
  post('searchState', {
    count: searchMatches.length,
    index: currentSearchIndex >= 0 ? currentSearchIndex + 1 : 0,
    invalidRegex: false
  });
}

function prepareInlineEdit() {
  const selection = editor.getSelection();
  if (!selection || selection.isEmpty()) {
    post('inlineSelection', { text: '' });
    return;
  }
  const text = currentModel().getValueInRange(selection);
  post('inlineSelection', { text });
}

function selectedTextForState() {
  const selection = editor.getSelection();
  if (!selection || selection.isEmpty()) return '';
  const text = currentModel().getValueInRange(selection);
  if (text.length > 200 || text.includes('\n')) return '';
  return text;
}

window.kajiMonacoReceive = (command: KajiCommand) => {
  try {
    const payload = commandPayload(command);
    if (command.command === 'bindEditor') bindEditor(command);
    else if (command.editorID !== editorID) return;
    else if (command.command === 'setModel') setModel(payload);
    else if (command.command === 'appendText') appendText(payload);
    else if (command.command === 'applyEdit') applyEdit(payload);
    else if (command.command === 'applyInlineEdit') applyInlineEdit(payload);
    else if (command.command === 'updateOptions') updateOptions(payload);
    else if (command.command === 'setTheme') setTheme(payload);
    else if (command.command === 'focus') editor.focus();
    else if (command.command === 'revealLine') revealLine(payload);
    else if (command.command === 'setScrollTop') setScrollTop(payload);
    else if (command.command === 'find') find(payload);
    else if (command.command === 'replaceCurrent') replaceCurrent(payload);
    else if (command.command === 'replaceAll') replaceAll(payload);
    else if (command.command === 'prepareInlineEdit') prepareInlineEdit();
    else if (command.command === 'quickOutline') quickOutline();
  } catch (error) {
    post('error', { message: error instanceof Error ? error.message : String(error) });
  }
};

editor.onDidChangeModelContent((event) => {
  if (suppressChange) return;
  const edits: ModelEdit[] = event.changes.map((change) => ({
    range: {
      startLineNumber: change.range.startLineNumber,
      startColumn: change.range.startColumn,
      endLineNumber: change.range.endLineNumber,
      endColumn: change.range.endColumn
    },
    text: change.text
  }));
  post('contentChanged', { version: currentModel().getVersionId(), edits });
  if (currentSearchNeedle.length > 0) {
    refreshSearchMatches();
    postSearchState();
  }
});

editor.onDidChangeCursorPosition((event) => {
  const selection = editor.getSelection();
  post('cursorChanged', {
    line: event.position.lineNumber,
    column: event.position.column,
    selectionLength: selection ? currentModel().getValueInRange(selection).length : 0
  });
  post('selectionChanged', { text: selectedTextForState() });
});

editor.onDidChangeCursorSelection(() => {
  post('selectionChanged', { text: selectedTextForState() });
});

editor.onDidScrollChange((event) => {
  post('scrollChanged', {
    scrollTop: event.scrollTop,
    scrollHeight: event.scrollHeight,
    viewportHeight: editor.getLayoutInfo().height
  });
});

editor.onDidFocusEditorText(() => post('focusChanged', { focused: true }));
editor.onDidBlurEditorText(() => post('focusChanged', { focused: false }));

monaco.editor.onDidChangeMarkers((resources) => {
  if (!model) return;
  const modelURI = model.uri.toString();
  if (resources.some((resource) => resource.toString() === modelURI)) {
    postDiagnostics();
  }
});

editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => post('saveRequested'));

post('ready', { userAgent: navigator.userAgent });
