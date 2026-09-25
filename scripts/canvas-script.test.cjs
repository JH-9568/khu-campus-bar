const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const scripts = readFileSync(new URL('../Sources/CampusScripts.swift', `file://${__filename}`), 'utf8');
const source = scripts.match(/static let canvas = #"""([\s\S]*?)"""#/)[1];

test('reads cookie-authenticated Canvas JSON and maps deadlines and announcements', async () => {
  const responses = [
    [{ id: 1, name: 'Fixture course' }],
    [{ context_code: 'course_1', assignment: { name: 'Fixture assignment', due_at: '2026-10-01T14:59:00Z', html_url: 'https://khcanvas.khu.ac.kr/courses/1/assignments/2' } }],
    [{ context_code: 'course_1', title: 'Fixture notice', posted_at: '2026-09-25T00:00:00Z', html_url: 'https://khcanvas.khu.ac.kr/courses/1/discussion_topics/3' }]
  ];
  let payload;
  await vm.runInNewContext(source, {
    URLSearchParams,
    fetch: async (path, options) => {
      assert.equal(options.headers.Accept, 'application/json');
      assert.equal(options.credentials, 'same-origin');
      return { ok: true, text: async () => `while(1);${JSON.stringify(responses.shift())}` };
    },
    window: { webkit: { messageHandlers: { canvasData: { postMessage: text => payload = JSON.parse(text) } } } }
  });
  assert.deepEqual(Array.from(payload.items, item => item.kind), ['assignment', 'announcement']);
  assert.equal(payload.items[0].course, 'Fixture course');
  assert.equal(payload.items[1].title, 'Fixture notice');
});

test('reports a failed endpoint instead of treating it as an empty course list', async () => {
  let payload;
  await vm.runInNewContext(source, {
    fetch: async () => ({ ok: false, status: 401 }),
    window: { webkit: { messageHandlers: { canvasData: { postMessage: text => payload = JSON.parse(text) } } } }
  });
  assert.match(payload.error, /401: \/api\/v1\/courses/);
  assert.equal(payload.items, undefined);
});

test('collects LearningX videos after DOM changes without waiting for a visible animation frame', () => {
  let cards = [], onMutation, payload;
  vm.runInNewContext(scripts.match(/static let learningX = #"""([\s\S]*?)"""#/)[1], {
    location: { host: 'khcanvas.khu.ac.kr', pathname: '/learningx/lti/dashboard' },
    document: { documentElement: {}, querySelectorAll: () => cards },
    MutationObserver: class { constructor(callback) { onMutation = callback; } observe() {} },
    window: { webkit: { messageHandlers: { learningX: { postMessage: text => payload = JSON.parse(text) } } } }
  });
  cards = [{
    querySelector: () => ({ textContent: 'Fixture course' }),
    querySelectorAll: () => [{ querySelector: selector => ({
      '.xnsti-left-title': { textContent: 'Fixture video', href: 'https://khcanvas.khu.ac.kr/video/1' },
      '.xnsti-left-icon': { classList: { contains: value => value === 'video' } },
      '.xnsti-right-due-at': { textContent: '2026.10.01 23:59' }
    })[selector] }]
  }];
  onMutation();
  assert.equal(payload.items.length, 1);
  assert.equal(payload.items[0].kind, 'video');
  assert.equal(payload.items[0].date, '2026.10.01 23:59');
});
