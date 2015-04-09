-------------------------------------------------------------------------------
-- Buzzer unit test.
-- @author Pauli
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------

describe("buzzer #buzz", function ()
    local regLen, regNum = 0x0327, 0x0328
    local short, medium, long = 0, 1, 2

    local function makeModule()
        local m, p, d = {}, {}, {}
        require("rinLibrary.utilities")(m, p, d)
        require("rinLibrary.K400Buzz")(m, p, d)
        return m, p, d
    end

    it("registers", function()
        local m = makeModule()
        assert.equal(m.REG_BUZZ_LEN, regLen)
        assert.equal(m.REG_BUZZ_NUM, regNum)
    end)

    it("enumerations", function()
        local m = makeModule()
        assert.equal(m.lengths.short,  short)
        assert.equal(m.lengths.medium, medium)
        assert.equal(m.lengths.long,   long)
    end)

    -- These tests are digging deep into the non-exposed internals
    describe("length", function()
        local z = require "tests.messages"
        local m = makeModule()

        it("initial", function()
            assert.is_nil(m.getLastBuzzLen())
            z.checkWriteRegHexAsync(m, {{ r=regLen, short }}, m.setBuzzLen)
        end)

        local cases = {
            { long,      long },
            { short,     short },
            { medium,    medium },
            { short - 1, short },
            { 'long',    long },
            { 'short',   short },
            { 'medium',  medium },
            { long + 1,  short },
        }
        for n = 1, #cases do
            it("test "..n, function()
                local i, val = cases[n][1], cases[n][2]

                z.checkWriteRegHexAsync(m, {{ r=regLen, val }}, m.setBuzzLen, i)
                assert.is_equal(val, m.getLastBuzzLen())
                z.checkNoWriteRegHexAsync(m, m.setBuzzLen, i)
            end)
        end
    end)

    it("buzz", function()
        local z = require "tests.messages"
        local m = makeModule()

        z.checkWriteRegHexAsync(m, {{ r=regNum, 1 },       { r=regLen, short }}, m.buzz)
        z.checkWriteRegHexAsync(m, {{ r=regNum, 1 }},                            m.buzz, 1)
        z.checkWriteRegHexAsync(m, {{ r=regNum, 4 }},                            m.buzz, 5)
        z.checkWriteRegHexAsync(m, {{ r=regLen, long },    { r=regLen, long}},   m.buzz, 3, 'long')
        z.checkWriteRegHexAsync(m, {{ r=regNum, 1 },       { r=regLen, short }}, m.buzz, 1, 'short')
        z.checkWriteRegHexAsync(m, {{ r=regLen, medium },  { r=regLen, medium }},m.buzz, 3, 'medium')
    end)
end)
