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
const policeCallerHint = document.getElementById('police-caller-hint');
const policeClock = document.getElementById('police-clock');
const policeDate = document.getElementById('police-date');
const policeCamId = document.getElementById('police-cam-id');
const cameraList = document.getElementById('camera-list');
const btnAnswer = document.getElementById('btn-answer');
const btnUnlock = document.getElementById('btn-unlock');
const btnClose = document.getElementById('btn-close');
const visitorHangupHint = document.getElementById('visitor-hangup-hint');
const barBtnAnswer = document.getElementById('bar-btn-answer');
const barBtnUnlock = document.getElementById('bar-btn-unlock');
const barBtnClose = document.getElementById('bar-btn-close');

let visitorInterval = null;
let policeClockInterval = null;
let visitorSeconds = 0;
let audioCtx = null;
let camerasLocked = false;

function postNui(event, data = {}) {
    const resourceName = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName()
        : 'dmss_videointercom';
    fetch(`https://${resourceName}/${event}`, {
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
        ring:     { freq: 880, duration: 0.15, repeat: 2, gap: 0.2  },
        doorbell: { freq: 660, duration: 0.25, repeat: 2, gap: 0.15 },
        answer:   { freq: 523, duration: 0.12, repeat: 1, gap: 0    },
        cctvOn:   { freq: 440, duration: 0.08, repeat: 1, gap: 0    },
        unlock:   { freq: 784, duration: 0.2,  repeat: 2, gap: 0.1  },
        callEnd:  { freq: 330, duration: 0.3,  repeat: 1, gap: 0    },
    };

    const tone = tones[type] || tones.answer;

    const play = () => {
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
    };

    if (ctx.state === 'suspended') {
        ctx.resume().then(play);
    } else {
        play();
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
    if (barBtnUnlock) {
        barBtnUnlock.disabled = !enabled;
        barBtnUnlock.classList.toggle('disabled', !enabled);
    }
}

function setAnswerVisible(visible) {
    btnAnswer.classList.toggle('hidden', !visible);
    if (barBtnAnswer) barBtnAnswer.classList.toggle('hidden', !visible);
}

function showVisitor(data) {
    visitorDevice.classList.remove('answered');
    visitorLedRed.classList.add('active');
    visitorStatus.textContent = 'In attesa di risposta...';
    visitorLocation.textContent = data.location || 'Centralino';
    visitorFooterText.textContent = 'In attesa di risposta dal personale';
    visitorPanel.classList.remove('hidden');
    if (visitorHangupHint) visitorHangupHint.classList.remove('hidden');
    startVisitorTimer();
}

function updateVisitorAnswered() {
    visitorDevice.classList.add('answered');
    visitorLedRed.classList.remove('active');
    visitorStatus.textContent = 'Centralino in ascolto';
    visitorFooterText.textContent = 'Parla al microfono · il centralino ti sente';
}

function hideVisitor() {
    visitorPanel.classList.add('hidden');
    if (visitorHangupHint) visitorHangupHint.classList.add('hidden');
    stopVisitorTimer();
}

function renderCameraList(cameras, activeIndex) {
    if (!cameraList) return;
    cameraList.innerHTML = '';

    if (!cameras || cameras.length === 0) return;

    cameras.forEach((cam) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'camera-btn';
        if (cam.index === activeIndex) btn.classList.add('active');
        if (camerasLocked) btn.classList.add('disabled');
        btn.textContent = cam.label || `CAM-${cam.index}`;
        btn.disabled = camerasLocked;
        btn.addEventListener('click', () => {
            if (cam.index === activeIndex || camerasLocked) return;
            postNui('switchCamera', { index: cam.index });
        });
        cameraList.appendChild(btn);
    });
}

function updatePoliceCamera(data) {
    policeCamId.textContent = data.camera || policeCamId.textContent;
    if (data.lockCameras !== undefined) camerasLocked = data.lockCameras === true;
    renderCameraList(data.cameras, data.activeCamera);
}

function updateIntercomUi(data) {
    if (data.caller) policeCaller.textContent = data.caller;

    if (data.callerHint && policeCallerHint) {
        policeCallerHint.textContent = data.callerHint;
    }

    if (data.hasPendingCall !== undefined) {
        setAnswerVisible(data.hasPendingCall === true);
    }

    if (data.canUnlock !== undefined) {
        setUnlockEnabled(data.canUnlock === true);
    }

    if (data.lockCameras !== undefined) {
        camerasLocked = data.lockCameras === true;
        if (data.cameras) {
            renderCameraList(data.cameras, data.activeCamera || 1);
        }
    }

    if (data.camera) {
        policeCamId.textContent = data.camera;
    }
}

function showPolice(data) {
    camerasLocked = data.lockCameras === true;

    policeCaller.textContent = data.caller || 'Nessuna chiamata';
    policeCamId.textContent = data.camera || 'CAM-01 · INGRESSO SX';

    if (policeCallerHint) {
        if (data.canUnlock) {
            policeCallerHint.textContent = 'In linea · parla al microfono';
        } else if (data.hasPendingCall) {
            policeCallerHint.textContent = 'Sta suonando all\'ingresso';
        } else {
            policeCallerHint.textContent = 'In attesa di un visitatore';
        }
    }

    renderCameraList(data.cameras, data.activeCamera || 1);
    policePanel.classList.remove('hidden');

    setAnswerVisible(data.hasPendingCall === true);
    setUnlockEnabled(data.canUnlock === true);

    startPoliceClock();
}

function hidePolice() {
    policePanel.classList.add('hidden');
    setAnswerVisible(false);
    setUnlockEnabled(false);
    camerasLocked = false;
    if (cameraList) cameraList.innerHTML = '';
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
        case 'updateIntercom':
            updateIntercomUi(data);
            break;
        case 'updateCamera':
            updatePoliceCamera(data);
            break;
        case 'hidePolice':
            hidePolice();
            break;
        case 'playSound':
            if (sound) playUiTone(sound);
            break;
        case 'enableUnlock':
            setAnswerVisible(false);
            setUnlockEnabled(true);
            break;
    }
});

btnHangup.addEventListener('click', () => postNui('hangUpCall'));
btnAnswer.addEventListener('click', () => postNui('answerCall'));
if (barBtnAnswer) barBtnAnswer.addEventListener('click', () => postNui('answerCall'));
btnUnlock.addEventListener('click', () => {
    if (!btnUnlock.disabled) postNui('unlockDoor');
});
if (barBtnUnlock) {
    barBtnUnlock.addEventListener('click', () => {
        if (!barBtnUnlock.disabled) postNui('unlockDoor');
    });
}
btnClose.addEventListener('click', () => postNui('closeMonitor'));
if (barBtnClose) barBtnClose.addEventListener('click', () => postNui('closeMonitor'));

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !visitorPanel.classList.contains('hidden')) {
        postNui('hangUpCall');
        return;
    }

    if (e.key === 'Escape' && !policePanel.classList.contains('hidden')) {
        postNui('closeMonitor');
    }
});
