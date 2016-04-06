-------------------------------------------------------------------------------
-- Library for K400 application support.
-- Provides wrappers for all device services
-- @module rinLibrary.K400
-- @author Pauli
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------
local loader = require('rinLibrary.deviceLoader')

-- submodules are merged in as follows (and in this order):
local modules = {
    "rinCon",
    "K400Reg",
    "GenericReg",
    "GenericUtil",
    "K400Stream",
    "K400Status",
    "K400Axle",
    "K400Keys",
    "K400Buzz",
    "K400LCD",
    "K400Dialog",
    "K400FSM",
    "K400Menu",
    "K400RTC",
    "K400Analog",
    "K400Batch",
    "K400Setpoint",
    "K400Print",
    "K400Command",
    "K400Users",
    "K400Passcode",
    "K400USB",
    "K400Weights"
}

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Module factory function begins here
return function (model)
    return loader(model, modules)
end
