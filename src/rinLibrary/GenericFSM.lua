-------------------------------------------------------------------------------
--- Finite State Machine Infrastructure.
-- Library routines to make the implementation of finite automata easier.
-- @module rinLibrary.Device.FSM
-- @author Pauli
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------
local dbg = require "rinLibrary.rinDebug"
local utils = require 'rinSystem.utilities'
local canonical = require('rinLibrary.namings').canonicalisation
local timers = require 'rinSystem.rinTimers'
local deepcopy = utils.deepcopy
local null, True, cb = utils.null, utils.True, utils.cb

local table = table
local type = type
local unpack = unpack
local error = error
local string = string

-------------------------------------------------------------------------------
-- Check the curent status of a single bit trigger
-- @param f Bit check function to call
-- @param s Settings
-- @return Boolean, true if all are set, false otherwise
-- @local
local function checkOneStatus(f, s)
    if s ~= nil then
        if type(s) ~= 'table' then return f(s) end
        return f(unpack(s))
    end
    return true
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Submodule function begins here
return function (_M, private, deprecated)

--- Finite State Machine Definition Arguments.
--
-- These are the parameters that can be given when creating a new finite state
-- machine.  All of these fields are optional, although it is good practice to
-- include a state name.
--
-- @table FiniteStateMachineDefinition
-- @field showState Boolean argument that displays the current state in the
-- top right display field.  By default, this is false and the state is not displayed.
--
-- @field trace Boolean argument that, when true, produce information trace about
-- state changes and transitions.  By default this is false and no trace is output.
--
-- @field name The name to be given to the state machine, use the first positional
-- argument instead of the <i>name=</i> version for brevity.  This is only used when
-- producing information messages.

--- State Definition Arguments.
--
-- When defining a state there are a number of arguments which can be included to
-- alter the bahaviour of the overall state machine.  The only mandatory argument is
-- the name and for simplicity this can be placed first without the name= tag.  All other
-- arguments are optional.
--
-- @table FiniteStateMachineStates
-- @field enter A function that will be called whenever this field becomes active.  It
-- will only be called once per transition.  An enter function cannot raise or clear
-- any events.  If you want an enter function to raise an event you can do
-- <i>timers.addEvent(fsm.raise, 'myevent')</i> which will raise the event after the enter
-- function has finished.
--
-- @field leave A function that will be called whenever this field is transitioned
-- away from (i.e. becoming inactive).  A leave function cannot raise or clear any events.
-- If you want a leave function to raise an event you can do
-- <i>timers.addEvent(fsm.raise, 'myevent')</i> which will raise the event after the leave
-- function has finished.
--
-- @field name Name of this state.  Generally use the first positional argument instead
-- of the <i>name=</i> form for brevity.
--
-- @field run A function that will be repeatedly called whenever this state is active.
--
-- @field short Short form of the name which is displayed in the upper right if
-- the enclosing finite state machine has the showState setting enabled.  This field
-- defaults to the state name if no separate value is supplied.

--- State Transition Arguments
--
-- A transition is the motion between two states.  These are triggered by a specified
-- condition or conditions.  Transitions are automatically processed in the order in
-- which they are defined.  The destination is mandatory and the from must either be
-- defined state name or nil (mean all currently defined states).  All the rest of the
-- arguments are optional.
--
-- Where there are multiple conditions set for activating a transition, <i>all</i> of
-- them must be satisfied for the transition to trigger.  If no conditions are set, the
-- transition will always activate.
--
-- @table FiniteStateMachineTransitions
-- @field activate A function that will be execute after this transition activates.  The state
-- machine will be in the destination state when this executes but the destination's entry
-- will not yet have been called, it is called after this run function returns.  An
-- activate function cannot raise or clear any events.  If you want an activate function to raise
-- an event you can do <i>timers.addEvent(fsm.raise, 'myevent')</i> which will raise the event
-- after the activate function has finished.
--
-- @field cond The condition under which the transition will activate.  This function
-- should return a boolean and if true, the transition will be taken.
--
-- @field dest The destination state for this transition.  This cannot be undefined and
-- must refer to a valid already defined state.  Generally, use the second positional
-- argument instead of the <i>dest=</i> form here.
--
-- @field event An event which causes this transition to activate.  Events are raised
-- by other portions of the application.  The event should typically be a string for
-- readability purposes.  Events that have been raised, remain raised until manually
-- cleared or a state transition or change occurs.
--
-- @field from The state from which this transition will go. Setting this to 'all' means
-- all states which can be useful for error handling.  Generally specify this using the
-- first positional argument not the <i>from=</i> form.
--
-- @field io The inputs that must be set for this transition to trigger.  Either
-- a number or a table of several numbers.
--
-- @field name The name for this transition, by default from-destination will be used.
-- This argument is only used for diagnostic messages and during tracing.
--
-- @field setpoint The setpoints that must be set for this transition to trigger.  Either
-- a number or a table of several numbers.
--
-- @field status The statuses that must be set for this transition to trigger.  Either a
-- string containing one status, or a table of several.
--
-- @field time The amount of time that the <i>from</i> state must have been active before
-- this transition will trigger.  This is only a minimum, it is highly likely that more
-- time will have elapsed before the transition activates.  Of course, all of the other
-- trigger conditions also have to be met.
--
-- @see rinLibrary.Device.Status.luastatus

