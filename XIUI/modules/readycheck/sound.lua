--[[
* ReadyCheck sound playback with configurable volume (0-150%).
* At 100% uses ashita.misc.play_sound (native wav volume).
* Other levels scale PCM samples via waveOut; values above 100% boost amplitude.
]]--

local bit = require('bit');
local ffi = require('ffi');

ffi.cdef[[
    typedef unsigned int UINT;
    typedef unsigned long DWORD;
    typedef unsigned short WORD;
    typedef unsigned long long DWORD_PTR;
    typedef long MMRESULT;
    typedef void* HWAVEOUT;

    typedef struct {
        WORD  wFormatTag;
        WORD  nChannels;
        DWORD nSamplesPerSec;
        DWORD nAvgBytesPerSec;
        WORD  nBlockAlign;
        WORD  wBitsPerSample;
        WORD  cbSize;
    } WAVEFORMATEX;

    typedef struct {
        char*  lpData;
        DWORD  dwBufferLength;
        DWORD  dwBytesRecorded;
        void*  dwUser;
        DWORD  dwFlags;
        DWORD  dwLoops;
        void*  lpNext;
        DWORD  reserved;
    } WAVEHDR;

    MMRESULT waveOutOpen(HWAVEOUT* phwo, UINT uDeviceID, const WAVEFORMATEX* pwfx,
        DWORD_PTR dwCallback, DWORD_PTR dwInstance, DWORD fdwOpen);
    MMRESULT waveOutPrepareHeader(HWAVEOUT hwo, WAVEHDR* pwh, UINT cbwh);
    MMRESULT waveOutWrite(HWAVEOUT hwo, WAVEHDR* pwh, UINT cbwh);
    MMRESULT waveOutUnprepareHeader(HWAVEOUT hwo, WAVEHDR* pwh, UINT cbwh);
    MMRESULT waveOutReset(HWAVEOUT hwo);
    MMRESULT waveOutClose(HWAVEOUT hwo);
]];

local winmm = ffi.load('winmm');

local WAVE_FORMAT_PCM = 1;
local WAVE_MAPPER     = 0xFFFFFFFF;
local CALLBACK_NULL   = 0;
local WHDR_DONE       = 0x00000001;

local active = nil;

local M = {};

local function cleanup_active()
    if not active then return; end

    if active.hwo ~= nil then
        winmm.waveOutReset(active.hwo);
        if active.header then
            winmm.waveOutUnprepareHeader(active.hwo, active.header, ffi.sizeof('WAVEHDR'));
        end
        winmm.waveOutClose(active.hwo);
    end

    active = nil;
end

function M.Tick()
    if not active or not active.header then return; end
    if bit.band(active.header.dwFlags, WHDR_DONE) ~= 0 then
        cleanup_active();
    end
end

local function read_u16(data, offset)
    local lo = data:byte(offset) or 0;
    local hi = data:byte(offset + 1) or 0;
    return bit.bor(lo, bit.lshift(hi, 8));
end

local function read_u32(data, offset)
    local b1 = data:byte(offset) or 0;
    local b2 = data:byte(offset + 1) or 0;
    local b3 = data:byte(offset + 2) or 0;
    local b4 = data:byte(offset + 3) or 0;
    return b1 + bit.lshift(b2, 8) + bit.lshift(b3, 16) + bit.lshift(b4, 24);
end

