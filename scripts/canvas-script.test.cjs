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
    [{name: 'Fixture assignment', html_url: 'https://khcanvas.khu.ac.kr/courses/1/assignments/2', submission: {workflow_state: 'unsubmitted'}}],
    [{ context_code: 'course_1', title: 'Fixture notice', posted_at: '2026-09-25T00:00:00Z', html_url: 'https://khcanvas.khu.ac.kr/courses/1/discussion_topics/3' }]
  ];
  let payload;
  await vm.runInNewContext(source, {
    URLSearchParams, URL, location: {origin: "https://khcanvas.khu.ac.kr"},
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
    URL, location: {origin: "https://khcanvas.khu.ac.kr"},
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
function loginFixture({origin = 'https://e-campus.khu.ac.kr', action = '', challenge = false, frame = false, csrf = true} = {}) {
  let submitted = 0;
  const form = {method: 'post', getAttribute: () => action};
  const id = {form, value: ''}, passwordField = {form, type: 'password', value: ''};
  const window = {OnLogon: () => submitted++};
  window.top = frame ? {} : window;
  const context = {window, URL, username: 'fixture-user', password: "quotes'\"\\and newline\n", location: {origin, pathname: '/xn-sso/login.php', href: origin + '/xn-sso/login.php'},
    document: {cookie: csrf ? 'xn_sso_csrf_token_for_this_login=fixture-token' : '', querySelector: selector => ({'form#form1': form, '#login_user_id': id, '#login_user_password': passwordField, '#login_form1_csrf_token': {}}[selector] ?? (challenge ? {} : null))}};
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

async function submissionFixture(assignments, {failure = false, paged = false} = {}) {
  let payload, pages = 0;
  await vm.runInNewContext(source, {
    URL, URLSearchParams, location: {origin: 'https://khcanvas.khu.ac.kr'},
    fetch: async path => {
      let body = [], link = '';
      if (path.includes('/courses?')) body = [{id: 1, name: 'Fixture course'}];
      if (path.includes('/assignments?')) {
        if (failure) return {ok: false, status: 403};
        pages++;
        body = paged && pages === 1 ? [] : assignments;
        if (paged && pages === 1) link = '<https://khcanvas.khu.ac.kr/api/v1/courses/1/assignments?page=2>; rel="next"';
      }
      return {ok: true, headers: {get: () => link}, text: async () => JSON.stringify(body)};
    },
    window: {webkit: {messageHandlers: {canvasData: {postMessage: text => payload = JSON.parse(text)}}}}
  });
  return {payload, pages};
}
test('submission states separate completed work from zero grades and resubmission requests', async () => {
  const submissions = [
    {workflow_state: 'submitted'}, {workflow_state: 'pending_review'},
    {workflow_state: 'graded', submitted_at: '2026-10-01T14:59:00Z'},
    {workflow_state: 'graded', grade: '0'}, {workflow_state: 'unsubmitted'},
    {workflow_state: 'submitted', redo_request: true}, {excused: true}
  ];
  const {payload} = await submissionFixture(submissions.map((submission, i) => ({
    name: `Task ${i}`, html_url: `https://khcanvas.khu.ac.kr/courses/1/assignments/${i}`, submission
  })));
  assert.deepEqual(payload.items.map(item => item.completed), [true, true, true, false, false, false, true]);
  assert.equal(payload.items[6].completionLabel, '제출 면제');
});
test('assignment pagination includes completed items beyond the first page', async () => {
  const {payload, pages} = await submissionFixture([{name: 'Page two', html_url: 'https://khcanvas.khu.ac.kr/courses/1/assignments/2', submission: {workflow_state: 'submitted'}}], {paged: true});
  assert.equal(pages, 2);
  assert.equal(payload.items[0].completed, true);
});
test('unavailable submission data is reported as a partial failure', async () => {
  const {payload} = await submissionFixture([], {failure: true});
  assert.match(payload.warning, /제출 상태 확인 실패/);
});

test('automatic login refuses to submit credentials without the school CSRF cookie', () => {
  const fixture = loginFixture({csrf: false});
  assert.equal(fixture.result, 'missing-csrf');
  assert.equal(fixture.submitted, 0);
  assert.equal(fixture.passwordField.value, '');
});

test('all app login entry points use the official SSO entry, not the bare form', () => {
  const store = readFileSync(new URL('../Sources/CampusStore.swift', `file://${__filename}`), 'utf8');
  assert.equal((store.match(/URLRequest\(url: AutoLoginPolicy.entryURL/g) || []).length, 2);
  assert.ok(!store.includes('https://e-campus.khu.ac.kr/xn-sso/login.php'));
});
