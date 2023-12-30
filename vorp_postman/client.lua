local RSGCore = exports['rsg-core']:GetCoreObject()
local PromptGroup = GetRandomIntInRange(0, 0xffffff)
local PromptGroup2 = GetRandomIntInRange(0, 0xffffff)
local PromptGroup3 = GetRandomIntInRange(0, 0xffffff)
local OfficeBlips = {}
local OfficePeds =  {}
local isWorking = false
local KeyToStart = Config.StartKey

local cacheVehicle = 0
local postOffice = 0
local deliverLocation = {}
local PackageList = {}
local KeyToPick = 0
local deliverypoints = {}
local StartButton
local StopButton
local AbbortButton
local startvehicletimer = false
local starttimer = false
local timer = Config.AfkTimer
local timervehicle = Config.VehicleTimer
local Crates = { "p_crate03d", "P_CRATE03X", "p_crate03c" }
local cinematicoff = false
local getNextJobZone = {}

local _in = Citizen.InvokeNative

Citizen.CreateThread(function()
    StartButton = CreateButtonPrompt(PromptGroup, Config.Key, _U("StartButtonText"))
    StopButton = CreateButtonPrompt(PromptGroup2, Config.Key,  _U("StopButtonText"))
    AbbortButton = CreateButtonPrompt(PromptGroup3, Config.Key, _U("AbbortButtonText"))
	while true do
        local sleep = true
        local pid = PlayerPedId()
        local pCoords = GetEntityCoords(pid, true, true)

        for i, k in pairs(Config.PostOffices) do
            local x = k.EnterOffice[1]
            local y = k.EnterOffice[2]
            local z = k.EnterOffice[3]
            local radius = k.EnterOffice[4]
            local pos = vector3(x, y, z)
            local dist = #(pCoords - pos)
            if (dist <= radius) then
                sleep = false
                if (isWorking) then
                    local label = CreateVarString(10, 'LITERAL_STRING', _U("JobEnd"))
                    PromptSetActiveGroupThisFrame(PromptGroup2, label)
                    if PromptHasHoldModeCompleted(StopButton) then
                        ClearAll()
                        isWorking = false
                        StopJob()
                        Wait(5000)
                    end
                else
                    local label = CreateVarString(10, 'LITERAL_STRING', _U("JobStart"))
                    PromptSetActiveGroupThisFrame(PromptGroup, label)
                    if PromptHasHoldModeCompleted(StartButton) then
                        StartJob(i)
                        Wait(5000)
                    end
                end
            end
        end
        if sleep then
            Citizen.Wait(500)
        else
            Citizen.Wait(0)
        end
	end
end)

function CreateButtonPrompt(promptGroup, control, text)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, control)
    PromptSetText(prompt, CreateVarString(10, "LITERAL_STRING", text))
    PromptSetHoldMode(prompt, true)
    PromptSetGroup(prompt, promptGroup)
    PromptRegisterEnd(prompt)
    return prompt
end

function ClearAll()
    for i, k in pairs(PackageList) do
        local _package = k
        DeleteObject(_package)
    end

    DeleteVehicle(cacheVehicle)
    _in(0x9E0AB9AAEE87CE28)
end

function StartJob(i)
    StartVehicleTimer()
    if Config.DisableCinematicMode then
        StopCinematic()
    end
    KeyToPick = Config.PaketButton
    deliverypoints = {}
    postOffice = i
    isWorking = true
    local _Po = Config.PostOffices[i]
    getNextJobZone = randomJobZone(_Po.JobZones)
    local vehicleHash = GetHashKey("CART06")
    RequestModel(vehicleHash)
    while not HasModelLoaded(vehicleHash) do
        RequestModel(vehicleHash)
        Wait(100)
    end
    cacheVehicle = CreateVehicle(vehicleHash, _Po.VehicleSpawn[1], _Po.VehicleSpawn[2], _Po.VehicleSpawn[3], _Po.VehicleSpawn[4], true, true)
    SetEntityAsMissionEntity(cacheVehicle, true, true)
    if Config.EnableVehicleBlip then
        local blip = _in(0x23F74C2FDA6E7C61, 1664425300, cacheVehicle)
        SetBlipSprite(blip, Config.Vehicleplipsprite, 1)
        _in(0x9CB1A1623062F402, blip, _U("VehicleBlipName"))
    end
    SpawnPackages()
    JobRun()
end

