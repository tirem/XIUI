local LUA_ROOT = 'XIUI/?.lua;XIUI/?/init.lua;';
local SOUND_MODULE = 'modules.readycheck.sound';

package.path = LUA_ROOT .. package.path;

local nativeFfi = require('ffi');

local function fail(message)
    error(message, 2);
end

local function expect_equal(actual, expected, message)
    if actual ~= expected then
        fail(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)));
    end
end

local function expect_sequence(actual, expected, message)
    expect_equal(#actual, #expected, message .. ' length');
    for index, expected_event in ipairs(expected) do
        expect_equal(actual[index], expected_event, message .. ' at event ' .. index);
    end
end

local function write_u16(value)
    return string.char(value % 256, math.floor(value / 256) % 256);
end

local function write_u32(value)
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    );
end

local function write_pcm_wav(path)
    local pcm = write_u16(1000) .. write_u16(64536);
    local fmt = write_u16(1) .. write_u16(1) .. write_u32(8000) .. write_u32(16000) .. write_u16(2) .. write_u16(16);
    local wav = 'RIFF' .. write_u32(36 + #pcm) .. 'WAVE' .. 'fmt ' .. write_u32(#fmt) .. fmt .. 'data' .. write_u32(#pcm) .. pcm;
    local file = assert(io.open(path, 'wb'));
    file:write(wav);
    file:close();
end

local function create_winmm(options, calls, missing_symbol)
    local library = {};
    local functions = {
        waveOutOpen = function(hwo)
            table.insert(calls.events, 'open');
            calls.open = calls.open + 1;
            if options.open_result == 0 then
                hwo[0] = nativeFfi.cast('void*', 1);
            end
            return options.open_result;
        end,
        waveOutPrepareHeader = function()
            table.insert(calls.events, 'prepare');
            calls.prepare = calls.prepare + 1;
            return options.prepare_result;
        end,
        waveOutWrite = function()
            table.insert(calls.events, 'write');
            calls.write = calls.write + 1;
            return options.write_result;
        end,
        waveOutUnprepareHeader = function()
            table.insert(calls.events, 'unprepare');
            calls.unprepare = calls.unprepare + 1;
            return 0;
        end,
        waveOutReset = function()
            table.insert(calls.events, 'reset');
            calls.reset = calls.reset + 1;
            return 0;
        end,
        waveOutClose = function()
            table.insert(calls.events, 'close');
            calls.close = calls.close + 1;
            return 0;
        end,
    };

    for name, fn in pairs(functions) do
        if name ~= missing_symbol then
            library[name] = fn;
        end
    end

    if missing_symbol then
        setmetatable(library, {
            __index = function(_, name)
                if name == missing_symbol then
                    error('missing WinMM symbol: ' .. name, 2);
                end
            end,
        });
    end

    return library;
end

local function load_sound(options)
    local calls = {
        load = 0,
        events = {},
        fallback = 0,
        open = 0,
        prepare = 0,
        write = 0,
        unprepare = 0,
        reset = 0,
        close = 0,
    };
    local ffi = {
        cdef = nativeFfi.cdef,
        new = nativeFfi.new,
        sizeof = nativeFfi.sizeof,
        load = function()
            table.insert(calls.events, 'load');
            calls.load = calls.load + 1;
            if options.load_fails or options.load_fails_on == calls.load then
                error('winmm unavailable');
            end

            local missing_symbol = options.missing_symbol;
            if options.missing_symbol_on_load and options.missing_symbol_on_load ~= calls.load then
                missing_symbol = nil;
            end
            return create_winmm(options, calls, missing_symbol);
        end,
    };

    package.loaded[SOUND_MODULE] = nil;
    package.loaded.ffi = ffi;
    _G.ashita = {
        misc = {
            play_sound = function()
                table.insert(calls.events, 'fallback');
                calls.fallback = calls.fallback + 1;
            end,
        },
    };

    local ok, sound = pcall(require, SOUND_MODULE);
    package.loaded.ffi = nativeFfi;
    if not ok then
        error(sound, 0);
    end

    return sound, calls;
end

local function with_sound(options, run)
    local sound, calls = load_sound(options);
    run(sound, calls);
    package.loaded[SOUND_MODULE] = nil;
end

local temporary_wav = os.tmpname();
write_pcm_wav(temporary_wav);

local tests = {
    {
        name = 'requiring the module does not load unavailable WinMM',
        run = function()
            with_sound({ load_fails = true }, function(_, calls)
                expect_equal(calls.load, 0, 'require should not load WinMM');
            end);
        end,
    },
    {
        name = 'zero volume does not load WinMM or play audio',
        run = function()
            with_sound({ load_fails = true }, function(sound, calls)
                sound.Play(temporary_wav, 0);
                expect_equal(calls.load, 0, 'zero volume should not load WinMM');
                expect_equal(calls.fallback, 0, 'zero volume should not play audio');
            end);
        end,
    },
    {
        name = 'full volume uses Ashita without loading WinMM',
        run = function()
            with_sound({ load_fails = true }, function(sound, calls)
                sound.Play(temporary_wav, 100);
                expect_equal(calls.load, 0, 'full volume should not load WinMM');
                expect_equal(calls.fallback, 1, 'full volume should use Ashita playback');
            end);
        end,
    },
    {
        name = 'scaled playback falls back when WinMM cannot load',
        run = function()
            with_sound({ load_fails = true }, function(sound, calls)
                sound.Play(temporary_wav, 50);
                expect_equal(calls.load, 1, 'scaled playback should load WinMM once');
                expect_equal(calls.fallback, 1, 'unavailable WinMM should use Ashita playback');
            end);
        end,
    },
    {
        name = 'scaled playback stops active output before WinMM acquisition fails',
        run = function()
            local acquisition_failures = {
                { load_fails_on = 2 },
                { missing_symbol = 'waveOutWrite', missing_symbol_on_load = 2 },
            };

            for _, failure in ipairs(acquisition_failures) do
                failure.open_result = 0;
                failure.prepare_result = 0;
                failure.write_result = 0;
                with_sound(failure, function(sound, calls)
                    sound.Play(temporary_wav, 50);
                    sound.Play(temporary_wav, 50);
                    expect_equal(calls.load, 2, 'second scaled playback should acquire WinMM');
                    expect_equal(calls.reset, 1, 'failed acquisition should reset active playback');
                    expect_equal(calls.unprepare, 1, 'failed acquisition should unprepare active playback');
                    expect_equal(calls.close, 1, 'failed acquisition should close active playback');
                    expect_equal(calls.fallback, 1, 'failed acquisition should use Ashita playback');
                    expect_sequence(calls.events, {
                        'load', 'open', 'prepare', 'write',
                        'reset', 'unprepare', 'close', 'load', 'fallback',
                    }, 'failed acquisition lifecycle');
                end);
            end
        end,
    },
    {
        name = 'scaled playback falls back when a WinMM symbol is unavailable',
        run = function()
            with_sound({ missing_symbol = 'waveOutWrite', open_result = 0, prepare_result = 0, write_result = 0 }, function(sound, calls)
                sound.Play(temporary_wav, 50);
                expect_equal(calls.load, 1, 'scaled playback should load WinMM once');
                expect_equal(calls.open, 0, 'symbol validation should happen before native calls');
                expect_equal(calls.fallback, 1, 'missing WinMM symbol should use Ashita playback');
            end);
        end,
    },
    {
        name = 'scaled playback falls back after waveOutOpen fails',
        run = function()
            with_sound({ open_result = 1, prepare_result = 0, write_result = 0 }, function(sound, calls)
                sound.Play(temporary_wav, 50);
                expect_equal(calls.open, 1, 'scaled playback should attempt waveOutOpen');
                expect_equal(calls.prepare, 0, 'failed open should not prepare a header');
                expect_equal(calls.close, 0, 'failed open should not close an unopened device');
                expect_equal(calls.fallback, 1, 'failed open should use Ashita playback');
            end);
        end,
    },
    {
        name = 'scaled playback closes after waveOutPrepareHeader fails',
        run = function()
            with_sound({ open_result = 0, prepare_result = 1, write_result = 0 }, function(sound, calls)
                sound.Play(temporary_wav, 50);
                expect_equal(calls.prepare, 1, 'scaled playback should prepare a header');
                expect_equal(calls.unprepare, 0, 'failed prepare should not unprepare a header');
                expect_equal(calls.close, 1, 'failed prepare should close the device');
                expect_equal(calls.fallback, 1, 'failed prepare should use Ashita playback');
            end);
        end,
    },
    {
        name = 'scaled playback cleans up and falls back after waveOutWrite fails',
        run = function()
            with_sound({ open_result = 0, prepare_result = 0, write_result = 1 }, function(sound, calls)
                sound.Play(temporary_wav, 50);
                expect_equal(calls.write, 1, 'scaled playback should write the header');
                expect_equal(calls.unprepare, 1, 'failed write should unprepare the header');
                expect_equal(calls.close, 1, 'failed write should close the device');
                expect_equal(calls.fallback, 1, 'failed write should use Ashita playback');
                expect_sequence(calls.events, {
                    'load', 'open', 'prepare', 'write', 'unprepare', 'close', 'fallback',
                }, 'failed write lifecycle');
            end);
        end,
    },
    {
        name = 'scaled playback writes through WinMM without Ashita fallback',
        run = function()
            with_sound({ open_result = 0, prepare_result = 0, write_result = 0 }, function(sound, calls)
                sound.Play(temporary_wav, 150);
                expect_equal(calls.load, 1, 'scaled playback should load WinMM once');
                expect_equal(calls.open, 1, 'scaled playback should open a device');
                expect_equal(calls.prepare, 1, 'scaled playback should prepare a header');
                expect_equal(calls.write, 1, 'scaled playback should write a header');
                expect_equal(calls.fallback, 0, 'successful scaled write should not use Ashita playback');
            end);
        end,
    },
};

local failed = 0;
for _, test in ipairs(tests) do
    local ok, err = xpcall(test.run, debug.traceback);
    if ok then
        io.write('PASS ', test.name, '\n');
    else
        failed = failed + 1;
        io.stderr:write('FAIL ', test.name, '\n', err, '\n');
    end
end

os.remove(temporary_wav);

if failed ~= 0 then
    error(string.format('%d test(s) failed', failed));
end

io.write(string.format('%d Ready Check audio tests passed\n', #tests));
