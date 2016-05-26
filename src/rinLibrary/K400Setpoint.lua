-------------------------------------------------------------------------------
--- Setpoint Functions.
-- Functions to control setpoint outputs
-- @module rinLibrary.Device.Setpoint
-- @author Darren Pearson
-- @author Merrick Heley
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------
local math = math
local bit32 = require "bit"
local timers = require 'rinSystem.rinTimers'
local dbg = require "rinLibrary.rinDebug"
local naming = require 'rinLibrary.namings'
local pow2 = require 'rinLibrary.powersOfTwo'

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Submodule function begins here
return function (_M, private, deprecated)

private.addRegisters{ io_status = 0x0051 }
local REG_IO_ENABLE         = 0x0054

local REG_SETP_NUM          = 0xA400

-- add Repeat to each registers below for each setpoint 0..15
local REG_SETP_REPEAT       = 0x0020
local REG_SETP_TYPE         = 0xA401
local REG_SETP_OUTPUT       = 0xA402
local REG_SETP_LOGIC        = 0xA403
local REG_SETP_ALARM        = 0xA404
local REG_SETP_NAME         = 0xA40E
local REG_SETP_SOURCE       = 0xA406
local REG_SETP_HYS          = 0xA409
local REG_SETP_SOURCE_REG   = 0xA40A

-- There are no wrapper functions for these five yet.
local REG_SETP_TIMING       = 0xA410
local REG_SETP_RESET        = 0xA411
local REG_SETP_PULSE_NUM    = 0xA412
local REG_SETP_TIMING_DELAY = 0xA40C
local REG_SETP_TIMING_ON    = 0xA40D

-- targets are stored in the product database rather than the settings one
local REG_SETP_TARGET       = 0xB080  -- add setpoint offset (0..15) for the other 16 setpoint targets

--- Setpoint Logic Types.
--@table Logic
-- @field high High
-- @field low Low
local logicMap = {
    high = 0,
    low  = 1
}

--- Setpoint Alarms Types.
--@table Alarms
-- @field none No alarm
-- @field single Beep once per second
-- @field double Beep twice per second
-- @field flash Flash the display
local alarmTypeMap = {
    none    = 0,
    single  = 1,
    double  = 2,
    flash   = 3
}

--- Setpoint Timing Types.
--@table Timing
-- @field level Level
-- @field edge Edge
-- @field pulse Pulse
-- @field latch Latch
local timingMap = {
    level = 0,
    edge  = 1,
    pulse = 2,
    latch = 3
}

--- Setpoint Source Types.
--@table Source
-- @field gross Setpoint uses the gross weight
-- @field net Setpoint uses the net weight
-- @field disp Setpoint uses the displayed weight
-- @field alt_gross Setpoint uses the gross weight in secondary units
-- @field alt_net Setpoint uses the net weight in secondary units
-- @field alt_disp Setpoint uses the displayed weight in secondary units
-- @field piece Setpoint uses the piece count value
-- @field reg Setpoint uses the value from the supplied register
local SOURCE_REG        = 7

local sourceMap
private.registerDeviceInitialiser(function()
    sourceMap = {
        gross     = 0,
        net       = 1,
        disp      = 2,
        alt_gross = private.nonbatching(3),
        alt_net   = private.nonbatching(4),
        alt_disp  = private.nonbatching(5),
        piece     = private.nonbatching(6),
        reg       = private.nonbatching(SOURCE_REG)
    }
end)

