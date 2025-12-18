local a = require(script.Parent.dfAttr)
print("a basic attack takes:",a.basicAttack(), "points") -- Call the function
print(a.health())
print(a.movement())
print(a.targetLock())

-- the goal is to make a realistic enemy
-- one that behaves like the player