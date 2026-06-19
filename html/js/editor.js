const editorOverlay = document.getElementById('editor-overlay');
const editorHitLabel = document.getElementById('editor-hit-label');
const editorModeTitle = document.getElementById('editor-mode-title');
const editorHelpList = document.getElementById('editor-help-list');

let editorDragging = false;
let editorActive = false;

function editorPost(event, data = {}) {
    const resourceName = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName()
        : 'dmss_videointercom';
    fetch(`https://${resourceName}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
    });
}

function setEditorHelp(mode) {
    if (mode === 'monitor') {
        editorModeTitle.textContent = 'Editor Monitor';
        editorHelpList.innerHTML = `
            <li><strong>Click sinistro</strong> — posiziona monitor</li>
            <li><strong>Trascina</strong> — sposta punto</li>
            <li><strong>Rotella</strong> — su / giù</li>
            <li><strong>Shift + rotella</strong> — ruota</li>
        `;
        return;
    }

    editorModeTitle.textContent = 'Editor Prop Citofono';
    editorHelpList.innerHTML = `
        <li><strong>Click sinistro</strong> — posiziona sul muro</li>
        <li><strong>Trascina</strong> — sposta prop</li>
        <li><strong>Rotella</strong> — altezza</li>
        <li><strong>Shift + rotella</strong> — ruota heading</li>
        <li><strong>Click destro</strong> — base sotto di te</li>
    `;
}

function showEditorOverlay(mode) {
    editorActive = true;
    editorDragging = false;
    setEditorHelp(mode);
    editorOverlay.classList.add('active');
    editorOverlay.classList.remove('dragging');
    editorHitLabel.textContent = 'Punta il muro e clicca';
}

function hideEditorOverlay() {
    editorActive = false;
    editorDragging = false;
    editorOverlay.classList.remove('active');
    editorOverlay.classList.remove('dragging');
}

editorOverlay.addEventListener('mousedown', (event) => {
    if (!editorActive || event.target.closest('.editor-panel')) return;

    if (event.button === 0) {
        editorDragging = true;
        editorOverlay.classList.add('dragging');
        editorPost('editorPointer', {
            type: 'down',
            x: event.clientX,
            y: event.clientY,
            button: 0,
        });
    } else if (event.button === 2) {
        event.preventDefault();
        editorPost('editorPointer', {
            type: 'down',
            x: event.clientX,
            y: event.clientY,
            button: 2,
        });
    }
});

editorOverlay.addEventListener('mousemove', (event) => {
    if (!editorActive || event.target.closest('.editor-panel')) return;

    editorPost('editorPointer', {
        type: 'move',
        x: event.clientX,
        y: event.clientY,
        dragging: editorDragging,
    });
});

editorOverlay.addEventListener('mouseup', (event) => {
    if (!editorActive || event.target.closest('.editor-panel')) return;

    if (event.button === 0 && editorDragging) {
        editorDragging = false;
        editorOverlay.classList.remove('dragging');
    }

    editorPost('editorPointer', {
        type: 'up',
        x: event.clientX,
        y: event.clientY,
        button: event.button,
        dragging: false,
    });
});

editorOverlay.addEventListener('wheel', (event) => {
    if (!editorActive || event.target.closest('.editor-panel')) return;
    event.preventDefault();

    editorPost('editorPointer', {
        type: 'scroll',
        delta: event.deltaY,
        shift: event.shiftKey,
    });
}, { passive: false });

editorOverlay.addEventListener('contextmenu', (event) => {
    if (editorActive) event.preventDefault();
});

document.getElementById('editor-save').addEventListener('click', () => editorPost('editorAction', { action: 'save' }));
document.getElementById('editor-cancel').addEventListener('click', () => editorPost('editorAction', { action: 'cancel' }));
document.getElementById('editor-snap').addEventListener('click', () => editorPost('editorAction', { action: 'snap' }));

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    if (data.action === 'showEditor') {
        showEditorOverlay(data.mode || 'prop');
    }

    if (data.action === 'hideEditor') {
        hideEditorOverlay();
    }

    if (data.action === 'editorHitLabel') {
        editorHitLabel.textContent = data.text || '';
    }
});
