$(document).ready(function () {
    const PROP_DATA = {
        barriers: [
            { id: "barrier1", name: "Orange Plastic", model: "prop_barrier_work06a" },
            { id: "barrier2", name: "Concrete Wall", model: "prop_barier_conc_05c" },
            { id: "barrier3", name: "Tire Wall", model: "prop_tyrewall_01a" }
        ],
        cones: [
            { id: "cone1", name: "Traffic Cone", model: "prop_roadcone01a" },
            { id: "cone2", name: "Bollard", model: "prop_bollard_01a" }
        ],
        lights: [
            { id: "light1", name: "Floodlight", model: "prop_worklight_03a" },
            { id: "light2", name: "Neon Pole", model: "v_ilev_neon_light" }
        ],
        markers: [
            { id: "marker1", name: "Start Arch", model: "stt_prop_stunt_arch_01" },
            { id: "marker2", name: "Chequered Flag", model: "prop_flag_finish" }
        ]
    };

    window.addEventListener('message', function (event) {
        const item = event.data;

        if (item.action === "open") {
            $("#tablet-wrapper").fadeIn(400);
            updateDashboard(item.data);
            updateHistory(item.sessionHistory);
        } else if (item.action === "close") {
            $("#tablet-wrapper").fadeOut(400);
        } else if (item.action === "updateHistory") {
            updateHistory(item.sessionHistory);
        } else if (item.action === "setPlacementMode") {
            if (item.active) {
                $("#placement-hud").fadeIn(200);
                $("#tablet-wrapper").fadeOut(200);
                if (item.subState) $("#current-substate").text(item.subState);
            } else {
                $("#placement-hud").fadeOut(200);
            }
        } else if (item.action === "updateBuilderState") {
            $("#current-builder-state").text(item.state);
            $(".mode-btn").removeClass("active");
            $(`.mode-btn[data-state="${item.state}"]`).addClass("active");
        } else if (item.action === "syncInspector") {
            if (item.active && item.data) {
                $("#inspector-idle").hide();
                $("#inspector-active").show();
                $("#insp-x").val(item.data.coords.x.toFixed(2));
                $("#insp-y").val(item.data.coords.y.toFixed(2));
                $("#insp-z").val(item.data.coords.z.toFixed(2));
                $("#insp-rx").val(item.data.rotation.x.toFixed(2));
                $("#insp-ry").val(item.data.rotation.y.toFixed(2));
                $("#insp-rz").val(item.data.rotation.z.toFixed(2));
                $("#insp-model").text(item.data.model || "Unknown");
            } else {
                $("#inspector-idle").show();
                $("#inspector-active").hide();
            }
        }
    });


    // NAVIGATION
    $(".nav-item").click(function () {
        const page = $(this).data("page");
        $(".nav-item").removeClass("active");
        $(this).addClass("active");

        $(".page").removeClass("active");
        $(`#page-${page}`).addClass("active");

        if (page === "props") {
            loadCategory("barriers");
        }
    });

    // MODE SELECTOR (FSM)
    $(".mode-btn").click(function () {
        const state = $(this).data("state");
        if (state === "PROP_PALETTE") {
            // Special case: switch to prop page
            $(".nav-item[data-page='props']").click();
            return;
        }
        sendAction("setBuilderState", { state: state });
    });

    // PROP CATEGORIES
    $(".tab").click(function () {
        $(".tab").removeClass("active");
        $(this).addClass("active");
        loadCategory($(this).data("cat"));
    });

    function loadCategory(cat) {
        const container = $("#prop-palette");
        container.empty();

        if (PROP_DATA[cat]) {
            PROP_DATA[cat].forEach(prop => {
                const el = $(`
                    <div class="prop-item" data-model="${prop.model}">
                        <div class="prop-icon">📦</div>
                        <div class="prop-name">${prop.name}</div>
                    </div>
                `);

                el.click(function () {
                    sendAction("selectProp", { model: prop.model });
                });

                container.append(el);
            });
        }
    }

    // ACTIONS
    $("#start-race").click(function () { sendAction("startQuickRace"); });
    $("#grid-start").click(function () { sendAction("requestGridStart"); });
    $("#clear-ghosts").click(function () { sendAction("clearGhosts"); });
    $("#replay-last").click(function () { sendAction("replayLastRun"); });

    // BUILDER ACTIONS
    $("#build-start-l").click(function () { sendAction("buildAction", { type: "setStart", side: "left" }); });
    $("#build-start-r").click(function () { sendAction("buildAction", { type: "setStart", side: "right" }); });
    $("#build-start-auto").click(function () { sendAction("buildAction", { type: "autoLink", side: "start" }); });
    $("#build-finish-l").click(function () { sendAction("buildAction", { type: "setFinish", side: "left" }); });
    $("#build-finish-r").click(function () { sendAction("buildAction", { type: "setFinish", side: "right" }); });
    $("#build-finish-auto").click(function () { sendAction("buildAction", { type: "autoLink", side: "finish" }); });
    $("#build-waypoint").click(function () { sendAction("buildAction", { type: "addWaypoint" }); });
    $("#build-zone").click(function () { sendAction("buildAction", { type: "startZone" }); });
    $("#build-save").click(function () { sendAction("buildAction", { type: "save" }); });
    $("#build-cancel").click(function () { sendAction("buildAction", { type: "cancel" }); });

    // SETTINGS ACTIONS
    $(".switch").change(function () {
        const id = $(this).attr("id");
        const val = $(this).is(":checked");
        sendAction("updateSetting", { id: id, value: val });
    });

    // CLOSE ON ESC
    $(document).keyup(function (e) {
        if (e.key === "Escape") {
            sendAction("closeUI");
        }
    });

    function updateDashboard(data) {
        if (!data) return;
        $("#active-track").text(data.trackName || "None");
        $("#track-type").text(data.trackType || "---");
        $("#pb-time").text(data.pbTime || "--:--:---");
        $("#wr-time").text(data.wrTime || "--:--:---");

        if (data.lastRun) {
            $("#no-last-run").hide();
            $("#last-run-card").show();
            $("#last-run-time").text(data.lastRun.timeStr);
        } else {
            $("#no-last-run").show();
            $("#last-run-card").hide();
        }
    }

    function updateHistory(history) {
        const container = $("#history-container");
        container.empty();

        if (!history || history.length === 0) {
            container.append('<div class="empty-state">No session history yet.</div>');
            return;
        }

        history.forEach((data, index) => {
            const timeStr = (data.time / 1000).toFixed(2) + "s";
            const el = $(`
                <div class="history-item">
                    <div class="hist-info">
                        <span class="hist-lap">LAP #${history.length - index}</span>
                        <span class="hist-time">${timeStr}</span>
                    </div>
                    <div class="hist-actions">
                        <button class="btn btn-sm btn-replay" data-idx="${index}">PLAY</button>
                        <button class="btn btn-sm btn-primary btn-chase" data-idx="${index}">CHASE</button>
                    </div>
                </div>
            `);

            el.find(".btn-replay").click(function () {
                sendAction("playSessionLap", { index: index });
            });

            el.find(".btn-chase").click(function () {
                sendAction("startChase", { index: index });
            });

            container.append(el);
        });
    }

    function sendAction(action, data) {
        $.post(`https://${GetParentResourceName()}/${action}`, JSON.stringify(data || {}));
    }

    // CLOCK SYNC
    setInterval(() => {
        const now = new Date();
        const time = now.getHours().toString().padStart(2, '0') + ":" + now.getMinutes().toString().padStart(2, '0');
        $(".tablet-clock").text(time);
    }, 1000);
});
