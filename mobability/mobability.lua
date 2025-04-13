--------------------------------------------------------------------------------
-- Addon: mobability
-- Autor: Waky
-- Versión: 1.0.2
-- Descripción: Shows alerts for mob actions in combat based on your selected mode.
--------------------------------------------------------------------------------

addon.name = 'mobability'
addon.author = 'Waky'
addon.version = '1.0.2'
addon.desc = 'Mobability. Shows alerts for mob actions in combat based on your selected mode.'
addon.link = ''

require('common')
local chat = require('chat')
local imgui = require('imgui')
local settings = require('settings')

--------------------------------------------------------------------------------
-- Tiempo máximo de vida de una alerta (en segundos)
--------------------------------------------------------------------------------
local ALERT_MAX_LIFETIME = 10

--------------------------------------------------------------------------------
-- Ajustes por defecto
--------------------------------------------------------------------------------
local default_settings = T {
    position = { x = 0.5, y = 0.25 },
    font_scale = 1.5,
    show_alerts = true,
    force_show_alert = false,
    max_width = 0, -- 0 = auto resize
    alert_mode = 0, -- 0: Only your current target; 1: All party/ally mobs
    alert_in_chat = false,
    show_spell_alerts = true,
    show_tp_alerts = true,
    limit_alerts = 5, -- Límite de alertas (0 = ilimitado)
    use_sound_spell = true, -- Usar sonido con Spell
    use_sound_tp = true, -- Usar sonido con TP Move
    alert_colors = {
        mob = { 1, 0, 0, 1 },
        message = { 1, 1, 1, 1 },
        action_spell = { 0, 1, 1, 1 },
        action_tp = { 0.047, 1.0, 0, 1 },
        target = { 1, 1, 0, 1 }
    },
    background_active = true, -- Habilitar fondo en las alertas
    background_color = { 0.047, 0.035, 0.035, 0.823 }
}

--------------------------------------------------------------------------------
-- Cargar configuración
--------------------------------------------------------------------------------
local userSettings = settings.load(default_settings)
if type(userSettings) ~= "table" then
    userSettings = default_settings
end

--------------------------------------------------------------------------------
-- Variables internas y globales
--------------------------------------------------------------------------------
flaggedEntities = flaggedEntities or T {} -- Hate list: IDs de mobs en combate
mobMapping = mobMapping or T {} -- Mapping: nombre (normalizado) -> localIndex
mobTargets = mobTargets or T {} -- Mapping: nombre del mob -> nombre del target

local mobability = T {
    settings = userSettings,
    guiOpen = { false },
    alertQueue = T {},
    testAlertActive = false,
    testAlertStart = 0,
    debug = false,
    alertInitialized = false,
}

--------------------------------------------------------------------------------
-- Función para guardar configuración (usa 'settings.save()' sin nombre)
--------------------------------------------------------------------------------
local function SaveConfig()
    settings.save()
end

--------------------------------------------------------------------------------
-- Registro de actualización de settings usando 'settings'
--------------------------------------------------------------------------------
settings.register("settings", "settings_update", function(s)
    if type(s) ~= "table" then
        s = default_settings
    end
    mobability.settings = s
    SaveConfig()
end)

