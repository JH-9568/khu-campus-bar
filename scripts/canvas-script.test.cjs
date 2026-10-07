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

const loginScript = scripts.match(/static let autoLogin = #"""([\s\S]*?)"""#/)[1];
function loginFixture({origin = 'https://e-campus.khu.ac.kr', action = '', challenge = false, frame = false} = {}) {
  let submitted = 0;
  const form = {method: 'post', getAttribute: () => action};
  const id = {form, value: ''}, passwordField = {form, type: 'password', value: ''};
  const window = {OnLogon: () => submitted++};
  window.top = frame ? {} : window;
  const context = {window, URL, username: 'fixture-user', password: "quotes'\"\\and newline\n", location: {origin, pathname: '/xn-sso/login.php', href: origin + '/xn-sso/login.php'},
    document: {querySelector: selector => ({'form#form1': form, '#login_user_id': id, '#login_user_password': passwordField, '#login_form1_csrf_token': {}}[selector] ?? (challenge ? {} : null))}};
  const result = vm.runInNewContext(`(function(){${loginScript}})()`, context);
  return {result, submitted, id, passwordField, expected: context.password};
}
test('automatic login submits the observed school form with literal credentials', () => {
  const fixture = loginFixture();
  assert.equal(fixture.result, true);
  assert.equal(fixture.submitted, 1);
  assert.equal(fixture.passwordField.value, fixture.expected);
});
test('automatic login refuses other origins, frames, redirected forms and challenges', () => {
  for (const options of [{origin:'https://evil.test'}, {action:'https://evil.test/login'}, {challenge:true}, {frame:true}]) {
    const fixture = loginFixture(options);
    assert.equal(fixture.result, false);
    assert.equal(fixture.submitted, 0);
    assert.equal(fixture.passwordField.value, '');
  }
});
