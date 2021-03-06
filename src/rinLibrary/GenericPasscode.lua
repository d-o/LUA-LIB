-------------------------------------------------------------------------------
-- Library for Passcode support.
-- @module rinLibrary.Device.Passcode
-- @author Darren Pearson
-- @author Merrick Heley
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------
local string = string
local tonumber = tonumber
local bit32 = require "bit"
local msg = require 'rinLibrary.rinMessage'

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Submodule function begins here
return function (_M, private, deprecated)

local REG_FULLPCODEDATA     = 0x00D0
local REG_SAFEPCODEDATA     = 0x00D1
local REG_OPERPCODEDATA     = 0x00D2

local REG_FULLPCODE         = 0x0019
local REG_SAFEPCODE         = 0x001A
local REG_OPERPCODE         = 0x001B

local passcodes = {
    full = { pcode = REG_FULLPCODE, pcodeData = REG_FULLPCODEDATA },
    safe = { pcode = REG_SAFEPCODE, pcodeData = REG_SAFEPCODEDATA },
    oper = { pcode = REG_OPERPCODE, pcodeData = REG_OPERPCODEDATA }
}

-------------------------------------------------------------------------------
-- Command to check to see if passcode entry required and prompt if so
-- @string pc Options are 'full','safe','oper'
-- @string[opt] code Passcode to unlock, nil to prompt user
-- @int[opt] tries Number of tries to make before giving up (default 1).
-- More than 3 consecutive incorrect attempts will lock the instrument until it
-- is rebooted.
-- @treturn bool True if unlocked, false otherwise
-- @usage
-- if device.checkPasscode('full', nil, 3) then
--     print('you have full access now')
-- end
function _M.checkPasscode(pc, code, tries)
    local pc = pc or 'full'
    local pcode = passcodes[pc].pcode
    local f = msg.removeErrHandler()
    local pass = ''
    local tries = tries or 1
    local count = 1

    local finished = _M.startDialog()
    while _M.dialogRunning() and _M.app.isRunning() do
        local m, err = private.readRegHex(pcode, 1.0)
        if not m then
            if count > tries then
                msg.setErrHandler(f)
                finished()
                return false
            end
            if count > 1 and err then
                _M.write('defaultWriter', string.upper(err),1.0)
                _M.buzz(1,_M.BUZZ_LONG)
                _M.app.delay(2.0)
            end
            if code then
                pass = code
                code = nil
            else
                local ok = false
                pass, ok = _M.edit('ENTER PCODE','','passcode')
                if not ok or not pass then
                    msg.setErrHandler(f)
                    finished()
                    return false
                end
            end
            m, err = private.writeRegHex(pcode, _M.toPrimary(pass, 0), 1.0)
            count = count + 1
        else
            break
        end
    end
    finished()
    msg.setErrHandler(f)
    return true
end

-------------------------------------------------------------------------------
-- Command to lock instrument
-- @string pc Options are 'full','safe','oper'
-- Set a timeout of thirty seconds before full access is lost
-- @usage
-- timers = require 'rinSystem.rinTimers'
-- timers.addTimer(0, 30, function() device.lockPasscode('full') end)
function _M.lockPasscode(pc)
    local pc = pc or 'full'
    local pcode = passcodes[pc].pcode
    local pcodeData = passcodes[pc].pcodeData

    local f = msg.removeErrHandler()
    local m, err = private.readRegHex(pcodeData, 1.0)
    if m then
        m = bit32.bxor(tonumber(m,16),0xFF)
        m, err = private.writeRegHex(pcode, _M.toPrimary(m, 0), 1.0)
    end
    msg.setErrHandler(f)
end

-------------------------------------------------------------------------------
-- Command to change instrument passcode
-- @string pc Options are 'full','safe','oper'
-- @string[opt] oldCode Passcode to unlock, nil to prompt user
-- @string[opt] newCode Passcode to set, nil to prompt user
-- @treturn bool True if successful
-- @treturn string New pass code if successful, nil otherwise
-- @usage
-- local pc = device.selectOption('ENTER PASSCODE', {'full', 'safe', 'oper'}, 'full', true)
-- if pc then
--     device.changePasscode(pc)
-- end
-- -- Save settings to set the passcode
-- device.saveSettings()
function _M.changePasscode(pc, oldCode, newCode)
   local pc = pc or 'full'
   local pcodeData = passcodes[pc].pcodeData
   if _M.checkPasscode(pc,oldCode) then
        if not newCode then
            local pass, ok = _M.edit('NEW','','passcode')
            if not ok then
               return false, nil
            end
            newCode = pass
        end
        local m, err = private.writeRegHex(pcodeData, _M.toPrimary(newCode, 0), 1.0)
        if not m then
            return false, nil
        else
            return true, newCode
        end
    end
    return false, nil
end

end
