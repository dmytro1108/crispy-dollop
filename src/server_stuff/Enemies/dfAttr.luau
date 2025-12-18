local functionsOut = {}

-- health
function functionsOut.health()
    -- set the default health
    return 100
end

-- movement
function functionsOut.movement()
    -- set movement speed
    return 10
end

-- targeting
function functionsOut.targetLock()
    -- set range within which targeting is triggered
    return 10
end

-- combat logic
function functionsOut.basicAttack()
    -- set the amount of damage caused
    return 10
end
return functionsOut