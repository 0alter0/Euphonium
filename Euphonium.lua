-- Euphonium By Lil Skittle

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

local pathParams = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	AgentCanClimb = false,
	WaypointSpacing = 2,
	Costs = {
		Water = math.huge,
		DangerZone = math.huge
	}
}

local DEADLY_NAMES = {
	"kill", "lava", "acid", "fire", "death", "spike", "trap", 
	"danger", "void", "poison", "laser", "deadly"
}

local DEADLY_COLORS = {
	Color3.new(1, 0, 0),
	Color3.new(1, 0.5, 0),
	Color3.new(0.5, 0, 0.5),
}

local WAYPOINT_VISUALIZE = true
local BARITONE_LINE = true
local currentPath = nil
local isMoving = false
local waypointParts = {}
local pathLines = {}
local blockedConnection = nil

local LINE_COLOR = Color3.fromRGB(0, 255, 255)
local LINE_THICKNESS = 0.15
local WAYPOINT_SIZE = 0.4
local PATH_LIFETIME = 8

local MIN_Y_POSITION = -500

local function isDeadlyPart(part)
	if not part:IsA("BasePart") then return false end
	
	local lowerName = part.Name:lower()
	for _, deadlyName in ipairs(DEADLY_NAMES) do
		if lowerName:find(deadlyName) then
			return true
		end
	end
	
	for _, deadlyColor in ipairs(DEADLY_COLORS) do
		local colorDiff = (part.Color - deadlyColor).Magnitude
		if colorDiff < 0.1 then
			return true
		end
	end
	
	return false
end

local function setupDeadlyPartAvoidance()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if isDeadlyPart(obj) then
			local modifier = obj:FindFirstChildOfClass("PathfindingModifier")
			if not modifier then
				modifier = Instance.new("PathfindingModifier")
				modifier.Label = "DangerZone"
				modifier.Parent = obj
			end
		end
	end
	
	workspace.DescendantAdded:Connect(function(obj)
		task.wait(0.1)
		if isDeadlyPart(obj) then
			local modifier = Instance.new("PathfindingModifier")
			modifier.Label = "DangerZone"
			modifier.Parent = obj
		end
	end)
end

