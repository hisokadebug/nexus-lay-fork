--Flight for the local character.
--Toggled with a T-pose gesture (both arms out to the sides),
--direction from the left thumbstick relative to the head,
--speed from how far the dominant hand is from the body.
--!strict

local NexusVRCharacterModel = script.Parent.Parent.Parent
local Settings = require(NexusVRCharacterModel:WaitForChild("State"):WaitForChild("Settings")).GetInstance()
local VRInputService = require(NexusVRCharacterModel:WaitForChild("State"):WaitForChild("VRInputService")).GetInstance()

local DEFAULTS = {
    Enabled = true,
    MaxSpeed = 40,                  --FlightMaxSpeed (studs/second).
    HandMinDistance = 1.2,          --FlightHandMinDistance: at or below this hand distance, speed is 0.
    HandMaxDistance = 2.4,          --FlightHandMaxDistance: at or above this hand distance, speed is MaxSpeed.
    DominantHand = "Right",         --FlightDominantHand: "Right" or "Left".
    Pose = "Superman",              --FlightPose: "Superman", "Vertical" or "FollowHead".
    GestureHoldTime = 0.5,          --FlightGestureHoldTime: seconds the T-pose is held to start flying.
    ExitGestureHoldTime = 0.8,      --Seconds the T-pose is held to stop flying (longer so extending a hand sideways doesn't cancel it).
    GestureMinHandOffset = 2.0,     --Minimum sideways distance of each hand from the head for the T-pose.
    SupermanMinSpeedRatio = 0.15,   --Speed ratio (0-1) above which the Superman pose lays the body flat.
}
local GESTURE_VERTICAL_MIN, GESTURE_VERTICAL_MAX = -1.6, 0.4 --Hand height relative to the head.
local GESTURE_MAX_FORWARD_OFFSET = 1.2
local BODY_DIRECTION_SMOOTHING = 0.15
local MAX_SUPERMAN_VERTICAL_COMPONENT = 0.9

local Flight = {}
Flight.__index = Flight

export type Flight = {
    Flying: boolean,
    GestureStartTime: number?,
    GestureReleased: boolean,
    BodyDirection: Vector3?,
} & typeof(setmetatable({}, Flight))



--[[
Returns a flight setting with the default if it isn't set.
--]]
local function GetSetting(Name: string): any
    local Value = Settings:GetSetting(`Flight.{Name}`)
    if Value == nil then
        return (DEFAULTS :: any)[Name]
    end
    return Value
end

--[[
Creates a flight object.
--]]
function Flight.new(): Flight
    return setmetatable({
        Flying = false,
        GestureReleased = true,
    }, Flight) :: Flight
end

--[[
Returns if the T-pose gesture is currently held.
--]]
function Flight.IsGestureHeld(self: Flight, HeadCFrame: CFrame, LeftHandCFrame: CFrame, RightHandCFrame: CFrame): boolean
    local MinOffset = GetSetting("GestureMinHandOffset")
    local HeadYawCFrame = CFrame.new(HeadCFrame.Position) * CFrame.Angles(0, math.atan2(-HeadCFrame.LookVector.X, -HeadCFrame.LookVector.Z), 0)
    local LeftRelative = HeadYawCFrame:PointToObjectSpace(LeftHandCFrame.Position)
    local RightRelative = HeadYawCFrame:PointToObjectSpace(RightHandCFrame.Position)
    for _, Relative in {LeftRelative, RightRelative} do
        if math.abs(Relative.X) < MinOffset then return false end
        if Relative.Y < GESTURE_VERTICAL_MIN or Relative.Y > GESTURE_VERTICAL_MAX then return false end
        if math.abs(Relative.Z) > GESTURE_MAX_FORWARD_OFFSET then return false end
    end
    return LeftRelative.X < 0 and RightRelative.X > 0
end

--[[
Returns the ratio (0 to 1) of the speed based on the dominant hand distance.
--]]
function Flight.GetHandSpeedRatio(self: Flight, HeadCFrame: CFrame, LeftHandCFrame: CFrame, RightHandCFrame: CFrame): number
    local HandCFrame = (GetSetting("DominantHand") == "Left" and LeftHandCFrame or RightHandCFrame)
    local Relative = HeadCFrame:PointToObjectSpace(HandCFrame.Position)
    local Distance = Vector2.new(Relative.X, Relative.Z).Magnitude
    local MinDistance, MaxDistance = GetSetting("HandMinDistance"), GetSetting("HandMaxDistance")
    return math.clamp((Distance - MinDistance) / math.max(MaxDistance - MinDistance, 0.001), 0, 1)
end

--[[
Starts flying.
--]]
function Flight.Start(self: Flight, Character: any): ()
    self.Flying = true
    self.BodyDirection = nil
    Character.IsFlying = true
    Character.Humanoid.PlatformStand = true
end

--[[
Stops flying and restores the normal character state.
--]]
function Flight.Stop(self: Flight, Character: any?): ()
    self.Flying = false
    self.GestureStartTime = nil
    self.BodyDirection = nil
    if not Character then return end
    Character.IsFlying = false
    Character.FlightBodyDirection = nil
    Character.IsLying = false
    if Character.Humanoid and Character.Humanoid.Health > 0 then
        Character.Humanoid.PlatformStand = false
        Character.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    end
end

--[[
Updates flight. Returns if the character is flying.
The inputs are the scaled local-space CFrames.
--]]
function Flight.Update(self: Flight, Character: any, HeadCFrame: CFrame, LeftHandCFrame: CFrame, RightHandCFrame: CFrame): boolean
    --Stop flying if it is disabled, the character died, or the character sat.
    if GetSetting("Enabled") == false or Character.Humanoid.Health <= 0 or Character:GetHumanoidSeatPart() then
        if self.Flying then
            self:Stop(Character)
        end
        return false
    end

    --Toggle flying with the gesture. The gesture must be released before it can toggle again.
    if self:IsGestureHeld(HeadCFrame, LeftHandCFrame, RightHandCFrame) then
        if self.GestureReleased then
            local StartTime = self.GestureStartTime or tick()
            self.GestureStartTime = StartTime
            local RequiredTime = (self.Flying and GetSetting("ExitGestureHoldTime") or GetSetting("GestureHoldTime"))
            if tick() - StartTime >= RequiredTime then
                self.GestureReleased = false
                self.GestureStartTime = nil
                if self.Flying then
                    self:Stop(Character)
                    return false
                else
                    self:Start(Character)
                end
            end
        end
    else
        self.GestureReleased = true
        self.GestureStartTime = nil
    end
    if not self.Flying then
        return false
    end

    --Determine the velocity from the thumbstick (direction) and the hand (speed).
    local EyeCFrame = (Character.Parts.Head.CFrame :: CFrame) * Character.Head:GetEyesOffset()
    local Look = EyeCFrame.LookVector
    local Right = Vector3.new(-Look.Z, 0, Look.X)
    Right = (Right.Magnitude > 0.001 and Right.Unit or EyeCFrame.RightVector)
    local Stick = VRInputService:GetThumbstickPosition(Enum.KeyCode.Thumbstick1)
    local Direction = (Look * Stick.Y) + (Right * Stick.X)
    if Direction.Magnitude > 1 then
        Direction = Direction.Unit
    end
    local SpeedRatio = self:GetHandSpeedRatio(HeadCFrame, LeftHandCFrame, RightHandCFrame)
    local Velocity = Direction * GetSetting("MaxSpeed") * SpeedRatio * Character:GetHumanoidScale("BodyHeightScale")
    Character.Parts.HumanoidRootPart.AssemblyLinearVelocity = Velocity --Instant stop when the hand is lowered (no drag).

    --Determine the body pose.
    local Pose = GetSetting("Pose")
    Character.IsLying = (Pose == "FollowHead")
    Character.FlightBodyDirection = nil
    if Pose == "Superman" and Velocity.Magnitude > 0.001 then
        local DesiredDirection = Velocity.Unit
        local Ratio = Velocity.Magnitude / math.max(GetSetting("MaxSpeed") * Character:GetHumanoidScale("BodyHeightScale"), 0.001)
        if Ratio >= GetSetting("SupermanMinSpeedRatio") and math.abs(DesiredDirection.Y) < MAX_SUPERMAN_VERTICAL_COMPONENT then
            local LastDirection = self.BodyDirection or DesiredDirection
            local NewDirection = LastDirection:Lerp(DesiredDirection, BODY_DIRECTION_SMOOTHING)
            if NewDirection.Magnitude > 0.001 then
                self.BodyDirection = NewDirection.Unit
                Character.FlightBodyDirection = self.BodyDirection
            end
        else
            self.BodyDirection = nil
        end
    else
        self.BodyDirection = nil
    end
    return true
end



return Flight
