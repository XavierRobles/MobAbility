--------------------------------------------------------------------------------
-- Addon: mobability
-- Autor: Waky
-- Versión: 1.0.0
-- Descripción: Shows alerts for mob actions in combat based on your selected mode.
--------------------------------------------------------------------------------

addon.name      = 'mobability';
addon.author    = 'Waky';
addon.version   = '1.0.0';
addon.desc      = 'Mobability. Shows alerts for mob actions in combat based on your selected mode.';
addon.link      = '';

require('common');
local chat     = require('chat');
local imgui    = require('imgui');
local settings = require('settings');

-- Tiempo máximo de vida de una alerta si la acción no termina (en segundos)
local ALERT_MAX_LIFETIME = 10;

---------------------------------------------------------------
-- Función única para convertir ServerID -> localIndex
---------------------------------------------------------------
local function ResolveLocalIndexFromId(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    -- Comprueba si está en el rango "0x1000000" (NPC/MOB)
    if bit.band(id, 0x1000000) ~= 0 then
        local idx = bit.band(id, 0xFFF);
        if idx >= 0x900 then
            idx = idx - 0x100;
        end
        if idx < 0x900 and entMgr:GetServerId(idx) == id then
            return idx;
        end
    end
    -- Búsqueda general
    for i = 1, 0x8FF do
        if entMgr:GetServerId(i) == id then
            return i;
        end
    end
    return 0;
end

---------------------------------------------------------------
-- Devuelve el localIndex de un mob si es válido, o 0 si no
-- (combina chequeos de spawnFlags, renderFlags, etc.)
---------------------------------------------------------------
local function GetValidMobIndexFromServerId(serverId)
    local localIndex = ResolveLocalIndexFromId(serverId);
    if localIndex == 0 then
        return 0;
    end
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    -- Chequeo spawnFlags (0x10 = mob)
    local spawnFlags = entMgr:GetSpawnFlags(localIndex);
    if bit.band(spawnFlags, 0x10) == 0 then
        return 0;
    end
    -- Chequeo de renderFlags para asegurar que sea una entidad válida
    local renderFlags = entMgr:GetRenderFlags0(localIndex);
    if bit.band(renderFlags, 0x200) ~= 0x200 or bit.band(renderFlags, 0x4000) ~= 0 then
        return 0;
    end
    return localIndex;
end

---------------------------------------------------------------
-- Ajustes por defecto
---------------------------------------------------------------
local default_settings = T{
    position          = { x = 0.5, y = 0.25 },
    font_scale        = 1.5,
    show_alerts       = true,
    force_show_alert  = false,
    max_width         = 0,     -- 0 = auto resize
    alert_mode        = 0,     -- 0: Only your current target  --   1: All party/ally mobs
    alert_in_chat     = false,
    show_spell_alerts = true,
    show_tp_alerts    = true,
    limit_alerts      = 5,         -- Límite de alertas (0 = ilimitado)
    use_sound_spell   = false,     -- Usar sonido con Spell
    use_sound_tp      = false,     -- Usar sonido con TP Move
    alert_colors = {
        mob           = { 1, 0, 0, 1 },          -- Color del nombre del mob
        message       = { 1, 1, 1, 1 },          -- Color del texto fijo
        action_spell  = { 0, 1, 1, 1 },          -- Color de la acción Spell
        action_tp     = { 0.047, 1.0, 0, 1 },    -- Color de la acción TP move (#0CFF00FF)
        target        = { 1, 1, 0, 1 }           -- Color del nombre del target
    }
};

---------------------------------------------------------------
-- Variables internas y globales
---------------------------------------------------------------
flaggedEntities = flaggedEntities or T{};    -- Lista de mobs en combate (key = localIndex)
mobMapping      = mobMapping or T{};         -- Mapping: nombre (normalizado) -> último localIndex
mobTargets      = mobTargets or T{};         -- Nombre del receptor para cada mob

local mobability = T{
    settings        = settings.load(default_settings),
    guiOpen         = { false },
    alertQueue      = T{},
    testAlertActive = false,
    testAlertStart  = 0
};

---------------------------------------------------------------
-- Función auxiliar: Obtener info básica de una entidad
---------------------------------------------------------------
local function GetEntity(idx)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    local name = entMgr:GetName(idx);
    if not name or name == "" then return nil; end
    local hp = 100;
    if entMgr.GetHPPercent then
        hp = entMgr:GetHPPercent(idx);
    end
    local dist = 0;
    if entMgr.GetDistance then
        dist = entMgr:GetDistance(idx);
    end
    return { Name = name, HPPercent = hp, Distance = dist };
end

---------------------------------------------------------------
-- Actualiza el mapping de mobs (nombre -> localIndex)
---------------------------------------------------------------
local function updateMobMapping(actor_id)
    local localIdx = ResolveLocalIndexFromId(actor_id);
    if localIdx and localIdx ~= 0 then
        local entMgr = AshitaCore:GetMemoryManager():GetEntity();
        local name = entMgr:GetName(localIdx);
        if name and name ~= "" then
            mobMapping[(name:lower()):gsub('^%s*(.-)%s*$', '%1')] = localIdx;
        end
    end
end

---------------------------------------------------------------
-- Normaliza cadenas (para comparar sin mayúsc/minúsc ni espacios sobrantes)
---------------------------------------------------------------
local function normalize(str)
    return str and str:lower():gsub('%s+', ' '):gsub('^%s*(.-)%s*$', '%1') or nil;
end

---------------------------------------------------------------
-- Obtener nombre de entidad dado un serverId (por si se requiere)
---------------------------------------------------------------
local function GetEntityName(serverId)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    for i = 0, 2303 do
        if entMgr:GetServerId(i) == serverId then
            local nm = entMgr:GetName(i);
            if nm and nm ~= "" then
                return nm;
            end
        end
    end
    return "Unknown";
end

---------------------------------------------------------------
-- Funciones para obtener target actual
---------------------------------------------------------------
local function GetCurrentTargetIndex()
    local targetManager = AshitaCore:GetMemoryManager():GetTarget();
    local currentTargetIndex = targetManager:GetTargetIndex(0);
    if currentTargetIndex == 0 or currentTargetIndex >= 0x900 then
        return nil;
    end
    return currentTargetIndex;
end

local function GetCurrentTargetName()
    local idx = GetCurrentTargetIndex();
    if not idx then return nil; end
    return AshitaCore:GetMemoryManager():GetEntity():GetName(idx);
end

---------------------------------------------------------------
-- Reproduce el sonido de alerta
---------------------------------------------------------------
local function playAlertSound(alertType)
    if (alertType == "Spell" and mobability.settings.use_sound_spell) then
        ashita.misc.play_sound(addon.path .. 'sound/spell_alert.wav');
    elseif (alertType == "TP" and mobability.settings.use_sound_tp) then
        ashita.misc.play_sound(addon.path .. 'sound/tp_alert.wav');
    end
end

---------------------------------------------------------------
-- Muestra una alerta flotante + chat (opcional)
---------------------------------------------------------------
local function showFloatingAlert(text, color, duration, mob, spell, alertType, extra)
    -- Comprueba si el tipo de alerta está habilitado (Spell, TP, etc.)
    local showType = true;
    if alertType == "Spell" then
        showType = mobability.settings.show_spell_alerts;
    elseif alertType == "TP" then
        showType = mobability.settings.show_tp_alerts;
    end
    if not showType then
        return;
    end

    -- Si en settings está habilitado el aviso en chat
    if mobability.settings.alert_in_chat then
        print(chat.header('MobAbility'):append(chat.message(text)));
    end

    -- Si no hay que mostrar avisos flotantes, salir
    if not mobability.settings.show_alerts then
        return;
    end

    local d = duration or 99999;
    local alert = {
        text      = text,
        color     = color or { 1.0, 1.0, 0.0, 1.0 },
        expires   = os.clock() + d,
        startTime = os.clock(),
        mob       = mob or nil,
        spell     = spell or nil,
        type      = alertType or "Spell"
    };
    if extra then
        alert.mobColor   = extra.mobColor;
        alert.spellColor = extra.spellColor;
        alert.target     = extra.target;
    end

    table.insert(mobability.alertQueue, alert);
    playAlertSound(alert.type);
end

---------------------------------------------------------------
-- Manejo de party
---------------------------------------------------------------
local function fetchPartyMembers()
    local members = T{};
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party then
        for i = 0, 17 do
            if party:GetMemberIsActive(i) == 1 then
                table.insert(members, party:GetMemberServerId(i));
            end
        end
    end
    return members;
end

---------------------------------------------------------------
-- Decodifica el packet 0x28 en detalle
---------------------------------------------------------------
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
        act.Reaction      = read(5)
        act.Animation     = read(12)
        act.SpecialEffect = read(7)
        act.Knockback     = read(3)
        act.Param         = read(17)
        act.Message       = read(10)
        act.Flags         = read(31)
        if read(1) == 1 then
            act.AdditionalEffect = {
                Damage  = read(10),
                Param   = read(17),
                Message = read(10)
            }
        end
        if read(1) == 1 then
            act.SpikesEffect = {
                Damage  = read(10),
                Param   = read(14),
                Message = read(10)
            }
        end
        return act
    end

    -- Parsea un target (con ID y posibles acciones)
    local function parseTarget()
        local target = T{}
        target.Id = read(32)
        local actionCount = read(4)
        if actionCount > 0 then
            local acts = T{}
            for i = 1, actionCount do
                table.insert(acts, parseAction())
            end
            target.Actions = acts
        end
        return target
    end

    -- Comienza la construcción del paquete resultante
    local packet = T{}
    packet.UserId = read(32)
    local targetCounter = read(6)
    bits.pos = bits.pos + 4  -- saltamos padding
    packet.Type = read(4)
    
    if packet.Type == 8 or packet.Type == 9 then
        packet.Param      = read(16)
        packet.SpellGroup = read(16)
    else
        packet.Param = read(32)
    end
    
    packet.Recast  = read(32)
    packet.Targets = T{}
    
    if targetCounter > 0 then
        for i = 1, targetCounter do
            table.insert(packet.Targets, parseTarget())
        end
    end

    return packet
end


---------------------------------------------------------------
-- Decodifica el packet 0x00E para ver si hay cambio en claim
---------------------------------------------------------------
local function decodeMobUpdate(e)
    if e.id ~= 0x00E then
        return nil;
    end
    local mobUpd = T{};
    mobUpd.LocalIndex = struct.unpack('H', e.data, 0x08 + 1);
    mobUpd.NewClaimId = struct.unpack('I', e.data, 0x2C + 1);
    return mobUpd;
end

---------------------------------------------------------------
-- Procesa la actualización de claim
---------------------------------------------------------------
local function processMobUpdate(e)
    if not e or not e.NewClaimId then return; end
    -- Comprueba si es válido
    local ent = GetEntity(e.LocalIndex);
    if not ent then return; end

    local partyIDs = fetchPartyMembers();
    for _, pid in ipairs(partyIDs) do
        if pid == e.NewClaimId then
            flaggedEntities[e.LocalIndex] = 1;
            break;
        end
    end
end

---------------------------------------------------------------
-- Resetea estados al cambiar de zona
---------------------------------------------------------------
local function resetZoneState(e)
    flaggedEntities         = T{};
    mobability.alertQueue   = T{};
end

---------------------------------------------------------------
-- Limpia alertas caducadas y mobs que ya no tienen odio
---------------------------------------------------------------
local function refreshFlaggedEntities()
    local currentTime = os.clock();

    -- Elimina alertas viejas
    for i = #mobability.alertQueue, 1, -1 do
        local alert = mobability.alertQueue[i];
        if alert.expires <= currentTime
           or (alert.startTime and (currentTime - alert.startTime > ALERT_MAX_LIFETIME))
        then
            table.remove(mobability.alertQueue, i);
        end
    end

    -- Quita mobs que murieron o se alejaron
    for idx, _ in pairs(flaggedEntities) do
        local ent = GetEntity(idx);
        if ent then
            if ent.HPPercent <= 0 or (ent.Distance and ent.Distance > 2500) then
                flaggedEntities[idx] = nil;
            end
        else
            flaggedEntities[idx] = nil;
        end
    end
end

---------------------------------------------------------------
-- Evento text_in: unificamos la lógica de spells y TP moves
-- para extraer la parte repetitiva y mostrar alertas.
---------------------------------------------------------------
local function HandleMobActionText(mobName, actionName, targetName, actionType, myName)
    -- Evita self-cast
    if normalize(mobName) == normalize(myName) then
        return;
    end

    -- Chequeo de "alert_mode"
    if mobability.settings.alert_mode == 1 then
        -- Modo 1: Todos los mobs que tengan odio con party
        local mappedIndex = mobMapping[normalize(mobName)];
        if not mappedIndex or not flaggedEntities[mappedIndex] then
            return;
        end
    else
        -- Modo 0: Sólo el mob que sea tu target actual
        local targetIndex = GetCurrentTargetIndex();
        if not targetIndex or not flaggedEntities[targetIndex] then
            return;
        end
        local mappedIndex = mobMapping[normalize(mobName)];
        if not mappedIndex or mappedIndex ~= targetIndex then
            return;
        end
    end

    -- Construimos el mensaje final
    local msg;
    if actionType == "Spell" then
        msg = string.format('%s starts casting %s on %s', mobName, actionName, targetName);
    else
        -- "TP"
        msg = string.format('%s readies %s on %s', mobName, actionName, targetName);
    end

    -- Mostramos alerta
    showFloatingAlert(msg, nil, 99999, mobName, actionName, actionType, {
        mobColor   = mobability.settings.alert_colors.mob,
        spellColor = (actionType == "TP")
                     and mobability.settings.alert_colors.action_tp
                     or  mobability.settings.alert_colors.action_spell,
        target     = targetName
    });
end

ashita.events.register('text_in', 'text_in_cb', function(e)
    local line             = e.message;
    local currentTargetName= GetCurrentTargetName() or "None";
    local myName           = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);

    -- Detectar Spell ("starts casting")
    do
        local mob_name, spell_name, targetName = line:match('^(.-) starts casting ([%a%s%-]+) on ([%a%s%-]+)%.');
        if not mob_name then
            mob_name, spell_name = line:match('^(.-) starts casting ([%a%s%-]+)%.');
            targetName = currentTargetName;
        end
        if mob_name and spell_name then
            mob_name = mob_name:gsub('^The%s+', '');
            -- Usar mobTargets si ya se conoce el objetivo
            if mobTargets[normalize(mob_name)] then
                targetName = mobTargets[normalize(mob_name)];
            elseif normalize(targetName) == normalize(mob_name) then
                targetName = currentTargetName;
            end
            HandleMobActionText(mob_name, spell_name, targetName, "Spell", myName);
        end
    end

    -- Detectar TP move ("readies")
    do
        local mob_tp, tp_move, targetNameTP = line:match('^(.-) readies ([%a%s%-]+) on ([%a%s%-]+)%.');
        if not mob_tp then
            mob_tp, tp_move = line:match('^(.-) readies ([%a%s%-]+)%.');
            targetNameTP = currentTargetName;
        end
        if mob_tp and tp_move then
            mob_tp = mob_tp:gsub('^The%s+', '');
            if mobTargets[normalize(mob_tp)] then
                targetNameTP = mobTargets[normalize(mob_tp)];
            elseif normalize(targetNameTP) == normalize(mob_tp) then
                targetNameTP = currentTargetName;
            end
            HandleMobActionText(mob_tp, tp_move, targetNameTP, "TP", myName);
        end
    end
end);

---------------------------------------------------------------
-- Evento packet_in: procesa packets 0x28 (acciones) y 0x00E (claim),
-- y 0x00A para reset en cambio de zona.
---------------------------------------------------------------
ashita.events.register('packet_in', 'mobability_packet_in_cb', function(e)
    if e.id == 0x28 then
        -- Decodifica la acción
        local pkt = decodeActionPacket(e);
        if not pkt then return; end

        -- Comprueba si no es el propio jugador
        local myServerId = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0);
        if pkt.UserId == myServerId then
            return;
        end

        -- Verifica si es un mob válido
        local localIdx = GetValidMobIndexFromServerId(pkt.UserId);
        if localIdx == 0 then
            return;
        end

        -- Actualiza el mobMapping con este mob
        updateMobMapping(pkt.UserId);

        -- Si la categoría es 4 o 11, significa que la acción (Spell/TP) ya finalizó.
        if pkt.Type == 4 or pkt.Type == 11 then
            local resMgr = AshitaCore:GetResourceManager();
            local finalName = nil;
            -- Primero buscamos si es un Spell
            local spell = resMgr:GetSpellById(pkt.Param);
            if spell and spell.Name[1] then
                finalName = spell.Name[1];
            else
                -- Si no, puede ser Ability (TP move)
                local ability = resMgr:GetAbilityById(pkt.Param + 512);
                if ability and ability.Name[1] then
                    finalName = ability.Name[1];
                end
            end
            if finalName then
                local actorName = GetEntityName(pkt.UserId);
                -- Buscamos en la cola de alertas y expiramos la que coincida
                for i, alert in ipairs(mobability.alertQueue) do
                    if alert.mob and alert.spell then
                        if normalize(alert.mob) == normalize(actorName) then
                            if alert.type == "Spell" then
                                if normalize(alert.spell) == normalize(finalName) then
                                    alert.expires = os.clock();
                                    break;
                                end
                            elseif alert.type == "TP" then
                                alert.expires = os.clock();
                                break;
                            end
                        end
                    end
                end
            end
        end

        -- Marca este mob como "flagged" si atacó o fue atacado por party
        local entMgr  = AshitaCore:GetMemoryManager():GetEntity();
        local partyIDs= fetchPartyMembers();
        for _, tgt in ipairs(pkt.Targets) do
            if tgt and tgt.Id then
                for _, pid in ipairs(partyIDs) do
                    if pid == tgt.Id then
                        flaggedEntities[localIdx] = 1;
                        local mobName   = entMgr:GetName(localIdx) or "Unknown";
                        local targetIdx = ResolveLocalIndexFromId(tgt.Id);
                        local targetName= entMgr:GetName(targetIdx) or "Unknown";
                        mobTargets[normalize(mobName)] = targetName;
                        break;
                    end
                end
            end
        end

    elseif e.id == 0x00E then
        -- Packet de actualización de Mob (claim, etc.)
        local upd = decodeMobUpdate(e);
        if upd then
            processMobUpdate(upd);
        end

    elseif e.id == 0x00A then
        -- Cambio de zona
        resetZoneState(e);
    end

    -- Refresca alertas y mobs en cada packet
    refreshFlaggedEntities();
end);

