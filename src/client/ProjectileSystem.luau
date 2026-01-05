local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")
local Camera = workspace.CurrentCamera

local Animator = Humanoid:FindFirstChildOfClass("Animator") 
local ThrowAnimation = ReplicatedStorage:FindFirstChild("Animation", true) and ReplicatedStorage.Animation:FindFirstChild("ThrowAnimation")
local ThrowTrack = ThrowAnimation and Animator:LoadAnimation(ThrowAnimation)

if ThrowTrack then
	ThrowTrack.Looped = false
end

-- Projectile class using metatables
local Projectile = {}
Projectile.__index = Projectile

local ProjectileManager = {
	Active = {},
	NextId = 1,
	UpdateConnection = nil
}

local DefaultConfig = {
	Speed = 120,
	Lifetime = 5,
	Range = 200,
	Gravity = 50,
	Damage = 35,
	HitboxSize = Vector3.new(3, 3, 3),
	Pierce = false,
	Tracking = false,
	TrackingStrength = 0.3,
	VFXPath = nil,
	Color = Color3.fromRGB(255, 100, 50),
}

function Projectile.new(config, startPos, direction, owner)
	local self = setmetatable({}, Projectile)
	
	self.Config = setmetatable(config or {}, {__index = DefaultConfig})
	self.Id = ProjectileManager.NextId
	ProjectileManager.NextId += 1
	
	self.Position = startPos
	self.Direction = direction.Unit
	self.Velocity = self.Direction * self.Config.Speed
	self.Owner = owner
	self.StartPos = startPos
	self.StartTime = tick()
	self.HitTargets = {}
	self.Active = true
	
	self:CreateVisual()
	return self
end

function Projectile:CreateVisual()
	if not self.Config.VFXPath then return end
	
	local vfx = ReplicatedStorage:FindFirstChild("VFX", true)
	if not vfx then return end
	
	local effect = vfx:FindFirstChild(self.Config.VFXPath, true)
	if not effect then return end
	
	self.Part = effect:Clone()
	self.Part.Parent = workspace
	
	for _, child in self.Part:GetDescendants() do
		if child:IsA("ParticleEmitter") or child:IsA("Beam") or child:IsA("Trail") then
			child.Enabled = true
		end
	end
end


-- Main physics update loop called every frame
function Projectile:Update(dt)
	if not self.Active then return false end
	
	if tick() - self.StartTime > self.Config.Lifetime then
		self:Destroy()
		return false
	end
	
	-- Apply gravity to velocity
	if self.Config.Gravity > 0 then
		self.Velocity += Vector3.new(0, -self.Config.Gravity * dt, 0)
		self.Direction = self.Velocity.Unit
	end
	
	if self.Config.Tracking then
		self:UpdateTracking(dt)
	end
	
	local prevPos = self.Position
	self.Position += self.Velocity * dt
	
	
	if self.Part then
		self.Part.CFrame = CFrame.new(self.Position, self.Position + self.Direction)
	end
	
	if self:CheckCollision(prevPos) then
		if not self.Config.Pierce then
			self:Destroy()
			return false
		end
	end
	
	if (self.Position - self.StartPos).Magnitude > self.Config.Range then
		self:Destroy()
		return false
	end
	
	return true
end

-- Homing behavior that curves toward nearest target
function Projectile:UpdateTracking(dt)
	local nearest = nil
	local nearestDist = math.huge
	
	for _, model in workspace:GetChildren() do
		if model == Character then continue end
		
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		
		if humanoid and root and humanoid.Health > 0 then
			local dist = (root.Position - self.Position).Magnitude
			if dist < nearestDist and dist < 150 then
				nearestDist = dist
				nearest = root
			end
		end
	end
	
	if nearest then
		local toTarget = (nearest.Position - self.Position).Unit
		self.Direction = (self.Direction + toTarget * self.Config.TrackingStrength * dt * 20).Unit
		self.Velocity = self.Direction * self.Config.Speed
	end
end

