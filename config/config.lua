-- ----------------------------------------------------------------
--   pr_carkeys — Config.lua
-- ----------------------------------------------------------------
Config = {}

-- ----------------------------------------------------------------
-- DEBUG
-- ----------------------------------------------------------------
Config.Debug = true

-- ----------------------------------------------------------------
-- SQL — "auto" detecta automaticamente, ou force:
-- "auto" | "oxmysql" | "ghmattimysql" | "mysql-async"
-- ----------------------------------------------------------------
Config.SQL = "auto"

-- ----------------------------------------------------------------
-- FRAMEWORK — "auto" detecta automaticamente, ou force:
-- "qb-core" | "qbx-core" | "es_extended" | "ox_core" | "ND_Core"
-- ----------------------------------------------------------------
Config.Framework = "auto"

-- ----------------------------------------------------------------
-- INVENTÁRIO — "auto" detecta automaticamente, ou force:
-- "ox_inventory" | "qb-inventory"
-- ----------------------------------------------------------------
Config.Inventory = "auto"

-- ----------------------------------------------------------------
-- BOLSAS
-- ----------------------------------------------------------------
Config.Bags = {

    carkey_bag = {
        label    = "Bolsa de Chaves",
        slots    = 10,
        weight   = 5000,
        openTime = 3000,
        anim = {
            dict = "clothingtie",
            clip = "try_tie_positive_a",
            flag = 49,
        },
    },

    carkey_bag_large = {
        label    = "Bolsa de Chaves Grande",
        slots    = 25,
        weight   = 15000,
        openTime = 4000,
        anim = {
            dict = "clothingtie",
            clip = "try_tie_positive_a",
            flag = 49,
        },
    },

}

-- ----------------------------------------------------------------
-- CHAVES
-- ----------------------------------------------------------------
Config.KeyTypes = {

    carkey_permanent = {
        label   = "Chave Original",
        keyType = "permanent",
        level   = "original",
    },

    carkey_copy = {
        label   = "Chave Cópia",
        keyType = "permanent",
        level   = "copy",
    },

    carkey_temp = {
        label   = "Chave Temporária",
        keyType = "temporary",
        level   = "copy",
    },

    carkey_single = {
        label   = "Chave Avulsa",
        keyType = "single_use",
        level   = "copy",
    },

}

-- ----------------------------------------------------------------
-- SOM — usa pr_3dsound (server-side, todos os players escutam)
-- ----------------------------------------------------------------
Config.Sound = {
    radius       = 8.0,
    volume       = 0.8,
    soundDefault = 'tranca_1',
    -- Arquivos devem estar em: pr_3dsound/html/sounds/pr_carkeys/tranca_1.ogg
    -- Copie os arquivos de pr_carkeys/song/ para essa pasta do pr_3dsound
    sounds = {
        { id = 'tranca_1', label = 'Som Padrao',      file = 'tranca_1.ogg' },
        { id = 'tranca_2', label = 'Som Alternativo', file = 'tranca_2.ogg' },
    },
}

-- ----------------------------------------------------------------
-- CONFIGURAÇÃO PADRÃO
-- ----------------------------------------------------------------
Config.Default = {
    closeInventory  = false,                                        --  manté o ox_inventory aberto mesmo com menu 
    LockKey         = 'L',                                          --  Trancar/Destrancar veiculo
    EngineKey       = 'Z',                                          --  Ligar/Desligar motor

    KeyMetadata = {
        showOwner = true,                                           --  Registra o dono do carro no metadata do veiculo
        openMenu  = false,                                          --  Define se quer abrir a bolsa no ox_inventory direto ou o menu Ox_lib primeiro
    },

    UseKeyAnim = {                                                  --  Configuraçao de animaçao ao abrir veiculo
        dict     = "anim@mp_player_intmenu@key_fob@",
        clip     = "fob_click",
        flag = 49,
        waitTime = 500,                                             --  duração da animação
        DefaultDistance = 8.0,                                      --  Distância padrão de destrancar/trancar veiculo
    }
}

-- ----------------------------------------------------------------
-- BLACK LIST DE VEÍCULOS (não precisam de chave)
-- Usar hash do modelo: GetHashKey('bmx') etc.
-- ----------------------------------------------------------------
Config.NoKeyNeeded = {
    [`bmx`]     = true,
    [`bmxst`]   = true,
    [`cruiser`] = true,
    [`fixter`]  = true,
    [`scorcher`]= true,
    [`tribike`] = true,
    [`tribike2`]= true,
    [`tribike3`]= true,
}

