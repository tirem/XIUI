local ORIGINAL_PACKAGE_PATH = package.path;
package.path = 'tests/startup/?.lua;tests/startup/?/init.lua;XIUI/?.lua;XIUI/?/init.lua;' .. package.path;

local host = require('support.host');

local function expect_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)), 2);
    end
end

local function expect_type(actual, expected, message)
    expect_equal(type(actual), expected, message);
end

local function expect_contains(actual, expected, message)
    if tostring(actual):find(expected, 1, true) == nil then
        error(string.format('%s: expected %s to contain %s', message, tostring(actual), expected), 2);
    end
end

local function expect_sequence(actual, expected, message)
    expect_equal(#actual, #expected, message .. ' length');
    for index, expected_value in ipairs(expected) do
        expect_equal(actual[index], expected_value, message .. ' at index ' .. index);
    end
end

local tests = {
    {
        name = 'unknown filesystem reads stay inside the virtual host',
        run = function()
            host.with_environment({ winmm_available = false }, function()
                local file = io.open('tests/startup/support/fake_clock.lua', 'r');
                if file ~= nil then
                    file:close();
                end
                expect_equal(file, nil, 'unknown io.open read');

                local chunk = loadfile('tests/startup/support/fake_clock.lua');
                expect_equal(chunk, nil, 'unknown loadfile read');

                local traversal_chunk = loadfile('XIUI/../tests/startup/support/fake_clock.lua');
                expect_equal(traversal_chunk, nil, 'traversal loadfile read');

                local ok = pcall(dofile, 'tests/startup/support/fake_clock.lua');
                expect_equal(ok, false, 'unknown dofile read');
            end);
        end,
    },
    {
        name = 'neutral host rejects unrecognized native signatures',
        run = function()
            host.with_environment({ winmm_available = false }, function()
                expect_equal(
                    ashita.memory.find('unexpected.dll', 0, '00', 0, 0),
                    0,
                    'unrecognized native signature'
                );
            end);
        end,
    },
    {
        name = 'neutral ImGui constants preserve None semantics',
        run = function()
            host.with_environment({ winmm_available = false }, function()
                expect_equal(ImGuiChildFlags_None, 0, 'ImGui child None flag');
                expect_equal(ImDrawCornerFlags_None, 0, 'ImGui corner None flag');
            end);
        end,
    },
    {
        name = 'real addon graph registers the load callback',
        run = function()
            host.with_environment({ winmm_available = false }, function(environment)
                environment.load_addon();
                expect_type(environment.get_event('load', 'load_cb'), 'function', 'registered load callback');
            end);
        end,
    },
    {
        name = 'registered load callback completes without a live game host',
        run = function()
            host.with_environment({ winmm_available = false }, function(environment)
                environment.load_addon();
                local expected = environment.observe_initializers();
                environment.invoke_event('load', 'load_cb');
                expect_sequence(environment.logs.initializer_calls, expected, 'registered initializer calls');
            end);
        end,
    },
    {
        name = 'unavailable WinMM is not acquired during startup',
        run = function()
            host.with_environment({ winmm_available = false }, function(environment)
                environment.load_addon();
                environment.observe_initializers();
                environment.invoke_event('load', 'load_cb');
                expect_equal(#environment.logs.winmm_loads, 0, 'WinMM startup acquisitions');
            end);
        end,
    },
    {
        name = 'startup emits no packets or persistent writes',
        run = function()
            host.with_environment({ winmm_available = false }, function(environment)
                environment.load_addon();
                environment.observe_initializers();
                environment.invoke_event('load', 'load_cb');
                expect_sequence(environment.logs.packets, {}, 'startup packets');
                expect_sequence(environment.logs.filesystem_mutations, {}, 'startup filesystem mutations');
                expect_sequence(environment.logs.settings_saves, {}, 'startup settings saves');
            end);
        end,
    },
    {
        name = 'failing cases restore process state',
        run = function()
            local sentinel = 'xiui.startup.restore.sentinel';
            local original_global = rawget(_G, sentinel);
            local original_loaded = package.loaded[sentinel];
            local original_preload = package.preload[sentinel];
            local original_open = io.open;

            local ok, err = pcall(function()
                host.with_environment({ winmm_available = false }, function()
                    _G[sentinel] = {};
                    package.loaded[sentinel] = {};
                    package.preload[sentinel] = function()
                        return true;
                    end;
                    io.open = function()
                        return nil;
                    end;
                    error('forced startup test failure');
                end);
            end);

            expect_equal(ok, false, 'failing case result');
            expect_contains(err, 'forced startup test failure', 'failing case error');
            expect_equal(rawget(_G, sentinel), original_global, 'global restoration');
            expect_equal(package.loaded[sentinel], original_loaded, 'package.loaded restoration');
            expect_equal(package.preload[sentinel], original_preload, 'package.preload restoration');
            expect_equal(io.open, original_open, 'library function restoration');
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
        io.stderr:write('FAIL ', test.name, '\n', tostring(err), '\n');
    end
end

package.path = ORIGINAL_PACKAGE_PATH;
if failed ~= 0 then
    error(string.format('%d startup test(s) failed', failed));
end
io.write(string.format('%d startup tests passed\n', #tests));
