const playwrightToolCache = require('./playwright-tool-cache');
const { PlaywrightClient } = require('./playwright-client');
const { ChromeDevToolsClient } = require('./chrome-devtools-client');
const { filterTools } = require('./safety');

function createProvider() {
  if (providerName() === 'chrome-devtools') return new ChromeDevToolsClient();
  return new PlaywrightClient();
}

function providerTools(provider) {
  if (typeof provider.tools === 'function') return filterTools(provider.tools());
  return playwrightToolCache.tools();
}

function providerName() {
  const value = (process.env.KAJI_BROWSER_PROVIDER || 'playwright').trim().toLowerCase();
  if (value === 'chrome-devtools' || value === 'chrome_devtools' || value === 'devtools') return 'chrome-devtools';
  return 'playwright';
}

module.exports = { createProvider, providerTools, providerName };
