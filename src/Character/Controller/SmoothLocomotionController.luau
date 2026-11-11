--Local character controller using teleporting.
--!strict

local VRService = game:GetService("VRService")

local BaseController = require(script.Parent:WaitForChild("BaseController"))
local Flight = require(script.Parent:WaitForChild("Flight"))

local NexusVRCharacterModel = script.Parent.Parent.Parent
local VRInputService = require(NexusVRCharacterModel:WaitForChild("State"):WaitForChild("VRInputService")).GetInstance()

local SmoothLocomotionController = {}
SmoothLocomotionController.__index = SmoothLocomotionController
setmetatable(SmoothLocomotionController, BaseController)

export type SmoothLocomotionController = {
    JoystickState: {[string]: Enum.KeyCode}?,
    Flight: Flight.Flight,
} & typeof(setmetatable({}, SmoothLocomotionController)) & BaseController.BaseController


--[[
Creates a smooth locomotion controller object.
--]]
function SmoothLocomotionController.new(): SmoothLocomotionController
    local self = setmetatable(BaseController.new(), SmoothLocomotionController) :: SmoothLocomotionController
    self.Flight = Flight.new()
    return self
end

--[[
Enables the controller.
--]]
function SmoothLocomotionController.Enable(self: SmoothLocomotionController): ()
    BaseController.Enable(self)
    self.JoystickState = {Thumbstick = Enum.KeyCode.Thumbstick2}
end

--[[
Disables the controller.
--]]
function SmoothLocomotionController.Disable(self: SmoothLocomotionController): ()
    self.Flight:Stop(self.Character)
    BaseController.Disable(self)
    self.JoystickState = nil
end

--[[
Updates the local character. Must also update the camara.
--]]
function SmoothLocomotionController.UpdateCharacter(self: SmoothLocomotionController): ()
    --Update the base character.
    BaseController.UpdateCharacter(self)
    if not self.Character then
        return
    end

    --Update flying (not supported with AvatarGestures since the character is not controlled by inputs).
    if not VRService.AvatarGestures then
        local VRInputs = VRInputService:GetVRInputs()
        local HeadCFrame = self:ScaleInput(VRInputs[Enum.UserCFrame.Head])
        local LeftHandCFrame = self:ScaleInput(VRInputs[Enum.UserCFrame.LeftHand])
        local RightHandCFrame = self:ScaleInput(VRInputs[Enum.UserCFrame.RightHand])
        if HeadCFrame and LeftHandCFrame and RightHandCFrame then
            self.Flight:Update(self.Character, HeadCFrame, LeftHandCFrame, RightHandCFrame)
        end
    end

    --Rotate the character.
    local DirectionState, _, StateChange = self:GetJoystickState(self.JoystickState)
    self:UpdateRotating(Enum.UserCFrame.RightHand, DirectionState, StateChange)
end



return SmoothLocomotionController