-- ----------------------------------------------------------------
-- CHAVE NO VEÍCULO
-- Quando o jogador liga o carro, a chave sai do inventário.
-- Ao sair com motor ligado, a chave fica no carro — outro player
-- pode entrar e pegar para si.
-- Ao desligar o motor, a chave volta ao inventário.
-- ----------------------------------------------------------------
Config.KeyInVehicle = {
    enabled     = true,
    keepVehicleEngineOn = true,                     --  mantem motor ligado ao sair do veiculo
    pickupTime  = 2000,                             -- ms para pegar a chave do carro (0 = instantâneo)
    pickupLabel = "Pegando chave do carro...",
}

-- ----------------------------------------------------------------
-- POLICIAL — acesso sem chave
-- Policiais podem trancar/destrancar qualquer veículo.
-- Com arma apontada para NPC, podem roubar as chaves sem lockpick.
-- ----------------------------------------------------------------
Config.Police = {
    enabled = true,
    jobs    = { "police", "sheriff", "swat" },
}

-- ----------------------------------------------------------------
-- HOTWIRE (ligar na força)
-- Tecla: RegisterKeyMapping (hotwireKey) — inicia Config.Minigame em modo parked/carjack.
-- Ao concluir: servidor chama export GiveTempKey (chave temporária lógica, sem item DB).
-- ----------------------------------------------------------------
Config.Hotwire = {
    enabled       = true,
    hintText      = "[H] Ligação direta",
    hotwireKey    = "H",
    --- "parked" = dificultMinigame.vehiParked | "carjack" = vehiCarjack (roubos/furtos)
    minigameMode  = "parked",
    notifySuccess = nil, -- nil = mensagem genérica de ligação direta (abaixo em vehicle_init)
    notifyFail    = nil, -- nil = usa Config.Notify.noPermission
}

