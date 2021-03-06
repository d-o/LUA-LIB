-------------------------------------------------------------------------------
--- Analogue Functions.
-- Functions to control M4401 analogue output
-- @module rinLibrary.Device.Analog
-- @author Darren Pearson
-- @author Merrick Heley
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------
local math = math
local bit32 = require "bit"
local naming = require 'rinLibrary.namings'
local utils = require 'rinSystem.utilities'
local dbg = require 'rinLibrary.rinDebug'

local unpack = unpack
local tonumber = tonumber

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Submodule function begins here
return function (_M, private, deprecated)

local maxAnalogueModules, warnedModuleNumberRange
private.registerDeviceInitialiser(function()
    maxAnalogueModules = private.a418(4) or 1
end)

local analogueDataRegisters             = { 0x0323, 0x030B, 0x030C, 0x030D }
local analogueTypeRegisters             = { 0xA801, 0xA811, 0xA821, 0xA831 }
--local analogueAbsRegisters              = { 0xA803, 0xA813, 0xA823, 0xA833 }
local analogueSourceRegisters           = { 0xA805, 0xA815, 0xA825, 0xA835 } -- must be set to option 3 "COMMS" if we are to control it via the comms
local analogueClipRegisters             = { 0xA806, 0xA816, 0xA826, 0xA836 }
--local analogueWeightLowRegisters        = { 0xA807, 0xA817, 0xA827, 0xA837 }
--local analogueWeightHighRegisters       = { 0xA808, 0xA818, 0xA828, 0xA838 }
--local analogueAdjustLowRegisters        = { 0xA809, 0xA819, 0xA829, 0xA839 }
--local analogueAdjustHighRegisters       = { 0xA80A, 0xA81A, 0xA82A, 0xA83A }
--local analogueRangeRegisters            = { 0xA80B, 0xA81B, 0xA82B, 0xA83B }
--local analogueWeightLowLiveRegisters    = { 0xA80C, 0xA81C, 0xA82C, 0xA83C }
--local analogueWeightHighLiveRegisters   = { 0xA80D, 0xA81D, 0xA82D, 0xA83D }

local CUR = 0
local VOLT = 1

local analogTypes = {
    current = CUR,
    volt = VOLT
}
local analogNames = utils.invert(analogTypes)

local curAnalogType = {}
local lastAnalogue = {}

local analogSourceMap, analogSourceOptions
private.registerDeviceInitialiser(function()
    analogSourceMap = {
        gross           = 0,
        net             = 1,
        gross_or_net    = 2,
        comms           = 3,
        batch           = private.a418(4)
    }
    analogSourceOptions = { analogSourceMap.comms, 0, private.a418(4) or 3 }
end)

--- Analog Source Map
-- Options for the analog 
--@table AnalogSource
-- @field gross Use gross weight only
-- @field net Use net weight only
-- @field gross_or_net Use either gross or net depending on which is currently displayed.
-- @field comms Control analogue using comms
-- @field batch Control using batch (A418 only)

-------------------------------------------------------------------------------
-- Provide backward compatibility with older library versions where the module
-- argument wan't required.
-- @param mod Module argument given
-- @param x Value argument given
-- @return Module referenced or nil on error
-- @return Value
-- @local
local function decodeModule(mod, x)
    if x == nil then
        return 1, mod
    end
    local m = tonumber(mod)
    if m and m >= 1 and m <= maxAnalogueModules then
        return m, x
    end
    if not warnedModuleNumberRange then
        if maxAnalogueModules == 1 then
            dbg.error('Analogue module number should be 1:', mod)
        else
            dbg.error('Bad analogue module number (1..'..maxAnalogueModules..'):', mod)
        end
        warnedModuleNumberRange = true
    end
    return nil
end

private.registerDeviceInitialiser(function()
    if private.a418(true) then
        local olddm = decodeModule
        decodeModule = function(mod, x)
            if x == nil then
                dbg.warn("Depricated:", 'analogue functions take a module argument first, assuming module 1')
                decodeModule = olddm
            end
            return olddm(mod, x)
        end
    end
end)

-------------------------------------------------------------------------------
-- Set the analog output type
-- @param module The analogue module to change
-- @param oType Type for output 'current' or 'volt'
-- @return The previous analog output type
-- @local
local function setType(module, oType)
    if module then
        local prev = curAnalogType[module]
        local new = naming.convertNameToValue(oType, analogTypes, VOLT, CUR, VOLT)

        if new ~= prev then
            private.writeReg(analogueTypeRegisters[module], new)
            curAnalogType[module] = new
        end
        return analogNames[prev]
    end
end

-------------------------------------------------------------------------------
-- Set the analog output type.
-- @param module The analogue module to change
-- @param source Source for output.
-- Must be set to 'comms' to control directly and this is the default.
-- @local
local function setSource(module, source)
    if module then
        local src = naming.convertNameToValue(source, analogSourceMap, unpack(analogSourceOptions))
        private.writeReg(analogueSourceRegisters[module], src)
    end
end

