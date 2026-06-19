Config = {}

-- Citofono: punto base + heading muro
Config.IntercomProp = vec4(5611.8848, -3122.9387, 8.6942, 268.0362)

-- Offset locale (avanti = staccato dal muro, destra, alto)
Config.PropOffset = vec3(0.12, 0.0, 1.1)

-- prop_gatecom_01 = citofono verticale | prop_ld_keypad_01 = tastierino
Config.IntercomModel = `prop_ld_keypad_01`

Config.UseVisualProp = true
Config.InteractRadius = 1.0
Config.SpawnDistance = 80.0

-- Monitor polizia
Config.PoliceMonitor = vec4(5627.8, -3135.5, 11.1454, 275.0)
Config.PoliceMonitorSize = vec3(0.8, 0.8, 1.2)

Config.CamOffset = vec3(0.5, -2.8, 1.6)
Config.DoorlockId = 1
Config.LocationLabel = 'Centralino'
Config.CameraLabel = 'CAM-01 · INGRESSO PRINCIPALE'
Config.VisitorTimeout = 60000
Config.Debug = false
Config.EditorAce = 'command.intercomeditor'