-- ----------------------------------------------------------------
-- MINIGAME CONFIG
-- ----------------------------------------------------------------
Config.Minigame = {
    minigame = "glitch-minigame",  -- ox_lib | glitch-minigame | mhacking
    game     = "BruteForce",         -- nome do minigame (ver lista no bridge)

    dificultMinigame = {
        -- ── Veículo estacionado (ligação direta) ──────────────
        vehiParked = {
            -- Campos universais
            rounds          = 3,
            speed           = 50,
            timeLimit       = 20000,
            maxFailures     = 3,
            zoneSize        = 25,
            -- HoldZone / SkillCheck
            perfectZoneSize = 10,
            randomizeZone   = true,
            -- NumberUp
            count           = 6,
            gridCols        = 3,
            maxMistakes     = 2,
            -- ComboInput
            comboLength     = 4,
            timePerCombo    = 5000,
            lengthIncrease  = 1,
            -- WireConnect
            wireCount       = 4,
            -- SimonSays
            flashSpeed      = 600,
            flashGap        = 200,
            -- AimTest
            targetsToHit    = 5,
            maxMisses       = 3,
            targetLifetime  = 3000,
            targetSize      = 40,
            -- CircleClick
            rotationSpeed   = 1.5,
            targetZoneSize  = 25,
            speedIncrease   = 0.2,
            randomizeDirection = true,
            -- Lockpick
            sweetSpotSize   = 20,
            shakeRange      = 30,
            lockTime        = 2000,
            -- Keymash
            keyPressValue   = 10,
            decayRate       = 2,
            -- Untangle
            nodeCount       = 6,
            -- Pairs / Memory
            gridSize        = 4,
            maxAttempts     = 10,
            -- MemoryColors
            memorizeTime    = 3000,
            answerTime      = 5000,
            -- Fingerprint
            showAlignedCount      = true,
            showCorrectIndicator  = true,
            -- CodeCrack
            digitCount      = 4,
            -- FirewallPulse
            requiredHacks   = 3,
            initialSpeed    = 1.0,
            maxSpeed        = 3.0,
            -- BackdoorSequence
            totalStages     = 3,
            keysPerStage    = 4,
            -- Rhythm
            lanes           = 4,
            noteSpeed       = 5,
            noteSpawnRate   = 1.5,
            requiredNotes   = 10,
            maxWrongKeys    = 3,
            maxMissedNotes  = 3,
            -- Memory / SequenceMemory
            squareCount     = 4,
            showTime        = 2000,
            maxWrongPresses = 2,
            delayBetween    = 500,
            -- VerbalMemory
            maxStrikes      = 3,
            wordsToShow     = 10,
            wordDuration    = 2000,
            -- NumberedSequence
            sequenceLength  = 4,
            guessTime       = 8000,
            -- SymbolSearch
            shiftInterval   = 3000,
            minKeyLength    = 3,
            maxKeyLength    = 5,
            -- VarHack
            blocks          = 5,
            -- WordCrack
            wordLength      = 5,
            -- Balance
            driftSpeed      = 1.0,
            sensitivity     = 1.0,
            greenZoneWidth  = 0.15,
            yellowZoneWidth = 0.25,
            driftRandomness = 0.5,
            maxDangerTime   = 3000,
            -- BruteForce
            numLives        = 3,
            -- DataCrack
            difficulty      = 1,
            -- CircuitBreaker
            levelNumber              = 1,
            difficultyLevel          = 1,
            delayStartMs             = 1000,
            minFailureDelayTimeMs    = 3000,
            maxFailureDelayTimeMs    = 8000,
            disconnectChance         = 0.3,
            disconnectCheckRateMs    = 1000,
            minReconnectTimeMs       = 1000,
            maxReconnectTimeMs       = 3000,
            -- PlasmaDrilling
            -- difficulty já declarado acima
            -- ox_lib skillcheck
            keys            = { 'w', 'a', 's', 'd' },
            -- difficulty já declarado acima (ox_lib usa tabela, mas aqui é número; ajuste se usar ox_lib)
        },

        -- ── Veículo com NPC (carjack) ─────────────────────────
        vehiCarjack = {
            -- Igual ao vehiParked mas mais difícil
            rounds          = 2,
            speed           = 65,
            timeLimit       = 15000,
            maxFailures     = 2,
            zoneSize        = 18,
            perfectZoneSize = 8,
            randomizeZone   = true,
            count           = 8,
            gridCols        = 3,
            maxMistakes     = 1,
            comboLength     = 5,
            timePerCombo    = 4000,
            lengthIncrease  = 1,
            wireCount       = 5,
            flashSpeed      = 500,
            flashGap        = 150,
            targetsToHit    = 6,
            maxMisses       = 2,
            targetLifetime  = 2500,
            targetSize      = 35,
            rotationSpeed   = 2.0,
            targetZoneSize  = 20,
            speedIncrease   = 0.3,
            randomizeDirection = true,
            sweetSpotSize   = 15,
            shakeRange      = 40,
            lockTime        = 1500,
            keyPressValue   = 10,
            decayRate       = 3,
            nodeCount       = 8,
            gridSize        = 4,
            maxAttempts     = 8,
            memorizeTime    = 2500,
            answerTime      = 4000,
            showAlignedCount      = false,
            showCorrectIndicator  = false,
            digitCount      = 5,
            requiredHacks   = 4,
            initialSpeed    = 1.2,
            maxSpeed        = 4.0,
            totalStages     = 4,
            keysPerStage    = 5,
            lanes           = 4,
            noteSpeed       = 7,
            noteSpawnRate   = 2.0,
            requiredNotes   = 12,
            maxWrongKeys    = 2,
            maxMissedNotes  = 2,
            squareCount     = 5,
            showTime        = 1500,
            maxWrongPresses = 1,
            delayBetween    = 400,
            maxStrikes      = 2,
            wordsToShow     = 12,
            wordDuration    = 1500,
            sequenceLength  = 5,
            guessTime       = 6000,
            shiftInterval   = 2000,
            minKeyLength    = 4,
            maxKeyLength    = 6,
            blocks          = 7,
            wordLength      = 6,
            driftSpeed      = 1.5,
            sensitivity     = 1.2,
            greenZoneWidth  = 0.10,
            yellowZoneWidth = 0.20,
            driftRandomness = 0.7,
            maxDangerTime   = 2000,
            numLives        = 2,
            difficulty      = 2,
            levelNumber              = 2,
            difficultyLevel          = 2,
            delayStartMs             = 800,
            minFailureDelayTimeMs    = 2000,
            maxFailureDelayTimeMs    = 6000,
            disconnectChance         = 0.4,
            disconnectCheckRateMs    = 800,
            minReconnectTimeMs       = 800,
            maxReconnectTimeMs       = 2500,
            keys            = { 'w', 'a', 's', 'd' },
        },
    }
}
-- ----------------------------------------------------------------
-- CARJACK (roubo de NPC com arma)
-- ----------------------------------------------------------------
Config.Carjack = {
    enabled        = true,                        --  true = permite roubos | false = Cancela roubos de veiculos de npc
    minTime        = { 5000, 7000 },              --  tempo de roubo e render npc
    cooldown       = { 5000, 10000 },             -- cooldown para roubo
    getPermKey     = false,                       -- true = chave permanente | false = chave temporária
    hintText       = "[E] Procurar chave",        --  Texto de render NPC "em roubo"
    label          = "Ligando veiculo...",        --  texto de progress  "em roubo"
    notifySuccess  = nil,                         -- nil = usa Config.Notify.keyUsed
    notifyFail     = nil,                         -- nil = usa Config.Notify.noPermission
    policeHint     = "[E] Confiscar veículo",     --  Texto de policial confisca
    policeLabel    = "Confiscando veículo...",    --  Texto de progress do policial a confiscar
    notifyPolice   = nil,                         -- nil = usa Config.Notify.keyUsed
    aimDistance    = 30.0,                        -- distância máxima para detectar NPC motorista
    npcReactChance = 0.30,                        -- chance do NPC puxar arma ao ser rendido (0.0 a 1.0)
    chance = {                                    -- chance do NPC reagir fugindo com veiculo de acordo com a classe da arma
        ["2685387236"] = 0.0,  -- melee
        ["416676503"]  = 0.5,  -- handguns
        ["-957766203"] = 0.75, -- SMG
        ["860033945"]  = 0.90, -- shotgun
        ["970310034"]  = 0.90, -- assault
        ["1159398588"] = 0.99, -- LMG
        ["3082541095"] = 0.99, -- sniper
        ["2725924767"] = 0.99, -- heavy
        ["1548507267"] = 0.0,  -- throwable
        ["4257178988"] = 0.0,  -- misc
    },
    blacklistedWeapons = {                      -- Armas que NÃO podem ser usadas para roubos de veiculo
        "WEAPON_UNARMED", "WEAPON_Knife", "WEAPON_Nightstick",
        "WEAPON_HAMMER",  "WEAPON_Bat",   "WEAPON_Crowbar",
        "WEAPON_Golfclub","WEAPON_Bottle","WEAPON_Dagger",
        "WEAPON_Hatchet", "WEAPON_KnuckleDuster", "WEAPON_Machete",
        "WEAPON_Grenade", "WEAPON_StickyBomb", "WEAPON_Molotov",
    },

}