-------------------------------------------------------------------------------
-- Check the status, setpoint and IO settings for a transition trigger
-- @param t Transition
-- @return Boolean, true if all statuses, IOs and setpoints are set
-- @local
local function checkBitConditions(t)
    return  checkOneStatus(_M.allStatusSet, t.status) and
            checkOneStatus(_M.allIOSet, t.io) and
            checkOneStatus(_M.allSETPSet, t.setpoint)
end

-------------------------------------------------------------------------------
-- Define and create a new state machine
-- @param args State machine parameteres
-- @return state machine
-- @see FiniteStateMachineDefinition
-- @usage
-- local fsm = device.stateMachine { 'my FSM' }
--                      .state { 'initialise' }
--                      .state { 'waiting', enter=enterWait }
--                      .trans { 'initialise', 'waiting', cond=readyToWait }
function _M.stateMachine(args)
    local initial, warnNoState = nil, false
    local name = args[1] or args.name or 'FSM'
    local states, current = {}, nil
    local events, raiseEvents, eventStatus = {}, {}, nil
    local showState, trace = args.showState or false, args.trace or false
    local fsm = {}

-------------------------------------------------------------------------------
-- Return a properly formatted error name string
-- @param module The function to be tagged as having the issue/warning.
-- @return Module string for debug library
-- @local
    local function ename(module)
        return 'FSM ' .. module .. ' (' .. name .. '):'
    end

-------------------------------------------------------------------------------
-- Check if a time based transition is due or not
-- @param t Transition
-- @return Boolean, true iff the time has passed
-- @local
    local function checkTime(t)
        return t.time == nil or timers.monotonicTime() >= (t.time + current.activeTime)
    end

-------------------------------------------------------------------------------
-- Check if an event has been raised or not
-- @param t Transition
-- @param pending Pending event table
-- @return Boolean, true iff the event has been raised
-- @local
    local function checkEvent(t, pending)
        return t.event == nil or pending[t.event]
    end

-------------------------------------------------------------------------------
-- Produce a warning meesage if an attempt is made to raise or clear an event
-- from the enter, leave or activate callbacks or if the event isn't defined
-- by any transition.
-- @param name The name of the calling function
-- @param verb The verb to use in the message
-- @param event The event being raised or cleared
-- @return true if all is okay, false otherwise
-- @local
    local function checkEventStatus(name, verb, event)
        if eventStatus ~= nil then
            dbg.error(ename(eventStatus), "Event '"..event.."' cannot be "..verb.." within activate, enter or leave")
            return false
        end
        if events[event] == nil then
            dbg.error(ename(name), "Event '"..event.."' is not defined")
            return false
        end
        return true
    end

-------------------------------------------------------------------------------
-- Set the state of the finite state machine
-- @param s State table
-- @param f Function to call between states, optional
-- @local
    local function setState(s, f)
        local prevName
        if trace then
            dbg.info('FSM', name..' state = ' ..s.name)
        end
        raiseEvents = {}
        if current ~= nil then
            prevName = current.name
            eventStatus = 'leave'   current.leave(s.name)
            -- Ensure that all messages are flushed when the state is changed.
            --_M.flush()
        end
        current = s
        current.activeTime = timers.monotonicTime()
        eventStatus = 'activate'    utils.call(f)
        if showState then _M.write('topRight', s.short) end
        eventStatus = 'enter'       current.enter(prevName)
        eventStatus = nil
    end