-------------------------------------------------------------------------------
-- Sets the analog output to minimum 0 through to maximum 50,000
-- @param module The analogue module to change
-- @param raw value in raw counts (0..50000)
-- @local
local function setRaw(module, raw)
    if module and lastAnalogue[module] ~= raw then
        private.writeRegAsync(analogueDataRegisters[module], raw)
        lastAnalogue[module] = raw
    end
end

-------------------------------------------------------------------------------
-- Sets the analogue output to minimum 0.0 through to maximum 1.0
-- @param module The analogue module to change
-- @param val value 0.0 to 1.0
-- @local
local function setVal(module, val)
    return setRaw(module, math.floor(50000 * val + 0.5))
end

-------------------------------------------------------------------------------
-- Control behaviour of analog output outside of normal range.
-- If clip is active then output will be clipped to the nominal range
-- otherwise the output will drive to the limit of the hardware
-- @param module The analogue module to change
-- @param c Boolean, clipping enabled?
-- @local
local function setClip(module, c)
    if module then
        if c == true then c = 1 elseif c == false then c = 0 end
        private.writeRegAsync(analogueClipRegisters[module], c)
    end
end

-------------------------------------------------------------------------------
-- Return the maximum number of analogue modules this device can support.
-- This does not mean that this many are installed, can be installed or are usable,
-- this is just the firmware's supported maximum.
-- @treturn int Maximum number of modules that are supported.
-- @usage
-- maxModules = device.getAnalogModuleMaximum()
-- print("This device can support at most " .. maxModules .. " analogue modules")
function _M.getAnalogModuleMaximum()
    return maxAnalogueModules
end

-------------------------------------------------------------------------------
-- Set the analog output type.
-- @int module The analogue module to change.  Defaults to 1 (M4401).
-- @tparam AnalogSource source Source for output.
-- Must be set to 'comms' to control directly and this is the default.
-- @usage
-- device.setAnalogSource(1, 'comms')
function _M.setAnalogSource(module, source)
    return setSource(decodeModule(module, source))
end

-------------------------------------------------------------------------------
-- Set the analog output type
-- @int module The analogue module to change
-- @string oType Type for output, 'current' or 'volt'
-- @treturn string The previous analog output type
-- @usage
-- device.setAnalogType(1, 'volt')
function _M.setAnalogType(module, oType)
    return setType(decodeModule(module, oType))
end

-------------------------------------------------------------------------------
-- Control behaviour of analog output outside of normal range.
-- If clip is active then output will be clipped to the nominal range
-- otherwise the output will drive to the limit of the hardware
-- @int module The analogue module to change.  Defaults to 1 (M4401).
-- @bool c Clipping enabled?
-- @usage
-- device.setAnalogClip(1, false)
function _M.setAnalogClip(module, c)
    return setClip(decodeModule(module, c))
end

-------------------------------------------------------------------------------
-- Sets the analog output to minimum 0 through to maximum 50,000
-- @int module The analogue module to change.  Defaults to 1 (M4401).
-- @int raw value in raw counts (0..50000)
-- @usage
-- device.setAnalogRaw(1, 25000)   -- mid scale, first analogue module
function _M.setAnalogRaw(module, raw)
    return setRaw(decodeModule(module, raw))
end

-------------------------------------------------------------------------------
-- Sets the analogue output to minimum 0.0 through to maximum 1.0
-- @int module The analogue module to change.  Defaults to 1 (M4401).
-- @number val value 0.0 to 1.0
-- @usage
-- device.setAnalogVal(1, 0.5)     -- mid scale, first analogue module
function _M.setAnalogVal(module, val)
    return setVal(decodeModule(module, val))
end

 ------------------------------------------------------------------------------
-- Sets the analogue output to minimum 0% through to maximum 100%
-- @int module The analogue module to change.  Defaults to 1 (M4401).
-- @number val Value 0 to 100 (in percent)
-- @usage
-- device.setAnalogPC(1, 50)       -- mid scale, first analogue module
function _M.setAnalogPC(module, val)
    module, val = decodeModule(module, val)
    return setVal(module, val / 100)
end

 ------------------------------------------------------------------------------
-- Sets the analogue output to minimum 0.0V through to maximum 10.0V
-- @int module The analogue module to change.  Defaults to 1 (M4401).
-- @number val value 0.0 to 10.0
-- @usage
-- device.setAnalogVolt(1, 5)      -- mid scale, first analogue module
function _M.setAnalogVolt(module, val)
    module, val = decodeModule(module, val)
    setType(module, 'volt')
    return setVal(module, val / 10)
end

 ------------------------------------------------------------------------------
-- Sets the analogue output to minimum 4.0 through to maximum 20.0 mA
-- @int module The analogue module to change.  Defaults to 1 (M4401).
-- @number val value 4.0 to 20.0
-- @usage
-- device.setAnalogCur(1, 12)      -- mid scale, first analogue module
function _M.setAnalogCur(module, val)
    module, val = decodeModule(module, val)
    setType(module, 'current')
    return setVal(module, (val - 4) * 0.0625)
end

-- Include to preserve tests
if _TEST then
  deprecated.CUR = CUR
  deprecated.VOLT = VOLT
  
  private.registerDeviceInitialiser(function()
    deprecated.ANALOG_COMMS = analogSourceMap.comms
  end)
end

end
