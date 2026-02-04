-- Snake (LÖVE2D) with Powerups
-- Controls: WASD move, P pause, R restart, Esc quit

-- =====================
-- Config
-- =====================
local CONFIG = {
	cellSize = 20,
	gridW = 32,
	gridH = 24,
	baseMoveInterval = 0.10, -- seconds per step

	wrapWalls = false,
	speedScales = true,      -- speed up slowly as score grows
	minMoveInterval = 0.05,

	powerup = {
		enabled = true,
		spawnDelayMin = 10.0,
		spawnDelayMax = 18.0,
		ttl = 8.0,
		timedDuration = 8.0,
	},
}

-- =====================
-- State
-- =====================
local state -- "start" | "playing" | "paused" | "gameover"
local snake
local dir, nextDir
local food
local score
local accumulator

local powerup -- {x,y,type,ttl} or nil
local nextPowerupIn
local activeTimed -- {type, remaining} or nil
local shield -- boolean

-- Powerup definitions
local POWERUPS = {
	shield = { label = "Shield", color = { 0.95, 0.85, 0.20 }, timed = false },
	ghost = { label = "Ghost", color = { 0.65, 0.75, 1.00 }, timed = true },
	double = { label = "Double", color = { 1.00, 0.40, 0.85 }, timed = true },
	slow = { label = "Slow", color = { 0.35, 1.00, 0.85 }, timed = true },
}

local function clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local function randRange(a, b)
	return a + (b - a) * love.math.random()
end

local function cellKey(x, y)
	return tostring(x) .. "," .. tostring(y)
end

local function inBounds(x, y)
	return x >= 1 and x <= CONFIG.gridW and y >= 1 and y <= CONFIG.gridH
end

local function wrapCell(x, y)
	if x < 1 then x = CONFIG.gridW end
	if x > CONFIG.gridW then x = 1 end
	if y < 1 then y = CONFIG.gridH end
	if y > CONFIG.gridH then y = 1 end
	return x, y
end

local function snakeOccupies(x, y, excludeTail)
	local last = #snake
	local limit = excludeTail and (last - 1) or last
	for i = 1, limit do
		if snake[i].x == x and snake[i].y == y then
			return true
		end
	end
	return false
end

local function spawnFood()
	local tries = CONFIG.gridW * CONFIG.gridH
	for _ = 1, tries do
		local x = love.math.random(1, CONFIG.gridW)
		local y = love.math.random(1, CONFIG.gridH)
		if not snakeOccupies(x, y, false) and (not powerup or powerup.x ~= x or powerup.y ~= y) then
			food = { x = x, y = y }
			return
		end
	end
	food = { x = 1, y = 1 }
end

local function scheduleNextPowerup()
	nextPowerupIn = randRange(CONFIG.powerup.spawnDelayMin, CONFIG.powerup.spawnDelayMax)
end