--------------------------------------------------------------------------------
-- Convierte ServerID -> localIndex
--------------------------------------------------------------------------------
local function ResolveLocalIndexFromId(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    if bit.band(id, 0x1000000) ~= 0 then
        local idx = bit.band(id, 0xFFF)
        if idx >= 0x900 then
            idx = idx - 0x100
        end
        if idx < 0x900 and entMgr:GetServerId(idx) == id then
            return idx
        end
    end
    for i = 1, 0x8FF do
        if entMgr:GetServerId(i) == id then
            return i
        end
    end
    return 0
end

--------------------------------------------------------------------------------
-- Devuelve el localIndex de un mob si es válido, o 0 si no
--------------------------------------------------------------------------------
local function GetValidMobIndexFromServerId(serverId)
    local localIndex = ResolveLocalIndexFromId(serverId)
    if localIndex == 0 then
        return 0
    end
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local spawnFlags = entMgr:GetSpawnFlags(localIndex)
    if bit.band(spawnFlags, 0x10) == 0 then
        return 0
    end
    local renderFlags = entMgr:GetRenderFlags0(localIndex)
    if bit.band(renderFlags, 0x200) ~= 0x200 or bit.band(renderFlags, 0x4000) ~= 0 then
        return 0
    end
    return localIndex
end

--------------------------------------------------------------------------------
-- Comprueba si un ID está en la lista de la party
--------------------------------------------------------------------------------
local function IsInParty(targetId, partyIDs)
    for _, pid in ipairs(partyIDs) do
        if pid == targetId then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Funciones para detectar el PET y el nombre del dueño
--------------------------------------------------------------------------------
local function GetPartyPets()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local pets = {}
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 then
            local memberTargetIdx = party:GetMemberTargetIndex(i)
            if memberTargetIdx and memberTargetIdx > 0 then
                local petIdx = entMgr:GetPetTargetIndex(memberTargetIdx)
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

local function GetPetNameById(petId)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local localIdx = ResolveLocalIndexFromId(petId)
    if localIdx and localIdx > 0 then
        return entMgr:GetName(localIdx) or "Unknown Pet"
    end
    return "Unknown Pet"
end

--------------------------------------------------------------------------------
-- Obtener info básica de una entidad
--------------------------------------------------------------------------------
local function GetEntity(idx)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local name = entMgr:GetName(idx)
    if not name or name == "" then
        return nil
    end

    local hp = entMgr.GetHPPercent and entMgr:GetHPPercent(idx) or 100
    local dist = entMgr.GetDistance and entMgr:GetDistance(idx) or 0
    return { Name = name, HPPercent = hp, Distance = dist }
end

--------------------------------------------------------------------------------
-- Actualiza el mapping de mobs (nombre -> localIndex)
--------------------------------------------------------------------------------
local function updateMobMapping(actor_id)
    local localIdx = ResolveLocalIndexFromId(actor_id)
    if localIdx ~= 0 then
        local entMgr = AshitaCore:GetMemoryManager():GetEntity()
        local name = entMgr:GetName(localIdx)
        if name and name ~= "" then
            mobMapping[(name:lower()):gsub('^%s*(.-)%s*$', '%1')] = localIdx
        end
    end
end

--------------------------------------------------------------------------------
-- Normaliza cadenas (sin mayúsculas ni espacios sobrantes)
--------------------------------------------------------------------------------
local function normalize(str)
    return str and str:lower():gsub('%s+', ' '):gsub('^%s*(.-)%s*$', '%1') or nil
end

--------------------------------------------------------------------------------
-- Obtener nombre de entidad dado un serverId
--------------------------------------------------------------------------------
local function GetEntityName(serverId)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    for i = 0, 2303 do
        if entMgr:GetServerId(i) == serverId then
            local nm = entMgr:GetName(i)
            if nm and nm ~= "" then
                return nm
            end
        end
    end
    return "Unknown"
end

--------------------------------------------------------------------------------
-- Funciones para obtener target actual
--------------------------------------------------------------------------------
local function GetCurrentTargetIndex()
    local targetManager = AshitaCore:GetMemoryManager():GetTarget()
    local currentTargetIndex = targetManager:GetTargetIndex(0)
    if currentTargetIndex == 0 or currentTargetIndex >= 0x900 then
        return nil
    end
    return currentTargetIndex
end

local function GetCurrentTargetName()
    local idx = GetCurrentTargetIndex()
    if not idx then
        return nil
    end
    return AshitaCore:GetMemoryManager():GetEntity():GetName(idx)
end

--------------------------------------------------------------------------------
-- Resuelve el nombre del receptor (imitando a Targetlines)
--------------------------------------------------------------------------------
local function ResolveTargetName(tgtId, fallback)
    local party = AshitaCore:GetMemoryManager():GetParty()
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 then
            local targetIndex = party:GetMemberTargetIndex(i)
            if targetIndex and targetIndex > 0 then
                local tId = entMgr:GetServerId(targetIndex)
                if tId and tId == tgtId then
                    return entMgr:GetName(targetIndex) or fallback
                end
            end
        end
    end
    return fallback
end

--------------------------------------------------------------------------------
-- Reproduce el sonido de alerta
--------------------------------------------------------------------------------
local function playAlertSound(alertType)
    if (alertType == "Spell" and mobability.settings.use_sound_spell) then
        ashita.misc.play_sound(addon.path .. 'sound/spell_alert.wav')
    elseif (alertType == "TP" and mobability.settings.use_sound_tp) then
        ashita.misc.play_sound(addon.path .. 'sound/tp_alert.wav')
    end
end

--------------------------------------------------------------------------------
-- Muestra una alerta flotante + aviso en chat (opcional)
--------------------------------------------------------------------------------
local function showFloatingAlert(text, color, duration, mob, spell, alertType, extra)
    local showType = true
    if alertType == "Spell" then
        showType = mobability.settings.show_spell_alerts
    elseif alertType == "TP" then
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
        type = alertType or "Spell"
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
-- Manejo de party: Devuelve lista de IDs de miembros activos
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

--------------------------------------------------------------------------------
-- Decodifica el paquete 0x28 en detalle
--------------------------------------------------------------------------------
local function decodeActionPacket(e)
    if e.id ~= 0x28 then
        return nil
    end

    local stream = e.data_raw
    local bits = { pos = 40, total = e.size * 8 }

    -- Función interna para leer n bits y avanzar el puntero
    local function read(n)
        if (bits.pos + n) > bits.total then
            bits.total = 0
            return 0
        end
        local value = ashita.bits.unpack_be(stream, 0, bits.pos, n)
        bits.pos = bits.pos + n
        return value
    end

    -- Parsea una acción dentro de un target
    local function parseAction()
        local act = {}
        act.Reaction = read(5)
        act.Animation = read(12)
        act.SpecialEffect = read(7)
        act.Knockback = read(3)
        act.Param = read(17)
        act.Message = read(10)
        act.Flags = read(31)
        if read(1) == 1 then
            act.AdditionalEffect = {
                Damage = read(10),
                Param = read(17),
                Message = read(10)
            }
        end
        if read(1) == 1 then
            act.SpikesEffect = {
                Damage = read(10),
                Param = read(14),
                Message = read(10)
            }
        end
        return act;
    end

    -- Parsea un target (con ID y posibles acciones)
    local function parseTarget()
        local target = T {};
        target.Id = read(32)
        local actionCount = read(4)
        if actionCount > 0 then
            local acts = T {};
            for i = 1, actionCount do
                table.insert(acts, parseAction())
            end
            target.Actions = acts;
        end
        return target;
    end

    -- Comienza la construcción del paquete resultante
    local packet = T {};
    packet.UserId = read(32)
    local targetCounter = read(6)
    bits.pos = bits.pos + 4;  -- saltamos padding
    packet.Type = read(4)

    if packet.Type == 8 or packet.Type == 9 then
        packet.Param = read(16)
        packet.SpellGroup = read(16)
    else
        packet.Param = read(32)
    end

    packet.Recast = read(32)
    packet.Targets = T {};

    if targetCounter > 0 then
        for i = 1, targetCounter do
            table.insert(packet.Targets, parseTarget())
        end
    end

    return packet
end

--------------------------------------------------------------------------------
-- Decodifica el paquete 0x00E (claim)
--------------------------------------------------------------------------------
local function decodeMobUpdate(e)
    if e.id ~= 0x00E then
        return nil
    end
    local mobUpd = T {}
    mobUpd.LocalIndex = struct.unpack('H', e.data, 0x08 + 1)
    mobUpd.NewClaimId = struct.unpack('I', e.data, 0x2C + 1)
    return mobUpd
end

--------------------------------------------------------------------------------
-- Procesa la actualización de claim
--------------------------------------------------------------------------------
local function processMobUpdate(e)
    if not e or not e.NewClaimId then
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
-- Resetea estados al cambiar de zona
--------------------------------------------------------------------------------
local function resetZoneState(e)
    flaggedEntities = T {}
    mobability.alertQueue = T {}
end

--------------------------------------------------------------------------------
-- Limpia alertas caducadas y elimina mobs sin odio
--------------------------------------------------------------------------------
local function refreshFlaggedEntities()
    local currentTime = os.clock()

    -- Elimina alertas caducadas
    for i = #mobability.alertQueue, 1, -1 do
        local alert = mobability.alertQueue[i]
        if alert.expires <= currentTime
                or (alert.startTime and (currentTime - alert.startTime > ALERT_MAX_LIFETIME)) then
            table.remove(mobability.alertQueue, i)
        end
    end

    -- Quita mobs que murieron o se alejaron
    for idx, _ in pairs(flaggedEntities) do
        local ent = GetEntity(idx)
        if ent then
            if ent.HPPercent <= 0 or (ent.Distance and ent.Distance > 2500) then
                flaggedEntities[idx] = nil
            end
        else
            flaggedEntities[idx] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Maneja el aviso de la acción (Spell/TP)
--------------------------------------------------------------------------------
local function HandleMobActionText(mobName, actionName, targetName, actionType, myName)
    -- Evita self-cast
    if normalize(mobName) == normalize(myName) then
        return
    end
    -- Si el mob se autoapunta, ajusta el target
    if normalize(mobName) == normalize(targetName) then
        targetName = mobName
    end

    if mobability.settings.alert_mode == 1 then
        local mappedIndex = mobMapping[normalize(mobName)]
        if (not mappedIndex) or (not flaggedEntities[mappedIndex]) then
            return
        end
    else
        local targetIndex = GetCurrentTargetIndex()
        if (not targetIndex) or (not flaggedEntities[targetIndex]) then
            return
        end
        local mappedIndex = mobMapping[normalize(mobName)]
        if (not mappedIndex) or (mappedIndex ~= targetIndex) then
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

_G.HandleMobActionText = HandleMobActionText

--------------------------------------------------------------------------------
-- Evento text_in: Procesa mensajes de Spell y TP
--------------------------------------------------------------------------------
ashita.events.register('text_in', 'text_in_cb', function(e)
    local line = e.message
    local currentTargetName = GetCurrentTargetName() or "None"
    local myName = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)

    -- Detectar spells
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
            elseif normalize(targetName) == normalize(mob_name) then
                targetName = currentTargetName
            end
            HandleMobActionText(mob_name, spell_name, targetName, "Spell", myName)
        end
    end

    -- Detectar TP moves
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
            elseif normalize(targetNameTP) == normalize(mob_tp) then
                targetNameTP = currentTargetName
            end
            HandleMobActionText(mob_tp, tp_move, targetNameTP, "TP", myName)
        end
    end
end)

