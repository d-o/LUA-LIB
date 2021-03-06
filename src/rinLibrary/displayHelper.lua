-------------------------------------------------------------------------------
-- Display Helper
-- Functions to assist writing to the LCD
-- @module rinLibrary.displayHelper
-- @author Merrick Heley
-- @copyright 2015 Rinstrum Pty Ltd
-------------------------------------------------------------------------------

local _M = {}

local ipairs = ipairs
local string = string
local tostring = tostring

local namings = require 'rinLibrary.namings'
local usb = require 'rinLibrary.rinUSB'
local timers = require 'rinSystem.rinTimers'

local canonical = namings.canonicalisation

local lpeg = require 'rinLibrary.lpeg'
local C, Cg, Cs = lpeg.C, lpeg.Cg, lpeg.Cs
local P, Pi, R, S, V, spc = lpeg.P, lpeg.Pi, lpeg.R, lpeg.S, lpeg.V, lpeg.space
local sdot = P'.'
local scdot = (1 - sdot) * sdot^-1
local equals, formatPosition = spc^0 * P'=' * spc^0

-------------------------------------------------------------------------------
-- Return the number of LCD characters a string will consume.
-- @function strLenLCD
-- @param s The string to assess
-- @return The number of display characters
-- @see padDots
-- @see strSubLCD
-- @local
local strLenPat = Cs((scdot / ' ' + sdot)^0)
function _M.strLenLCD(s)
    return #strLenPat:match(s)
end

-------------------------------------------------------------------------------
-- Takes a string and pads ... with . . . for R420 to handle.
-- @function padDots
-- @param s String
-- @return Padded string
-- @see strSubLCD
-- @see strLenLCD
-- @local
local padDotsPat = Cs((scdot + sdot / ' .')^0)
function _M.padDots(s)
    return padDotsPat:match(s)
end

-------------------------------------------------------------------------------
-- Extract a substring based on the LCD width.
-- @param s String to substring
-- @param stPos Starting position
-- @param endPos Ending position, nil for end of string
-- @return The substring between display positions stPos and endPos
-- @see padDots
-- @see strLenLCD
-- @local
function _M.strSubLCD(s, stPos, endPos)
    if endPos == nil then
        endPos = #s
    end

    local n = 0
    local function process(s)
        n = n + 1
        return n >= stPos and n <= endPos and s or ''
    end
    return Cs(((scdot + sdot) / process)^0):match(s)
end

-------------------------------------------------------------------------------
-- Right justify a string in a given field
-- @param s string to justify
-- @param w width to justify to
-- @return justified string
-- @usage
-- if device.rightJustify('hello', 6) == ' hello' then
--     print('yes')
-- end
-- @local
function _M.rightJustify(s, w)
    s = tostring(s)
    local l = _M.strLenLCD(s)
    if l >= w then
        return s
    end
    if s:sub(1, 1) == '.' then l = l - 1 end
    return string.rep(" ", w-l) .. s
end

-- Values for rangerC
local sT = {gross='G', net='N', uload='U', oload='O', error='E', none='G'}
local mT = {motion='M', notmotion=' '}
local zT = {coz='Z', notcoz=' '}
local rT = {range1='1', range2='2', none='-'}
local uT = {kg=' kg', lb=' lb', t='  t',  g='  g', oz=' oz', n='  n', arrow_l='   ', p='  p', l='  L', arrow_h='   ', none='   '}

-------------------------------------------------------------------------------
-- Convert a value in an item table to its rangerC value.
-- @param item Item table, i.e. 'status', 'motion', 'coz', 'range', 'units'.
-- @param value Value to get the rangerC value of.
-- @return string value if valid, nil and invalid otherwise.
-- @usage
--  local status = rangerCFunc('status', 'gross')
--  -- status = 'G'
function _M.rangerCFunc(item, value)

  local tb = {status=sT, motion=mT, coz=zT, range=rT, units=uT}
  
  local itemTb = namings.convertNameToValue(namings.canonicalisation(item) or 'none', tb)
  
  local newValue = namings.convertNameToValue(value or 'none', itemTb)
  
  if (newValue == nil) then
    return nil, "invalid"
  end
  
  return newValue
