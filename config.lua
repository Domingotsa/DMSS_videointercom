Config = {}

-- Prop 3D del citofono (x, y, z, heading)
Config.IntercomProp = vec4(5629.6636, -3136.2673, 12.1455, 275.2273)

-- Modello GTA del citofono
Config.IntercomModel = `hei_prop_hei_keypad_03`

-- Punto monitor polizia: dove aprire il menu centralino (x, y, z, rotation)
Config.PoliceMonitor = vec4(5627.8, -3135.5, 12.1455, 275.0)

-- Offset telecamera rispetto al prop (x, y, z)
Config.CamOffset = vec3(0.5, -2.8, 1.6)

-- ID serratura in ox_doorlock
Config.DoorlockId = 1

-- Etichette UI
Config.LocationLabel = 'Centralino'
Config.CameraLabel = 'CAM-01 · INGRESSO PRINCIPALE'

-- Timeout attesa risposta visitatore (ms)
Config.VisitorTimeout = 60000
