(() => {
  const enabled = navigator.maxTouchPoints > 0 || matchMedia('(pointer: coarse)').matches;
  let move = [0, 0];
  let actions = [];
  window.swordsterReadInput = () => {
    const result = JSON.stringify({ enabled, move, actions });
    actions = [];
    return result;
  };
  if (!enabled) return;
  document.documentElement.classList.add('mobile-game');
  const controls = document.createElement('div');
  controls.id = 'touch-controls';
  controls.innerHTML = `
    <div id="move-stick" aria-label="Movement joystick"><span id="stick-knob"></span></div>
    <div class="touch-actions">
      <div class="touch-row"><button data-action="pause">PAUSE</button><button data-action="ranges">RANGES</button><button data-action="restart">RESTART</button></div>
      <div class="touch-row"><button class="ult" data-action="ult" data-slot="0">ULT 1</button><button class="ult" data-action="ult" data-slot="1">ULT 2</button><button class="ult" data-action="ult" data-slot="2">ULT 3</button></div>
      <div class="touch-row"><button data-action="swap" data-slot="0">SLOT 1</button><button data-action="swap" data-slot="1">SLOT 2</button><button data-action="swap" data-slot="2">SLOT 3</button></div>
      <div class="touch-row"><button class="primary" data-action="dash">DASH</button><button class="primary strike" data-action="converge">STRIKE</button><button data-action="fullscreen" aria-label="Fullscreen">⛶</button></div>
    </div>`;
  document.body.append(controls);
  const stick = document.getElementById('move-stick');
  const knob = document.getElementById('stick-knob');
  let stickPointer = null;
  function reset() {
    stickPointer = null;
    move = [0, 0];
    knob.style.transform = 'translate(-50%, -50%)';
  }
  function steer(event) {
    const rect = stick.getBoundingClientRect();
    const radius = rect.width * 0.34;
    let x = (event.clientX - rect.left - rect.width / 2) / radius;
    let y = (event.clientY - rect.top - rect.height / 2) / radius;
    const length = Math.hypot(x, y);
    if (length > 1) { x /= length; y /= length; }
    move = length < 0.12 ? [0, 0] : [x, y];
    knob.style.transform = `translate(calc(-50% + ${x * radius}px), calc(-50% + ${y * radius}px))`;
  }
  stick.addEventListener('pointerdown', event => {
    if (stickPointer !== null) return;
    event.preventDefault();
    stickPointer = event.pointerId;
    stick.setPointerCapture(stickPointer);
    steer(event);
  });
  stick.addEventListener('pointermove', event => {
    if (event.pointerId === stickPointer) steer(event);
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    stick.addEventListener(type, event => { if (event.pointerId === stickPointer) reset(); });
  }
  controls.querySelectorAll('button').forEach(button => {
    button.addEventListener('pointerdown', event => {
      event.preventDefault();
      if (button.dataset.action === 'fullscreen') {
        const request = document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen?.();
        request?.catch(() => {});
        return;
      }
      actions.push({ name: button.dataset.action, slot: Number(button.dataset.slot || 0) });
    });
  });
  document.getElementById('canvas').addEventListener('pointerdown', event => {
    const rect = event.currentTarget.getBoundingClientRect();
    actions.push({ name: 'aim', x: (event.clientX - rect.left) / rect.width * 1280,
                  y: (event.clientY - rect.top) / rect.height * 720 });
  });
  window.addEventListener('blur', () => { reset(); actions = []; });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { reset(); actions = [{ name: 'suspend' }]; }
  });
})();
