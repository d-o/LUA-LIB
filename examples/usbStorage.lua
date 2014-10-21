-------------------------------------------------------------------------------
-- usbStorage
--
-- Application to demonstrate how to use the basic features of the USB
-- storage subsystem.
-------------------------------------------------------------------------------
local dbg = require 'rinLibrary.rinDebug'
local rinApp = require "rinApp"                 --  load in the application framework
local usb = require "rinLibrary.rinUSB"

--=============================================================================
-- Connect to the instruments you want to control
-- Define any Application variables you wish to use
--=============================================================================
local device = rinApp.addK400("K401")           --  make a connection to the instrument
device.loadRIS("myApp.RIS")                     -- load default instrument settings

--=============================================================================
-- This function is called when the user chooses to write to the USB device
local function usbBackup(path)
    dbg.info('Saving state to the USB device at '..path)
	usb.copyDirectory("data", path .. '/data')  -- Copy the data directory
    usb.copyFiles(".", path .. '/lua', '.lua')  -- back up .lua files
    usb.copyFiles(".", path , '.ris')           -- back up .ris files
    usb.copyFiles(".", path , '.csv')           -- back up .ris files
end

--=============================================================================
-- This function is called when the user chooses to read from the USB device
local function usbUpdate(path)
    usb.copyFiles(path, ".", 'ris')             -- copy new settings files
    usb.copyFiles(path, ".", 'csv')             -- copy CSV files
    return true                                 -- force a reboot
end

--=============================================================================
-- Set up the USB storage handling subsystem
device.usbActivateStorage {
    backup = usbBackup,
    update = usbUpdate
}

--=============================================================================
-- run the application
device.write('bottomLeft', 'INSERT USB STORAGE DEVICE')
rinApp.run()
--=============================================================================
