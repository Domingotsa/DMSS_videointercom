const visitorPanel = document.getElementById('visitor-panel');
const policePanel = document.getElementById('police-panel');
const visitorStatus = document.getElementById('visitor-status');
const visitorLocation = document.getElementById('visitor-location');
const visitorTimer = document.getElementById('visitor-timer');
const visitorLedRed = document.getElementById('visitor-led-red');
const visitorDevice = document.querySelector('.visitor-device');
const visitorFooterText = document.getElementById('visitor-footer-text');
const btnHangup = document.getElementById('btn-hangup');
const policeCaller = document.getElementById('police-caller');
const policeClock = document.getElementById('police-clock');
const policeDate = document.getElementById('police-date');
const policeCamId = document.getElementById('police-cam-id');
const btnAnswer = document.getElementById('btn-answer');
const btnUnlock = document.getElementById('btn-unlock');
const btnClose = document.getElementById('btn-close');

let visitorInterval = null;
let policeClockInterval = null;
let visitorSeconds = 0;
let audioCtx = null;

function postNui(event, data = {}) {
    fetch(`https://${GetParentResourceName()}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
}

function getAudioContext() {
    if (!audioCtx) {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    return audioCtx;
}

function playUiTone(type) {
    const ctx = getAudioContext();

    const tones = {
        ring: { freq: 880, duration: 0.15, repeat: 2, gap: 0.2 },
        doorbell: { freq: 660, duration: 0.25, repeat: 2, gap: 0.15 },
        answer: { freq: 523, duration: 0.12, repeat: 1, gap: 0 },
        cctvOn: { freq: 440, duration: 0.08, repeat: 1, gap: 0 },
        unlock: { freq: 784, duration: 0.2, repeat: 2, gap: 0.1 },
        callEnd: { freq: 330, duration: 0.3, repeat: 1, gap: 0 },
    };

    const tone = tones[type] || tones.answer;
    let start = ctx.currentTime;

    for (let i = 0; i < tone.repeat; i += 1) {
        const o = ctx.createOscillator();
        const g = ctx.createGain();
        o.type = 'sine';
        o.frequency.value = tone.freq + (i * 40);
        o.connect(g);
        g.connect(ctx.destination);
        g.gain.setValueAtTime(0.0001, start);
        g.gain.exponentialRampToValueAtTime(0.08, start + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, start + tone.duration);
        o.start(start);
        o.stop(start + tone.duration);
        start += tone.duration + tone.gap;
    }
}

function formatTime(seconds) {
    const m = Math.floor(seconds / 60).toString().padStart(2, '0');
    const s = (seconds % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
}

function startVisitorTimer() {
    visitorSeconds = 0;
    visitorTimer.textContent = formatTime(0);
    clearInterval(visitorInterval);
    visitorInterval = setInterval(() => {
        visitorSeconds += 1;
        visitorTimer.textContent = formatTime(visitorSeconds);
    }, 1000);
}

function stopVisitorTimer() {
    clearInterval(visitorInterval);
    visitorInterval = null;
}

function startPoliceClock() {
    const tick = () => {
        const now = new Date();
        policeClock.textContent = now.toLocaleTimeString('it-IT', { hour12: false });
        policeDate.textContent = now.toLocaleDateString('it-IT');
    };
    tick();
    clearInterval(policeClockInterval);
    policeClockInterval = setInterval(tick, 1000);
}

function stopPoliceClock() {
    clearInterval(policeClockInterval);
    policeClockInterval = null;
}

function setUnlockEnabled(enabled) {
    btnUnlock.disabled = !enabled;
    btnUnlock.classList.toggle('disabled', !enabled);
}

function showVisitor(data) {
    visitorDevice.classList.remove('answered');
    visitorLedRed.classList.add('active');
    visitorStatus.textContent = 'In attesa di risposta...';
    visitorLocation.textContent = data.location || 'Centralino';
    visitorFooterText.textContent = 'In attesa di risposta dal personale';
    visitorPanel.classList.remove('hidden');
    startVisitorTimer();
}

function updateVisitorAnswered() {
    visitorDevice.classList.add('answered');
    visitorLedRed.classList.remove('active');
    visitorStatus.textContent = 'Centralino in ascolto';
    visitorFooterText.textContent = 'Sei in linea con il centralino';
}

function hideVisitor() {
    visitorPanel.classList.add('hidden');
    stopVisitorTimer();
}

function showPolice(data) {
    policeCaller.textContent = data.caller || 'Sconosciuto';
    policeCamId.textContent = data.camera || 'CAM-01 · INGRESSO PRINCIPALE';
    policePanel.classList.remove('hidden');

    const answered = data.canUnlock === true;
    btnAnswer.classList.toggle('hidden', answered);
    setUnlockEnabled(answered);

    startPoliceClock();
}

function hidePolice() {
    policePanel.classList.add('hidden');
    btnAnswer.classList.add('hidden');
    setUnlockEnabled(false);
    stopPoliceClock();
}

window.addEventListener('message', (event) => {
    const { action, sound, ...data } = event.data;

    switch (action) {
        case 'showVisitor':
            showVisitor(data);
            break;
        case 'visitorAnswered':
            updateVisitorAnswered();
            break;
        case 'hideVisitor':
            hideVisitor();
            break;
        case 'showPolice':
            showPolice(data);
            break;
        case 'hidePolice':
            hidePolice();
            break;
        case 'playSound':
            if (sound) playUiTone(sound);
            break;
        case 'enableUnlock':
            btnAnswer.classList.add('hidden');
            setUnlockEnabled(true);
            break;
    }
});

btnHangup.addEventListener('click', () => postNui('hangUpCall'));
btnAnswer.addEventListener('click', () => postNui('answerCall'));
btnUnlock.addEventListener('click', () => {
    if (!btnUnlock.disabled) postNui('unlockDoor');
});
btnClose.addEventListener('click', () => postNui('closeMonitor'));

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !visitorPanel.classList.contains('hidden')) {
        postNui('hangUpCall');
        return;
    }

    if (e.key === 'Escape' && !policePanel.classList.contains('hidden')) {
        postNui('closeMonitor');
    }
});