local function spawnPowerup()
	if not CONFIG.powerup.enabled then return end
	if powerup ~= nil then return end

	local types = { "shield", "ghost", "double", "slow" }
	local chosenType = types[love.math.random(1, #types)]

	local tries = CONFIG.gridW * CONFIG.gridH
	for _ = 1, tries do
		local x = love.math.random(1, CONFIG.gridW)
		local y = love.math.random(1, CONFIG.gridH)
		local onFood = (food and food.x == x and food.y == y)
		if not onFood and not snakeOccupies(x, y, false) then
			powerup = { x = x, y = y, type = chosenType, ttl = CONFIG.powerup.ttl }
			return
		end
	end
end

local function resetPowerupState()
	powerup = nil
	activeTimed = nil
	shield = false
	scheduleNextPowerup()
end

local function resetGame()
	score = 0
	accumulator = 0
	state = "start"

	local startX = math.floor(CONFIG.gridW / 2)
	local startY = math.floor(CONFIG.gridH / 2)
	snake = {
		{ x = startX,     y = startY },
		{ x = startX - 1, y = startY },
		{ x = startX - 2, y = startY },
	}
	dir = { x = 1, y = 0 }
	nextDir = { x = 1, y = 0 }

	resetPowerupState()
	spawnFood()
end

local function startPlaying()
	if state == "start" or state == "gameover" then
		resetGame()
	end
	state = "playing"
end

local function setNextDir(dx, dy)
	-- Prevent instant 180-degree reversal
	if dx == -dir.x and dy == -dir.y then
		return
	end
	nextDir = { x = dx, y = dy }
	if state == "start" then
		startPlaying()
	end
end

local function currentMoveInterval()
	local interval = CONFIG.baseMoveInterval

	if CONFIG.speedScales then
		interval = interval - 0.002 * score
	end
	interval = clamp(interval, CONFIG.minMoveInterval, CONFIG.baseMoveInterval)

	if activeTimed and activeTimed.type == "slow" then
		interval = interval * 1.75
	elseif activeTimed and activeTimed.type == "ghost" then
		-- no speed change
	elseif activeTimed and activeTimed.type == "double" then
		-- no speed change
	end

	return interval
end

local function applyPowerup(pType)
	if pType == "shield" then
		shield = true
		return
	end

	activeTimed = { type = pType, remaining = CONFIG.powerup.timedDuration }
end

local function updatePowerups(dt)
	if CONFIG.powerup.enabled then
		if powerup then
			powerup.ttl = powerup.ttl - dt
			if powerup.ttl <= 0 then
				powerup = nil
				scheduleNextPowerup()
			end
		else
			nextPowerupIn = nextPowerupIn - dt
			if nextPowerupIn <= 0 then
				spawnPowerup()
				if powerup == nil then
					scheduleNextPowerup()
				end
			end
		end
	end

	if activeTimed then
		activeTimed.remaining = activeTimed.remaining - dt
		if activeTimed.remaining <= 0 then
			activeTimed = nil
		end
	end
end

local function triggerGameOver()
	state = "gameover"
end

local function tryConsumeShield()
	if shield then
		shield = false
		return true
	end
	return false
end

local function stepSnake()
	dir = nextDir

	local head = snake[1]
	local newX = head.x + dir.x
	local newY = head.y + dir.y

	if CONFIG.wrapWalls then
		newX, newY = wrapCell(newX, newY)
	else
		if not inBounds(newX, newY) then
			if tryConsumeShield() then
				newX, newY = clamp(newX, 1, CONFIG.gridW), clamp(newY, 1, CONFIG.gridH)
			else
				triggerGameOver()
				return
			end
		end
	end

	local willEatFood = (food and food.x == newX and food.y == newY)
	local excludeTail = not willEatFood
	local ghostActive = (activeTimed and activeTimed.type == "ghost")

	if not ghostActive and snakeOccupies(newX, newY, excludeTail) then
		if tryConsumeShield() then
			-- Shield prevents the death; allow the move anyway.
		else
			triggerGameOver()
			return
		end
	end

	-- Move head
	table.insert(snake, 1, { x = newX, y = newY })

	-- Collect powerup (if any)
	if powerup and powerup.x == newX and powerup.y == newY then
		applyPowerup(powerup.type)
		powerup = nil
		scheduleNextPowerup()
	end

	-- Food resolution
	if willEatFood then
		local gain = 1
		if activeTimed and activeTimed.type == "double" then
			gain = 2
		end
		score = score + gain
		spawnFood()
	else
		table.remove(snake) -- pop tail
	end
end

-- =====================
-- LÖVE Callbacks
-- =====================
function love.load()
	love.math.setRandomSeed(os.time())
	love.window.setTitle("Snake (WASD) + Powerups")
	love.window.setMode(CONFIG.gridW * CONFIG.cellSize, CONFIG.gridH * CONFIG.cellSize, { resizable = false, vsync = true })
	love.graphics.setBackgroundColor(0.06, 0.06, 0.08)
	resetGame()
end

function love.keypressed(key)
	if key == "escape" then
		love.event.quit()
		return
	end

	if key == "p" then
		if state == "playing" then
			state = "paused"
		elseif state == "paused" then
			state = "playing"
		end
		return
	end

	if key == "r" then
		resetGame()
		return
	end

	if key == "w" then setNextDir(0, -1)
	elseif key == "a" then setNextDir(-1, 0)
	elseif key == "s" then setNextDir(0, 1)
	elseif key == "d" then setNextDir(1, 0)
	end
end

function love.update(dt)
	if state ~= "playing" then return end

	updatePowerups(dt)

	accumulator = accumulator + dt
	local interval = currentMoveInterval()
	while accumulator >= interval do
		accumulator = accumulator - interval
		stepSnake()
		if state ~= "playing" then break end
		interval = currentMoveInterval()
	end
end

local function drawCell(x, y, color)
	love.graphics.setColor(color[1], color[2], color[3])
	love.graphics.rectangle(
		"fill",
		(x - 1) * CONFIG.cellSize,
		(y - 1) * CONFIG.cellSize,
		CONFIG.cellSize - 1,
		CONFIG.cellSize - 1
	)
end

local function drawCenteredText(text, y)
	love.graphics.printf(text, 0, y, CONFIG.gridW * CONFIG.cellSize, "center")
end

function love.draw()
	-- Food
	if food then
		drawCell(food.x, food.y, { 0.95, 0.25, 0.25 })
	end

	-- Powerup
	if powerup then
		local def = POWERUPS[powerup.type]
		drawCell(powerup.x, powerup.y, def.color)
		love.graphics.setColor(0, 0, 0)
		local labelChar = string.sub(def.label, 1, 1)
		love.graphics.print(labelChar,
			(powerup.x - 1) * CONFIG.cellSize + 6,
			(powerup.y - 1) * CONFIG.cellSize + 2
		)
	end

	-- Snake
	for i, seg in ipairs(snake) do
		if i == 1 then
			drawCell(seg.x, seg.y, { 0.35, 0.95, 0.55 })
		else
			drawCell(seg.x, seg.y, { 0.20, 0.70, 0.40 })
		end
	end

	-- HUD
	love.graphics.setColor(1, 1, 1)
	love.graphics.print("Score: " .. tostring(score), 10, 10)

	local hudY = 30
	if shield then
		love.graphics.print("Shield: ON", 10, hudY)
		hudY = hudY + 18
	end
	if activeTimed then
		local def = POWERUPS[activeTimed.type]
		love.graphics.print(def.label .. ": " .. string.format("%.1fs", math.max(0, activeTimed.remaining)), 10, hudY)
		hudY = hudY + 18
	end
	if state == "paused" then
		love.graphics.setColor(1, 1, 1)
		drawCenteredText("Paused", (CONFIG.gridH * CONFIG.cellSize) / 2 - 30)
		drawCenteredText("Press P to resume", (CONFIG.gridH * CONFIG.cellSize) / 2 - 10)
	elseif state == "start" then
		love.graphics.setColor(1, 1, 1)
		drawCenteredText("Snake", (CONFIG.gridH * CONFIG.cellSize) / 2 - 50)
		drawCenteredText("WASD to move", (CONFIG.gridH * CONFIG.cellSize) / 2 - 25)
		drawCenteredText("Eat food, avoid crashing", (CONFIG.gridH * CONFIG.cellSize) / 2 - 5)
		drawCenteredText("P pause   R restart   Esc quit", (CONFIG.gridH * CONFIG.cellSize) / 2 + 15)
	elseif state == "gameover" then
		love.graphics.setColor(1, 1, 1)
		drawCenteredText("Game Over", (CONFIG.gridH * CONFIG.cellSize) / 2 - 35)
		drawCenteredText("Press R to restart", (CONFIG.gridH * CONFIG.cellSize) / 2 - 10)
	end
end