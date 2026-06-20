# DMSS_videointercom

Sistema di citofono video per FiveM con telecamere CCTV, comunicazione vocale privata e monitor di sorveglianza. Compatibile con **Qbox (qbx_core)**, **ox_target**, **ox_doorlock** e **pma-voice**.

## Funzionalità

- Visitatore suona il citofono → notifica alla polizia con nome del chiamante
- Agente risponde dal monitor → si apre un canale vocale privato (nessun leak in proximity)
- Agente può sbloccare la porta direttamente dal monitor
- Supporto multi-camera CCTV con switch in-game
- Prop citofono e telecamere spawnable con supporto interior/MLO
- Notifiche tramite **ss-libs**

## Dipendenze

| Risorsa | Obbligatoria |
|---|---|
| `qbx_core` | ✅ |
| `ox_lib` | ✅ |
| `ox_target` | ✅ |
| `ox_doorlock` | ✅ |
| `ss-libs` | ✅ |
| `pma-voice` | ✅ (se `VoiceEnabled = true`) |

> Richiede anche `setr voice_enableCalls 1` nel `server.cfg` per il canale vocale privato.

## Installazione

1. Copia la cartella `DMSS_videointercom` in `resources/`
2. Aggiungi `ensure DMSS_videointercom` nel `server.cfg` (dopo `ss-libs`, `ox_target`, `ox_doorlock`)
3. Configura `config.lua` con le coordinate del tuo MLO/location

## Configurazione

### Citofono

```lua
Config.IntercomProp    = vec4(x, y, z, heading)  -- posizione base del citofono
Config.IntercomModel   = `prop_ld_keypad_01`      -- modello prop
Config.PropDepth       = -0.02                    -- offset profondità nel muro
Config.PropOffset      = vec3(0.0, 0.30, 0.5)    -- offset Y/Z rispetto alla base
Config.InteractRadius  = 2.0                      -- raggio interazione ox_target
Config.SpawnDistance   = 80.0                     -- distanza spawn prop
Config.VisitorTimeout  = 60000                    -- timeout chiamata senza risposta (ms)
Config.LocationLabel   = 'Centralino'             -- nome mostrato al visitatore
```

### Telecamere CCTV

Ogni entry in `Config.CctvProps` definisce una telecamera:

```lua
Config.CctvProps = {
    {
        label        = 'CAM-01 · INGRESSO',        -- nome mostrato nel monitor
        model        = `prop_cctv_cam_04a`,         -- modello prop telecamera
        coords       = vec4(x, y, z, heading),      -- posizione prop
        feedView     = vec4(x, y, z, heading),      -- punto di vista del feed
        feedPitch    = -25.0,                       -- inclinazione verticale (negativo = giù)
        feedFov      = 60.0,                        -- field of view
        intercomFeed = true,   -- questa cam viene usata quando si risponde al citofono
        monitorFeed  = true,   -- questa cam appare nel monitor sorveglianza
    },
}

Config.IntercomCameraIndex = 1  -- indice fallback se nessuna cam ha intercomFeed = true
```

### Monitor Polizia

```lua
Config.PoliceJob           = 'police'                        -- nome job richiesto
Config.PoliceRequireDuty   = true                            -- richiede onduty
Config.PoliceMonitor       = vec4(x, y, z, heading)         -- posizione monitor
Config.PoliceMonitorRadius = 2.5                             -- raggio interazione
Config.DoorlockId          = 1152                            -- ID porta ox_doorlock
```

### Voce

```lua
Config.VoiceEnabled           = true
Config.VoiceResource          = 'pma-voice'
Config.VoiceCallVolume        = 100
Config.VoiceProximityOverride = 0.01  -- proximity override durante la chiamata
```

## Comandi

| Comando | Descrizione |
|---|---|
| `/intercomrefresh` | Ricarica zone, prop e CCTV senza riavviare la risorsa |
| `/intercomrespawn` | Respawna solo i prop |

## Crediti

Sviluppato da **DMSS** — sistema citofono per server Qbox/FiveM.