--- Setpoint Types.
--@table Types
-- @field off Setpoint is always inactive
-- @field on Setpoint is always active
-- @field over Setpoint is active when the source is over the target amount
-- @field under Setpoint is active when the source is under the target amount
-- @field coz Setpoint is active when the source is in the centre of zero
-- @field zero Setpoint is active when the source is in the zero band
-- @field net Setpoint is active when net weight is displayed
-- @field motion Setpoint is active when the weight is unstable
-- @field error Setpoint is active when there is an error
-- @field logic_and A binary logic AND is performed on the source with the mask value
-- @field logic_or A binary logic OR is performed on the source with the mask value
-- @field logic_xor A binary logic XOR is performed on the source with the mask value
-- @field scale_ready Setpoint is active when the scale is stable in the zero band for the set period of time (non-batching units only)
-- @field scale_exit Setpoint is active when there has been a print since the weight left the zero band (non-batching units only)
-- @field tol Setpoint is active when (batching units only)
-- @field pause Setpoint is active when (batching units only)
-- @field wait Setpoint is active when (batching units only)
-- @field run Setpoint is active when (batching units only)
-- @field fill Setpoint is active when (batching units only)
-- @field buzzer Setpoint is active when the buzzer is beeping
local typeMap
private.registerDeviceInitialiser(function()
    typeMap = {
        off         = 0,
        on          = 1,
        over        = 2,
        under       = 3,
        coz         = 4,
        zero        = 5,
        net         = 6,
        motion      = 7,
        error       = 8,
        logic_and   = 9,
        logic_or    = 10,
        logic_xor   = 11,
        scale_ready = private.nonbatching(12),
        scale_exit  = private.nonbatching(13),
        tol         = private.batching(12),
        pause       = private.batching(13),
        wait        = private.batching(14),
        run         = private.batching(15),
        fill        = private.batching(16),
        buzzer      = private.batching(17) or 14
    }
end)

local lastOutputs = nil
local timedOutputs = 0   -- keeps track of which IO are already running off timers
-- bits set if under LUA control, clear if under instrument control
local lastIOEnable = nil

local NUM_SETP = nil

-------------------------------------------------------------------------------
-- Write the bit mask of the IOs, bits must first be enabled for comms control.
-- @param outp 32 bit mask of IOs
-- @see setOutputEnable
-- @usage
-- -- set IO3 on
-- setOutputEnable(0x04)
-- setOutputs(0x04)
-- @local
local function setOutputs(outp)
    if outp ~= lastOutputs then
        private.writeRegAsync('io_status', outp)
        lastOutputs = outp
    end
end

-------------------------------------------------------------------------------
-- Enable IOs for comms control.
-- @param en 32 bit mask of IOs
-- @see setOutputs
-- @usage
-- -- set IO3 on
-- setOutputEnable(0x04)
-- setOutputs(0x04)
-- @local
local function setOutputEnable(en)
    if en ~= lastIOEnable then
        private.writeRegAsync(REG_IO_ENABLE, en)
        lastIOEnable = en
    end
end

-------------------------------------------------------------------------------
-- Turns IO Output on.
-- @param ... list of IO to turn on 1..32
-- @see enableOutput
-- @usage
-- -- set IOs 3 and 4 on
-- device.turnOn(3, 4)
function _M.turnOn(...)
    local curOutputs = lastOutputs or 0
    for _,v in ipairs{...} do
        if v < 32 and v > 0 and private.checkOutput(v) then
            curOutputs = bit32.bor(curOutputs, pow2[v-1])
        end
    end

    setOutputs(curOutputs)
end

-------------------------------------------------------------------------------
-- Turns IO Output off.
-- @param ... list of IO to turn off 1..32
-- @see enableOutput
-- @usage
-- -- set IOs 3 and 4 off
-- device.turnOff(3, 4)
function _M.turnOff(...)
    local curOutputs = lastOutputs or 0
    for _,v in ipairs{...} do
        if v < 32 and v > 0 and private.checkOutput(v) then
            curOutputs = bit32.band(curOutputs, bit32.bnot(pow2[v-1]))
        end
    end

    setOutputs(curOutputs)
end

-------------------------------------------------------------------------------
-- Turns IO Output on for a period of time.
-- @param IO is output 1..32
-- @param t is time in seconds
-- @see enableOutput
-- @usage
-- -- turn IO 1 on for 5 seconds
-- device.turnOnTimed(1, 5)
function _M.turnOnTimed(IO, t)
    if private.checkOutput(IO) then
        local IOMask = pow2[IO - 1]
        if bit32.band(timedOutputs, IOMask) == 0 then
            _M.turnOn(IO)
            timers.addTimer(0, t, function ()
                timedOutputs = bit32.band(timedOutputs, bit32.bnot(IOMask))
                _M.turnOff(IO)
            end)
            timedOutputs = bit32.bor(timedOutputs, IOMask)
        else
            dbg.warn('IO Timer overlap: ', IO)
        end
    end
