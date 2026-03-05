-- ============================================================
-- GhostReplay: Track Builder Prop Configuration
-- Edit this file to add, remove, or rename any builder props.
-- ============================================================

TrackProps = {
    -- ── Categories ── --
    -- Each key is a category displayed in the Prop Palette UI.
    -- Each value is a list of GTA V prop model names.

    Flags = {
        "prop_beachflag_01",
        "prop_flag_eu",
    },

    Arches = {
        "prop_sign_road_01a",
        "prop_gate_airport_01",
        "prop_sign_road_03a",
    },

    Barriers = {
        "prop_barrier_work06a",
        "prop_barrier_work05",
        "prop_barier_conc_05c",
        "prop_barier_conc_04c",
        "prop_tyrewall_01a",
        "prop_tyrewall_02a",
        "prop_snowplough_pile_01",
    },

    Cones = {
        "prop_roadcone01a",
        "prop_roadcone02a",
        "prop_mp_cone_02",
        "prop_bollard_01a",
    },

    Tyres = {
        "prop_rub_tyre_01",
        "prop_rub_tyre_02",
        "prop_rub_tyre_03",
    },

    Lights = {
        "prop_worklight_03a",
        "prop_worklight_04a",
        "prop_wall_light_15a",
        "prop_wall_light_01a",
    },

    Smoke = {
        "prop_smoke_machine",
        "prop_beach_fire",
        "prop_cs_smoke_trail",
    },

    Misc = {
        "prop_jersey_barrier_01",
        "prop_juicbst_sign",
        "prop_dumpster_01a",
        "prop_bench_01a",
    },

    -- ── Checkpoint Gate Styles ──
    -- Used by the new Two-Prop Gate system.
    GateStyles = {
        { name = "Racing Flags", left = "prop_beachflag_01",   right = "prop_beachflag_01" },
        { name = "Tyre Gate",    left = "prop_tyrewall_01a",  right = "prop_tyrewall_01a" },
        { name = "Light Gate",   left = "prop_worklight_03a", right = "prop_worklight_03a" },
        { name = "Smoke Gate",   left = "prop_smoke_machine", right = "prop_smoke_machine" },
    },
}

-- ── Category Display Order ──
-- Controls the order categories appear in the UI palette.
TrackPropCategoryOrder = {
    "Arches", "Barriers", "Cones", "Tyres", "Lights", "Flags", "Smoke", "Misc"
}

-- ── Category Icons (Emoji) ──
-- Shown in the NUI palette header button for each category.
TrackPropCategoryIcons = {
    Arches   = "🏛️",
    Barriers = "🚧",
    Cones    = "🔶",
    Tyres    = "🔘",
    Lights   = "💡",
    Flags    = "🚩",
    Smoke    = "💨",
    Misc     = "📦",
}