local function clearWaypoints()
	for _, part in ipairs(waypointParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	waypointParts = {}
end

local function clearPathLines()
	for _, line in ipairs(pathLines) do
		if line and line.Parent then
			line:Destroy()
		end
	end
	pathLines = {}
end

local function stopMovement()
	isMoving = false
	if blockedConnection then
		blockedConnection:Disconnect()
		blockedConnection = nil
	end
	if humanoid and humanoid.Parent then
		humanoid:MoveTo(rootPart.Position)
	end
	clearWaypoints()
	clearPathLines()
	
	if rootPart and rootPart.Parent then
		for _, obj in ipairs(rootPart:GetChildren()) do
			if obj:IsA("BodyVelocity") and obj.Name == "JumpVelocity" then
				obj:Destroy()
			end
		end
	end
end

local function createPathLine(point1, point2)
	if not BARITONE_LINE then return end
	
	local distance = (point1 - point2).Magnitude
	local midpoint = (point1 + point2) / 2
	
	local line = Instance.new("Part")
	line.Size = Vector3.new(LINE_THICKNESS, LINE_THICKNESS, distance)
	line.CFrame = CFrame.lookAt(midpoint, point2)
	line.Anchored = true
	line.CanCollide = false
	line.Material = Enum.Material.Neon
	line.Color = LINE_COLOR
	line.Transparency = 0.3
	line.Parent = workspace
	
	table.insert(pathLines, line)
end

local function visualizeWaypoint(position, waypointType)
	if not WAYPOINT_VISUALIZE then return end
	
	local part = Instance.new("Part")
	part.Size = Vector3.new(WAYPOINT_SIZE, WAYPOINT_SIZE, WAYPOINT_SIZE)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Ball
	
	if waypointType == Enum.PathWaypointAction.Jump then
		part.Color = Color3.fromRGB(255, 255, 0)
		part.Size = Vector3.new(WAYPOINT_SIZE * 1.5, WAYPOINT_SIZE * 1.5, WAYPOINT_SIZE * 1.5)
	else
		part.Color = LINE_COLOR
	end
	
	part.Transparency = 0.4
	part.Parent = workspace
	table.insert(waypointParts, part)
end

local function visualizePath(waypoints)
	clearWaypoints()
	clearPathLines()
	
	for i = 1, #waypoints - 1 do
		createPathLine(waypoints[i].Position, waypoints[i + 1].Position)
		visualizeWaypoint(waypoints[i].Position, waypoints[i].Action)
	end
	
	if #waypoints > 0 then
		visualizeWaypoint(waypoints[#waypoints].Position, waypoints[#waypoints].Action)
	end
	
	task.delay(PATH_LIFETIME, function()
		clearPathLines()
		clearWaypoints()
	end)
end

local function moveToPosition(targetPosition)
	if isMoving then
		stopMovement()
		task.wait(0.1)
	end
	
	clearWaypoints()
	clearPathLines()
	
	local path = PathfindingService:CreatePath(pathParams)
	
	local success, err = pcall(function()
		path:ComputeAsync(rootPart.Position, targetPosition)
	end)
	
	if not success or path.Status ~= Enum.PathStatus.Success then
		warn("Path computation failed or no path found")
		return
	end
	
	local waypoints = path:GetWaypoints()
	
	visualizePath(waypoints)
	
	isMoving = true
	currentPath = path
	
	blockedConnection = path.Blocked:Connect(function(idx)
		if idx > 1 then
			stopMovement()
			warn("Path blocked, recomputing...")
			task.wait(0.2)
			moveToPosition(targetPosition)
		end
	end)
	
	for i, waypoint in ipairs(waypoints) do
		if not isMoving then 
			break 
		end
		
		if rootPart.Position.Y < MIN_Y_POSITION then
			warn("Player fell too far, stopping pathfinding")
			stopMovement()
			break
		end
		
		local yDifference = rootPart.Position.Y - waypoint.Position.Y
		if yDifference > 20 and waypoint.Action ~= Enum.PathWaypointAction.Jump then
			warn("Waypoint too far below current position, skipping to next")
			continue
		end
		
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			local jumpDir = waypoint.Position
			if waypoints[i + 1] then
				jumpDir = waypoints[i + 1].Position
			end
			
			humanoid:MoveTo(jumpDir)
			
			local waitStart = tick()
			repeat
				task.wait(0.05)
				if not isMoving then break end
			until (rootPart.Position - waypoint.Position).Magnitude < 3 or (tick() - waitStart) > 3
			
			if not isMoving then break end
			
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			
			local jumpVec = (jumpDir - rootPart.Position).Unit
			local bodyVel = Instance.new("BodyVelocity")
			bodyVel.Name = "JumpVelocity"
			bodyVel.MaxForce = Vector3.new(4000, 0, 4000)
			bodyVel.Velocity = Vector3.new(jumpVec.X * 16, 0, jumpVec.Z * 16)
			bodyVel.Parent = rootPart
			
			task.delay(0.3, function()
				if bodyVel and bodyVel.Parent then 
					bodyVel:Destroy() 
				end
			end)
			
			task.wait(0.1)
			humanoid:MoveTo(jumpDir)
			
			local jumpStart = tick()
			repeat
				task.wait(0.05)
				if not isMoving then break end
				
				local inAir = humanoid:GetState() == Enum.HumanoidStateType.Freefall or 
				              humanoid:GetState() == Enum.HumanoidStateType.Jumping
				if not inAir then break end
			until (tick() - jumpStart) > 2
		else
			humanoid:MoveTo(waypoint.Position)
		end
		
		local startTime = tick()
		repeat
			task.wait(0.05)
			if not isMoving then break end
			
			local dist = (rootPart.Position - waypoint.Position).Magnitude
			local threshold = waypoint.Action == Enum.PathWaypointAction.Jump and 8 or 5
			
			if dist < threshold then 
				break 
			end
			
			if (tick() - startTime) > 1 then
				humanoid:MoveTo(waypoint.Position)
			end
		until (tick() - startTime) > 8
	end
	
	stopMovement()
	print("Pathfinding complete")
end

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		local mouse = player:GetMouse()
		if mouse.Target and mouse.Target:IsA("BasePart") then
			local part = mouse.Target
			local mod = part:FindFirstChildOfClass("PathfindingModifier")
			if not mod then
				mod = Instance.new("PathfindingModifier")
				mod.Parent = part
			end
			mod.Label = "DangerZone"
			
			local origColor = part.Color
			part.Color = Color3.fromRGB(255, 0, 0)
			task.wait(0.3)
			part.Color = origColor
			
			print("Marked", part.Name, "as deadly")
		end
		
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		local mouse = player:GetMouse()
		if mouse.Target then
			local target = mouse.Hit.Position
			
			local marker = Instance.new("Part")
			marker.Size = Vector3.new(2, 0.5, 2)
			marker.Position = target
			marker.Anchored = true
			marker.CanCollide = false
			marker.Material = Enum.Material.Neon
			marker.Color = Color3.fromRGB(255, 0, 0)
			marker.Transparency = 0.5
			marker.Parent = workspace
			
			game:GetService("Debris"):AddItem(marker, 2)
			
			moveToPosition(target)
		end
	end
end)

setupDeadlyPartAvoidance()

local function onDeath()
	print("Character died, stopping pathfinding")
	stopMovement()
end

local function onCharacterAdded(newCharacter)
	stopMovement()
	
	task.wait(0.5)
	
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	
	humanoid.Died:Connect(onDeath)
	
	print("Character respawned, pathfinding ready")
end

humanoid.Died:Connect(onDeath)

player.CharacterAdded:Connect(onCharacterAdded)

print("Pathfinding loaded!")
print("Right-click: Navigate | Middle-click: Mark part as deadly") -- this is only for when i add a working GUI, ALL prints are just for future me