end

-------------------------------------------------------------------------------
-- Sets IO Output under LUA control.
-- @param ... list of IO to enable (input 1..32)
-- @see releaseOutput
-- @usage
-- device.enableOutput(1,2,3,4)
-- device.turnOn(1)
-- device.turnOff(2)
-- device.turnOnTimed(3, 0.500) -- pulse output 3 for 500 milliseconds
-- device.releaseOutput(1,2,3,4)

function _M.enableOutput(...)
    local curIOEnable = lastIOEnable or 0

    for i,v in ipairs(arg) do
        v = tonumber(v)
        curIOEnable = bit32.bor(curIOEnable, pow2[v-1])
        private.setIOkind(v, true)
    end

    setOutputEnable(curIOEnable)
end

-------------------------------------------------------------------------------
-- Sets IO Output under instrument control.
-- @param ... list of IO to release to the instrument(input 1..32)
-- @see enableOutput
-- @usage
-- device.enableOutput(1, 2, 3, 4)
-- device.turnOn(1)
-- device.turnOff(2)
-- device.turnOnTimed(3, 0.500)  -- pulse output 3 for 500 milliseconds
-- device.releaseOutput(1, 2, 3, 4)
function _M.releaseOutput(...)
    local curIOEnable = lastIOEnable or 0

    for i,v in ipairs(arg) do
        v = tonumber(v)
        curIOEnable = bit32.band(curIOEnable, bit32.bnot(pow2[v-1]))
        private.setIOkind(v, false)
    end

    setOutputEnable(curIOEnable)
end

--------------------------------------------------------------------------------
-- Returns actual register address for a particular setpoint parameter.
-- @param setp is setpoint 1 .. setPointCount()
-- @param register is REG_SETP_*
-- @see setPointCount
-- @return address of this register for setpoint setp
-- @usage
-- -- edit the target for setpoint 3
-- device.editReg(device.setpRegAddress(3, device.REG_SETP_TARGET))
function _M.setpRegAddress(setp, register)
    local reg = private.getRegisterNumber(register)

    if (setp > _M.setPointCount()) or (setp < 1) then
        dbg.error('Setpoint Invalid: ', setp)
        return nil
    elseif reg == REG_SETP_TARGET then
        return reg+setp-1
    else
        return reg+((setp-1)*REG_SETP_REPEAT)
    end
end

--------------------------------------------------------------------------------
-- Write to a set point register.
-- @param setp Setpoint 1 .. setPointCount()
-- @param reg Register (REG_SETP_*)
-- @param v Value to write
-- @see setPointCount
-- @local
local function setpParam(setp, reg, v)
    local r = private.getRegisterNumber(reg)
    private.writeReg(_M.setpRegAddress(setp, r), v)
end

-------------------------------------------------------------------------------
-- Set the number of enabled Setpoints.
-- this disables all setpoints above the set number
-- @param n is the number of setpoints 1 .. setPointCount()
-- @see setPointCount
-- @usage
-- -- reduce the number of active setpoints to setpoints 1 to 4 temporarily
-- device.setNumSetp(4)
-- ...
-- -- re-enable previously disabled setpoints
-- device.setNumSetp(8)
function _M.setNumSetp(n)
    if (n > _M.setPointCount()) or (n < 1) then
        dbg.error('Setpoint Invalid: ', n)
    else
        private.writeReg(REG_SETP_NUM, n-1)
    end
end

-------------------------------------------------------------------------------
-- Set Target for setpoint.
-- @param setp Setpoint 1 .. setPointCount()
-- @param target Target value
-- @see setPointCount
-- @usage
-- -- set the target for setpoint 5 to 150
-- device.setpTarget(5, 150)
function _M.setpTarget(setp,target)
    private.writeReg(_M.setpRegAddress(setp, REG_SETP_TARGET), target)
end

-------------------------------------------------------------------------------
-- Set which Output the setpoint controls.
-- @param setp is setpoint 1 .. setPointCount()
-- @param IO is output 1..32, 0 for none
-- @see setPointCount
-- @usage
-- -- make setpoint 12 use IO 3
-- device.setpIO(12, 3)
function _M.setpIO(setp, IO)
    setpParam(setp, REG_SETP_OUTPUT, IO)