--------------------------------------------------------------------------------
-- Evento packet_in: Procesa paquetes 0x28 (acciones), 0x00E (claim), 0x00A (reset)
--------------------------------------------------------------------------------
ashita.events.register('packet_in', 'mobability_packet_in_cb', function(e)
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
        updateMobMapping(pkt.UserId)

        -- Verifica targets para actualizar flaggedEntities
        local entMgr = AshitaCore:GetMemoryManager():GetEntity()
        local party = AshitaCore:GetMemoryManager():GetParty()
        local pets = GetPartyPets()
        local partyIDs = fetchPartyMembers()

        for _, tgt in ipairs(pkt.Targets) do
            if tgt and tgt.Id then
                local addToHate = false
                local resolvedName = nil

                if pets[tgt.Id] then
                    resolvedName = string.format("%s's pet: %s", pets[tgt.Id], GetPetNameById(tgt.Id))
                    addToHate = true
                else
                    if IsInParty(tgt.Id, partyIDs) then
                        local targetIdx = ResolveLocalIndexFromId(tgt.Id)
                        resolvedName = entMgr:GetName(targetIdx) or "Unknown"
                        addToHate = true
                    end
                end

                if addToHate then
                    flaggedEntities[localIdx] = 1
                    local mobName = entMgr:GetName(localIdx) or "Unknown"
                    mobTargets[normalize(mobName)] = ResolveTargetName(tgt.Id, resolvedName)
                    if mobability.debug then
                        print(chat.header(addon.name):append(chat.message(
                                "MobID: " .. pkt.UserId ..
                                        " | LocalIdx: " .. localIdx ..
                                        " | MobName: " .. mobName ..
                                        " | TargetID: " .. tgt.Id ..
                                        " | ResolvedTarget: " .. resolvedName
                        )))
                    end
                    break
                end
            end
        end

        -- Si es un Spell o TP finalizado, cerramos la alerta
        if pkt.Type == 4 or pkt.Type == 11 then
            local resMgr = AshitaCore:GetResourceManager()
            local finalName = nil
            local spell = resMgr:GetSpellById(pkt.Param)
            if spell and spell.Name[1] then
                finalName = spell.Name[1]
            else
                local ability = resMgr:GetAbilityById(pkt.Param + 512)
                if ability and ability.Name[1] then
                    finalName = ability.Name[1]
                end
            end
            if finalName then
                local actorName = GetEntityName(pkt.UserId)
                for i, alert in ipairs(mobability.alertQueue) do
                    if alert.mob and alert.spell and normalize(alert.mob) == normalize(actorName) then
                        if (alert.type == "Spell" and normalize(alert.spell) == normalize(finalName))
                                or alert.type == "TP" then
                            alert.expires = os.clock()
                            break
                        end
                    end
                end
            end
        end

    elseif e.id == 0x00E then
        local upd = decodeMobUpdate(e)
        if upd then
            processMobUpdate(upd)
        end

    elseif e.id == 0x00A then
        resetZoneState(e)
    end

    refreshFlaggedEntities()
end)

