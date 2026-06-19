Config = {}



-- ── Posizione citofono (solo config, nessun editor in-game) ───────────

--

-- IntercomProp: punto base sul muro + heading (gradi, direzione verso la stanza)

-- PropOffset:   offset locale rispetto al punto base

--   X = profondità (avanti, staccato dal muro)

--   Y = destra

--   Z = altezza

-- PropRotation: rotazione euler aggiuntiva (pitch, roll, extra heading)

--   Per prop_ld_keypad_01 usa di solito vec3(0, 90, 0)

--   Per prop_gatecom_01 usa vec3(0, 0, 0) — solo heading da IntercomProp.w



Config.IntercomProp = vec4(5611.8848, -3122.9387, 8.6942, 268.0362)

Config.PropOffset = vec3(0.06, 0.0, 0.5)

Config.PropRotation = vec3(0.0, 0.0, 0.0)



-- prop_gatecom_01 = citofono verticale | prop_ld_keypad_01 = tastierino

Config.IntercomModel = `prop_ld_keypad_01`



Config.UseVisualProp = true

Config.InteractRadius = 1.2

Config.SpawnDistance = 80.0



-- ── Monitor polizia ─────────────────────────────────────────────────

Config.PoliceMonitor = vec4(5627.8, -3135.5, 11.1454, 275.0)

Config.PoliceMonitorSize = vec3(0.8, 0.8, 1.2)



-- Offset telecamera CCTV rispetto al prop (avanti, indietro, alto)

Config.CamOffset = vec3(0.5, -2.8, 1.6)



Config.DoorlockId = 1

Config.LocationLabel = 'Centralino'

Config.CameraLabel = 'CAM-01 · INGRESSO PRINCIPALE'

Config.VisitorTimeout = 60000

Config.Debug = false


