--------------------------------------------------------------------------------
-- Addon: mobability
-- Autor: Waky
-- Versión: 1.0.2
-- Descripción:
--   Muestra alertas para:
--     • Spells ( "Mob starts casting X on Y" )
--     • TP moves ( "Mob readies X on Y" )
--     • 2H / SP abilities ( "Mob uses X on Y" )
--   Filtra mobs que tengan odio (hate) con la party/alianza o con tu "current target".
--   Permite configuración en /mobability.
--------------------------------------------------------------------------------

addon.name = 'mobability'
addon.author = 'Waky'
addon.version = '1.0.2'
addon.desc = 'Mobability. Shows alerts for mob actions in combat based on your selected mode.'
addon.link = ''

--------------------------------------------------------------------------------
-- Librerías / requires
--------------------------------------------------------------------------------
require('common')
local chat = require('chat')
local imgui = require('imgui')
local settings = require('settings')

--------------------------------------------------------------------------------
-- CONFIGURACIÓN Y AJUSTES POR DEFECTO
--------------------------------------------------------------------------------

-- Tiempo máximo de vida de una alerta (en segundos) si no se cierra antes.
local ALERT_MAX_LIFETIME = 10

-- Ajustes por defecto que se cargarán si no existe archivo de settings
local default_settings = T {
    position = { x = 0.5, y = 0.25 }, -- Dónde aparecerá la ventana de alertas
    font_scale = 1.5,
    show_alerts = true,
    force_show_alert = false,
    max_width = 0, -- 0 => auto-resize
    alert_mode = 0, -- 0 => sólo alertas de tu current target; 1 => todos los mobs en hate con la party
    alert_in_chat = false,
    show_spell_alerts = true,
    show_tp_alerts = true,
    limit_alerts = 5, -- 0 => ilimitado
    use_sound_spell = true, -- Reproducir sonido en spells
    use_sound_tp = true, -- Reproducir sonido en TP/2H
    alert_colors = {
        mob = { 1, 0, 0, 1 }, -- Color del nombre del mob
        message = { 1, 1, 1, 1 }, -- Color del mensaje "readies/casting"
        action_spell = { 0, 1, 1, 1 }, -- Color del spell
        action_tp = { 0.047, 1.0, 0, 1 }, -- Color del TP move
        target = { 1, 1, 0, 1 }     -- Color del target al que se dirige
    },
    background_active = true, -- Habilitar fondo en las alertas
    background_color = { 0.047, 0.035, 0.035, 0.823 } -- Color translúcido
}

--------------------------------------------------------------------------------
-- CARGA DE SETTINGS
--------------------------------------------------------------------------------

local userSettings = settings.load(default_settings)
if type(userSettings) ~= "table" then
    userSettings = default_settings
end

--------------------------------------------------------------------------------
-- Variables internas / Tablas globales
--------------------------------------------------------------------------------
flaggedEntities = flaggedEntities or T {} -- Mobs en odio (hate) hacia la party
mobMapping = mobMapping or T {} -- Mapping: mob_name_normalized => localIndex
mobTargets = mobTargets or T {} -- Mapping: mob_name => nombre del target

--------------------------------------------------------------------------------
-- Tabla con nombres de “2H” / SP abilities que reconocemos
--------------------------------------------------------------------------------
local knownTwoHourNames = T {
    ["Mighty Strikes"] = true,
    ["Hundred Fists"] = true,
    ["Benediction"] = true,
    ["Manafont"] = true,
    ["Chainspell"] = true,
    ["Perfect Dodge"] = true,
    ["Invincible"] = true,
    ["Blood Weapon"] = true,
    ["Call Wyvern"] = true,
    ["Meikyo Shisui"] = true,
    ["Astral Flow"] = true,
    ["Soul Voice"] = true,
    ["Familiar"] = true,
    ["Eagle Eye Shot"] = true,
    ["Mijin Gakure"] = true,
    ["Charm"] = true,
}

--------------------------------------------------------------------------------
-- “mobability” Table: Principales variables de estado
--------------------------------------------------------------------------------
local mobability = T {
    settings = userSettings,
    guiOpen = { false },
    alertQueue = T {},
    testAlertActive = false,
    testAlertStart = 0,
    debug = false,
    alertInitialized = false
}

--------------------------------------------------------------------------------
-- Registrar callback de settings => guardamos config
--------------------------------------------------------------------------------
local function SaveConfig()
    settings.save()
end

settings.register("settings", "settings_update", function(s)
    if type(s) ~= "table" then
        s = default_settings
    end
    mobability.settings = s
    SaveConfig()
end)

--------------------------------------------------------------------------------
-- Funciones auxiliares: normalizar texto, etc.
--------------------------------------------------------------------------------