--------------------------------------------------------------------------------
-- Evento d3d_present: Dibuja alertas y la ventana de configuración
--------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'mobability_present_cb', function()
    local io = imgui.GetIO()
    if not io or not io.DisplaySize then
        return
    end

    local screen_w = io.DisplaySize[0] or io.DisplaySize.x
    local screen_h = io.DisplaySize[1] or io.DisplaySize.y

    -- Control de testAlert para cerrar tras 10s
    if mobability.testAlertActive and os.clock() >= mobability.testAlertStart + 10 then
        mobability.settings.force_show_alert = false
        mobability.testAlertActive = false
        SaveConfig()
    end

    -- Eliminar alertas expiradas
    for i = #mobability.alertQueue, 1, -1 do
        if mobability.alertQueue[i].expires <= os.clock() then
            table.remove(mobability.alertQueue, i)
        end
    end

    local base_x = screen_w * mobability.settings.position.x
    local base_y = screen_h * mobability.settings.position.y

    -- Posicionar ventana de alertas
    if not mobability.alertInitialized then
        imgui.SetNextWindowPos({ base_x, base_y }, ImGuiCond_FirstUseEver, { 0, 0 })
        mobability.alertInitialized = true
    end

    -- Fondo translúcido si hay alertas
    if (#mobability.alertQueue > 0) and mobability.settings.background_active then
        imgui.PushStyleColor(ImGuiCol_WindowBg, mobability.settings.background_color)
    else
        imgui.PushStyleColor(ImGuiCol_WindowBg, { 1, 1, 1, 0 })
    end

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
                imgui.TextColored(mobability.settings.alert_colors.mob, alert.mob)
                imgui.SameLine(0, 0)

                if alert.type == "Spell" then
                    imgui.TextColored(mobability.settings.alert_colors.message, " starts casting: ")
                elseif alert.type == "TP" then
                    imgui.TextColored(mobability.settings.alert_colors.message, " readies ")
                else
                    imgui.TextColored(mobability.settings.alert_colors.message, " ")
                end

                imgui.SameLine(0, 0)
                if alert.type == "TP" then
                    imgui.TextColored(mobability.settings.alert_colors.action_tp, alert.spell)
                else
                    imgui.TextColored(mobability.settings.alert_colors.action_spell, alert.spell)
                end

                if alert.target then
                    imgui.SameLine(0, 0)
                    imgui.TextColored(mobability.settings.alert_colors.message, " on ")
                    imgui.SameLine(0, 0)
                    imgui.TextColored(mobability.settings.alert_colors.target, alert.target)
                end
            else
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

    -- Menu de configuración
    if mobability.guiOpen[1] then
        if imgui.Begin('Mobability Config', mobability.guiOpen, ImGuiWindowFlags_AlwaysAutoResize) then
            --------------------------------------------------------------------
            -- General Settings
            --------------------------------------------------------------------
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

            imgui.Spacing()
            --------------------------------------------------------------------
            -- TP Move Alerts
            --------------------------------------------------------------------
            imgui.Text("TP MOVE ALERTS")
            imgui.Separator()
            do
                local tmp_show_tp = { mobability.settings.show_tp_alerts }
                if imgui.Checkbox("Show TP Move Alerts", tmp_show_tp) then
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
                if imgui.SliderInt("Alert Limit (0 = unlimited)", tmp_limit_alerts, 0, 10) then
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
                if imgui.Checkbox("Use sound with TP Move", tmp_use_sound_tp) then
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

            imgui.Spacing()
            --------------------------------------------------------------------
            -- Background Settings
            --------------------------------------------------------------------
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

            imgui.Spacing()
            --------------------------------------------------------------------
            -- Test Alert
            --------------------------------------------------------------------
            if imgui.Button("Test Alert") then
                showFloatingAlert("Test alert: Config mode activated", { 0, 1, 1, 1 },
                        10, "Test", "Test", "Spell", {
                            mobColor = mobability.settings.alert_colors.mob,
                            spellColor = mobability.settings.alert_colors.action_spell,
                            target = "TestTarget"
                        }
                )
                mobability.testAlertActive = true
                mobability.testAlertStart = os.clock()
            end
        end
        imgui.End()
    end
end)

--------------------------------------------------------------------------------
-- Evento command: Alterna la ventana de configuración /mobability
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
-- (Opcional) Comando para imprimir la lista de mobs en combate (hate list)
--------------------------------------------------------------------------------
--[[
ashita.events.register('command', 'mobability_hate_list_cb', function(e)
    local args = e.command:args()
    if args[1] ~= '/mobht' then
        return
    end
    e.blocked = true
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    print("=== Party Hate List ===")
    for index, _ in pairs(flaggedEntities) do
        local mobName  = entMgr:GetName(index)    or "Unknown"
        local serverId = entMgr:GetServerId(index)or 0
        print(string.format("Index: %d | Name: %s | ServerID: %d", index, mobName, serverId))
    end
    print("=== End of list ===")
end)
]]

--------------------------------------------------------------------------------
-- Fin del addon
--------------------------------------------------------------------------------
return {}
