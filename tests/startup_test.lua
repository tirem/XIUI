local fake_ashita = require('support.fake_ashita');

return {
    {
        name = 'normal module graph loads without FFXI',
        run = function()
            fake_ashita.install();
            local modules = require('modules.init');
            assert(type(modules) == 'table', 'modules.init did not return the module registry');
        end,
    },
};