function kmhToMps(speed)
    return speed / 3.6
end

Citizen.CreateThread(function()
    if Config.EnableMaxVehSpeed then
        while true do
            local sleep = true
    
            if cacheVehicle ~= 0 then
                sleep = false
                local maxSpeedKmh = Config.MaxVehicleSpeed -- Maximale Geschwindigkeit in Kilometern pro Stunde
                local maxSpeedMps = kmhToMps(maxSpeedKmh) -- Maximale Geschwindigkeit in Metern pro Sekunde
    
                local currentSpeed = GetEntitySpeed(cacheVehicle) -- Aktuelle Geschwindigkeit des Fahrzeugs in Metern pro Sekunde
    
                -- Reduziere die Geschwindigkeit, wenn sie die maximale Geschwindigkeit überschreitet
                if currentSpeed > maxSpeedMps then
                    local forwardVector = GetEntityForwardVector(cacheVehicle)
                    SetEntityVelocity(cacheVehicle, forwardVector.x * maxSpeedMps, forwardVector.y * maxSpeedMps, forwardVector.z * maxSpeedMps)
                end
            end
            if sleep then
                Citizen.Wait(1000)
            else
                Citizen.Wait(0)
            end
        end
    end
end)

function SpawnPackages()
    for i = 1, 5, 1 do
        local Pos = GetEntityCoords(cacheVehicle, true, true)
        local packageHash = GetHashKey(Crates[math.random(1, #Crates)])
        RequestModel(packageHash)
        while not HasModelLoaded(packageHash) do
            RequestModel(packageHash)
            Wait(1)
        end
        local packageEntity = CreateObject(packageHash, Pos.x, Pos.y, Pos.z, true, true, true, true, true)
        SetEntityAsMissionEntity(packageEntity, true, true)
        table.insert(PackageList, packageEntity)
        _in(0x6B9BBD38AB0796DF, packageEntity, cacheVehicle, 0, 0.0, (-1.8 + (i / 2.0)), 0.09, 0.0, 0.0, 0.0, 0, 0, 0, 0, 2, true)
    end
    TriggerServerEvent("vorp_postman:GiveCartPackage", cacheVehicle, PackageList)
end

function JobRun()
    Citizen.CreateThread(function ()
        NewLocation()
        while (isWorking and DoesEntityExist(cacheVehicle) and deliverLocation ~= nil and #PackageList ~= 0) do
            local ped = PlayerPedId()
            local Pos = GetEntityCoords(ped)
            local currentPackage = PackageList[1]
            if (IsEntityAttachedToEntity(currentPackage, ped)) then
                DisableControlAction(0, 0xAC4BD4F1, true)-- TAB
                if Config.disableRunning then
                    DisableControlAction(0, 0x8FFC75D6, true)-- Shift
                end
                DisableControlAction(0, 0x8CC9CD42, true)-- X
                DisableControlAction(0, 0xE31C6A41, true)-- M
  
                local deliverLoc = vector3(deliverLocation.Pos[1], deliverLocation.Pos[2],deliverLocation.Pos[3])
                local distance = GetDistanceBetweenCoords(Pos.x, Pos.y, Pos.z, deliverLoc.x, deliverLoc.y, deliverLoc.z, true)
                if (distance <= 15.0) then
                    local zoneName = deliverLocation.Name
                    local displayText = "Paket ablegen beim ".. zoneName .. ""
                    if (distance <= 1.5) then
                        displayText = _U("LabelPickup") .. displayText
                        if (IsControlJustReleased(0, KeyToPick)) then
                            DropPackage(currentPackage)
                        end
                    end
                    DrawText3D(deliverLoc.x, deliverLoc.y, deliverLoc.z, displayText)
                else
                    local zoneName = deliverLocation.Name
                    local label = CreateVarString(10, 'LITERAL_STRING', _U("JobWork") .. " ".. zoneName)
                    PromptSetActiveGroupThisFrame(PromptGroup3, label)
                    if PromptHasHoldModeCompleted(AbbortButton) then
                        table.remove(PackageList, 1)
                        DetachEntity(currentPackage, false, true)
                        ClearPedTasks(PlayerPedId(), 1, 1)
                        starttimer = false
                        Citizen.Wait(2000)
                        while (not NetworkHasControlOfEntity(currentPackage)) do
                            Citizen.Wait(0)
                            NetworkRequestControlOfEntity(currentPackage)
                        end
                
                        Citizen.Wait(100)
                        DeleteEntity(currentPackage)
                        NewLocation()
                    end
                end
            else
                local packageLoc = GetEntityCoords(currentPackage)
                local distance = #(Pos - packageLoc)
                if (distance <= 5.0) and not IsPedInAnyVehicle(PlayerPedId(), true) then
                    local displayText = "Paket nehmen"
                    if (distance <= 1.5) and not IsPedInAnyVehicle(PlayerPedId(), true) then
                        _in(0x7DFB49BCDB73089A, currentPackage, true)
                        displayText = displayText .. _U("LabelPickup")
                        if (IsControlJustReleased(0, KeyToPick)) then
                            PickPackage(currentPackage)
                        end
                    end
                    DrawText3D(packageLoc.x, packageLoc.y, packageLoc.z, displayText)
                end
            end
            Wait(0)
        end 
    end)
end

function StopCinematic()
    cinematicoff = true
    Citizen.CreateThread(function ()
        while true do
            if cinematicoff then
                SetCinematicButtonActive(false)
                Citizen.Wait(0)
            else
                return
            end
            
        end
    end)
end

function StartVehTimer(packageEntity)
    starttimer = true
    timer = Config.AfkTimer * 60 * 1000
    Citizen.CreateThread(function ()
        while starttimer do
            if timer > 0 then
                timer = timer - 1000
                --print(timer)
            else
                starttimer = false
                DetachEntity(packageEntity, false, true)
                ClearPedTasks(PlayerPedId(), 1, 1)

                Citizen.Wait(1000)

                while (not NetworkHasControlOfEntity(packageEntity)) do
                    Citizen.Wait(0)
                    NetworkRequestControlOfEntity(packageEntity)
                end

                Citizen.Wait(100)
                DeleteEntity(packageEntity)

                ClearAll()
                isWorking = false
                cacheVehicle = 0
                postOffice = 0
                deliverLocation = {}
                PackageList = {}
                KeyToPick = 0
                deliverypoints = {}
                startvehicletimer = false
                _in(0x9E0AB9AAEE87CE28)
                deliverypoints = {}
                cinematicoff = false
                RSGCore.Functions.Notify('Postman : You Took A Long Time....', 'error')
                --TriggerEvent('vorp:NotifyLeft', _U("JobTip"), _U("JobTip2"), Config.NotifyDict, Config.NotifyTexture, Config.NotifyTime, Config.NotifyColor)
                return
            end
            Citizen.Wait(1000)
        end
    end)
end

function StartVehicleTimer()
    startvehicletimer = true
    timervehicle = Config.VehicleTimer * 60 * 1000
    Citizen.CreateThread(function ()
        while startvehicletimer do
            if timervehicle > 0 then
                timervehicle = timervehicle - 1000
                --print(timervehicle)
            else
                startvehicletimer = false
                DetachEntity(packageEntity, false, true)
                ClearPedTasks(PlayerPedId(), 1, 1)

                Citizen.Wait(1000)

                while (not NetworkHasControlOfEntity(packageEntity)) do
                    Citizen.Wait(0)
                    NetworkRequestControlOfEntity(packageEntity)
                end

                Citizen.Wait(100)
                DeleteEntity(packageEntity)

                ClearAll()
                isWorking = false
                cacheVehicle = 0
                postOffice = 0
                deliverLocation = {}
                PackageList = {}
                KeyToPick = 0
                deliverypoints = {}
                startvehicletimer = false
                _in(0x9E0AB9AAEE87CE28)
                deliverypoints = {}
                cinematicoff = false
                --TriggerEvent('vorp:NotifyLeft', _U("JobTip"), _U("JobTip2"), Config.NotifyDict, Config.NotifyTexture, Config.NotifyTime, Config.NotifyColor)
                RSGCore.Functions.Notify('Postman : You Took A Long Time....', 'error')
                return
            end
            Citizen.Wait(1000)
        end
    end)
end

function StopJob()
    cacheVehicle = 0
    postOffice = 0
    deliverLocation = {}
    PackageList = {}
    KeyToPick = 0
    deliverypoints = {}
    startvehicletimer = false
    cinematicoff = false
    --TriggerEvent('vorp:NotifyLeft', _U("JobTip"), _U("JobEnd2"), Config.NotifyDict, Config.NotifyTexture, Config.NotifyTime, Config.NotifyColor)
     RSGCore.Functions.Notify('Postman : Thank you for your work, see you later', 'error')
end

function NewLocation()
        if (#PackageList <= 0) then
            RSGCore.Functions.Notify('Postman : Return to the office and hand over the carriage, you have delivered all the packages', 'error')
            --TriggerEvent('vorp:NotifyLeft', _U("JobTip"), _U("JobEnd3"), Config.NotifyDict, Config.NotifyTexture, Config.NotifyTime, Config.NotifyColor)
            _in(0x9E0AB9AAEE87CE28)
            deliverLocation = {}
            deliverypoints = {}
            return
        end
        deliverLocation = getNextJobZone()

        table.insert(deliverypoints, deliverLocation)
        StartGpsMultiRoute(70, true, true)
        _in(0x64C59DD6834FA942, deliverLocation.Pos[1], deliverLocation.Pos[2], deliverLocation.Pos[3])
        _in(0x4426D65E029A4DC0, true)
        local zoneName = deliverLocation.Name
        RSGCore.Functions.Notify('Postman : Drive to '..zoneName..' and deliver the package there', 'error')
        --TriggerEvent('vorp:NotifyLeft', _U("JobTip"), _U("JobWork2")..zoneName.._U("JobWork3"), Config.NotifyDict, Config.NotifyTexture, Config.NotifyTime, Config.NotifyColor)
end

function PickPackage(packageEntity)
    Citizen.CreateThread(function ()
        LoadAnim("mech_carry_box")

        _in(0xEA47FE3719165B94, PlayerPedId(), "mech_carry_box", "idle", 1.0, 8.0, -1, 31, 0, 0, 0, 0)
        _in(0x6B9BBD38AB0796DF, packageEntity, PlayerPedId(), GetEntityBoneIndexByName(PlayerPedId(), "SKEL_R_Finger12"), 0.20, -0.028, 0.001, 15.0, 175.0, 0.0, true, true, false, true, 1, true)
        StartVehTimer(packageEntity)
        while (IsEntityAttachedToEntity(packageEntity, PlayerPedId())) do
            _in(0x7DFB49BCDB73089A, packageEntity, false)
            if (not IsEntityPlayingAnim(PlayerPedId(), "mech_carry_box", "idle", 3)) then
                _in(0xEA47FE3719165B94, PlayerPedId(), "mech_carry_box", "idle", 1.0, 8.0, -1, 31, 0, 0, 0, 0)
            end
            Citizen.Wait(0)
        end
    end)
end

function DropPackage(packageEntity)
    Citizen.CreateThread(function ()
        table.remove(PackageList, 1)
        DetachEntity(packageEntity, false, true)
        ClearPedTasks(PlayerPedId(), 1, 1)
        starttimer = false

        Citizen.Wait(2000)
        while (not NetworkHasControlOfEntity(packageEntity)) do
            Citizen.Wait(0)
            NetworkRequestControlOfEntity(packageEntity)
        end

        Citizen.Wait(100)
        DeleteEntity(packageEntity)
        TriggerServerEvent("vorp_postman:GetReward", postOffice, deliverLocation)
        NewLocation()
    end)
    
end

function LoadAnim(dict)
    _in(0xA862A2AD321F94B4, dict)
    while (not _in(0x27FF6FE8009B40CA, dict)) do
        Wait(100)
    end
end

function DrawText3D(x, y, z, text)
    local onScreen,_x,_y=GetScreenCoordFromWorldCoord(x, y, z)
    local px,py,pz=table.unpack(GetGameplayCamCoord())  
    local dist = GetDistanceBetweenCoords(px,py,pz, x,y,z, 1)
    local str = CreateVarString(10, "LITERAL_STRING", text, Citizen.ResultAsLong())
    if onScreen then
    	SetTextScale(0.30, 0.30)
  		SetTextFontForCurrentCommand(1)
    	SetTextColor(255, 255, 255, 215)
    	SetTextCentre(1)
    	DisplayText(str,_x,_y)
    	local factor = (string.len(text)) / 225
    	DrawSprite("feeds", "hud_menu_4a", _x, _y+0.0125,0.015+ factor, 0.03, 0.1, 35, 35, 35, 190, 0)
    end
end

function DrawTxt(text, x, y, fontscale, fontsize, r, g, b, alpha, textcentred, shadow)
    local str = CreateVarString(10, "LITERAL_STRING", text, Citizen.ResultAsLong())
    SetTextScale(fontscale, fontsize)
    SetTextColor(r, g, b, alpha)
    SetTextCentre(textcentred)
    if (shadow) then
        SetTextDropshadow(1, 0, 0, 0, 255)
    end
    --Function.Call(Hash.SET_TEXT_FONT_FOR_CURRENT_COMMAND, 1)
    _in(0xADA9255D, 1)
    DisplayText(str, x, y)
end

function InitPostMan()
    Citizen.CreateThread(function ()
        for i, k in pairs(Config.PostOffices) do
            local ped = k.NPCModel
            local pedHash = GetHashKey(ped)
            RequestModel(pedHash)
            while not HasModelLoaded(pedHash) do
                RequestModel(pedHash)
                Citizen.Wait(1)
            end
            ---LoadModel(pedHash)
            local blipIcon = k.BlipIcon
            local x = k.EnterOffice[1]
            local y = k.EnterOffice[2]
            local z = k.EnterOffice[3]
            local Pedx = k.NPCOffice[1]
            local Pedy = k.NPCOffice[2]
            local Pedz = k.NPCOffice[3]
            local Pedh = k.NPCOffice[4]
            
            if k.Blip then
                local _blip = _in(0x554D9D53F696D002, 1664425300, x, y, z)
                _in(0x74F74D3207ED525C, _blip, blipIcon, 1)
                _in(0x9CB1A1623062F402, _blip, k.Name)
                table.insert(OfficeBlips, _blip)
            end
            if k.NPC then
                local _PedOffice = CreatePed(pedHash, Pedx, Pedy, Pedz, Pedh, false, true, true, true)
                _in(0x283978A15512B2FE, _PedOffice, true)
                table.insert(OfficePeds, _PedOffice)
                SetEntityNoCollisionEntity(PlayerPedId(), _PedOffice, false)
                SetEntityCanBeDamaged(_PedOffice, false)
                SetEntityInvincible(_PedOffice, true)
                SetBlockingOfNonTemporaryEvents(_PedOffice, true)
                SetPedCanBeTargetted(_PedOffice, false)
                FreezeEntityPosition(_PedOffice, true)
                SetModelAsNoLongerNeeded(pedHash)
            end
        end
    end)
end

function LoadModel(model)
    Citizen.CreateThread(function ()
        RequestModel(model)
        while not HasModelLoaded(model) do
            RequestModel(model)
            Citizen.Wait(1)
        end
    end)
    
end

function SetupOpenPrompt()
    Citizen.CreateThread(function()
        local str = "Öffnen"
        OpenPrompt = PromptRegisterBegin()
        PromptSetControlAction(OpenPrompt, Config.Key)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(OpenPrompt, str)
        PromptSetEnabled(OpenPrompt, true)
        PromptSetVisible(OpenPrompt, true)
        PromptSetStandardMode(OpenPrompt, true)
        PromptSetGroup(OpenPrompt, PromptGroup3)
        _in(0xC5F428EE08FA7F2C, OpenPrompt, true)
        PromptRegisterEnd(OpenPrompt)

        local str3 = "Truhen Menü"
        EditPrompt = PromptRegisterBegin()
        PromptSetControlAction(EditPrompt, Config.Menu)
        str3 = CreateVarString(10, 'LITERAL_STRING', str3)
        PromptSetText(EditPrompt, str3)
        PromptSetEnabled(EditPrompt, true)
        PromptSetVisible(EditPrompt, true)
        PromptSetStandardMode(EditPrompt, true)
        PromptSetGroup(EditPrompt, PromptGroup3)
        _in(0xC5F428EE08FA7F2C, EditPrompt, true)
        PromptRegisterEnd(EditPrompt)
    end)
end

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    Wait(2000)
    InitPostMan()
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
        Wait(10000)
        InitPostMan()
end)


AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    for i,k in pairs(OfficePeds) do
        DeleteEntity(k)
    end
    print('The resource ' .. resourceName .. ' was stopped.')
end)

function randomJobZone(tbl)
    local availableIndices = {}
    for i = 1, #tbl do
        table.insert(availableIndices, i)
    end
  
    return function()
        if #availableIndices == 0 then
            return nil
        end
    
        local index = math.random(1, #availableIndices)
        local randomIndex = table.remove(availableIndices, index)
        return tbl[randomIndex]
    end
end