-- ----------------------------------------------------------------
-- NOTIFICAÇÕES
-- ----------------------------------------------------------------
Config.Notify = {
    bagOpened       = { title = "Bolsa de Chaves", description = "Bolsa aberta!",                      type = "success" },
    bagClosed       = { title = "Bolsa de Chaves", description = "Bolsa fechada.",                     type = "inform"  },
    noKeys          = { title = "Bolsa de Chaves", description = "A bolsa esta vazia.",                type = "error"   },
    keyUsed         = { title = "Chave",           description = "Veiculo desbloqueado.",              type = "success" },
    keyLocked       = { title = "Chave",           description = "Veiculo bloqueado.",                 type = "inform"  },
    keyUsedEngine   = { title = "Chave",           description = "Motor ligado!",                      type = "success" },
    keyExpired      = { title = "Chave",           description = "Essa chave expirou.",                type = "error"   },
    keyUsedUp       = { title = "Chave",           description = "Chave de uso unico consumida.",      type = "inform"  },
    vehicleNotFound = { title = "Chave",           description = "Nenhum veiculo encontrado proximo.", type = "error"   },
    noPermission    = { title = "Sistema",         description = "Sem permissao.",                     type = "error"   },
    keyLocked       = { title = "Veículo",         description = "Veículo bloqueado.",                 type = "inform"  },
    keyReturned     = { title = "Chave",           description = "Chave devolvida ao inventário.",     type = "inform"  },
    keyStolen       = { title = "Chave",           description = "Sua chave foi pega por alguem.",     type = "error"   },
    keyInVehicle    = { title = "Chave",           description = "Chave encontrada no veiculo!",       type = "success" },
}