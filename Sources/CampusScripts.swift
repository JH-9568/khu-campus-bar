enum CampusScripts {
    static let canvas = #"""
    (async () => {
      try {
        const get = async path => {
          const response = await fetch(path, {credentials: 'same-origin'});
          if (!response.ok) throw new Error(`Canvas API ${response.status}`);
          return await response.json();
        };
        const courses = await get('/api/v1/courses?enrollment_state=active&per_page=100');
        if (!Array.isArray(courses)) throw new Error('과목 목록을 읽지 못했습니다');
        const names = Object.fromEntries(courses.map(c => [String(c.id), c.name]));
        const events = await get('/api/v1/users/self/upcoming_events?per_page=100');
        const items = (Array.isArray(events) ? events : []).map(e => ({
          kind: e.assignment ? 'assignment' : 'activity',
          title: e.assignment?.name || e.title || '',
          course: names[String(e.context_code || '').replace('course_', '')] || '강의실',
          date: e.assignment?.due_at || e.start_at || null,
          url: e.assignment?.html_url || e.html_url || ''
        }));
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
        window.webkit.messageHandlers.canvasData.postMessage(JSON.stringify({items}));
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
      const observer = new MutationObserver(() => requestAnimationFrame(scan));
      observer.observe(document.documentElement, {childList: true, subtree: true, characterData: true});
      scan();
    })();
    """#
}
