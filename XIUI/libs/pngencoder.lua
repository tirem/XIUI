--[[
    Pure Lua PNG Encoder

    Encodes 32-bit RGBA images to PNG format.
    Designed for small images (32x32) with uncompressed deflate for simplicity.

    References:
    - PNG Specification: https://www.libpng.org/pub/png/spec/1.2/PNG-Chunks.html
    - DEFLATE (RFC 1951): https://www.w3.org/Graphics/PNG/RFC-1951
    - ZLIB (RFC 1950): https://datatracker.ietf.org/doc/html/rfc1950
]]

local pngencoder = {};

-- PNG signature (8 bytes)
local PNG_SIGNATURE = string.char(137, 80, 78, 71, 13, 10, 26, 10);

-- CRC32 lookup table (polynomial 0xEDB88320, reflected)
local crc32_table = nil;

---Build the CRC32 lookup table
local function build_crc32_table()
    if crc32_table then return end

    crc32_table = {};
    for i = 0, 255 do
        local crc = i;
        for _ = 1, 8 do
            if crc % 2 == 1 then
                crc = bit.bxor(bit.rshift(crc, 1), 0xEDB88320);
            else
                crc = bit.rshift(crc, 1);
            end
        end
        crc32_table[i] = crc;
    end
end

---Calculate CRC32 of a string
---@param data string The data to calculate CRC32 for
---@return number The CRC32 value
local function crc32(data)
    build_crc32_table();

    local crc = 0xFFFFFFFF;
    for i = 1, #data do
        local byte = string.byte(data, i);
        local index = bit.band(bit.bxor(crc, byte), 0xFF);
        crc = bit.bxor(bit.rshift(crc, 8), crc32_table[index]);
    end

    return bit.bxor(crc, 0xFFFFFFFF);
end

---Calculate Adler-32 checksum
---@param data string The data to checksum
---@return number The Adler-32 value
local function adler32(data)
    local s1 = 1;
    local s2 = 0;
    local MOD_ADLER = 65521;

    for i = 1, #data do
        s1 = (s1 + string.byte(data, i)) % MOD_ADLER;
        s2 = (s2 + s1) % MOD_ADLER;
    end

    return s2 * 65536 + s1;
end

---Write a 32-bit big-endian integer to string
---@param value number The value to write
---@return string 4-byte big-endian representation
local function write_uint32_be(value)
    -- Handle negative values from bit operations
    if value < 0 then
        value = value + 0x100000000;
    end
    return string.char(
        bit.band(bit.rshift(value, 24), 0xFF),
        bit.band(bit.rshift(value, 16), 0xFF),
        bit.band(bit.rshift(value, 8), 0xFF),
        bit.band(value, 0xFF)
    );
end

---Write a 16-bit little-endian integer to string
---@param value number The value to write
---@return string 2-byte little-endian representation
local function write_uint16_le(value)
    return string.char(
        bit.band(value, 0xFF),
        bit.band(bit.rshift(value, 8), 0xFF)
    );
end

