// Load the emulator page in headless Chrome and wait for it to declare
// itself ready: try.js removes the Boot button's disabled attribute only
// after the wasm module has initialised and the AROS ROMs have arrived. A
// rejected ES module graph, a wasm init failure, or a missing ROM all
// leave the button disabled, which fails the wait below. Run by
// smoke-test.sh; takes the page URL as its argument.
import puppeteer from 'puppeteer-core';

const url = process.argv[2];
if (!url) {
  console.error('usage: node smoke-page.mjs <url>');
  process.exit(2);
}

// The page probes these and treats a 404 as "no config" / "no list", so
// the browser's resulting resource-load console errors are expected. The
// favicon is the browser's own probe (and a mounted custom shell may not
// ship one).
const EXPECTED_404 = [/copperline\.json$/, /files\/index\.json$/, /favicon\.ico$/];

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH ?? '/usr/bin/google-chrome',
  args: ['--no-sandbox'],
});
let failed = false;
const errors = [];
try {
  const page = await browser.newPage();
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    const src = m.location()?.url ?? '';
    if (m.type() === 'error' && !EXPECTED_404.some((re) => re.test(src))) {
      errors.push(`console.error: ${m.text()} (${src})`);
    }
  });

  await page.goto(url, { waitUntil: 'load', timeout: 30_000 });
  await page.waitForFunction(
    () => {
      const b = document.getElementById('boot');
      return b instanceof HTMLButtonElement && !b.disabled;
    },
    { timeout: 60_000 },
  );

  const status = await page.$eval('#load-status', (el) => el.textContent);
  console.log(`page ready: ${JSON.stringify(status)}`);
  if (errors.length) failed = true;
} catch (e) {
  console.error(String(e));
  failed = true;
} finally {
  // On a timeout the collected errors are the diagnosis (e.g. the failed
  // module import that kept Boot disabled) - print them either way.
  if (errors.length) console.error(errors.join('\n'));
  await browser.close();
}
process.exit(failed ? 1 : 0);