end

-------------------------------------------------------------------------------
-- Convert a string to Ranger C
-- @param string String to write to the display
-- @param status Status to display. Convert using rangerCFunc.
-- @param motion Motion annunciator. Convert using rangerCFunc.
-- @param coz Centre-of-zero annunciator. Convert using rangerCFunc.
-- @param range Range annunciator. Convert using rangerCFunc.
-- @param units Units annunciator. Convert using rangerCFunc.
-- @param red Red traffic light annunciator (boolean)
-- @param green Green traffic light annunciator (boolean)
-- @param sock Socket if remote USB or ethernet display.
-- @return string on success, nil and error on failure
function _M.rangerC(string, status, motion, coz, range, units, red, green, sock)
  local sign
  local weight
  
  -- Check the length of the input
  if (#string > 7) then
    return nil, "string too long"
  end
  
  -- Extract the sign name
  if (string:sub(1,1) == '-') then
    sign = '-'
    
    if (red and green) then
      sign = '\125'
    elseif (green) then
      sign = '\109'
    elseif (red) then
      sign = '\061'
    end
    
    weight = string:sub(2)
  else
    sign = ' '
    
    if (red and green) then
      sign = '\112'
    elseif (green) then
      sign = '\096'
    elseif (red) then
      sign = '\048'
    end
    
    weight = string
  end
  
  if (#weight < 7) then
    weight = ("       " .. weight ):sub(-7)
  end
  
  if (sock) then
    return '\02' .. sign .. weight .. status .. motion .. coz .. 
      range .. units .. '\03' 
  end
  
  return '\\02' .. sign .. weight .. status .. motion .. coz .. 
      range .. units .. '\\03' 

end

-------------------------------------------------------------------------------
-- Build a transmittable message using rangerC
-- @param displayItem Item in the display table to create a message for
-- @return Framed message
-- @local
function _M.frameRangerC(displayItem)
  return _M.rangerC(displayItem.curString, 
                    displayItem.curStatus, 
                    displayItem.curMotion, 
                    displayItem.curCoz, 
                    displayItem.curRange, 
                    displayItem.curUnits1,
                    displayItem.curRed,
                    displayItem.curGreen,
                    displayItem.sock)
end

-------------------------------------------------------------------------------
-- Write a message to a register either synchronously or asynchronously
-- @param private The private portion of a K400 device
-- @param sync Boolean, true means synchronous writing
-- @param reg Register to write to
-- @param s String to write
-- @return reply received from instrument, nil if error
-- @return err error string if error received, nil otherwise
-- @local
function _M.writeRegHex(private, sync, reg, s)
    local f = private[sync and 'writeRegHex' or 'writeRegHexAsync']
    return f(reg, s)
end

-------------------------------------------------------------------------------
-- Write a status to the displayTable item based on the current statuses on the
-- R400. This is used for status mirroring.
-- @param me displayTable item to update
-- @param anyStatusSet Private function to check if any status is set
-- @param allStatusSet Private function to check if all statuses are set
-- @param dualRangeMode Private function to check if dualrange mode is enabled
-- @local
function _M.writeStatus(me, anyStatusSet, allStatusSet, dualRangeMode)
  
  if anyStatusSet('error') then
    me.curStatus = _M.rangerCFunc('status', 'error')
  elseif anyStatusSet('uload') then
    me.curStatus = _M.rangerCFunc('status', 'uload')
  elseif anyStatusSet('oload') then
    me.curStatus = _M.rangerCFunc('status', 'oload')
  elseif anyStatusSet('gross') then     
    me.curStatus = _M.rangerCFunc('status', 'gross')
  elseif anyStatusSet('net') then
    me.curStatus = _M.rangerCFunc('status', 'net')
  else
    me.curStatus = _M.rangerCFunc('status', 'none')
  end
  
  if anyStatusSet('motion') then
    me.curMotion = _M.rangerCFunc('motion', 'motion')
  else
    me.curMotion = _M.rangerCFunc('motion', 'notmotion')
  end
  
  if anyStatusSet('coz') then
    me.curCoz = _M.rangerCFunc('coz', 'coz')
  else
    me.curCoz = _M.rangerCFunc('coz', 'notcoz')
  end
  
  if (dualRangeMode == 'single') then
    me.curRange = _M.rangerCFunc('range', 'none')
  else
    if anyStatusSet('range1') then
      me.curRange = _M.rangerCFunc('range', 'range1')
    elseif anyStatusSet('range2') then
      me.curRange = _M.rangerCFunc('range', 'range2')
    else
      me.curRange = _M.rangerCFunc('range', 'none')
    end
  end
    
end

-------------------------------------------------------------------------------
-- Set the annunciators to on
-- @param me displayTable item to set annunciators for
-- @param ... Annunciators to enable
-- @local
function _M.setAnnun(me, ...)
  local argi
                    
  for i,v in ipairs(arg) do
    argi = canonical(v)
    
    if (argi == 'all') then 
      me.curStatus = _M.rangerCFunc('status', 'net')
      me.curMotion = _M.rangerCFunc('motion', 'motion')
      me.curCoz = _M.rangerCFunc('coz', 'coz')
      me.curRange = _M.rangerCFunc('range', 'range1')
    elseif (argi == 'net' ) then
      me.curStatus = _M.rangerCFunc('status', 'net')
    elseif (argi == 'motion') then
      me.curMotion = _M.rangerCFunc('motion', 'motion')
    elseif (argi == 'coz') then
      me.curCoz = _M.rangerCFunc('coz', 'coz')
    elseif (argi == 'range1') then
      me.curRange = _M.rangerCFunc('range', 'range1')
    elseif (argi == 'range2') then
      me.curRange = _M.rangerCFunc('range', 'range2')
    end                        
  end                    
  
end

-------------------------------------------------------------------------------
-- Set the annunciators to off
-- @param me displayTable item to clear annunciators for
-- @param ... Annunciators to disable
-- @local
function _M.clearAnnun(me, ...)
  local argi
                    
  for i,v in ipairs(arg) do
    argi = canonical(v)
    
    if (argi == 'all') then 
      me.curStatus = _M.rangerCFunc('status', 'gross')
      me.curMotion = _M.rangerCFunc('motion', 'notmotion')
      me.curCoz = _M.rangerCFunc('coz', 'notcoz')
      me.curRange = _M.rangerCFunc('range', 'none')  
    elseif (argi == 'net' ) then
      me.curStatus = _M.rangerCFunc('status', 'gross')
    elseif (argi == 'motion') then
      me.curMotion = _M.rangerCFunc('motion', 'notmotion')
    elseif (argi == 'coz') then
      me.curCoz = _M.rangerCFunc('coz', 'notcoz')
    elseif (argi == 'range1') then
      me.curRange = _M.rangerCFunc('range', 'none')
    elseif (argi == 'range2') then
      me.curRange = _M.rangerCFunc('range', 'none')
    end                        
  end
  
end

-------------------------------------------------------------------------------
-- Handle the traffic lights
-- @param me displayTable item to set annunciators for
-- @param value Value to set the traffic lights too. (boolean true or false)
-- @param ... Taffic lights to enable or disable
-- @local
function _M.handleTraffic (me, value, ...)
  local argi
  
  for i,v in ipairs(arg) do
    argi = canonical(v)
    
    if (argi == 'all') then
      me.curRed = value
      me.curGreen = value
    elseif (argi == 'redlight') then
      me.curRed = value
    elseif (argi == 'greenlight') then
      me.curGreen = value
    end
  end
end

-------------------------------------------------------------------------------
-- Set a display to USB mode (rather than R400 serial)
-- @param me displayTable item to enable USB mode for
-- @local
function _M.addUSB(me)
  me.transmit = function (sync)
    local toSend = _M.frameRangerC(me)
    
    if (me.sock) then
      return me.sock:write(toSend)
    end
    return nil, "transmit failed"
  end

  usb.serialUSBdeviceHandler(function (c, err, port)
    if (err == 'open') then
      me.sock = port
    else
      me.sock = nil
    end
  end)
                              
  timers.addTimer(0.2, 0.2, me.transmit, false)
end

return _M
