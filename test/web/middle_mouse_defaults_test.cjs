const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

test('middle mouse defaults are prevented without stopping propagation', () => {
  const html = fs.readFileSync(path.join(__dirname, '../../web/index.html'), 'utf8');
  const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
    .filter(([, attributes]) => !/\bsrc\s*=/i.test(attributes))
    .map(([, , source]) => source);
  const listeners = new Map();
  const window = {
    addEventListener(type, listener, options) {
      const registered = listeners.get(type) ?? [];
      registered.push({ listener, options });
      listeners.set(type, registered);
    },
  };

  for (const [index, source] of scripts.entries()) {
    vm.runInNewContext(source, {
      window,
      document: { getElementById: () => ({ remove() {} }) },
    }, { filename: `web/index.html inline script ${index + 1}` });
  }

  assert.deepEqual([...listeners.keys()].sort(), ['auxclick', 'flutter-first-frame', 'mousedown']);
  for (const type of ['mousedown', 'auxclick']) {
    const [registration] = listeners.get(type);
    assert.equal(registration.options, true, `${type} listener uses capture phase`);

    for (const button of [0, 1, 2]) {
      let defaultPrevented = false;
      registration.listener({
        button,
        preventDefault() { defaultPrevented = true; },
        stopPropagation() { assert.fail(`${type} stopped propagation`); },
      });
      assert.equal(defaultPrevented, button === 1, `${type} button ${button}`);
    }
  }
});