end

-------------------------------------------------------------------------------
-- Set the TYPE of the setpoint controls.
-- @param setp is setpoint 1 .. setPointCount()
-- @param sType is setpoint type
-- @see setPointCount
-- @usage
-- -- set setpoint 10 to over
-- device.setpType(10, 'over')
function _M.setpType(setp, sType)
    local v = naming.convertNameToValue(sType, typeMap)
    setpParam(setp, REG_SETP_TYPE, v)
end

-------------------------------------------------------------------------------
-- Set the Logic for the setpoint controls.
-- High means the output will be on when the setpoint is active and
-- low means the output will be on when the setpoint is inactive.
-- @param setp is setpount 1 .. setPointCount()
-- @param lType is setpoint logic type "high" or "low"
-- @see setPointCount
-- @usage
-- -- make setpoint 4 active high
-- device.setpLogic(4, 'high')
function _M.setpLogic(setp, lType)
    local v = naming.convertNameToValue(lType, logicMap)
    setpParam(setp, REG_SETP_LOGIC, v)
end

-------------------------------------------------------------------------------
-- Set the Alarm for the setpoint.
-- The alarm can beep once a second, twice a second or flash the display when
-- the setpoint is active
-- @param setp is setpoint 1 .. setPointCount()
-- @param aType is alarm type
-- @see setPointCount
-- @usage
-- -- disable the alarm on setpoint 11
-- device.setpAlarm(11, 'none')
function _M.setpAlarm(setp, aType)
    local v = naming.convertNameToValue(aType, alarmTypeMap)
    setpParam(setp, REG_SETP_ALARM, v)
end

-------------------------------------------------------------------------------
-- Set the Name of the setpoint.
-- This name will be displayed when editing targets via the keys.
-- @function setpName
-- @param setp is setpoint 1 .. setPointCount()
-- @param v is setpoint name (8 character string)
-- @see setPointCount
-- @usage
-- -- name setpoint 6 fred
-- device.setpName(6, 'fred')
function _M.setpName(setp, v)
    dbg.error("K400Setpoint:", "unable to name setpoints on this device")
end
private.registerDeviceInitialiser(function()
    if private.nonbatching(true) then
        _M.setpName = function(setp, v)
            setpParam(setp, REG_SETP_NAME, v)
        end
    end
end)

-------------------------------------------------------------------------------
-- Set the data source of the setpoint controls.
-- @param setp is setpoint 1 .. setPointCount()
-- @param sType is setpoint source type (string)
-- @param reg is register address for setpoints using source register type source data.
-- For other setpoint source types parameter reg is not required.
-- @see setPointCount
-- @usage
-- -- set setpoint 1 to use the displayed weight
-- device.setpSource(1, 'disp')
--
-- -- set setpoint 2 to use the total weight
-- device.setpSource(2, 'reg', 'grandtotal')
function _M.setpSource(setp, sType, reg)
    local v = naming.convertNameToValue(sType, sourceMap)

    setpParam(setp, REG_SETP_SOURCE, v)
    if (v == SOURCE_REG) and reg then
        setpParam(setp, REG_SETP_SOURCE_REG, private.getRegisterNumber(reg))
    end
end

-------------------------------------------------------------------------------
-- Set the Hysteresis for of the setpoint controls.
-- @param setp is setpoint 1 .. setPointCount()
-- @param v is setpoint hysteresis
-- @see setPointCount
-- @usage
-- -- set setpoint 1 target to 1200 and hysteresis to 10
-- device.setTarget(1, 1200)
-- device.setpHys(1, 10)
function _M.setpHys(setp, v)
    setpParam(setp, REG_SETP_HYS, _M.toPrimary(v))
end

-------------------------------------------------------------------------------
-- Query the number of set points that are available.
-- @return The number of set points
-- @usage
-- local n = device.setPointCount()
function _M.setPointCount()
    if NUM_SETP == nil then
        local n = private.getRegMax(REG_SETP_NUM)
        if n ~= nil then
            NUM_SETP = tonumber(n, 16) + 1
        end
    end
    return NUM_SETP
end

end

