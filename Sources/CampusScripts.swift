enum CampusScripts {
    // Arguments arrive through WKWebView's structured API, never JS interpolation.
    static let autoLogin = #"""
    if (window.top !== window || location.origin !== 'https://e-campus.khu.ac.kr'
        || location.pathname !== '/xn-sso/login.php') return false;
    const form = document.querySelector('form#form1');
    const id = document.querySelector('#login_user_id');
    const passwordField = document.querySelector('#login_user_password');
    const action = form && new URL(form.getAttribute('action') || location.href, location.href);
    if (!form || !id || !passwordField || id.form !== form || passwordField.form !== form
        || passwordField.type !== 'password' || form.method.toLowerCase() !== 'post'
        || action.origin !== location.origin || action.pathname !== location.pathname
        || typeof window.OnLogon !== 'function'
        || !document.querySelector('#login_form1_csrf_token')
        || document.querySelector('iframe[src*="recaptcha"], iframe[src*="hcaptcha"], input[autocomplete="one-time-code"]')) return false;
    if (!document.cookie.split(';').some(c => c.trim().startsWith('xn_sso_csrf_token_for_this_login=')
        && c.trim().slice('xn_sso_csrf_token_for_this_login='.length).length > 0)) return 'missing-csrf';
    id.value = username;
    passwordField.value = password;
    window.OnLogon();
    return true;
    """#

    // Only booleans/counts: never inspect input values, cookie values or response text.
    static let loginDiagnostics = #"""
    JSON.stringify({form: Boolean(document.querySelector('form#form1')),
      csrfCookie: document.cookie.split(';').filter(c => c.trim().startsWith('xn_sso_csrf_token_for_this_login=')).length,
      scripts: document.scripts.length, frames: document.querySelectorAll('iframe').length,
      refresh: Boolean(document.querySelector('meta[http-equiv="refresh"]'))})
    """#

    static let canvas = #"""
    (async () => {
      try {
        const get = async path => {
          let next = new URL(path, location.origin), rows = [], seen = new Set();
          while (next) {
            if (next.origin !== location.origin || seen.has(next.href) || seen.size >= 100)
              throw new Error('목록 페이지를 모두 확인하지 못했습니다');
            seen.add(next.href);
            const response = await fetch(next.href, {
              credentials: 'same-origin', headers: {Accept: 'application/json'}
            });
            if (!response.ok) throw new Error(`Canvas API ${response.status}: ${next.pathname}`);
            const body = JSON.parse((await response.text()).replace(/^\s*while\(1\);/, ''));
            if (!Array.isArray(body)) throw new Error('목록 응답 형식이 바뀌었습니다');
            rows.push(...body);
            const link = response.headers?.get('Link') || '';
            const following = link.split(',').map(s => s.match(/<([^>]+)>;\s*rel="next"/)).find(Boolean);
            next = following ? new URL(following[1], location.origin) : null;
          }
          return rows;
        };
        const courses = await get('/api/v1/courses?enrollment_state=active&per_page=100');
        const names = Object.fromEntries(courses.map(c => [String(c.id), c.name]));
        const events = await get('/api/v1/users/self/upcoming_events?per_page=100');
        const items = events.map(e => ({
          kind: e.assignment ? 'assignment' : 'activity',
          title: e.assignment?.name || e.title || '',
          course: names[String(e.context_code || '').replace('course_', '')] || '강의실',
          date: e.assignment?.due_at || e.start_at || null,
          url: e.assignment?.html_url || e.html_url || ''
        }));
        // Include the current student's submission; do not fetch grades or other students.
        // Keep partial course failures explicit while retaining upcoming events as a fallback.
        const warnings = [];
        for (const course of courses) {
          try {
            const assignments = await get(`/api/v1/courses/${course.id}/assignments?include[]=submission&per_page=100`);
            for (const a of assignments) {
              if (a.published === false || a.submission_types?.includes('not_graded')) continue;
              const s = a.submission;
              const completed = Boolean(s && !s.redo_request && (s.excused ||
                ['submitted', 'pending_review'].includes(s.workflow_state) ||
                (s.workflow_state === 'graded' && s.submitted_at)));
              const item = {
                kind: 'assignment', title: a.name || '', course: course.name,
                date: a.due_at || null, url: a.html_url || '', completed,
                completionLabel: completed ? (s.excused ? '제출 면제' : '제출 완료') : null,
                completedAt: completed ? s.submitted_at || s.graded_at || null : null
              };
              const existing = items.findIndex(e => e.url === item.url);
              if (existing >= 0) items[existing] = item; else items.push(item);
            }
          } catch { warnings.push(`${course.name}: 제출 상태 확인 실패`); }
        }
        const params = new URLSearchParams({per_page: '100'});
        const start = new Date(Date.now() - 14 * 86400000);
        params.set('start_date', start.toISOString().slice(0, 10));
        courses.forEach(c => params.append('context_codes[]', `course_${c.id}`));
        if (courses.length) {
          const announcements = await get(`/api/v1/announcements?${params}`);
          for (const a of Array.isArray(announcements) ? announcements : []) {
            items.push({
              kind: 'announcement', title: a.title || '',
              course: names[String(a.context_code || '').replace('course_', '')] || '강의실',
              date: a.posted_at || a.created_at || null,
              url: a.html_url || ''
            });
          }
        }
        window.webkit.messageHandlers.canvasData.postMessage(JSON.stringify({items, warning: warnings.join(" · ")}));
      } catch (error) {
        window.webkit.messageHandlers.canvasData.postMessage(JSON.stringify({error: String(error)}));
      }
    })();
    """#

    static let learningX = #"""
    (() => {
      if (location.host !== 'khcanvas.khu.ac.kr' || location.pathname !== '/learningx/lti/dashboard') return;
      let previous = '';
      const scan = () => {
        const cards = [...document.querySelectorAll('.xn-student-course-container')];
        if (!cards.length) return;
        const items = cards.flatMap(card => {
          const course = card.querySelector('.xnscc-header-title')?.textContent?.trim() || '강의실';
          return [...card.querySelectorAll('.xn-student-todo-item-container')].map(row => {
            const link = row.querySelector('.xnsti-left-title');
            const icon = row.querySelector('.xnsti-left-icon');
            return {
              kind: icon?.classList.contains('video') || icon?.classList.contains('youtube') ? 'video' : 'assignment',
              title: link?.textContent?.trim() || '',
              course,
              date: row.querySelector('.xnsti-right-due-at')?.textContent?.trim() || null,
              url: link?.href || ''
            };
          });
        });
        const json = JSON.stringify({items});
        if (json !== previous) {
          previous = json;
          window.webkit.messageHandlers.learningX.postMessage(json);
        }
      };
      const observer = new MutationObserver(scan);
      observer.observe(document.documentElement, {childList: true, subtree: true, characterData: true});
      scan();
    })();
    """#
}