-- normaliza cadenas => todo minúsculas, sin espacios sobrantes
local function normalize(str)
    return (str and str:lower():gsub('%s+', ' '):gsub('^%s*(.-)%s*$', '%1')) or nil
end

-- Convierte un serverId => localIndex (si es válido)
local function ResolveLocalIndexFromId(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()

    -- Shortcut para NPC/MOB (bit 0x1000000)
    if bit.band(id, 0x1000000) ~= 0 then
        local idx = bit.band(id, 0xFFF)
        if idx >= 0x900 then
            idx = idx - 0x100
        end
        if idx < 0x900 and entMgr:GetServerId(idx) == id then
            return idx
        end
    end

    -- Búsqueda general
    for i = 1, 0x8FF do
        if entMgr:GetServerId(i) == id then
            return i
        end
    end
    return 0
end

-- Devuelve localIndex si es un mob válido; o 0 si no
local function GetValidMobIndexFromServerId(serverId)
    local idx = ResolveLocalIndexFromId(serverId)
    if idx == 0 then
        return 0
    end

    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local spawnFlags = entMgr:GetSpawnFlags(idx)
    -- 0x10 => mob
    if bit.band(spawnFlags, 0x10) == 0 then
        return 0
    end
    local renderFlags = entMgr:GetRenderFlags0(idx)
    if bit.band(renderFlags, 0x200) ~= 0x200 or bit.band(renderFlags, 0x4000) ~= 0 then
        return 0
    end
    return idx
end

-- Devuelve info básica de la entidad: nombre, hp%, distance
local function GetEntity(idx)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local nm = entMgr:GetName(idx)
    if (not nm) or nm == "" then
        return nil
    end
    local hp = entMgr.GetHPPercent and entMgr:GetHPPercent(idx) or 100
    local dist = entMgr.GetDistance and entMgr:GetDistance(idx) or 0
    return { Name = nm, HPPercent = hp, Distance = dist }
end

--------------------------------------------------------------------------------
-- Manejo de Party / Pets
--------------------------------------------------------------------------------

local function fetchPartyMembers()
    local members = T {}
    local party = AshitaCore:GetMemoryManager():GetParty()
    if party then
        for i = 0, 17 do
            if party:GetMemberIsActive(i) == 1 then
                table.insert(members, party:GetMemberServerId(i))
            end
        end
    end
    return members
end

local function IsInParty(tid, partyIDs)
    for _, pid in ipairs(partyIDs) do
        if pid == tid then
            return true
        end
    end
    return false
end

-- Devuelve un map: petId => OwnerName
local function GetPartyPets()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local pets = {}
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 then
            local pIdx = party:GetMemberTargetIndex(i)
            if pIdx and pIdx > 0 then
                local petIdx = entMgr:GetPetTargetIndex(pIdx)
                if petIdx and petIdx > 0 then
                    local petId = entMgr:GetServerId(petIdx)
                    if petId and petId ~= 0 then
                        pets[petId] = party:GetMemberName(i)
                    end
                end
            end
        end
    end
    return pets
end

-- Convierte petId => nombre del pet
local function GetPetNameById(petId)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local lIdx = ResolveLocalIndexFromId(petId)
    if lIdx > 0 then
        return entMgr:GetName(lIdx) or "Unknown Pet"
    end
    return "Unknown Pet"
end

-- Devuelve index actual (o nil) del target del jugador
local function GetCurrentTargetIndex()
    local tgtMgr = AshitaCore:GetMemoryManager():GetTarget()
    local idx = tgtMgr:GetTargetIndex(0)
    if idx == 0 or idx >= 0x900 then
        return nil
    end
    return idx
end

-- Nombre del target actual
local function GetCurrentTargetName()
    local cIdx = GetCurrentTargetIndex()
    if not cIdx then
        return nil
    end
    local ent = AshitaCore:GetMemoryManager():GetEntity()
    return ent:GetName(cIdx)
end

--------------------------------------------------------------------------------
-- Reproducir sonidos
--------------------------------------------------------------------------------
local function playAlertSound(alertType)
    if alertType == "Spell" and mobability.settings.use_sound_spell then
        ashita.misc.play_sound(addon.path .. 'sound/spell_alert.wav')
    elseif (alertType == "TP" or alertType == "2H") and mobability.settings.use_sound_tp then
        ashita.misc.play_sound(addon.path .. 'sound/tp_alert.wav')
    end
end

--------------------------------------------------------------------------------
-- showFloatingAlert => crea la alerta y la mete en alertQueue
--------------------------------------------------------------------------------
local function showFloatingAlert(text, color, duration, mob, spell, alertType, extra)
    local showType = true
    if alertType == "Spell" then
        showType = mobability.settings.show_spell_alerts
    elseif (alertType == "TP" or alertType == "2H") then
        showType = mobability.settings.show_tp_alerts
    end
    if not showType then
        return
    end

    -- Si en settings está habilitado el aviso en chat
    if mobability.settings.alert_in_chat then
        print(chat.header('MobAbility'):append(chat.message(text)))
    end
    if not mobability.settings.show_alerts then
        return
    end

    local d = duration or 99999
    local alert = {
        text = text,
        color = color or { 1.0, 1.0, 0.0, 1.0 },
        expires = os.clock() + d,
        startTime = os.clock(),
        mob = mob,
        spell = spell,
        type = alertType
    }
    if extra then
        alert.mobColor = extra.mobColor
        alert.spellColor = extra.spellColor
        alert.target = extra.target
    end

    table.insert(mobability.alertQueue, alert)
    playAlertSound(alert.type)
end

--------------------------------------------------------------------------------
-- refreshFlaggedEntities => limpia alertas viejas y mobs sin odio
--------------------------------------------------------------------------------
local function refreshFlaggedEntities()
    local now = os.clock()

    -- Elimina alertas expiradas
    for i = #mobability.alertQueue, 1, -1 do
        local al = mobability.alertQueue[i]
        if al.expires <= now or (al.startTime and (now - al.startTime > ALERT_MAX_LIFETIME)) then
            table.remove(mobability.alertQueue, i)
        end
    end

    -- Elimina mobs que murieron o se alejaron
    for idx, _ in pairs(flaggedEntities) do
        local ent = GetEntity(idx)
        if ent then
            if ent.HPPercent <= 0 or ent.Distance > 2500 then
                flaggedEntities[idx] = nil
            end
        else
            flaggedEntities[idx] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- resetZoneState => al cambiar zona
--------------------------------------------------------------------------------
local function resetZoneState(e)
    flaggedEntities = T {}
    mobability.alertQueue = T {}
end

--------------------------------------------------------------------------------
-- processMobUpdate => maneja 0x00E (claim)
--------------------------------------------------------------------------------
local function processMobUpdate(e)
    if (not e) or (not e.NewClaimId) then
        return
    end
    local ent = GetEntity(e.LocalIndex)
    if not ent then
        return
    end
    local partyIDs = fetchPartyMembers()
    for _, pid in ipairs(partyIDs) do
        if pid == e.NewClaimId then
            flaggedEntities[e.LocalIndex] = 1
            break
        end
    end
end

--------------------------------------------------------------------------------
-- Decodifica packet 0x28 => acción
--------------------------------------------------------------------------------
local function decodeActionPacket(e)
    if e.id ~= 0x28 then
        return nil
    end
    local data = e.data_raw
    local pos = 40
    local total = e.size * 8

    local function read(n)
        if (pos + n) > total then
            total = 0
            return 0
        end
        local val = ashita.bits.unpack_be(data, 0, pos, n)
        pos = pos + n
        return val
    end

    local pkt = T {}
    pkt.UserId = read(32)
    local tCount = read(6)
    pos = pos + 4
    pkt.Type = read(4)

    if pkt.Type == 8 or pkt.Type == 9 then
        pkt.Param = read(16)
        pkt.SpellGroup = read(16)
    else
        pkt.Param = read(32)
    end
    pkt.Recast = read(32)
    pkt.Targets = T {}

    if tCount > 0 then
        for i = 1, tCount do
            local function parseAction()
                local act = {}
                act.Reaction = read(5)
                act.Animation = read(12)
                act.SpecialEffect = read(7)
                act.Knockback = read(3)
                act.Param = read(17)
                act.Message = read(10)
                act.Flags = read(31)
                local hasAdd = (read(1) == 1)
                if hasAdd then
                    act.AdditionalEffect = {
                        Damage = read(10),
                        Param = read(17),
                        Message = read(10)
                    }
                end
                local hasSpikes = (read(1) == 1)
                if hasSpikes then
                    act.SpikesEffect = {
                        Damage = read(10),
                        Param = read(14),
                        Message = read(10)
                    }
                end
                return act
            end
            local function parseTarget()
                local tg = T {}
                tg.Id = read(32)
                local acCt = read(4)
                if acCt > 0 then
                    local acts = T {}
                    for j = 1, acCt do
                        table.insert(acts, parseAction())
                    end
                    tg.Actions = acts
                end
                return tg
            end
            table.insert(pkt.Targets, parseTarget())
        end
    end

    return pkt
end

--------------------------------------------------------------------------------
-- Funciones que manejan spells/TP/2H
--------------------------------------------------------------------------------

-- Spells y TP
local function HandleMobActionText(mobName, actionName, targetName, actionType, myName)
    -- Evitar self-cast del player
    if normalize(mobName) == normalize(myName) then
        return
    end

    -- Filtrado por alert_mode + flagged
    if mobability.settings.alert_mode == 1 then
        local mappedIndex = mobMapping[normalize(mobName)]
        if not mappedIndex or not flaggedEntities[mappedIndex] then
            return
        end
    else
        local cIdx = GetCurrentTargetIndex()
        if not cIdx or not flaggedEntities[cIdx] then
            return
        end
        local mappedIndex = mobMapping[normalize(mobName)]
        if not mappedIndex or mappedIndex ~= cIdx then
            return
        end
    end

    local msg
    if actionType == "Spell" then
        msg = string.format('%s starts casting %s on %s', mobName, actionName, targetName)
    else
        msg = string.format('%s readies %s on %s', mobName, actionName, targetName)
    end

    showFloatingAlert(msg, nil, 99999, mobName, actionName, actionType, {
        mobColor = mobability.settings.alert_colors.mob,
        spellColor = (actionType == "TP")
                and mobability.settings.alert_colors.action_tp
                or mobability.settings.alert_colors.action_spell,
        target = targetName
    })
end

-- 2H => "Mob uses <2H> on <Target>"
local function HandleMobTwoHourText(mobName, abilityName, targetName, myName)
    -- Evita self-cast (player)
    if normalize(mobName) == normalize(myName) then
        return
    end

    if mobability.settings.alert_mode == 1 then
        local mappedIndex = mobMapping[normalize(mobName)]
        if not mappedIndex or not flaggedEntities[mappedIndex] then
            return
        end
    else
        local cIdx = GetCurrentTargetIndex()
        if not cIdx or not flaggedEntities[cIdx] then
            return
        end
        local mappedIndex = mobMapping[normalize(mobName)]
        if not mappedIndex or mappedIndex ~= cIdx then
            return
        end
    end

    local msg = string.format('%s uses %s on %s', mobName, abilityName, targetName)
    showFloatingAlert(msg, nil, 99999, mobName, abilityName, "2H", {
        mobColor = mobability.settings.alert_colors.mob,
        spellColor = mobability.settings.alert_colors.action_spell,
        target = targetName
    })
end

_G.HandleMobActionText = HandleMobActionText

--------------------------------------------------------------------------------
-- EVENTO text_in => Detecta los mensajes de chat
--------------------------------------------------------------------------------
ashita.events.register('text_in', 'text_in_cb', function(e)
    local line = e.message
    local currentTargetName = GetCurrentTargetName() or "None"
    local myName = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)

    -- Spells => "mob starts casting X on Y"
    do
        local mob_name, spell_name, targetName = line:match('^(.-) starts casting ([%a%s%-]+) on ([%a%s%-]+)%.')
        if not mob_name then
            mob_name, spell_name = line:match('^(.-) starts casting ([%a%s%-]+)%.')
            targetName = currentTargetName
        end
        if mob_name and spell_name then
            mob_name = mob_name:gsub('^The%s+', '')
            if mobTargets[normalize(mob_name)] then
                targetName = mobTargets[normalize(mob_name)]
            end
            HandleMobActionText(mob_name, spell_name, targetName, "Spell", myName)
        end
    end

    -- TP => "mob readies X on Y"
    do
        local mob_tp, tp_move, targetNameTP = line:match('^(.-) readies ([%a%s%-]+) on ([%a%s%-]+)%.')
        if not mob_tp then
            mob_tp, tp_move = line:match('^(.-) readies ([%a%s%-]+)%.')
            targetNameTP = currentTargetName
        end
        if mob_tp and tp_move then
            mob_tp = mob_tp:gsub('^The%s+', '')
            if mobTargets[normalize(mob_tp)] then
                targetNameTP = mobTargets[normalize(mob_tp)]
            end
            HandleMobActionText(mob_tp, tp_move, targetNameTP, "TP", myName)
        end
    end

    -- 2H => "Mob uses <2H> on <target>" => solo si <2H> está en knownTwoHourNames
    do
        local mob_2h, ability_2h, target_2h = line:match('^(.-) uses ([%a%s%-]+) on ([%a%s%-]+)%.')
        if mob_2h and ability_2h and target_2h then
            mob_2h = mob_2h:gsub('^The%s+', '')
            if knownTwoHourNames[ability_2h] then
                if mobTargets[normalize(mob_2h)] then
                    target_2h = mobTargets[normalize(mob_2h)]
                end
                HandleMobTwoHourText(mob_2h, ability_2h, target_2_2h or target_2h, myName)
            end
        else
            -- Sin "on <target>"
            local mob_2h2, ability_2h2 = line:match('^(.-) uses ([%a%s%-]+)%.')
            if mob_2h2 and ability_2h2 then
                mob_2h2 = mob_2h2:gsub('^The%s+', '')
                if knownTwoHourNames[ability_2h2] then
                    local fallbackTarget = mobTargets[normalize(mob_2h2)] or mob_2h2
                    HandleMobTwoHourText(mob_2h2, ability_2h2, fallbackTarget, myName)
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- EVENTO packet_in => maneja 0x28, 0x00E, 0x00A
--------------------------------------------------------------------------------
ashita.events.register('packet_in', 'mobability_packet_in_cb', function(e)
    -- 0x28 => acción
    if e.id == 0x28 then
        local pkt = decodeActionPacket(e)
        if not pkt then
            return
        end

        local myServerId = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)
        if pkt.UserId == myServerId then
            return
        end

        local localIdx = GetValidMobIndexFromServerId(pkt.UserId)
        if localIdx == 0 then
            return
        end

        local entMgr = AshitaCore:GetMemoryManager():GetEntity()
        local mobName = entMgr:GetName(localIdx) or "Unknown"
        mobMapping[normalize(mobName)] = localIdx

        -- A) Chequeo de 2H => Type=6 (JobAbility) o Type=11 (NPC TP) + ability
        do
            local resMgr = AshitaCore:GetResourceManager()
            if (pkt.Type == 6 or pkt.Type == 11) and pkt.Param > 0 then
                local ab = resMgr:GetAbilityById(pkt.Param + 512)
                if ab and ab.Name[1] then
                    local abName = ab.Name[1]
                    if knownTwoHourNames[abName] then
                        -- => es una 2H
                        local finalTarget = nil
                        if #pkt.Targets > 0 then
                            local tFirst = pkt.Targets[1]
                            if tFirst and tFirst.Id then
                                if tFirst.Id == pkt.UserId then
                                    finalTarget = mobName
                                else
                                    local tIdx = ResolveLocalIndexFromId(tFirst.Id)
                                    if tIdx > 0 then
                                        local nm = entMgr:GetName(tIdx)
                                        if nm and nm ~= "" then
                                            finalTarget = nm
                                        end
                                    end
                                end
                            end
                        end
                        if not finalTarget then
                            finalTarget = mobName
                        end

                        -- Filtrado => si flagged o current target
                        local alreadyFlagged = flaggedEntities[localIdx]
                        local show = false
                        if mobability.settings.alert_mode == 1 then
                            if alreadyFlagged then
                                show = true
                            end
                        else
                            local cIdx = GetCurrentTargetIndex()
                            if cIdx and cIdx == localIdx and flaggedEntities[cIdx] then
                                show = true
                            end
                        end
                        if show then
                            local msg = string.format('%s uses %s on %s', mobName, abName, finalTarget)
                            showFloatingAlert(msg, nil, 99999, mobName, abName, "2H", {
                                mobColor = mobability.settings.alert_colors.mob,
                                spellColor = mobability.settings.alert_colors.action_spell,
                                target = finalTarget
                            })
                        end
                    end
                end
            end
        end

        local alreadyFlagged = flaggedEntities[localIdx] and true or false
        local pets = GetPartyPets()
        local partyIDs = fetchPartyMembers()
        local addToHate = false
        local finalResolved = nil

        -- B) Marcamos hate / resolvemos a quién se dirige
        for _, tgt in ipairs(pkt.Targets) do
            if tgt and tgt.Id then
                local resolvedName = nil

                -- 1) Pet
                if pets[tgt.Id] then
                    resolvedName = string.format("%s's pet: %s", pets[tgt.Id], GetPetNameById(tgt.Id))
                    addToHate = true
                    -- 2) Party
                elseif IsInParty(tgt.Id, partyIDs) then
                    local tIdx = ResolveLocalIndexFromId(tgt.Id)
                    resolvedName = entMgr:GetName(tIdx) or "Unknown"
                    addToHate = true
                    -- 3) Self-cast
                elseif pkt.UserId == tgt.Id then
                    resolvedName = mobName
                    -- 4) Jugador/NPC Externo => solo si ya flagged
                else
                    if alreadyFlagged then
                        local tIdx = ResolveLocalIndexFromId(tgt.Id)
                        if tIdx > 0 then
                            local nm = entMgr:GetName(tIdx)
                            if nm and nm ~= "" then
                                resolvedName = nm
                            else
                                resolvedName = "Unknown"
                            end
                        else
                            resolvedName = "Unknown"
                        end
                    end
                end

                if resolvedName then
                    finalResolved = resolvedName
                    break
                end
            end
        end

        if addToHate then
            flaggedEntities[localIdx] = 1
        end
        if finalResolved then
            mobTargets[normalize(mobName)] = finalResolved
        end

        -- C) Spell/TP final => cierra la alerta
        if pkt.Type == 4 or pkt.Type == 11 then
            local resMgr = AshitaCore:GetResourceManager()
            local finalName = nil
            local sp = resMgr:GetSpellById(pkt.Param)
            if sp and sp.Name[1] and sp.Name[1] ~= "" then
                finalName = sp.Name[1]
            else
                local ab = resMgr:GetAbilityById(pkt.Param + 512)
                if ab and ab.Name[1] and ab.Name[1] ~= "" then
                    finalName = ab.Name[1]
                end
            end

            if finalName then
                for i, alert in ipairs(mobability.alertQueue) do
                    if alert.mob and alert.spell
                            and normalize(alert.mob) == normalize(mobName) then
                        if (alert.type == "Spell"
                                and normalize(alert.spell) == normalize(finalName))
                                or (alert.type == "TP" or alert.type == "2H") then
                            alert.expires = os.clock()
                            break
                        end
                    end
                end
            end
        end

        -- 0x00E => Claim
    elseif e.id == 0x00E then
        local lIndex = struct.unpack('H', e.data, 0x08 + 1)
        local newCid = struct.unpack('I', e.data, 0x2C + 1)
        if lIndex and newCid then
            processMobUpdate({ LocalIndex = lIndex, NewClaimId = newCid })
        end

        -- 0x00A => cambio de zona
    elseif e.id == 0x00A then
        resetZoneState(e)
    end

    refreshFlaggedEntities()
