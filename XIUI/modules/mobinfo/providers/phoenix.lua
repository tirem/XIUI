local files = require('modules.mobinfo.providers.files');

return {
    Name = 'Phoenix',
    Url = 'https://github.com/phoenixffxi/Phoenix/tree/live',
    LoadZone = function(zoneId)
        return files.LoadZone('phoenix', zoneId);
    end,
};