local function parse_wav_pcm(path)
    local f = io.open(path, 'rb');
    if not f then return nil; end
    local data = f:read('*all');
    f:close();

    if not data or #data < 44 or data:sub(1, 4) ~= 'RIFF' or data:sub(9, 12) ~= 'WAVE' then
        return nil;
    end

    local fmt = nil;
    local pcm = nil;
    local pos = 13;

    while pos + 8 <= #data do
        local chunkId = data:sub(pos, pos + 3);
        local chunkSize = read_u32(data, pos + 4);
        local chunkStart = pos + 8;

        if chunkId == 'fmt ' and chunkSize >= 16 then
            fmt = {
                wFormatTag      = read_u16(data, chunkStart),
                nChannels       = read_u16(data, chunkStart + 2),
                nSamplesPerSec  = read_u32(data, chunkStart + 4),
                nAvgBytesPerSec = read_u32(data, chunkStart + 8),
                nBlockAlign     = read_u16(data, chunkStart + 12),
                wBitsPerSample  = read_u16(data, chunkStart + 14),
            };
        elseif chunkId == 'data' then
            pcm = data:sub(chunkStart, chunkStart + chunkSize - 1);
        end

        pos = chunkStart + chunkSize + (chunkSize % 2);
    end

    if not fmt or not pcm then return nil; end
    if fmt.wFormatTag ~= WAVE_FORMAT_PCM then return nil; end
    if fmt.wBitsPerSample ~= 16 then return nil; end

    return fmt, pcm;
end

local function scale_pcm16(pcm, multiplier)
    local sampleCount = math.floor(#pcm / 2);
    local dst = ffi.new('char[?]', #pcm);

    for i = 0, sampleCount - 1 do
        local offset = i * 2 + 1;
        local lo = pcm:byte(offset) or 0;
        local hi = pcm:byte(offset + 1) or 0;
        local sample = bit.bor(lo, bit.lshift(hi, 8));
        if sample >= 32768 then
            sample = sample - 65536;
        end

        sample = math.floor(sample * multiplier + (sample >= 0 and 0.5 or -0.5));
        if sample > 32767 then
            sample = 32767;
        elseif sample < -32768 then
            sample = -32768;
        end

        local unsigned = sample >= 0 and sample or (sample + 65536);
        dst[i * 2]     = bit.band(unsigned, 0xFF);
        dst[i * 2 + 1] = bit.band(bit.rshift(unsigned, 8), 0xFF);
    end

    return dst, #pcm;
end

local function play_scaled(path, volumePercent)
    local fmt, pcm = parse_wav_pcm(path);
    if not fmt or not pcm then
        ashita.misc.play_sound(path);
        return;
    end

    cleanup_active();

    local multiplier = volumePercent / 100;
    local buffer, length = scale_pcm16(pcm, multiplier);

    local wfx = ffi.new('WAVEFORMATEX');
    wfx.wFormatTag      = fmt.wFormatTag;
    wfx.nChannels       = fmt.nChannels;
    wfx.nSamplesPerSec  = fmt.nSamplesPerSec;
    wfx.nAvgBytesPerSec = fmt.nAvgBytesPerSec;
    wfx.nBlockAlign     = fmt.nBlockAlign;
    wfx.wBitsPerSample  = fmt.wBitsPerSample;
    wfx.cbSize          = 0;

    local hwo = ffi.new('HWAVEOUT[1]');
    local result = winmm.waveOutOpen(hwo, WAVE_MAPPER, wfx, 0, 0, CALLBACK_NULL);
    if result ~= 0 then
        ashita.misc.play_sound(path);
        return;
    end

    local header = ffi.new('WAVEHDR');
    header.lpData         = buffer;
    header.dwBufferLength = length;
    header.dwFlags        = 0;
    header.dwLoops        = 0;

    result = winmm.waveOutPrepareHeader(hwo[0], header, ffi.sizeof('WAVEHDR'));
    if result ~= 0 then
        winmm.waveOutClose(hwo[0]);
        ashita.misc.play_sound(path);
        return;
    end

    result = winmm.waveOutWrite(hwo[0], header, ffi.sizeof('WAVEHDR'));
    if result ~= 0 then
        winmm.waveOutUnprepareHeader(hwo[0], header, ffi.sizeof('WAVEHDR'));
        winmm.waveOutClose(hwo[0]);
        ashita.misc.play_sound(path);
        return;
    end

    active = {
        hwo    = hwo[0],
        header = header,
        buffer = buffer,
    };
end

function M.Play(path, volumePercent)
    volumePercent = tonumber(volumePercent) or 100;
    if volumePercent <= 0 then
        return;
    end
    if volumePercent == 100 then
        cleanup_active();
        ashita.misc.play_sound(path);
        return;
    end
    play_scaled(path, volumePercent);
end

return M;