---Create a PNG chunk
---@param chunk_type string 4-character chunk type
---@param data string Chunk data
---@return string The complete chunk with length, type, data, and CRC
local function create_chunk(chunk_type, data)
    local length = write_uint32_be(#data);
    local crc_data = chunk_type .. data;
    local crc_value = crc32(crc_data);
    local crc_bytes = write_uint32_be(crc_value);

    return length .. chunk_type .. data .. crc_bytes;
end

---Create IHDR chunk data
---@param width number Image width
---@param height number Image height
---@return string IHDR chunk data
local function create_ihdr(width, height)
    return write_uint32_be(width) ..     -- Width
           write_uint32_be(height) ..    -- Height
           string.char(8) ..             -- Bit depth: 8 bits per channel
           string.char(6) ..             -- Color type: 6 = RGBA
           string.char(0) ..             -- Compression method: 0 = deflate
           string.char(0) ..             -- Filter method: 0
           string.char(0);               -- Interlace method: 0 = none
end

---Create uncompressed deflate blocks from data
---Splits data into 65535-byte blocks as needed
---@param data string The raw data to wrap
---@return string Deflate blocks
local function create_deflate_blocks(data)
    local result = {};
    local data_len = #data;
    local offset = 1;
    local MAX_BLOCK_SIZE = 65535;

    while offset <= data_len do
        local remaining = data_len - offset + 1;
        local block_size = math.min(remaining, MAX_BLOCK_SIZE);
        local is_final = (offset + block_size > data_len);

        -- Block header byte:
        -- Bit 0: BFINAL (1 if last block)
        -- Bits 1-2: BTYPE (00 for uncompressed)
        -- Remaining bits: padding to byte boundary (all 0)
        local header = is_final and 0x01 or 0x00;

        -- LEN: block size (16-bit little-endian)
        local len = write_uint16_le(block_size);
        -- NLEN: one's complement of LEN
        local nlen = write_uint16_le(bit.bxor(block_size, 0xFFFF));

        -- Block data
        local block_data = string.sub(data, offset, offset + block_size - 1);

        table.insert(result, string.char(header) .. len .. nlen .. block_data);
        offset = offset + block_size;
    end

    return table.concat(result);
end

---Create zlib-wrapped deflate data
---@param data string The raw data to compress
---@return string Zlib-wrapped data
local function create_zlib_data(data)
    -- CMF byte: CM=8 (deflate), CINFO=7 (32K window)
    local cmf = 0x78;  -- 0111 1000 = CINFO=7, CM=8

    -- FLG byte: No dict, default compression
    -- FCHECK must make (CMF*256 + FLG) divisible by 31
    local flg = 0x01;  -- Start with minimal flags
    local check = (cmf * 256 + flg) % 31;
    if check ~= 0 then
        flg = flg + (31 - check);
    end

    -- Create deflate blocks (uncompressed)
    local deflate_data = create_deflate_blocks(data);

    -- Adler-32 checksum of uncompressed data (big-endian)
    local adler = adler32(data);
    local adler_bytes = write_uint32_be(adler);

    return string.char(cmf, flg) .. deflate_data .. adler_bytes;
end

---Convert ARGB pixel data to filtered PNG scanlines
---@param width number Image width
---@param height number Image height
---@param pixels table Array of ARGB uint32 values, indexed as pixels[y * width + x + 1] (1-based)
---@return string Filtered scanline data ready for compression
local function create_scanlines(width, height, pixels)
    local lines = {};

    for y = 0, height - 1 do
        -- Filter type byte (0 = None)
        local line = { string.char(0) };

        for x = 0, width - 1 do
            local pixel = pixels[y * width + x + 1] or 0;

            -- Convert ARGB to RGBA
            -- ARGB: 0xAARRGGBB
            local a = bit.band(bit.rshift(pixel, 24), 0xFF);
            local r = bit.band(bit.rshift(pixel, 16), 0xFF);
            local g = bit.band(bit.rshift(pixel, 8), 0xFF);
            local b = bit.band(pixel, 0xFF);

            table.insert(line, string.char(r, g, b, a));
        end

        table.insert(lines, table.concat(line));
    end

    return table.concat(lines);
end

---Encode a 32-bit RGBA image as PNG
---@param width number Image width in pixels
---@param height number Image height in pixels
---@param pixels table Array of ARGB uint32 values. Indexed as pixels[y * width + x + 1] (1-based Lua indexing). Each value is 0xAARRGGBB format.
---@return string PNG file data that can be written with io.open(path, 'wb')
function pngencoder.EncodePNG(width, height, pixels)
    -- Create filtered scanlines (raw pixel data with filter bytes)
    local scanlines = create_scanlines(width, height, pixels);

    -- Wrap in zlib format
    local compressed = create_zlib_data(scanlines);

    -- Build PNG file
    local chunks = {
        PNG_SIGNATURE,
        create_chunk('IHDR', create_ihdr(width, height)),
        create_chunk('IDAT', compressed),
        create_chunk('IEND', ''),
    };

    return table.concat(chunks);
end

---Encode and save a PNG file
---@param path string File path to save to
---@param width number Image width in pixels
---@param height number Image height in pixels
---@param pixels table Array of ARGB uint32 values
---@return boolean success True if file was saved successfully
---@return string? error Error message if failed
function pngencoder.SavePNG(path, width, height, pixels)
    local png_data = pngencoder.EncodePNG(width, height, pixels);

    local file, err = io.open(path, 'wb');
    if not file then
        return false, 'Failed to open file: ' .. tostring(err);
    end

    local ok, write_err = file:write(png_data);
    file:close();

    if not ok then
        return false, 'Failed to write file: ' .. tostring(write_err);
    end

    return true;
end

---Encode from raw RGBA byte string (alternative input format)
---@param width number Image width in pixels
---@param height number Image height in pixels
---@param rgba_bytes string Raw RGBA bytes (4 bytes per pixel, row-major order)
---@return string PNG file data
function pngencoder.EncodePNGFromRGBA(width, height, rgba_bytes)
    local lines = {};
    local bytes_per_row = width * 4;

    for y = 0, height - 1 do
        -- Filter type byte (0 = None)
        local row_start = y * bytes_per_row + 1;
        local row_data = string.sub(rgba_bytes, row_start, row_start + bytes_per_row - 1);
        table.insert(lines, string.char(0) .. row_data);
    end

    local scanlines = table.concat(lines);
    local compressed = create_zlib_data(scanlines);

    local chunks = {
        PNG_SIGNATURE,
        create_chunk('IHDR', create_ihdr(width, height)),
        create_chunk('IDAT', compressed),
        create_chunk('IEND', ''),
    };

    return table.concat(chunks);
end

---Encode from FFI pointer to ARGB data (for D3D texture data)
---@param width number Image width in pixels
---@param height number Image height in pixels
---@param argb_ptr userdata FFI pointer to uint32_t ARGB pixel data
---@param pitch number? Row pitch in bytes (default: width * 4)
---@return string PNG file data
function pngencoder.EncodePNGFromARGBPtr(width, height, argb_ptr, pitch)
    pitch = pitch or (width * 4);
    local pixels_per_row = pitch / 4;

    local lines = {};

    for y = 0, height - 1 do
        -- Filter type byte (0 = None)
        local line = { string.char(0) };

        for x = 0, width - 1 do
            local pixel = argb_ptr[y * pixels_per_row + x];

            -- Convert ARGB (0xAARRGGBB) to RGBA bytes
            local a = bit.band(bit.rshift(pixel, 24), 0xFF);
            local r = bit.band(bit.rshift(pixel, 16), 0xFF);
            local g = bit.band(bit.rshift(pixel, 8), 0xFF);
            local b = bit.band(pixel, 0xFF);

            table.insert(line, string.char(r, g, b, a));
        end

        table.insert(lines, table.concat(line));
    end

    local scanlines = table.concat(lines);
    local compressed = create_zlib_data(scanlines);

    local chunks = {
        PNG_SIGNATURE,
        create_chunk('IHDR', create_ihdr(width, height)),
        create_chunk('IDAT', compressed),
        create_chunk('IEND', ''),
    };

    return table.concat(chunks);
end

---Save PNG directly from FFI pointer to ARGB data
---@param path string File path to save to
---@param width number Image width in pixels
---@param height number Image height in pixels
---@param argb_ptr userdata FFI pointer to uint32_t ARGB pixel data
---@param pitch number? Row pitch in bytes (default: width * 4)
---@return boolean success True if file was saved successfully
---@return string? error Error message if failed
function pngencoder.SavePNGFromARGBPtr(path, width, height, argb_ptr, pitch)
    local png_data = pngencoder.EncodePNGFromARGBPtr(width, height, argb_ptr, pitch);

    local file, err = io.open(path, 'wb');
    if not file then
        return false, 'Failed to open file: ' .. tostring(err);
    end

    local ok, write_err = file:write(png_data);
    file:close();

    if not ok then
        return false, 'Failed to write file: ' .. tostring(write_err);
    end

    return true;
end

---Bilinear interpolation helper
---@param c00 number Top-left pixel value (0-255)
---@param c10 number Top-right pixel value (0-255)
---@param c01 number Bottom-left pixel value (0-255)
---@param c11 number Bottom-right pixel value (0-255)
---@param tx number X interpolation factor (0-1)
---@param ty number Y interpolation factor (0-1)
---@return number Interpolated value (0-255)
local function bilinear_interp(c00, c10, c01, c11, tx, ty)
    local a = c00 * (1 - tx) + c10 * tx;
    local b = c01 * (1 - tx) + c11 * tx;
    return math.floor(a * (1 - ty) + b * ty + 0.5);
end

---Bilinear upscale ARGB pixel data
---@param src_ptr userdata FFI pointer to source ARGB pixels
---@param src_width number Source width
---@param src_height number Source height
---@param src_pitch number Source pitch in bytes
---@param dst_width number Destination width
---@param dst_height number Destination height
---@return table Array of ARGB uint32 values for destination (1-based indexing)
local function bilinear_upscale(src_ptr, src_width, src_height, src_pitch, dst_width, dst_height)
    local src_pixels_per_row = src_pitch / 4;
    local dst_pixels = {};

    local x_ratio = (src_width - 1) / (dst_width - 1);
    local y_ratio = (src_height - 1) / (dst_height - 1);

    for dst_y = 0, dst_height - 1 do
        local src_y_f = dst_y * y_ratio;
        local src_y0 = math.floor(src_y_f);
        local src_y1 = math.min(src_y0 + 1, src_height - 1);
        local ty = src_y_f - src_y0;

        for dst_x = 0, dst_width - 1 do
            local src_x_f = dst_x * x_ratio;
            local src_x0 = math.floor(src_x_f);
            local src_x1 = math.min(src_x0 + 1, src_width - 1);
            local tx = src_x_f - src_x0;

            -- Get 4 source pixels
            local p00 = src_ptr[src_y0 * src_pixels_per_row + src_x0];
            local p10 = src_ptr[src_y0 * src_pixels_per_row + src_x1];
            local p01 = src_ptr[src_y1 * src_pixels_per_row + src_x0];
            local p11 = src_ptr[src_y1 * src_pixels_per_row + src_x1];

            -- Extract ARGB channels from each pixel
            local a00 = bit.band(bit.rshift(p00, 24), 0xFF);
            local r00 = bit.band(bit.rshift(p00, 16), 0xFF);
            local g00 = bit.band(bit.rshift(p00, 8), 0xFF);
            local b00 = bit.band(p00, 0xFF);

            local a10 = bit.band(bit.rshift(p10, 24), 0xFF);
            local r10 = bit.band(bit.rshift(p10, 16), 0xFF);
            local g10 = bit.band(bit.rshift(p10, 8), 0xFF);
            local b10 = bit.band(p10, 0xFF);

            local a01 = bit.band(bit.rshift(p01, 24), 0xFF);
            local r01 = bit.band(bit.rshift(p01, 16), 0xFF);
            local g01 = bit.band(bit.rshift(p01, 8), 0xFF);
            local b01 = bit.band(p01, 0xFF);

            local a11 = bit.band(bit.rshift(p11, 24), 0xFF);
            local r11 = bit.band(bit.rshift(p11, 16), 0xFF);
            local g11 = bit.band(bit.rshift(p11, 8), 0xFF);
            local b11 = bit.band(p11, 0xFF);

            -- Bilinear interpolate each channel
            local a = bilinear_interp(a00, a10, a01, a11, tx, ty);
            local r = bilinear_interp(r00, r10, r01, r11, tx, ty);
            local g = bilinear_interp(g00, g10, g01, g11, tx, ty);
            local b = bilinear_interp(b00, b10, b01, b11, tx, ty);

            -- Combine back to ARGB
            local dst_pixel = bit.bor(
                bit.lshift(a, 24),
                bit.lshift(r, 16),
                bit.lshift(g, 8),
                b
            );

            dst_pixels[dst_y * dst_width + dst_x + 1] = dst_pixel;
        end
    end

    return dst_pixels;
end

---Encode from D3D8 locked rect data (D3DLOCKED_RECT structure)
---This is the most common use case for extracting textures from FFXI
---@param width number Image width in pixels
---@param height number Image height in pixels
---@param pBits userdata Pointer to the locked bits (from D3DLOCKED_RECT.pBits)
---@param pitch number Row pitch in bytes (from D3DLOCKED_RECT.Pitch)
---@return string PNG file data
function pngencoder.EncodePNGFromLockedRect(width, height, pBits, pitch)
    local ffi = require('ffi');
    -- Cast pBits to uint32_t pointer for ARGB access
    local argb_ptr = ffi.cast('uint32_t*', pBits);
    return pngencoder.EncodePNGFromARGBPtr(width, height, argb_ptr, pitch);
end

---Encode from D3D8 locked rect with bilinear upscaling
---@param src_width number Source image width
---@param src_height number Source image height
---@param pBits userdata Pointer to the locked bits
---@param pitch number Row pitch in bytes
---@param dst_width number Destination width (upscaled)
---@param dst_height number Destination height (upscaled)
---@return string PNG file data
function pngencoder.EncodePNGFromLockedRectUpscaled(src_width, src_height, pBits, pitch, dst_width, dst_height)
    local ffi = require('ffi');
    local argb_ptr = ffi.cast('uint32_t*', pBits);

    -- Upscale with bilinear interpolation
    local upscaled_pixels = bilinear_upscale(argb_ptr, src_width, src_height, pitch, dst_width, dst_height);

    -- Encode the upscaled pixels
    return pngencoder.EncodePNG(dst_width, dst_height, upscaled_pixels);
end

---Save PNG from D3D8 locked rect with bilinear upscaling
---@param path string File path to save to
---@param src_width number Source image width
---@param src_height number Source image height
---@param pBits userdata Pointer to the locked bits
---@param pitch number Row pitch in bytes
---@param dst_width number Destination width (upscaled)
---@param dst_height number Destination height (upscaled)
---@return boolean success
---@return string? error
function pngencoder.SavePNGFromLockedRectUpscaled(path, src_width, src_height, pBits, pitch, dst_width, dst_height)
    local png_data = pngencoder.EncodePNGFromLockedRectUpscaled(src_width, src_height, pBits, pitch, dst_width, dst_height);

    local file, err = io.open(path, 'wb');
    if not file then
        return false, 'Failed to open file: ' .. tostring(err);
    end

    local ok, write_err = file:write(png_data);
    file:close();

    if not ok then
        return false, 'Failed to write file: ' .. tostring(write_err);
    end

    return true;
end

---Save PNG directly from D3D8 locked rect data
---@param path string File path to save to
---@param width number Image width in pixels
---@param height number Image height in pixels
---@param pBits userdata Pointer to the locked bits (from D3DLOCKED_RECT.pBits)
---@param pitch number Row pitch in bytes (from D3DLOCKED_RECT.Pitch)
---@return boolean success True if file was saved successfully
---@return string? error Error message if failed
function pngencoder.SavePNGFromLockedRect(path, width, height, pBits, pitch)
    local png_data = pngencoder.EncodePNGFromLockedRect(width, height, pBits, pitch);

    local file, err = io.open(path, 'wb');
    if not file then
        return false, 'Failed to open file: ' .. tostring(err);
    end

    local ok, write_err = file:write(png_data);
    file:close();

    if not ok then
        return false, 'Failed to write file: ' .. tostring(write_err);
    end

    return true;
end

return pngencoder;
