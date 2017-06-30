#!/usr/bin/env lua
-------------------------------------------------------------------------------
-- Menu
--
-- An example of how to use the menu UI class.
--
-- Creates a menu containing the various items available and runs it.
-------------------------------------------------------------------------------
local rinApp = require "rinApp"         --  load in the application framework

--=============================================================================
-- Connect to the instruments you want to control
--=============================================================================
local device = rinApp.addK400()         --  make a connection to the instrument

-- Sample menu hooked onto the F3 short press
-- This includes examples of all the available field types
local menu = device.createMenu { 'TOP MENU', loop=false } -- create a menu
    .integer    { 'INT', 3, min=1, max=5 }          -- Add an integer item
    .integer    { 'ONE', 1 }                        -- Another integer without min and max limits
    .integer    { 'UNWRIT', 16, readonly=true }     -- An unmodifiable integer
    .menu       { 'NUMBER' }                        -- A submenu called NUMBERS
        .integer    { 'COUNT', 0, min=0, max=9 }
        .number     { 'SCALE', 1, min=0.9, max=1.1} -- A real number with limits
        .number     { 'FUDGE', 2.7182818 }          -- Another real number
        .passcode   { 'SECRET', 1111 }              -- A pass code entry field
        .fin()                                      -- End the sub menu
    .menu       { 'STRING', secondary = 'EDITING' }
        .string     { 'SHORT', 'abc', 3 }           -- Three character string
        .string     { 'LONG', 'hello', 15 }         -- A longer string
        .fin        {}
    .boolean    { 'OKAY?' }                         -- A yes/no field
    .boolean    { 'SURE?', 'YEP', 'YEP', 'NOPE' }   -- A two pick list
    .list       { 'PROD',                           -- A pick list of three elements
                    { 'WHEAT', 'RICE', 'CORN' } }   -- That wraps top to bottom
    .menu       { 'REG', secondary = 'VIEWER' }
        .register   { 'USER 1', 'userid1' }
        .register   { 'USER 2', 'userid2', prompt = 'U2' }
        .register   { 'MVV', 'absmvv' }
        .fin()
    .item       { 'PRESS', secondary = 'ME NOW',
                    onRun=function() print('hello user') end }
    .item       { 'quit', uppercasePrompt = false, exit=true } -- don't upper case this one

device.write('bottomLeft', 'WELCOME TO THE MENU EXAMPLE')
device.write('bottomRight', 'F3 FOR THE MENU F2 FOR ENABLES')
device.setKeyCallback('f3', menu.run, 'short')

-- A second sample menu that illustrates the ways of enabling and disabling
-- items.  This menu is hooked up to F2 function key.
local enableMenu                                    -- Has to be separate
enableMenu = device.createMenu { 'ENABLE MENU' }
    .list       { 'CHOOSE', { 'A', 'B', 'C' }, default = 'A' }
    .integer    { 'A', 1,   enabled = function()   -- An integer that appears based on the list choise
                                          return enableMenu.getValue('CHOOSE') == 'A'
                                      end }
    .integer    { 'B', 2,   enabled = function()   -- A string that appears based on the list choice
                                          return enableMenu.getValue('CHOOSE') == 'B'
                                      end }
    .menu       { 'C',      enabled = function()      -- A menu that appears based on the list choice
                                          return enableMenu.getValue('CHOOSE') == 'C'
                                      end }
        .integer    { 'C1', 3 }
        .integer    { 'C2', 4 }
        .fin()
    -- Menu items that turn on and off other items
    -- Also an item that toggles the read only status of another
    .item       { '+  D', onRun=function() enableMenu.enable('D', true)  end,
                          enabled=function() return not enableMenu.enabled('D') end }
    .item       { '-  D', onRun=function() enableMenu.enable('D', false) end,
                          enabled=function() return enableMenu.enabled('D') end }
    .item       { 'ro D', onRun=function() enableMenu.setReadonly('D', not enableMenu.isReadonly('D'))  end }
    .integer    { 'D', 5 }
    .item       { 'QUIT', exit=true }
device.setKeyCallback('f2', enableMenu.run, 'short')


-- We can query out menu fields via the top level menu
function printMenuContents()
    for _, n in ipairs{'integer', 'another', 'count', 'scale', 'fudge',
                        'secret', 'short', 'long', 'product'
    } do
        print(n, menu.getValue(n))
    end
end
device.setKeyCallback('f3', printMenuContents, 'long')

device.setKeyCallback('f1', function()
    device.write('bottomLeft', 'SAVING', 'time=2, clear')
    menu.toCSV('settings.csv')
end, 'short')
device.setKeyCallback('f1', function()
    device.write('bottomLeft', 'LOADING', 'time=2, clear')
    menu.fromCSV('settings.csv')
end, 'long')

rinApp.run()