end)

--------------------------------------------------------------------------------
-- EVENTO d3d_present => dibuja alertas y config
--------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'mobability_present_cb', function()
    local io = imgui.GetIO()
    if (not io) or (not io.DisplaySize) then
        return
    end
    local screen_w = io.DisplaySize.x
    local screen_h = io.DisplaySize.y
    if (not screen_w) or (not screen_h) then
        return
    end

    if mobability.testAlertActive and os.clock() >= (mobability.testAlertStart + 10) then
        mobability.settings.force_show_alert = false
        mobability.testAlertActive = false
        SaveConfig()
    end

    -- Elimina alertas expiradas
    for i = #mobability.alertQueue, 1, -1 do
        if mobability.alertQueue[i].expires <= os.clock() then
            table.remove(mobability.alertQueue, i)
        end
    end

    local base_x = screen_w * mobability.settings.position.x
    local base_y = screen_h * mobability.settings.position.y

    -- Solo ajustamos posición la primera vez
    if not mobability.alertInitialized then
        imgui.SetNextWindowPos({ base_x, base_y }, ImGuiCond_FirstUseEver, { 0, 0 })
        mobability.alertInitialized = true
    end

    -- Si hay alertas y background_active => color de fondo
    if (#mobability.alertQueue > 0) and mobability.settings.background_active then
        imgui.PushStyleColor(ImGuiCol_WindowBg, mobability.settings.background_color)
    else
        imgui.PushStyleColor(ImGuiCol_WindowBg, { 1, 1, 1, 0 })
    end

    -- Ventana principal de alertas
    if imgui.Begin('##mobability_alert_list', false, bit.bor(
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoTitleBar,
            ImGuiWindowFlags_NoResize,
            ImGuiWindowFlags_NoCollapse,
            ImGuiWindowFlags_NoScrollbar,
            (not mobability.guiOpen[1] and ImGuiWindowFlags_NoMove) or 0)) then

        imgui.SetWindowFontScale(mobability.settings.font_scale)

        -- Guardar posición
        local posx, posy = imgui.GetWindowPos()
        mobability.settings.position.x = posx / screen_w
        mobability.settings.position.y = posy / screen_h
        SaveConfig()

        -- Render de las alertas
        local count = 0
        for _, alert in ipairs(mobability.alertQueue) do
            if mobability.settings.limit_alerts > 0 and count >= mobability.settings.limit_alerts then
                break
            end
            count = count + 1

            if alert.mob and alert.spell then
                -- Dibuja “Mob” (rojo)
                imgui.TextColored(mobability.settings.alert_colors.mob, alert.mob)
                imgui.SameLine(0, 0)

                -- Dependiendo del type => “starts casting: ” / “readies ” / “ uses ”
                if alert.type == "Spell" then
                    imgui.TextColored(mobability.settings.alert_colors.message, " starts casting: ")
                elseif alert.type == "TP" then
                    imgui.TextColored(mobability.settings.alert_colors.message, " readies ")
                elseif alert.type == "2H" then
                    imgui.TextColored(mobability.settings.alert_colors.message, " uses ")
                else
                    imgui.TextColored(mobability.settings.alert_colors.message, " ??? ")
                end

                imgui.SameLine(0, 0)

                -- Nombre de la acción (spell / TP / 2H)
                if alert.type == "TP" then
                    imgui.TextColored(mobability.settings.alert_colors.action_tp, alert.spell)
                else
                    imgui.TextColored(mobability.settings.alert_colors.action_spell, alert.spell)
                end

                -- “ on X ”
                if alert.target then
                    local isSelf = (alert.target == alert.mob)
                    -- De momento mostramos siempre “ on X ”
                    imgui.SameLine(0, 0)
                    imgui.TextColored(mobability.settings.alert_colors.message, " on ")
                    imgui.SameLine(0, 0)
                    imgui.TextColored(mobability.settings.alert_colors.target, alert.target)
                end

            else
                -- caso alert.text genérico
                imgui.PushStyleColor(ImGuiCol_Text, alert.color)
                imgui.TextUnformatted(alert.text)
                imgui.PopStyleColor()
            end
        end
    end
    imgui.End()
    imgui.PopStyleColor()

    local style = imgui.GetStyle()
    style.WindowBorderSize = 0

    -- Ventana de Config
    if mobability.guiOpen[1] then
        if imgui.Begin('Mobability Config', mobability.guiOpen, ImGuiWindowFlags_AlwaysAutoResize) then

            imgui.Text("2H ALERTS DETECTION:")
            imgui.Text("    - Por lines en chat ('Mob uses <2H> on <Target>'), se filtra con knownTwoHourNames.")
            imgui.Text("    - Por packet_in con Type=6/11 + ID de ability en knownTwoHourNames.")
            imgui.Spacing()

            imgui.Text("GENERAL SETTINGS")
            imgui.Separator()
            do
                local tmp_show_alerts = { mobability.settings.show_alerts }
                if imgui.Checkbox("Show floating alerts", tmp_show_alerts) then
                    mobability.settings.show_alerts = tmp_show_alerts[1]
                    SaveConfig()
                end

                local tmp_alert_in_chat = { mobability.settings.alert_in_chat }
                if imgui.Checkbox("Show alerts in chat", tmp_alert_in_chat) then
                    mobability.settings.alert_in_chat = tmp_alert_in_chat[1]
                    SaveConfig()
                end

                local tmp_font_scale = { mobability.settings.font_scale }
                if imgui.SliderFloat("Text size", tmp_font_scale, 0.5, 5.0) then
                    mobability.settings.font_scale = tmp_font_scale[1]
                    SaveConfig()
                end
            end

            imgui.Spacing()
            --------------------------------------------------------------------
            -- Spell Alerts
            --------------------------------------------------------------------
            imgui.Text("SPELL ALERTS")
            imgui.Separator()
            do
                local tmp_show_spell = { mobability.settings.show_spell_alerts }
                if imgui.Checkbox("Show Spell Alerts", tmp_show_spell) then
                    mobability.settings.show_spell_alerts = tmp_show_spell[1]
                    SaveConfig()
                end
            end

            --------------------------------------------------------------------
            -- TP/2H Move Alerts
            --------------------------------------------------------------------
            imgui.Spacing()
            imgui.Text("TP/2H ALERTS")
            imgui.Separator()
            do
                local tmp_show_tp = { mobability.settings.show_tp_alerts }
                if imgui.Checkbox("Show TP/2H Alerts", tmp_show_tp) then
                    mobability.settings.show_tp_alerts = tmp_show_tp[1]
                    SaveConfig()
                end
            end

            imgui.Spacing()
            --------------------------------------------------------------------
            -- Alert Mode
            --------------------------------------------------------------------
            imgui.Text("ALERT MODE")
            imgui.Separator()
            do
                if imgui.RadioButton("Only your current target", mobability.settings.alert_mode == 0) then
                    mobability.settings.alert_mode = 0
                    SaveConfig()
                end
                imgui.SameLine()
                if imgui.RadioButton("All party/ally mobs", mobability.settings.alert_mode == 1) then
                    mobability.settings.alert_mode = 1
                    SaveConfig()
                end
            end

            imgui.Spacing()
            --------------------------------------------------------------------
            -- Alert Limit
            --------------------------------------------------------------------
            imgui.Text("ALERT LIMIT")
            imgui.Separator()
            do
                local tmp_limit_alerts = { mobability.settings.limit_alerts }
                if imgui.SliderInt("Alert Limit (0=unlimited)", tmp_limit_alerts, 0, 10) then
                    mobability.settings.limit_alerts = tmp_limit_alerts[1]
                    SaveConfig()
                end
            end

            imgui.Spacing()
            --------------------------------------------------------------------
            -- Sound Settings
            --------------------------------------------------------------------
            imgui.Text("SOUND SETTINGS")
            imgui.Separator()
            do
                local tmp_use_sound_spell = { mobability.settings.use_sound_spell }
                if imgui.Checkbox("Use sound with Spell", tmp_use_sound_spell) then
                    mobability.settings.use_sound_spell = tmp_use_sound_spell[1]
                    SaveConfig()
                end
                local tmp_use_sound_tp = { mobability.settings.use_sound_tp }
                if imgui.Checkbox("Use sound with TP/2H", tmp_use_sound_tp) then
                    mobability.settings.use_sound_tp = tmp_use_sound_tp[1]
                    SaveConfig()
                end
            end

            imgui.Spacing()
            --------------------------------------------------------------------
            -- Alert Colors
            --------------------------------------------------------------------
            imgui.Text("ALERT COLORS")
            imgui.Separator()
            do
                local tmp_mob = { unpack(mobability.settings.alert_colors.mob) }
                if imgui.ColorEdit4("Mob Color", tmp_mob) then
                    mobability.settings.alert_colors.mob = tmp_mob
                    SaveConfig()
                end

                local tmp_message = { unpack(mobability.settings.alert_colors.message) }
                if imgui.ColorEdit4("Message Color", tmp_message) then
                    mobability.settings.alert_colors.message = tmp_message
                    SaveConfig()
                end

                local tmp_action_spell = { unpack(mobability.settings.alert_colors.action_spell) }
                if imgui.ColorEdit4("Spell Action Color", tmp_action_spell) then
                    mobability.settings.alert_colors.action_spell = tmp_action_spell
                    SaveConfig()
                end

                local tmp_action_tp = { unpack(mobability.settings.alert_colors.action_tp) }
                if imgui.ColorEdit4("TP Move Color", tmp_action_tp) then
                    mobability.settings.alert_colors.action_tp = tmp_action_tp
                    SaveConfig()
                end

                local tmp_target = { unpack(mobability.settings.alert_colors.target) }
                if imgui.ColorEdit4("Target Color", tmp_target) then
                    mobability.settings.alert_colors.target = tmp_target
                    SaveConfig()
                end
            end


            --------------------------------------------------------------------
            -- Background Settings
            --------------------------------------------------------------------
            imgui.Spacing()
            imgui.Text("BACKGROUND SETTINGS")
            imgui.Separator()
            do
                local tmp_bg_active = { mobability.settings.background_active }
                if imgui.Checkbox("Enable Background", tmp_bg_active) then
                    mobability.settings.background_active = tmp_bg_active[1]
                    SaveConfig()
                end

                local tmp_bg_color = { unpack(mobability.settings.background_color) }
                if imgui.ColorEdit4("Background Color", tmp_bg_color) then
                    mobability.settings.background_color = tmp_bg_color
                    SaveConfig()
                end
            end


            --------------------------------------------------------------------
            -- Test Alert
            --------------------------------------------------------------------
            imgui.Spacing()
            if imgui.Button("Test Alert") then
                showFloatingAlert("Test alert: Config mode activated", { 0, 1, 1, 1 }, 10, "Test", "Test", "Spell", {
                    mobColor = mobability.settings.alert_colors.mob,
                    spellColor = mobability.settings.alert_colors.action_spell,
                    target = "TestTarget"
                })
                mobability.testAlertActive = true
                mobability.testAlertStart = os.clock()
            end
        end
        imgui.End()
    end
end)

