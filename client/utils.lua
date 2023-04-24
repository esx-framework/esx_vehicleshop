local NumberCharset = {}
for i = 48, 57 do table.insert(NumberCharset, string.char(i)) end

local Charset = {}
for i = 65, 90 do table.insert(Charset, string.char(i)) end
for i = 97, 122 do table.insert(Charset, string.char(i)) end

function GeneratePlate()
    math.randomseed(GetGameTimer())

    local generatedPlate = ""
    for i = 1, Config.PlateLetters do
        generatedPlate = generatedPlate .. Charset[math.random(1, #Charset)]
    end

    if Config.PlateUseSpace then
        generatedPlate = generatedPlate .. " "
    end

    for i = 1, Config.PlateNumbers do
        generatedPlate = generatedPlate .. NumberCharset[math.random(1, #NumberCharset)]
    end

    if IsPlateTaken(generatedPlate) then
        return GeneratePlate()
    end

    return string.upper(generatedPlate)
end

function IsPlateTaken(plate)
    local isPlateTaken = false

    ESX.TriggerServerCallback('esx_vehicleshop:isPlateTaken', function(result)
        isPlateTaken = result
    end, plate)

    while isPlateTaken == false do
        Wait(0)
    end

    return isPlateTaken
end