-------------------------------------------------------------------------------
-- Add a state to a finite state machine
-- @function state
-- @param args State definition arguments
-- @return The finite state machine
-- @see FiniteStateMachineStates
-- @usage
-- local fsm = device.stateMachine { 'my FSM' }
--                      .state { 'initialise' }
--                      .state { 'waiting', enter=enterWait }
--                      .trans { 'initialise', 'waiting', cond=readyToWait }
    function fsm.state(args)
        local name = args[1] or args.name
        local state = {
            name = name,
            ref = canonical(name),
            short = args.short or string.upper(name),
            run = cb(args.run, null),
            enter = cb(args.enter, null),
            leave = cb(args.leave, null),
            trans = {}
        }
        if state.ref == 'all' then
            error(ename'state' .. " state '" .. name .. "' is reserved")
        elseif states[state.ref] ~= nil then
            error(ename'state' .. " state '" .. name .. "' already defined")
        end
        states[state.ref] = state
        if initial == nil then
            initial = state
            setState(state)
        end
        return fsm
    end

-------------------------------------------------------------------------------
-- Add a state transition to a finite state machine
-- @function trans
-- @param args Transition arguments table
-- @return The finite state machine
-- @see FiniteStateMachineTransitions
-- @usage
-- local fsm = device.stateMachine { 'my FSM' }
--                      .state { 'initialise' }
--                      .state { 'waiting', enter=enterWait }
--                      .trans { 'initialise', 'waiting', cond=readyToWait }
    function fsm.trans(args)
        local from = canonical(args[1] or args.from)
        local dest = canonical(args[2] or args.dest)
        local name = args.name or (tostring(from) .. '-' .. tostring(dest))

        if from ~= 'all' and states[from] == nil then
            error(ename'trans' .. ' unknown from state for '..name)
        elseif states[dest] == nil then
            error(ename'trans' .. ' unknown destination state for '..name)
        else
            local t = {
                name        = name,
                cond        = cb(args.cond, True),
                cname       = args.cname,
                time        = args.time,
                status      = deepcopy(args.status),
                io          = deepcopy(args.io),
                setpoint    = deepcopy(args.setpoint),
                activate    = cb(args.activate, null),
                dest        = states[dest]
            }

            if args.event ~= nil then
                t.event = canonical(args.event)
                events[t.event] = true
            end

            if from == 'all' then
                for _, s in pairs(states) do
                    if s.ref ~= dest then
                        table.insert(s.trans, t)
                    end
                end
            else
                table.insert(states[from].trans, t)
            end
        end
        return fsm
    end

-------------------------------------------------------------------------------
-- Get the name of the current finite state machine state
-- @function getState
-- @return string or nil if no current state
-- @see setState
-- @usage
-- print('state is currently', fsm.getState())
    function fsm.getState()
        return current ~= nil and current.name or nil
    end

-------------------------------------------------------------------------------
-- Set the current state of the finite state machine to the specified state.
-- This function ignores all the defined transitions but still calls the enter
-- and leave callbacks properly.
-- @function setState
-- @param s State to set to
-- @return True
-- @see getState
-- @see reset
-- @usage
-- fsm.setState('initial')
    function fsm.setState(s)
        local new = states[canonical(s)]
        if new then
            setState(new)
        else
            dbg.error(ename'setState', 'Unknown state '..s)
        end
        return true
    end

-------------------------------------------------------------------------------
-- Reset the finite state machine to its initial state.
-- This function ignores all the defined transitions but still calls the enter
-- and leave callbacks properly.
-- @function reset
-- @return True
-- @see setState
-- @usage
-- fsm.reset()
    function fsm.reset()
        setState(initial)
        return true
    end

