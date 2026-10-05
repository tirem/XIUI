local files = require('modules.mobinfo.providers.files');

return {
    Name = 'LandSandBoat',
    Url = 'https://github.com/LandSandBoat/server',
    LoadZone = function(zoneId)
        return files.LoadZone('lsb', zoneId);
    end,
};
