(() => {
  const desktop = document.getElementById('project-desktop');
  const workspace = document.getElementById('workspace');
  const traditional = document.getElementById('traditional-desktop');
  const openCuppa = document.getElementById('open-cuppa');
  const createProject = document.getElementById('create-project');
  const clock = document.getElementById('desktop-time');
  const date = document.getElementById('desktop-date');
  const timeZone = 'Asia/Shanghai';
  const timeFormat = new Intl.DateTimeFormat('zh-CN', {
    timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
  });
  const dateFormat = new Intl.DateTimeFormat('zh-CN', {
    timeZone, month: 'long', day: 'numeric', weekday: 'long'
  });
  const lunarFormat = new Intl.DateTimeFormat('zh-CN-u-ca-chinese', {
    timeZone, month: 'long', day: 'numeric'
  });
  const projectListKey = 'design-canvas-projects';

  function readProjects() {
    return CuppaCaptureStore.mergeProjects(CuppaCaptureStore.projects(localStorage.getItem(projectListKey)), globalThis.cuppaBootstrap?.projects||[]);
  }
  function visibleProjects() { try { return readProjects(); } catch { return globalThis.cuppaBootstrap?.projects||[]; } }

  let projectName = visibleProjects().find(project => project.id === projectId)?.name || 'CUPPA';
  document.querySelectorAll('[data-project-name]').forEach(label => {
    label.textContent = projectName;
    label.title = projectName;
  });

  function updateClock() {
    const now = new Date();
    clock.textContent = timeFormat.format(now);
    const lunar = lunarFormat.formatToParts(now);
    const month = lunar.find(part => part.type === 'month')?.value || '';
    const day = Number(lunar.find(part => part.type === 'day')?.value);
    const digits = '〇一二三四五六七八九十';
    const lunarDay = day <= 10 ? '初' + digits[day]
      : day < 20 ? '十' + digits[day - 10]
      : day === 20 ? '二十'
      : day < 30 ? '廿' + digits[day - 20] : day === 30 ? '三十' : '';
    date.textContent = dateFormat.format(now) + (month && lunarDay ? ' ' + month + lunarDay : '');
  }

  // Motion is presentation-only: routes and saved canvas state remain unchanged.
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const motionEase = 'cubic-bezier(.22,1,.36,1)';
  let activeScreen = null;
  let finishScreenMotion = null;
  let pendingNavigation = false;

  function revealScreen(next, animate) {
    if (finishScreenMotion) finishScreenMotion();
    const previous = activeScreen;
    activeScreen = next;
    [workspace, traditional, desktop].forEach(screen => { screen.hidden = screen !== next; });
    if (!animate || reducedMotion.matches || !next.animate || previous === next) return;

    // Keep the previous screen behind the arriving screen without changing its layout.
    const previousStyle = previous?.getAttribute('style');
    const previousInert = previous?.inert;
    if (previous) {
      previous.hidden = false;
      Object.assign(previous.style, { position: 'absolute', inset: '0', zIndex: '60', pointerEvents: 'none' });
      previous.inert = true;
    }
    const enteringCanvas = next === workspace;
    const incoming = next.animate([
      { opacity: 0, transform: enteringCanvas ? 'translateY(10px) scale(.985)' : 'translateY(-6px) scale(1.008)' },
      { opacity: 1, transform: 'translateY(0) scale(1)' }
    ], { duration: 360, easing: motionEase, fill: 'both' });
    const outgoing = previous?.animate([
      { opacity: 1, transform: 'translateY(0) scale(1)' },
      { opacity: 0, transform: enteringCanvas ? 'translateY(-6px) scale(1.018)' : 'translateY(6px) scale(.99)' }
    ], { duration: 200, easing: motionEase, fill: 'both' });
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      incoming.cancel();
      outgoing?.cancel();
      if (previous) {
        previous.hidden = true;
        if (previousStyle === null) previous.removeAttribute('style');
        else previous.setAttribute('style', previousStyle);
        previous.inert = previousInert;
      }
      if (finishScreenMotion === finish) finishScreenMotion = null;
    };
    finishScreenMotion = finish;
    incoming.finished.then(finish, finish);
  }

  reducedMotion.addEventListener('change', event => {
    if (event.matches && finishScreenMotion) finishScreenMotion();
  });

  function showScreen(moveFocus) {
    const canvasVisible = location.hash === '#cuppa';
    const traditionalVisible = location.hash === '#traditional-desktop';
    const next = canvasVisible ? workspace : traditionalVisible ? traditional : desktop;
    revealScreen(next, moveFocus || canvasVisible);

    document.title = canvasVisible ? projectName + ' · WEAVIA'
      : traditionalVisible ? '传统桌面' : '项目空间桌面';

    if (next === desktop) updateClock();
    if (!moveFocus) return;
    const focusTarget = canvasVisible ? document.getElementById('workspace')
      : traditionalVisible ? traditional : openCuppa;
    focusTarget.focus({ preventScroll: true });
  }

  function navigate(hash) {
    if (location.hash !== hash) location.hash = hash;
  }

  function openProject(id) {
    // The Mac featured tile continues the current real project, not the web demo's empty ID.
    if (globalThis.mouseCompanionMac && !id) id = projectId;
    if (globalThis.mouseCompanionMac && id !== projectId) { mouseCompanionMac.switchProject(id); return; }
    if (id === projectId) {
      navigate('#cuppa');
      return;
    }
    const url = new URL(location.href);
    if (id) url.searchParams.set('project', id);
    else url.searchParams.delete('project');
    url.hash = 'cuppa';
    if (pendingNavigation) return;
    pendingNavigation = true;
    const leave = () => location.assign(url);
    if (reducedMotion.matches || !activeScreen?.animate) { leave(); return; }
    activeScreen.animate([
      { opacity: 1, transform: 'scale(1)' },
      { opacity: .12, transform: 'scale(.99)' }
    ], { duration: 160, easing: motionEase, fill: 'forwards' }).finished.then(leave, leave);
  }

  const dialog = document.getElementById('project-create-dialog');
  document.getElementById('close-project-create').onclick = () => dialog.close();
  createProject.addEventListener('click', () => {
    const form = dialog.querySelector('form');
    const list = dialog.querySelector('.project-create-list');
    form.reset();
    form.querySelector('.project-create-error').textContent = '';
    list.replaceChildren();
    for (const project of visibleProjects()) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = project.name;
      button.onclick = () => {
        dialog.close();
        openProject(project.id);
      };
      list.append(button);
    }
    form.onsubmit = event => {
      event.preventDefault();
      const name = form.elements.name.value.trim();
      if (!name) return;
      if (globalThis.mouseCompanionMac) { mouseCompanionMac.createProject(name); dialog.close(); return; }
      const project = { id: crypto.randomUUID(), name };
      try {
        if (globalThis.cuppaBootstrap?.error) throw Error(globalThis.cuppaBootstrap.error);
        localStorage.setItem(projectListKey, JSON.stringify([...readProjects(), project]));
      } catch {
        form.querySelector('.project-create-error').textContent = '当前浏览器无法保存项目。';
        return;
      }
      openProject(project.id);
    };
    dialog.showModal();
    form.elements.name.focus();
  });
  function updateNativeProjects(projects, currentId, materials = []) {
    if (!globalThis.mouseCompanionMac) return;
    const current = projects.find(project => project.id === currentId);
    projectName = current?.name || currentId || '当前项目';
    openCuppa.setAttribute('aria-label', '继续 ' + projectName + ' 项目画布');
    const caption = openCuppa.querySelector('.featured-project-caption');
    caption.querySelector('strong').textContent = projectName;
    caption.querySelector('span').textContent = materials.filter(item => item.saved).length + ' 份已入画布 · ' + materials.filter(item => !item.saved).length + ' 份待整理';
    caption.querySelector('small').textContent = '本机项目 · 点击继续画布';
    document.querySelectorAll('[data-project-name]').forEach(label => { label.textContent = projectName; label.title = projectName; });
    const others = projects.filter(project => project.id !== currentId);
    document.querySelectorAll('.orbit-project').forEach((oldTile, index) => {
      const project = others[index];
      if (!project) { oldTile.hidden = true; return; }
      let tile = oldTile;
      if (tile.tagName !== 'BUTTON') {
        tile = document.createElement('button'); tile.type = 'button'; tile.className = oldTile.className; tile.innerHTML = oldTile.innerHTML; oldTile.replaceWith(tile);
      }
      tile.hidden = false; tile.style.pointerEvents = 'auto'; tile.style.cursor = 'pointer';
      tile.querySelector('h2').textContent = project.name;
      tile.setAttribute('aria-label', '打开 ' + project.name + ' 项目');
      tile.onclick = () => openProject(project.id);
    });
    document.querySelector('.project-grid').setAttribute('aria-label', '本机项目');
    if (location.hash === '#cuppa') document.title = projectName + ' · WEAVIA';
  }
  globalThis.weaviaProjectDesktop = Object.freeze({ update: updateNativeProjects, open: openProject });
  if (globalThis.mouseCompanionMac) updateNativeProjects(visibleProjects(), projectId);
  openCuppa.addEventListener('click', () => openProject(globalThis.mouseCompanionMac ? projectId : ''));
  document.getElementById('projects').addEventListener('click', () => navigate('#projects'));
  document.getElementById('open-traditional-desktop').addEventListener('click', () => navigate('#traditional-desktop'));
  window.addEventListener('hashchange', () => showScreen(true));
  window.addEventListener('keydown', event => {
    if (!workspace.hidden) return;
    if (!traditional.hidden && event.key === 'Escape') {
      event.preventDefault();
      navigate('#projects');
    }
    event.stopPropagation();
  }, true);
  window.addEventListener('paste', event => {
    if (workspace.hidden) event.stopPropagation();
  }, true);

  showScreen(false);
  window.setInterval(() => {
    if (!desktop.hidden) updateClock();
  }, 1000);
})();