-------------------------------------------------------------------------------
-- Raise an event which will be processed later.
-- The event must be one that has been defined in a transition.
-- Events are cleared on a state transition or state change.
-- @function raise
-- @return True
-- @param event The event to raise
-- @usage
-- fsm.raise('begin')
    function fsm.raise(event)
        event = canonical(event)
        if checkEventStatus('raise', 'raised', event) then
            raiseEvents[event] = true
        end
        return true
    end

-------------------------------------------------------------------------------
-- Clear an event.
-- The event must be one that has been defined in a transition.
-- @function clear
-- @return True
-- @param event The event to raise
-- @usage
-- fsm.clear('begin')
    function fsm.clear(event)
        event = canonical(event)
        if checkEventStatus('clear', 'cleared', event) then
            raiseEvents[event] = nil
        end
        return true
    end

-------------------------------------------------------------------------------
-- Step the finite state machine.
-- This calls the current state's run call back if defined and then checks for
-- all the transitions from the current state and executes them if required.
--
-- You will usually want to call the finite state machine's run function from your
-- main loop.
-- @function run
-- @return True
-- @usage
-- device.setMainLoop(fsm.run)
    function fsm.run()
        if current == nil then
            if not warnNoState then
                dbg.error(ename'run', 'No current state')
                warnNoState = true
            end
        else
            current.run()
            for _, t in ipairs(current.trans) do
                if t.cond() and checkEvent(t, raiseEvents) and checkBitConditions(t) and checkTime(t) then
                    if trace then
                        dbg.info('FSM', name..' trans '..t.name)
                    end
                    setState(t.dest, t.activate)
                    break
                end
            end
        end
        return true
    end

-------------------------------------------------------------------------------
-- Dump a DOT representation of the FSM to the given file.
-- This output can be converting in a graphical representation of the FSM using the
-- dot program from the <a href="http://www.graphviz.org/">graphviz</a> tools.
--
-- dot -Tpdf >myGraph.pdf <myGraph.dot
-- @function dump
-- @param filename Name of the output file.
-- @param showCurrent Boolean, highlight the current node.  By default, this
-- is not highlighted.
-- @return The finite state machine
-- @usage
-- fsm.dump('myGraph.dot')
    function fsm.dump(filename, showCurrent)
        -- Colourblind friend colour set
        local black, orange, blue, dblue ='#000000', '#E69F00', '#56B4E9', '#0072B2'
        local green, yellow, red, pink = '#009E73', '#F0E442', '#D55E00', '#CC79A7'

        local file = io.open(filename, 'w')
        local function w(...)
            file:write(...)
        end

        w('digraph "', name, '" {\n')
        w(' graph [label="', name, '", labelloc=t, fontsize=20];\n')
        for _, s in pairs(states) do
            -- State
            w(' "', s.ref, '" [label="', s.name)
            if showCurrent and s == current then w('\\ncurrent') end
            w('"')
            if s == initial then
                w(' style=filled color="', yellow, '"')
            end
            w(' fontsize=14];\n')

            -- State's transitions
            for _, t in pairs(s.trans) do
                local col, lbl

                -- Append transition attributes to the lists
                local function a(s, c)
                    if lbl == nil then
                        w(' [')
                    end
                    if c ~= nil then
                        if col == nil then col = c else col = col .. ':' .. c end
                    end
                    if lbl == nil then lbl = s else lbl = lbl .. '\\n' .. s end
                end

                -- Process the bit based transition triggers
                local function bits(b, c, pre)
                    if b ~= nil then
                        if type(b) == 'table' then
                            for _, v in pairs(b) do
                                a(pre .. v, c)
                                c = nil
                            end
                        else
                            a(pre .. b, c)
                        end
                    end
                end

                w('  "', s.ref, '" -> "', t.dest.ref, '"')
                if t.time and t.time > 0 then a('t='..t.time, green) end
                if t.event then a(t.event, red) end
                if t.cond ~= True then
                    a(t.cname or 'Cond', dblue)
                end
                bits(t.status, pink, '')
                bits(t.io, blue, 'IO ')
                bits(t.setpoint, orange, 'SP ')
                if lbl then
                    w('color="', col, '" label="', lbl, '" fontsize=10]')
                end
                w(';\n')
                if not lbl then break end
            end
        end
        w('}\n')
        file:close()
        utils.sync(false)

        return fsm
    end

    return fsm
end
end
