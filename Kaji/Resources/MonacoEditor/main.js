require.config({ paths: { vs: './vs' } });
window.MonacoEnvironment = {
  getWorkerUrl: function () {
    return './vs/base/worker/workerMain.js';
  }
};
require(['vs/editor/editor.main'], function () {
  var params = new URLSearchParams(window.location.search);
  var editorID = params.get('editorID') || 'default';
  var model = null;
  var suppressChange = false;
  var searchNeedle = '';
  var searchCaseSensitive = false;
  var searchRegex = false;
  var searchMatches = [];
  var searchIndex = -1;
  var editor = monaco.editor.create(document.getElementById('editor'), {
    automaticLayout: true,
    minimap: { enabled: false },
    scrollBeyondLastLine: false,
    renderLineHighlight: 'line',
    fixedOverflowWidgets: true,
    wordBasedSuggestions: 'off',
    padding: { top: 4, bottom: 4 },
    scrollbar: { vertical: 'visible', horizontal: 'visible', useShadows: false }
  });

  function post(type, payload) {
    if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.kajiMonaco) return;
    window.webkit.messageHandlers.kajiMonaco.postMessage({ type: type, editorID: editorID, payload: payload || {} });
  }

  function asString(value, fallback) {
    return typeof value === 'string' ? value : fallback || '';
  }

  function asNumber(value, fallback) {
    return typeof value === 'number' && isFinite(value) ? value : fallback || 0;
  }

  function asBoolean(value, fallback) {
    return typeof value === 'boolean' ? value : !!fallback;
  }

  function currentModel() {
    return editor.getModel();
  }

  function setModel(payload) {
    var uri = monaco.Uri.parse(asString(payload.uri, 'kaji://editor/' + editorID));
    var language = asString(payload.language, 'plaintext');
    var text = asString(payload.text, '');
    var existing = monaco.editor.getModel(uri);
    suppressChange = true;
    try {
      model = existing || monaco.editor.createModel(text, language, uri);
      if (existing && existing.getValue() !== text) existing.setValue(text);
      monaco.editor.setModelLanguage(model, language);
      editor.setModel(model);
      editor.updateOptions({ readOnly: asBoolean(payload.readOnly, false) });
      setTimeout(postSearchState, 0);
    } finally {
      suppressChange = false;
    }
  }

  function applyEdit(payload) {
    if (!payload.range) return;
    var range = payload.range;
    editor.executeEdits('kaji-apply-edit', [{
      range: new monaco.Range(asNumber(range.startLineNumber, 1), asNumber(range.startColumn, 1), asNumber(range.endLineNumber, 1), asNumber(range.endColumn, 1)),
      text: asString(payload.text, ''),
      forceMoveMarkers: true
    }]);
  }

  function applyInlineEdit(payload) {
    var selection = editor.getSelection();
    var text = asString(payload.text, '');
    if (!selection || selection.isEmpty()) {
      var position = editor.getPosition() || { lineNumber: 1, column: 1 };
      selection = new monaco.Range(position.lineNumber, position.column, position.lineNumber, position.column);
    }
    editor.executeEdits('kaji-inline-edit', [{ range: selection, text: text, forceMoveMarkers: true }]);
  }

  function setDiagnostics(payload) {
    var markers = Array.isArray(payload.markers) ? payload.markers.map(function (marker) {
      return {
        startLineNumber: asNumber(marker.startLineNumber, 1),
        startColumn: asNumber(marker.startColumn, 1),
        endLineNumber: asNumber(marker.endLineNumber, asNumber(marker.startLineNumber, 1)),
        endColumn: asNumber(marker.endColumn, asNumber(marker.startColumn, 1) + 1),
        severity: markerSeverity(asString(marker.severity, 'information')),
        message: asString(marker.message, ''),
        source: asString(marker.source, 'Kaji')
      };
    }) : [];
    if (model) monaco.editor.setModelMarkers(model, 'kaji', markers);
  }

  function markerSeverity(severity) {
    if (severity === 'error') return monaco.MarkerSeverity.Error;
    if (severity === 'warning') return monaco.MarkerSeverity.Warning;
    if (severity === 'hint') return monaco.MarkerSeverity.Hint;
    return monaco.MarkerSeverity.Info;
  }

  function updateOptions(payload) {
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

  function setTheme(payload) {
    var name = asString(payload.name, 'kaji-editor-theme');
    monaco.editor.defineTheme(name, {
      base: asString(payload.base, 'vs-dark') === 'vs' ? 'vs' : 'vs-dark',
      inherit: true,
      colors: payload.colors || {},
      rules: []
    });
    monaco.editor.setTheme(name);
  }

  function revealLine(payload) {
    var line = Math.max(1, Math.floor(asNumber(payload.line, 1)));
    var column = Math.max(1, Math.floor(asNumber(payload.column, 1)));
    var position = { lineNumber: line, column: column };
    editor.setPosition(position);
    editor.revealPositionInCenter(position, monaco.editor.ScrollType.Smooth);
  }

  function find(payload) {
    searchNeedle = asString(payload.needle, '');
    searchCaseSensitive = asBoolean(payload.caseSensitive, false);
    searchRegex = asBoolean(payload.regex, false);
    refreshSearchMatches();
    if (searchMatches.length === 0) {
      searchIndex = -1;
      postSearchState();
      return;
    }
    searchIndex = asString(payload.direction, 'next') === 'previous'
      ? (searchIndex <= 0 ? searchMatches.length - 1 : searchIndex - 1)
      : (searchIndex + 1) % searchMatches.length;
    revealSearchMatch();
    postSearchState();
  }

  function replaceCurrent(payload) {
    if (searchIndex < 0 || searchIndex >= searchMatches.length) return;
    editor.executeEdits('kaji-replace-current', [{ range: searchMatches[searchIndex].range, text: asString(payload.replacement, ''), forceMoveMarkers: true }]);
    refreshSearchMatches();
    searchIndex = searchMatches.length === 0 ? -1 : Math.min(searchIndex, searchMatches.length - 1);
    revealSearchMatch();
    postSearchState();
  }

  function replaceAll(payload) {
    refreshSearchMatches();
    var replacement = asString(payload.replacement, '');
    var edits = searchMatches.map(function (match) { return { range: match.range, text: replacement, forceMoveMarkers: true }; });
    if (edits.length > 0) editor.executeEdits('kaji-replace-all', edits);
    refreshSearchMatches();
    searchIndex = searchMatches.length > 0 ? 0 : -1;
    revealSearchMatch();
    postSearchState();
  }

  function refreshSearchMatches() {
    if (!model || searchNeedle.length === 0) {
      searchMatches = [];
      return;
    }
    try {
      searchMatches = model.findMatches(searchNeedle, false, searchRegex, searchCaseSensitive, null, false).map(function (match) { return { range: match.range }; });
    } catch (error) {
      searchMatches = [];
      post('searchState', { count: 0, index: 0, invalidRegex: true });
    }
  }

  function revealSearchMatch() {
    if (searchIndex < 0 || searchIndex >= searchMatches.length) return;
    var match = searchMatches[searchIndex];
    editor.setSelection(match.range);
    editor.revealRangeInCenter(match.range, monaco.editor.ScrollType.Smooth);
  }

  function postSearchState() {
    post('searchState', { count: searchMatches.length, index: searchIndex >= 0 ? searchIndex + 1 : 0, invalidRegex: false });
  }

  function prepareInlineEdit() {
    var selection = editor.getSelection();
    if (!selection || selection.isEmpty()) {
      post('inlineSelection', { text: '' });
      return;
    }
    post('inlineSelection', { text: currentModel().getValueInRange(selection) });
  }

  function selectedTextForState() {
    var selection = editor.getSelection();
    if (!selection || selection.isEmpty()) return '';
    var text = currentModel().getValueInRange(selection);
    return text.length > 200 || text.indexOf('\n') >= 0 ? '' : text;
  }

  window.kajiMonacoReceive = function (message) {
    try {
      var payload = message.payload || {};
      if (message.command === 'setModel') setModel(payload);
      else if (message.command === 'applyEdit') applyEdit(payload);
      else if (message.command === 'applyInlineEdit') applyInlineEdit(payload);
      else if (message.command === 'setDiagnostics') setDiagnostics(payload);
      else if (message.command === 'updateOptions') updateOptions(payload);
      else if (message.command === 'setTheme') setTheme(payload);
      else if (message.command === 'focus') editor.focus();
      else if (message.command === 'revealLine') revealLine(payload);
      else if (message.command === 'setScrollTop') editor.setScrollTop(Math.max(0, asNumber(payload.scrollTop, 0)));
      else if (message.command === 'find') find(payload);
      else if (message.command === 'replaceCurrent') replaceCurrent(payload);
      else if (message.command === 'replaceAll') replaceAll(payload);
      else if (message.command === 'prepareInlineEdit') prepareInlineEdit();
    } catch (error) {
      post('error', { message: error instanceof Error ? error.message : String(error) });
    }
  };

  editor.onDidChangeModelContent(function (event) {
    if (suppressChange) return;
    post('contentChanged', {
      version: currentModel().getVersionId(),
      edits: event.changes.map(function (change) {
        return {
          range: {
            startLineNumber: change.range.startLineNumber,
            startColumn: change.range.startColumn,
            endLineNumber: change.range.endLineNumber,
            endColumn: change.range.endColumn
          },
          text: change.text
        };
      })
    });
    if (searchNeedle.length > 0) {
      refreshSearchMatches();
      postSearchState();
    }
  });

  editor.onDidChangeCursorPosition(function (event) {
    var selection = editor.getSelection();
    post('cursorChanged', {
      line: event.position.lineNumber,
      column: event.position.column,
      selectionLength: selection ? currentModel().getValueInRange(selection).length : 0
    });
    post('selectionChanged', { text: selectedTextForState() });
  });
  editor.onDidChangeCursorSelection(function () { post('selectionChanged', { text: selectedTextForState() }); });
  editor.onDidScrollChange(function (event) {
    post('scrollChanged', { scrollTop: event.scrollTop, scrollHeight: event.scrollHeight, viewportHeight: editor.getLayoutInfo().height });
  });
  editor.onDidFocusEditorText(function () { post('focusChanged', { focused: true }); });
  editor.onDidBlurEditorText(function () { post('focusChanged', { focused: false }); });
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function () { post('saveRequested'); });
  post('ready', { userAgent: navigator.userAgent });
});
