Config = {}



-- ── Citofono ────────────────────────────────────────────────────────

Config.IntercomProp = vec4(5611.8848, -3122.9387, 8.6942, 268.0362)

Config.PropDepth = -0.02

Config.PropOffset = vec3(0.0, 0.30, 0.5)

Config.PropRotation = vec3(0.0, 0.0, 0.0)



Config.IntercomModel = `prop_ld_keypad_01`

Config.UseVisualProp = true

Config.InteractRadius = 2.0

Config.SpawnDistance = 80.0

-- Attesa caricamento MLO/interior prima dello spawn (ms)

Config.InteriorLoadTimeout = 15000

Config.SpawnMaxAttempts = 15

Config.SpawnRetryDelay = 2500

Config.SpawnMaintainInterval = 2000



-- ── Telecamere CCTV ─────────────────────────────────────────────────
-- virtual = true: solo feed (nessun prop), tipicamente integrata nel citofono
-- intercomFeed: cam usata quando si risponde al citofono (volto visitatore)
-- monitorFeed: cam selezionabile nel monitor di sorveglianza

Config.CctvProps = {

    {

        label = 'CIT · VISITATORE',

        virtual = true,

        feedOffset = vec3(0.0, 0.10, 1.42),

        feedPitch = -10.0,

        feedFov = 40.0,

        intercomFeed = true,

        monitorFeed = true,

    },

    {

        label = 'CAM-01 · INGRESSO CITOFONO',

        model = `prop_cctv_cam_04a`,

        coords = vec4(5612.3066, -3122.3130, 10.9600, 268.0),

        propOffset = vec3(0.0, 0.0, 0.0),

        depth = 0.0,

        rotation = vec3(0.0, 0.0, 0.0),

        feedView = vec4(5611.0845, -3122.1223, 12.9319, 163.8805),

        feedPitch = -12.0,

        feedFov = 60.0,

        monitorFeed = true,

    },

    {

        label = 'CAM-02 · INGRESSO PRINCIPALE',

        model = `prop_cctv_pole_04`,

        coords = vec4(5615.1562, -3119.0627, 10.8450, 105.0),

        propOffset = vec3(0.0, 0.0, 0.0),

        depth = 0.0,

        rotation = vec3(0.0, 0.0, 0.0),

        feedView = vec4(5615.6694, -3119.4661, 16.5735, 226.8939),

        feedPitch = -30.0,

        feedFov = 60.0,

        monitorFeed = true,

    },

}



-- Alterna CIT + CAM-01 sul monitor mentre suona il citofono (entrambe visibili a rotazione)

Config.DualCamPreviewOnRing = true

Config.DualCamPreviewInterval = 3000



-- intercomFeed: telecamera usata quando si risponde al citofono

-- monitorFeed: telecamere visibili nel monitor di sorveglianza

Config.IntercomCameraIndex = 1

-- PoliceMonitor: base + heading | PoliceMonitorOffset: Y destra, Z alto

-- PoliceMonitorRadius: raggio interazione sphere zone

-- PoliceJob: nome job Qbox (deve essere in servizio / on duty)



Config.PoliceJob = 'police'

Config.PoliceRequireDuty = true

Config.PoliceMonitor = vec4(5639.2100, -3137.3723, 11.1186, 125.0196)

Config.PoliceMonitorOffset = vec3(0.0, 0.0, 0.0)

Config.PoliceMonitorRadius = 2.5



Config.DoorlockId = 1152

Config.LocationLabel = 'Centralino'

Config.VisitorTimeout = 60000

-- Comunicazione vocale durante la chiamata citofono (pma-voice)

Config.VoiceEnabled = true

Config.VoiceResource = 'pma-voice'

Config.VoiceCallVolume = 100

-- Metri proximity durante chiamata: la voce va SOLO sul canale call (visitatore <-> polizia).
-- 0.01 = praticamente zero leak in proximity. Richiede server.cfg: setr voice_enableCalls 1

Config.VoiceProximityOverride = 0.01

Config.Debug = false


