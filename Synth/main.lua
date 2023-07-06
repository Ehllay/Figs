vanilla_model.PLAYER:setVisible(false)
-- config --
local config = {
    modelPart = models.main_model.Body.Tail1, -- model part of tail
    
    rotVelocityStrength = 10,
    rotVelocityLimit = 7,

    verticalVelocityStrength = 5,
    verticalVelocityMin = -1,
    verticalVelocityMax = 12,

    lessCurveWhenUp = true,

    wagSpeed = 1,
    wagStrength = 16,
    enableWag = {}, -- if any variable in this table is true tail will wag

    walkWagSpeed = 1,
    walkWagStrength = 12,
    
    -- table containing functions with argument rot that is table of vectors that controls tail rotation, returning true will stop physics, can be used for sleeping animation
    rotOverride = {}
}

keybinds:newKeybind("tail wag", "key.keyboard.v"):onPress(function() pings.tailWag(true) end):onRelease(function() pings.tailWag(false) end)
function pings.tailWag(x)
    config.enableWag.defaultKeybind = x
end

-- code --
if not config.modelPart then
    error("model part not found")
end

local wagTime = 0
local walkWagTime = 0
local parts = {}
local vel = vec(0, 0, 0) -- velocity or something
local rot = {} -- list of tail rotations
local oldRot = {} -- mom of list of tail rotations

local targetRot = vec(0, 0, 0)
local mulRot = {}
local addRot = {}
-- find parts
do
    local currentPart = config.modelPart
    local n, i = currentPart:getName():match("^(.-)(-?%d*)$")
    i = tonumber(i) or 1
    while currentPart do
        table.insert(parts, currentPart)
        local r = currentPart:getRot()
        table.insert(rot, r)
        i = i + 1
        currentPart = currentPart[n..i]
    end
    local startRotLimit = #parts * 0.4
    local startRotSum = vec(0, 0, 0)
    local averageAbsRot = vec(0, 0, 0) 
    for i = 1, #parts do
        startRotSum = startRotSum + math.max(1 - (i - 1) / startRotLimit, 0) * rot[i]
        averageAbsRot = averageAbsRot + rot[i]:copy():applyFunc(math.abs)
    end
    targetRot = averageAbsRot / #parts * startRotSum:applyFunc(function(a) return a < 0 and -1 or 1 end)
    for i = 1, #parts do
        local r = rot[i]
        local add = vec(0, 0, 0)
        local mul = vec(1, 1, 1)
        for axis = 1, 3 do
            local difference = r[axis] - targetRot[axis]
            local flippedDifference = r[axis] + targetRot[axis]
            if math.abs(difference) <= math.abs(flippedDifference) then
                add[axis] = difference
            else
                add[axis] = flippedDifference
                mul[axis] = -1
            end
        end
        mulRot[i] = mul
        addRot[i] = add
        rot[i] = targetRot
        oldRot[i] = targetRot
    end
end

-- blink vars
time = 1
nextBlink = 0

neofetching = false --neofetch state var
neofetchUV = 24/64  -- neofetch UV

--action wheel code
mainPage = action_wheel:newPage()
action_wheel:setPage(mainPage)

neofetch = mainPage:newAction() -- neofetch code
    :title("Neofetch")
    :item("minecraft:command_block")
    :hoverColor(1,0,1)
    :onLeftClick(function()
        neofetching = not neofetching
    end)