--------------------------------------------------------------------------------
-- Comando /mobability or /mb => abre/cierra config
--------------------------------------------------------------------------------
ashita.events.register('command', 'mobability_command_cb', function(e)
    local args = e.command:args()
    if #args == 0 then
        return
    end
    if args[1] == '/mobability' or args[1] == '/mb' then
        e.blocked = true
        mobability.guiOpen[1] = not mobability.guiOpen[1]
    end
end)

--------------------------------------------------------------------------------
-- (Opcional) /mobht => lista mobs en hate only DEV mode
--------------------------------------------------------------------------------
--[[
ashita.events.register('command','mobability_hate_list_cb',function(e)
    local args= e.command:args()
    if args[1]~='/mobht' then
        return
    end
    e.blocked= true
    local entMgr= AshitaCore:GetMemoryManager():GetEntity()
    print("=== Party Hate List ===")
    for idx,_ in pairs(flaggedEntities) do
        local nm= entMgr:GetName(idx) or "Unknown"
        local sid= entMgr:GetServerId(idx) or 0
        print(string.format("Index:%d | Name:%s | ServerID:%d", idx, nm, sid))
    end
    print("=== End of list ===")
end)
]]

--------------------------------------------------------------------------------
-- Fin del addon
--------------------------------------------------------------------------------
return {}
