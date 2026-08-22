local source_path = debug.getinfo(1, 'S').source:sub(2);
local repository_root = source_path:match('^(.*)[/\\]tests[/\\]run%.lua$') or '.';

package.path = table.concat({
    repository_root .. '/tests/?.lua',
    repository_root .. '/tests/?/init.lua',
    repository_root .. '/XIUI/?.lua',
    repository_root .. '/XIUI/?/init.lua',
    package.path,
}, ';');

local suites = {
    require('startup_test'),
};

local failures = 0;
local tests_run = 0;

for _, suite in ipairs(suites) do
    for _, test_case in ipairs(suite) do
        tests_run = tests_run + 1;
        local ok, result = xpcall(test_case.run, debug.traceback);
        if ok then
            print('PASS ' .. test_case.name);
        else
            failures = failures + 1;
            io.stderr:write('FAIL ' .. test_case.name .. '\n' .. result .. '\n');
        end
    end
end

if failures > 0 then
    io.stderr:write(string.format('%d of %d tests failed.\n', failures, tests_run));
    os.exit(1);
end

print(string.format('%d tests passed.', tests_run));