function events.tick()
    -- update rotation
    for i = #rot, 1, -1 do
        oldRot[i] = rot[i]
        if i ~= 1 then
            rot[i] = rot[i - 1]:copy()
        else
            rot[i] = rot[i]:copy()
        end
    end
    -- override
    for _, v in ipairs(config.rotOverride) do
        if v(rot) then
            return
        end
    end
    -- velocity
    local bodyRot = player:getBodyYaw(1)
    local playerVel = vectors.rotateAroundAxis(bodyRot, player:getVelocity(), vec(0, 1, 0))
    local bodyVel = (bodyRot - player:getBodyYaw(0) + 180) % 360 - 180
    bodyVel = math.clamp(bodyVel * config.rotVelocityStrength, -config.rotVelocityLimit, config.rotVelocityLimit)
    -- check if in liquid 
    local pos = parts[1]:partToWorldMatrix():apply()
    local inFluid = #world.getBlockState(pos + vec(0, 0.5, 0)):getFluidTags() ~= 0
    -- body pitch
    local bodyPitch = 0
    local playerPose = player:getPose()
    if playerPose == "SWIMMING" then
        if inFluid then
            bodyPitch = -90 - player:getRot().x
        else
            bodyPitch = -90
        end
    elseif playerPose == "FALL_FLYING" or playerPose == "SPIN_ATTACK" then
        bodyPitch = -90 - player:getRot().x
    end
    playerVel = vectors.rotateAroundAxis(bodyPitch, playerVel, vec(1, 0, 0))
    -- update velocity
    local currentTargetRot = targetRot:copy()
    if inFluid then
        local t = math.clamp(math.cos(math.rad(bodyPitch)), 0, 1)
        currentTargetRot.x = math.lerp(currentTargetRot.x, -0.8 * math.abs(currentTargetRot.x), t)
    elseif #world.getBlockState(pos):getFluidTags() ~= 0 then
        currentTargetRot.x = 0
    end
    vel = inFluid and vel * 0.4 or vel * 0.7
    vel = vel + (currentTargetRot - rot[1]) * 0.1
    -- update rotation
    rot[1] = rot[1] + vel
    rot[1].x = rot[1].x * (1 - math.clamp(math.abs(bodyVel / config.rotVelocityLimit) * 0.25 + playerVel.z * 1.5, -0.05, 1))
    rot[1].x = rot[1].x + math.clamp(playerVel.y * config.verticalVelocityStrength, -config.verticalVelocityMax, -config.verticalVelocityMin)
    rot[1].y = rot[1].y + bodyVel * math.clamp(1 - playerVel.xz:length() * 8, 0.2, 1) + math.clamp(playerVel.x * 20, -2, 2)
    -- wag
    rot[1].y = rot[1].y + math.cos(walkWagTime * config.walkWagSpeed) * config.walkWagStrength * math.clamp(playerVel.z * 4, 0, 1)
    for _, v in pairs(config.enableWag) do
        if v then
            rot[1].y = rot[1].y + math.cos(wagTime * config.wagSpeed) * config.wagStrength
            break
        end
    end
    -- time
    wagTime = wagTime + 1
    walkWagTime = walkWagTime + math.clamp(playerVel.z * 4, 0, 1)
	
	-- blinking
	
    

	frames = {
        0,         -- open eyes
        8/64, -- half closed eyes
        16/64, -- closed eyes
    }
    
    if time > 4 and neofetching == false then
        time = 1
        nextBlink = world.getTime() + math.random(15,100)
    end

    if neofetching == false then
        models.main_model.Head.Face:setUV(frames[time], -78)
    else
        models.main_model.Head.Face:setUV(neofetchUV, -78)
    end

    if nextBlink < world.getTime() then
        time = time + 1
    end

    

end

function events.render(delta)
    if config.lessCurveWhenUp then
        for i, v in ipairs(parts) do
            local r = math.lerp(oldRot[i], rot[i], delta)
            local m = mulRot[i]:copy()
            if r.x < 0 then
                m.x = 1
                v:setRot(math.lerp(oldRot[i], rot[i], delta) * m + addRot[i])
            else
                v:setRot(r * m + addRot[i])
            end
        end
    else
        for i, v in ipairs(parts) do
            v:setRot(math.lerp(oldRot[i], rot[i], delta) * mulRot[i] + addRot[i])
        end
    end
end

return config -- code by Auria <3