---------------------------------------------------------------
-- Evento d3d_present: Dibuja alertas y la ventana de configuración
---------------------------------------------------------------
ashita.events.register('d3d_present', 'mobability_present_cb', function()
    local io = imgui.GetIO();
    if not io or not io.DisplaySize then
        return;
    end

    local screen_w = io.DisplaySize[0] or io.DisplaySize.x;
    local screen_h = io.DisplaySize[1] or io.DisplaySize.y;

    -- Control de testAlert para cerrar tras 10s
    if mobability.testAlertActive and os.clock() >= mobability.testAlertStart + 10 then
        mobability.settings.force_show_alert = false;
        mobability.testAlertActive = false;
        settings.save();
    end

    local base_x = screen_w * mobability.settings.position.x;
    local base_y = screen_h * mobability.settings.position.y;

    -- Eliminación adicional de alertas caducadas
    -- (Puede parecer redundante con refreshFlaggedEntities, pero se deja para no alterar lógica)
    for i = #mobability.alertQueue, 1, -1 do
        if mobability.alertQueue[i].expires <= os.clock() then
            table.remove(mobability.alertQueue, i);
        end
    end

    -- Posición y estilo de la ventana de alertas
    if not mobability.alertInitialized then
        imgui.SetNextWindowPos({ base_x, base_y }, ImGuiCond_FirstUseEver, { 0, 0 });
        mobability.alertInitialized = true;
    end
    imgui.SetNextWindowBgAlpha(0.0);

    local alert_flags = bit.bor(
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoScrollbar
    );
    if not mobability.guiOpen[1] then
        alert_flags = bit.bor(alert_flags, ImGuiWindowFlags_NoMove);
    end

    local style = imgui.GetStyle();
    local oldBorderSize = style.WindowBorderSize;
    style.WindowBorderSize = 0;

    if imgui.Begin('##mobability_alert_list', false, alert_flags) then
        imgui.SetWindowFontScale(mobability.settings.font_scale);

        -- Guarda nueva posición al mover la ventana
        local posx, posy = imgui.GetWindowPos();
        mobability.settings.position.x = posx / screen_w;
        mobability.settings.position.y = posy / screen_h;
        settings.save();

        local count = 0;
        for _, alert in ipairs(mobability.alertQueue) do
            -- Respeta el "limit_alerts" si > 0
            if mobability.settings.limit_alerts > 0 and count >= mobability.settings.limit_alerts then
                break;
            end
            count = count + 1;

            if alert.mob and alert.spell then
                imgui.TextColored(mobability.settings.alert_colors.mob, alert.mob);
                imgui.SameLine(0, 0);

                if alert.type == "Spell" then
                    imgui.TextColored(mobability.settings.alert_colors.message, " starts casting: ");
                elseif alert.type == "TP" then
                    imgui.TextColored(mobability.settings.alert_colors.message, " readies ");
                else
                    imgui.TextColored(mobability.settings.alert_colors.message, " ");
                end

                imgui.SameLine(0, 0);
                if alert.type == "TP" then
                    imgui.TextColored(mobability.settings.alert_colors.action_tp, alert.spell);
                else
                    imgui.TextColored(mobability.settings.alert_colors.action_spell, alert.spell);
                end

                if alert.target then
                    imgui.SameLine(0, 0);
                    imgui.TextColored(mobability.settings.alert_colors.message, " on ");
                    imgui.SameLine(0, 0);
                    imgui.TextColored(mobability.settings.alert_colors.target, alert.target);
                end
            else
                imgui.PushStyleColor(ImGuiCol_Text, alert.color);
                imgui.TextUnformatted(alert.text);
                imgui.PopStyleColor();
            end
        end
    end
    imgui.End();
    style.WindowBorderSize = oldBorderSize;

    -- Ventana de Config
    if mobability.guiOpen[1] then
        if imgui.Begin('Mobability Config', mobability.guiOpen, ImGuiWindowFlags_AlwaysAutoResize) then
            imgui.Text("GENERAL SETTINGS");
            imgui.Separator();

            do
                local show_alerts = { mobability.settings.show_alerts };
                if imgui.Checkbox("Show floating alerts", show_alerts) then
                    mobability.settings.show_alerts = not mobability.settings.show_alerts;
                    settings.save();
                end

                local alert_in_chat = { mobability.settings.alert_in_chat };
                if imgui.Checkbox("Show alerts in chat", alert_in_chat) then
                    mobability.settings.alert_in_chat = not mobability.settings.alert_in_chat;
                    settings.save();
                end

                local font_scale = { mobability.settings.font_scale };
                if imgui.SliderFloat("Text size", font_scale, 0.5, 5.0) then
                    mobability.settings.font_scale = font_scale[1];
                    settings.save();
                end
            end

            imgui.Spacing();
            imgui.Text("SPELL ALERTS");
            imgui.Separator();
            do
                local show_spell = { mobability.settings.show_spell_alerts };
                if imgui.Checkbox("Show Spell Alerts", show_spell) then
                    mobability.settings.show_spell_alerts = not mobability.settings.show_spell_alerts;
                    settings.save();
                end
            end

            imgui.Spacing();
            imgui.Text("TP MOVE ALERTS");
            imgui.Separator();
            do
                local show_tp = { mobability.settings.show_tp_alerts };
                if imgui.Checkbox("Show TP Move Alerts", show_tp) then
                    mobability.settings.show_tp_alerts = not mobability.settings.show_tp_alerts;
                    settings.save();
                end
            end

            imgui.Spacing();
            imgui.Text("ALERT MODE");
            imgui.Separator();
            do
                if imgui.RadioButton("Only your current target", mobability.settings.alert_mode == 0) then
                    mobability.settings.alert_mode = 0;
                    settings.save();
                end
                imgui.SameLine();
                if imgui.RadioButton("All party/ally mobs", mobability.settings.alert_mode == 1) then
                    mobability.settings.alert_mode = 1;
                    settings.save();
                end
            end

            imgui.Spacing();
            imgui.Text("ALERT LIMIT");
            imgui.Separator();
            do
                local limit_alerts = { mobability.settings.limit_alerts };
                if imgui.SliderInt("Alert Limit (0 = unlimited)", limit_alerts, 0, 10) then
                    mobability.settings.limit_alerts = limit_alerts[1];
                    settings.save();
                end
            end

            imgui.Spacing();
            imgui.Text("SOUND SETTINGS");
            imgui.Separator();
            do
                local use_sound_spell = { mobability.settings.use_sound_spell };
                if imgui.Checkbox("Use sound with Spell", use_sound_spell) then
                    mobability.settings.use_sound_spell = not mobability.settings.use_sound_spell;
                    settings.save();
                end
                local use_sound_tp = { mobability.settings.use_sound_tp };
                if imgui.Checkbox("Use sound with TP Move", use_sound_tp) then
                    mobability.settings.use_sound_tp = not mobability.settings.use_sound_tp;
                    settings.save();
                end
            end

            imgui.Spacing();
            imgui.Text("ALERT COLORS");
            imgui.Separator();
            do
                local temp_mob = { unpack(mobability.settings.alert_colors.mob) };
                if imgui.ColorEdit4("Mob Color", temp_mob) then
                    mobability.settings.alert_colors.mob = temp_mob;
                    settings.save();
                end

                local temp_message = { unpack(mobability.settings.alert_colors.message) };
                if imgui.ColorEdit4("Message Color", temp_message) then
                    mobability.settings.alert_colors.message = temp_message;
                    settings.save();
                end

                local temp_action_spell = { unpack(mobability.settings.alert_colors.action_spell) };
                if imgui.ColorEdit4("Spell Action Color", temp_action_spell) then
                    mobability.settings.alert_colors.action_spell = temp_action_spell;
                    settings.save();
                end

                local temp_action_tp = { unpack(mobability.settings.alert_colors.action_tp) };
                if imgui.ColorEdit4("TP Move Color", temp_action_tp) then
                    mobability.settings.alert_colors.action_tp = temp_action_tp;
                    settings.save();
                end

                local temp_target = { unpack(mobability.settings.alert_colors.target) };
                if imgui.ColorEdit4("Target Color", temp_target) then
                    mobability.settings.alert_colors.target = temp_target;
                    settings.save();
                end
            end

            imgui.Spacing();
            if imgui.Button("Test Alert") then
                showFloatingAlert("Test alert: Config mode activated", {0,1,1,1}, 10, "Test", "Test", "Spell", {
                    mobColor   = mobability.settings.alert_colors.mob,
                    spellColor = mobability.settings.alert_colors.action_spell,
                    target     = "TestTarget"
                });
                mobability.testAlertActive = true;
                mobability.testAlertStart  = os.clock();
            end
        end
        imgui.End();
    end
end);

---------------------------------------------------------------
-- Evento command: Alterna la ventana de configuración /mobability
---------------------------------------------------------------
ashita.events.register('command', 'mobability_command_cb', function(e)
    local args = e.command:args();
    if #args == 0 then return; end
    if args[1] == '/mobability' or args[1] == '/mb' then
        e.blocked = true;
        mobability.guiOpen[1] = not mobability.guiOpen[1];
    end
end);

---------------------------------------------------------------
-- (Opcional) Comando para imprimir la lista de mobs in combat (party hate list) DEV only
---------------------------------------------------------------
-- ashita.events.register('command', 'mobability_hate_list_cb', function(e)
--   local args = e.command:args();
--   if args[1] ~= '/mobht' then return; end
--    e.blocked = true;
--    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
--   print("=== Party Hate List ===");
 --   for index, _ in pairs(flaggedEntities) do
 --       local mobName = entMgr:GetName(index) or "Unknown";
 --       local serverId = entMgr:GetServerId(index) or 0;
 --       print(string.format("Index: %d | Name: %s | ServerID: %d", index, mobName, serverId));
 --   end
--    print("=== End of list ===");
--end);

--------------------------------------------------------------------------------
-- End of addon
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Fin del addon
--------------------------------------------------------------------------------
return {};
