--[[
	Credit: Copyright (c) 2019 RexmecK
	Repository: https://github.com/RexmecK/Lua-Bitmap
]]--
local function newData()
	local data = {}
	data.bytes = ""

	function data:append(n, byteSize)
		if not byteSize then byteSize = 1 end

		local bytes = ""
		local h = string.format("%0"..(byteSize*2).."X", n)
		for i=1,byteSize or 1 do 
			local id = (i-1)*2
			bytes = string.char(
				tonumber(
					h:sub(id+1, id+2) , 16
				)
			)..bytes
		end
		self.bytes = self.bytes..bytes
	end

	function data:appendBytes(...)
		local b = ""
		local ar = {...}
		for i=1,#ar do 
			b = b..string.char(ar[i])
		end
		self.bytes = self.bytes..b
	end

	function data:appendBegin(n, byteSize)
		if not byteSize then byteSize = 1 end
		local bytes = ""
		local h = string.format("%0"..(byteSize*2).."X", n)
		for i=1,byteSize or 1 do 
			local id = (i-1)*2
			bytes = string.char(
				tonumber(
					h:sub(id+1, id+2) , 16
				)
			)..bytes
		end
		self.bytes = bytes..self.bytes
	end

	function data:size()
		return self.bytes:len()
	end

	return data
end

bitmap = {}
bitmap.size = {0,0}
bitmap.map = {}

function bitmap:new(x,y)
	local newbitmap = {}
	for i,v in pairs(self) do
		newbitmap[i] = v
	end
	newbitmap.size = {x,y}

	for sx=1,x do
		newbitmap.map[sx] = {}
		for sy=1,y do
			newbitmap.map[sx][sy] = {0,0,0,0}
		end
	end
	return newbitmap
end

function bitmap:setPixelColor(x,y,color)
	if not self.map[x] or not self.map[x][y] then error("Out of bounds ("..x..", "..y..")".." with size: ("..self.size[1]..", "..self.size[2]..")") end
	self.map[x][y] = color
end

function bitmap:getPixelColor(x,y,color)
	if not self.map[x] or not self.map[x][y] then error("Out of bounds ("..x..", "..y..")".." with size: ("..self.size[1]..", "..self.size[2]..")") end
	return self.map[x][y]
end

--makes a bitmap binary file
function bitmap:binary()
	local PixelData = {}
	for y=1,self.size[2] do
		for x=1,self.size[1] do
			local color = self.map[x][y]
			PixelData[#PixelData+1] = string.char(math.min(math.max(color[3], 0), 255))		--	b
			PixelData[#PixelData+1] = string.char(math.min(math.max(color[2], 0), 255))		--	g
			PixelData[#PixelData+1] = string.char(math.min(math.max(color[1], 0), 255))		--	r
			PixelData[#PixelData+1] = string.char(math.min(math.max(color[4], 0), 255))		--	a
		end
	end
	
	local InfoHeaderData = newData()
	InfoHeaderData:append(self.size[1],4)					--	Horizontal width of bitmap in pixels
	InfoHeaderData:append(self.size[2],4)					--	Vertical height of bitmap in pixels
	InfoHeaderData:append(1,2)								--	Number of color planes being used
	InfoHeaderData:append(32,2)								--	Number of bits per pixel
	InfoHeaderData:append(3,4)								--	BI_BITFIELDS, no pixel array compression used
	InfoHeaderData:append(32,4)								--	Size of the raw bitmap data (including padding)
	InfoHeaderData:append(2835,4)							--	horizontal resolution: Pixels/meter
	InfoHeaderData:append(2835,4)							--	vertical resolution: Pixels/meter
	InfoHeaderData:append(0,4)								--	Number of colors in the palette
	InfoHeaderData:append(0,4)								--	0 = all
	InfoHeaderData:appendBytes(0,0,255,0)					--	Red channel bit mask (valid because BI_BITFIELDS is specified)
	InfoHeaderData:appendBytes(0,255,0,0)					--	Red channel bit mask (valid because BI_BITFIELDS is specified)
	InfoHeaderData:appendBytes(255,0,0,0)					--	Red channel bit mask (valid because BI_BITFIELDS is specified)
	InfoHeaderData:appendBytes(0,0,0,255)					--	Red channel bit mask (valid because BI_BITFIELDS is specified)
	InfoHeaderData:appendBytes(32,110,105,87)				--	LCS_WINDOWS_COLOR_SPACE
	InfoHeaderData:append(0,36)								--	CIEXYZTRIPLE Color Space endpoints	
	InfoHeaderData:append(0,4)								--	0 Red Gamma
	InfoHeaderData:append(0,4)								--	0 Green Gamma
	InfoHeaderData:append(0,4)								--	0 Blue Gamma
	InfoHeaderData:appendBegin(InfoHeaderData:size()+4,4)	--	Size of InfoHeader

	local HeaderData = newData()
	HeaderData:appendBytes(string.byte("B"), string.byte("M"))				--	signature
	HeaderData:append(InfoHeaderData:size() + #PixelData + 14,4)			--	File size in bytes
	HeaderData:append(0,2)													--	unused
	HeaderData:append(0,2)													--	unused
	HeaderData:append(HeaderData:size() + InfoHeaderData:size() + 4,4)		--	Pixel data file address

	return HeaderData.bytes..InfoHeaderData.bytes..table.concat(PixelData)
end

function bitmap:save(at)
	local binaryData = self:binary()
	local file = io.open(at, "wb")
	if file then
		file:write(binaryData)
		return file:close()
	end
	return false
end