-- Uses OverlapParams and Raycasting for accurate hit detection
function Projectile:CheckCollision(prevPos)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {Character, self.Part}
	
	local hitParts = workspace:GetPartBoundsInBox(CFrame.new(self.Position), self.Config.HitboxSize, overlapParams)
	
	for _, part in hitParts do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model then continue end
		
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end
		if self.HitTargets[model] then continue end
		
		self:OnHit(model)
		return true
	end
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {Character, self.Part}
	
	local travelVector = self.Position - prevPos
	local travelDist = travelVector.Magnitude
	
	if travelDist > 0 then
		local result = workspace:Raycast(prevPos, travelVector, rayParams)
		
		if result then
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			
			if model and model:FindFirstChildOfClass("Humanoid") then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid.Health > 0 and not self.HitTargets[model] then
					self:OnHit(model)
					return true
				end
			else
				return true
			end
		end
	end
	
	return false
end

function Projectile:OnHit(target)
	self.HitTargets[target] = true
	
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(self.Config.Damage)
		
		
		if humanoid.Health <= 0 then
			local originalPos = target:FindFirstChild("HumanoidRootPart")
			local respawnPosition = originalPos and originalPos.Position or target:GetPivot().Position
			
			task.delay(3, function()
				if target and target.Parent then
					humanoid.Health = 100
					if originalPos then
						target:PivotTo(CFrame.new(respawnPosition))
					end
				end
			end)
		end
	end
end

function Projectile:Destroy()
	self.Active = false
	
	if self.Part then
		for _, child in self.Part:GetDescendants() do
			if child:IsA("ParticleEmitter") or child:IsA("Trail") or child:IsA("Beam") then
				child.Enabled = false
			end
		end
		Debris:AddItem(self.Part, 0.5)
	end
end

-- Spawns a new projectile and registers it with the manager
function ProjectileManager.Fire(config, startPos, direction, owner)
	local projectile = Projectile.new(config, startPos, direction, owner or Player)
	ProjectileManager.Active[projectile.Id] = projectile
	ProjectileManager.EnsureRunning()
	return projectile.Id
end

function ProjectileManager.UpdateAll(dt)
	for id, projectile in pairs(ProjectileManager.Active) do
		if not projectile:Update(dt) then
			ProjectileManager.Active[id] = nil
		end
	end
end

function ProjectileManager.EnsureRunning()
	if ProjectileManager.UpdateConnection then return end
	
	ProjectileManager.UpdateConnection = RunService.Heartbeat:Connect(function(dt)
		ProjectileManager.UpdateAll(dt)
	end)
end

function ProjectileManager.Clear()
	for _, projectile in pairs(ProjectileManager.Active) do
		projectile:Destroy()
	end
	table.clear(ProjectileManager.Active)
end

local throwing = false
local cooldown = false
local trackingMode = false

-- Convert mouse position to world direction using ViewportPointToRay
local function FireProjectile()
	local mouse = UserInputService:GetMouseLocation()
	local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)
	local spawnPos = RootPart.Position + RootPart.CFrame.LookVector * 3 + Vector3.new(0, 2, 0)
	
	ProjectileManager.Fire({
		VFXPath = "Red Orb",
		Speed = 120,
		Damage = 35,
		Tracking = trackingMode,
		TrackingStrength = 0.55,
		HitboxSize = Vector3.new(4, 4, 4),
	}, spawnPos, ray.Direction)
	
	throwing = false
end


if ThrowTrack then
	ThrowTrack:GetMarkerReachedSignal("Throw"):Connect(FireProjectile)
	ThrowTrack.Stopped:Connect(function()
		throwing = false
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	
	-- Toggle tracking mode
	if input.KeyCode == Enum.KeyCode.F then
		trackingMode = not trackingMode
		print(trackingMode and "Tracking ON" or "Tracking OFF")
	end
	
	if throwing or cooldown then return end
	
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		cooldown = true
		task.delay(1, function() cooldown = false end)
		
		if ThrowTrack then
			throwing = true
			ThrowTrack:Play()
			task.delay(0.3, function()
				if throwing then FireProjectile() end
			end)
		else
			FireProjectile()
		end
	end
end)

return {Projectile = Projectile, Manager = ProjectileManager}
