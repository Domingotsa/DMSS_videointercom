Config = {}



-- ── Citofono ────────────────────────────────────────────────────────

Config.IntercomProp = vec4(5611.8848, -3122.9387, 8.6942, 268.0362)

Config.PropDepth = -0.02

Config.PropOffset = vec3(0.0, 0.35, 0.5)

Config.PropRotation = vec3(0.0, 0.0, 0.0)



Config.IntercomModel = `prop_ld_keypad_01`

Config.UseVisualProp = true

Config.InteractRadius = 2.0

Config.SpawnDistance = 80.0



-- ── Telecamere CCTV ─────────────────────────────────────────────────

Config.CctvProps = {

    {

        label = 'CAM-01 · INGRESSO SX',

        model = `prop_cctv_cam_04a`,

        coords = vec4(5612.3066, -3122.3130, 10.9600, 268.0),

        propOffset = vec3(0.0, 0.0, 0.0),

        depth = 0.0,

        rotation = vec3(0.0, 0.0, 0.0),

        feedView = vec4(5611.4189, -3122.3662, 12.8084, 268.0),

        feedPitch = -12.0,

        feedFov = 55.0,

        intercomFeed = true,

        monitorFeed = true,

    },

    {

        label = 'CAM-02 · INGRESSO PRINCIPALE',

        model = `prop_cctv_pole_04`,

        coords = vec4(5629.5938, -3128.6658, 11.1480, 273.2512),

        propOffset = vec3(0.0, 0.0, 0.0),

        depth = 0.0,

        rotation = vec3(0.0, 0.0, 0.0),

        feedView = vec4(5611.88, -3124.50, 9.00, 105.0),

        feedPitch = -8.0,

        feedFov = 60.0,

        monitorFeed = true,

    },

}



-- intercomFeed: telecamera usata quando si risponde al citofono (CAM-01)

-- monitorFeed: telecamere visibili nel monitor di sorveglianza

Config.IntercomCameraIndex = 1

-- PoliceMonitor: base + heading | PoliceMonitorOffset: Y destra, Z alto

-- PoliceMonitorRadius: raggio interazione sphere zone

-- PoliceJob: nome job Qbox (deve essere in servizio / on duty)



Config.PoliceJob = 'police'

Config.PoliceRequireDuty = true

Config.PoliceMonitor = vec4(5627.8, -3135.5, 11.1454, 275.0)

Config.PoliceMonitorOffset = vec3(0.0, 0.0, 0.0)

Config.PoliceMonitorRadius = 2.5



Config.DoorlockId = 1

Config.LocationLabel = 'Centralino'

Config.VisitorTimeout = 60000

-- Comunicazione vocale durante la chiamata citofono (pma-voice)

Config.VoiceEnabled = true

Config.VoiceResource = 'pma-voice'

Config.Debug = false


