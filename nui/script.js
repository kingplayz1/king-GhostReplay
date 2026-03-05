// ============================================================
// GhostReplay Builder v2 — NUI Script
// Handles all message events, navigation, prop palette,
// property inspector, builder mode chips, and settings
// ============================================================

$(document).ready(function () {

    // ──────────────────────────────────────────────
    // STATE
    // ──────────────────────────────────────────────
    let propData = {};     // { Category: [model, ...] }
    let categories = [];     // Ordered category names
    let catIcons = {};     // { Cat: "🔶" }
    let activeCategory = null;
    let activePropIndex = 0;

    // ──────────────────────────────────────────────
    // NUI MESSAGE HANDLER
    // ──────────────────────────────────────────────
    window.addEventListener('message', function (event) {
        const msg = event.data;
        if (!msg || !msg.action) return;

        switch (msg.action) {

            // ── Open main tablet UI ──
            case 'open':
                $('#tablet-wrapper').fadeIn(350);
                updateDashboard(msg.data);
                updateHistory(msg.sessionHistory);
                break;

            // ── Open builder after /trackbuilder ──
            case 'openBuilder':
                $('#tablet-wrapper').fadeIn(350);
                navigateTo('builder');
                if (msg.propData) {
                    propData = msg.propData;
                    categories = msg.categories || Object.keys(propData);
                    catIcons = msg.icons || {};
                    buildCatTabs();
                    if (categories.length > 0) loadCategory(categories[0]);
                }
                break;

            // ── Close ──
            case 'close':
            case 'closeBuilder':
                $('#tablet-wrapper').fadeOut(300);
                break;

            // ── Minimize to game (preview mode) ──
            case 'minimizeBuilder':
                $('#tablet-wrapper').fadeOut(200);
                $('#placement-hud').fadeIn(200);
                break;

            // ── Restore from game preview ──
            case 'restoreBuilder':
                $('#tablet-wrapper').fadeIn(300);
                $('#placement-hud').fadeOut(200);
                break;

            // ── Set placement mode HUD visible ──
            case 'setPlacementMode':
                if (msg.active) {
                    $('#placement-hud').fadeIn(200);
                } else {
                    $('#placement-hud').fadeOut(200);
                }
                break;

            // ── FSM state update ──
            case 'builderStateChange':
                const s = msg.state || 'IDLE';
                const builderOn = (s !== 'IDLE');
                $('#fsm-pill').text(s);
                $('#builder-state-badge').text(s);
                $('.badge-dot').toggleClass('active', builderOn);
                // Highlight correct mode chip
                $('.mode-chip').removeClass('active');
                $(`.mode-chip[data-state="${s}"]`).addClass('active');
                // Update sidebar toggle button
                setBuilderToggleState(builderOn);
                // Auto-navigate to builder page when builder activates
                if (builderOn &&
                    (s === 'ENTER_BUILDER' || s === 'PROP_PREVIEW')) {
                    navigateTo('builder');
                }
                break;

            // ── Legacy state update (backwards compat) ──
            case 'updateBuilderState':
                const s2 = msg.state || 'IDLE';
                $('#fsm-pill').text(s2);
                $('#builder-state-badge').text(s2);
                setBuilderToggleState(s2 !== 'IDLE');
                break;

            // ── Prop category switched (from keyboard ALT+Scroll) ──
            case 'builderCategoryChange':
                if (msg.category) {
                    $('.cat-tab').removeClass('active');
                    $(`.cat-tab[data-cat="${msg.category}"]`).addClass('active');
                    loadCategory(msg.category, msg.propIndex ? msg.propIndex - 1 : 0);
                }
                break;

            // ── Prop changed within category (TAB key) ──
            case 'builderPropChange':
                $('.prop-item').removeClass('active');
                $(`.prop-item[data-model="${msg.prop}"]`).addClass('active');
                activePropIndex = (msg.index || 1) - 1;
                break;

            // ── Inspector sync ──
            case 'syncInspector':
                updateInspector(msg.active, msg.data);
                break;

            // ── Undo/Redo state ──
            case 'updateUndoState':
                $('#undo-btn').prop('disabled', !msg.canUndo);
                $('#redo-btn').prop('disabled', !msg.canRedo);
                $('#undo-depth').text(`${msg.undoDepth} / ${msg.redoDepth}`);
                break;

            // ── Track analysis result ──
            case 'trackAnalysis':
                if (msg.meta) updateAnalysisDisplay(msg.meta);
                break;

            // ── History update ──
            case 'updateHistory':
                updateHistory(msg.sessionHistory);
                break;

            // ── Dashboard update ──
            case 'updateDashboard':
                updateDashboard(msg.data);
                break;
        }
    });

    // ──────────────────────────────────────────────
    // NAVIGATION
    // ──────────────────────────────────────────────
    $(document).on('click', '.nav-item', function () {
        const page = $(this).data('page');
        navigateTo(page);
    });

    function navigateTo(page) {
        $('.nav-item').removeClass('active');
        $(`.nav-item[data-page="${page}"]`).addClass('active');
        $('.page').removeClass('active');
        $(`#page-${page}`).addClass('active');

        if (page === 'props') {
            if (categories.length > 0 && !activeCategory) {
                loadCategory(categories[0]);
            }
        }
    }

    // ──────────────────────────────────────────────
    // BUILDER MODE CHIPS
    // ──────────────────────────────────────────────
    $(document).on('click', '.mode-chip', function () {
        const state = $(this).data('state');
        sendAction('setBuilderFSM', { state });
    });

    // ──────────────────────────────────────────────
    // BUILDER MODE TOGGLE BUTTON (sidebar)
    // ──────────────────────────────────────────────
    $('#builder-toggle-btn').click(function () {
        sendAction('toggleBuilderMode', {});
    });

    function setBuilderToggleState(isActive) {
        const btn = $('#builder-toggle-btn');
        const label = $('#builder-toggle-label');
        const status = $('#builder-toggle-status');

        if (isActive) {
            btn.addClass('active');
            label.text('EXIT BUILDER');
            status.text('ON');
        } else {
            btn.removeClass('active');
            label.text('ENTER BUILDER');
            status.text('OFF');
        }
    }

    // ──────────────────────────────────────────────
    // DASHBOARD BUTTONS
    // ──────────────────────────────────────────────
    $('#start-race').click(() => sendAction('startQuickRace'));
    $('#grid-start').click(() => sendAction('requestGridStart'));
    $('#clear-ghosts').click(() => sendAction('clearGhosts'));
    $('#replay-last').click(() => sendAction('replayLastRun'));

    // ──────────────────────────────────────────────
    // BUILDER BUTTONS
    // ──────────────────────────────────────────────
    $('#build-save').click(() => sendAction('buildAction', { type: 'save' }));
    $('#build-cancel').click(() => sendAction('buildAction', { type: 'exitBuilder' }));
    $('#analyze-track').click(() => sendAction('buildAction', { type: 'analyze' }));
    $('#insp-delete').click(() => sendAction('buildAction', { type: 'deleteSelected' }));

    // ── Undo/Redo from UI ──
    $('#undo-btn').click(() => sendAction('buildAction', { type: 'undo' }));
    $('#redo-btn').click(() => sendAction('buildAction', { type: 'redo' }));

    // ── Snap toggles ──
    $('#snap-grid').change(function () {
        sendAction('builderSetting', { key: 'snapGrid', value: this.checked });
    });
    $('#snap-magnetic').change(function () {
        sendAction('builderSetting', { key: 'snapMagnetic', value: this.checked });
    });
    $('#snap-ground').change(function () {
        sendAction('builderSetting', { key: 'snapGround', value: this.checked });
    });

    // ── Full settings ──
    $('#set-gridsize').change(function () {
        sendAction('builderSetting', { key: 'gridSize', value: parseFloat(this.value) });
    });
    $('.switch').change(function () {
        const id = $(this).attr('id');
        sendAction('updateSetting', { id, value: this.checked });
    });

    // ──────────────────────────────────────────────
    // PROP PALETTE
    // ──────────────────────────────────────────────
    function buildCatTabs() {
        const container = $('#cat-tabs').empty();
        categories.forEach(cat => {
            const icon = catIcons[cat] || '📦';
            const tab = $(`<div class="cat-tab" data-cat="${cat}">${icon} ${cat}</div>`);
            tab.click(function () {
                $('.cat-tab').removeClass('active');
                $(this).addClass('active');
                loadCategory(cat);
                sendAction('builderSetting', { key: 'activeCategory', value: cat });
            });
            container.append(tab);
        });
    }

    function loadCategory(cat, highlightIndex) {
        activeCategory = cat;
        const props = propData[cat] || [];
        const grid = $('#prop-grid').empty();

        props.forEach((model, i) => {
            const shortName = model.replace('prop_', '').replace('stt_', '').replace(/_/g, ' ').toUpperCase();
            const icon = getCategoryIcon(cat);
            const item = $(`
                <div class="prop-item ${i === (highlightIndex || 0) ? 'active' : ''}" data-model="${model}" data-cat="${cat}" data-index="${i}">
                    <div class="prop-icon">${icon}</div>
                    <div class="prop-name">${shortName}</div>
                </div>
            `);
            item.click(function () {
                $('.prop-item').removeClass('active');
                $(this).addClass('active');
                activePropIndex = i;
                sendAction('selectProp', { model, category: cat, index: i });
            });
            grid.append(item);
        });
    }

    function getCategoryIcon(cat) {
        return catIcons[cat] || '📦';
    }

    // ──────────────────────────────────────────────
    // PROPERTY INSPECTOR
    // ──────────────────────────────────────────────
    function updateInspector(active, data) {
        if (active && data) {
            $('#inspector-idle').hide();
            $('#inspector-active').show();
            $('#insp-x').val(formatCoord(data.coords && data.coords.x));
            $('#insp-y').val(formatCoord(data.coords && data.coords.y));
            $('#insp-z').val(formatCoord(data.coords && data.coords.z));
            $('#insp-rx').val(formatCoord(data.rotation && data.rotation.x));
            $('#insp-ry').val(formatCoord(data.rotation && data.rotation.y));
            $('#insp-rz').val(formatCoord(data.rotation && data.rotation.z));
            $('#insp-model').text(data.model || '---');
            $('#insp-snap').text(data.snap ? '✅ ON' : '❌ OFF');
        } else {
            $('#inspector-idle').show();
            $('#inspector-active').hide();
        }
    }

    function formatCoord(v) {
        return (typeof v === 'number') ? v.toFixed(2) : '---';
    }

    // ──────────────────────────────────────────────
    // ANALYSIS DISPLAY
    // ──────────────────────────────────────────────
    function updateAnalysisDisplay(meta) {
        $('#info-class').text(meta.class || '---');
        $('#info-dist').text(meta.distance ? meta.distance + 'm' : '---');
        $('#info-turns').text(meta.turns ?? '---');
        $('#info-diff').text(meta.difficulty ? `${meta.difficulty}/10` : '---');
        $('#info-props').text(meta.propCount ?? '---');
        $('#info-cps').text(meta.checkpointCount ?? '---');
    }

    // ──────────────────────────────────────────────
    // DASHBOARD
    // ──────────────────────────────────────────────
    function updateDashboard(data) {
        if (!data) return;
        $('#active-track').text(data.trackName || 'None');
        $('#track-type').text(data.trackType || '---');
        $('#pb-time').text(data.pbTime || '--:--:---');
        $('#wr-time').text('WR: ' + (data.wrTime || '--:--:---'));

        if (data.lastRun) {
            $('#no-last-run').hide();
            $('#last-run-card').show();
            $('#last-run-time').text(data.lastRun.timeStr);
        } else {
            $('#no-last-run').show();
            $('#last-run-card').hide();
        }
    }

    // ──────────────────────────────────────────────
    // HISTORY
    // ──────────────────────────────────────────────
    function updateHistory(history) {
        const container = $('#history-container').empty();
        if (!history || history.length === 0) {
            container.append('<div class="empty-state">No session history yet.</div>');
            return;
        }
        history.forEach((data, index) => {
            const timeStr = (data.time / 1000).toFixed(2) + 's';
            const el = $(`
                <div class="history-item">
                    <div>
                        <div class="hist-lap">LAP #${history.length - index}</div>
                        <div class="hist-time">${timeStr}</div>
                    </div>
                    <div class="button-row">
                        <button class="btn btn-sm btn-secondary btn-replay" data-idx="${index}">▶ PLAY</button>
                        <button class="btn btn-sm btn-primary btn-chase" data-idx="${index}">🏎 CHASE</button>
                    </div>
                </div>
            `);
            el.find('.btn-replay').click(() => sendAction('playSessionLap', { index }));
            el.find('.btn-chase').click(() => sendAction('startChase', { index }));
            container.append(el);
        });
    }

    // ──────────────────────────────────────────────
    // CLOCK SYNC
    // ──────────────────────────────────────────────
    setInterval(() => {
        const now = new Date();
        const h = String(now.getHours()).padStart(2, '0');
        const m = String(now.getMinutes()).padStart(2, '0');
        $('.tablet-clock').text(`${h}:${m}`);
    }, 1000);

    // ──────────────────────────────────────────────
    // ESC TO CLOSE
    // ──────────────────────────────────────────────
    $(document).keyup(function (e) {
        if (e.key === 'Escape') sendAction('closeUI');
    });

    // ──────────────────────────────────────────────
    // SEND TO LUA
    // ──────────────────────────────────────────────
    function sendAction(action, data) {
        $.post(`https://${GetParentResourceName()}/${action}`, JSON.stringify(data || {}));
    }

});
