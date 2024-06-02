local pluginName     = select(1,...);
local componentName  = select(2,...); 
local signalTable    = select(3,...);
local my_handle      = select(4,...);

-- ==========================================
-- Struct packing/unpacking functions
-- ==========================================
local log2 = math.log(2)
local function frexp(x)
	if x == 0 then return 0.0,0.0 end
	local e = math.floor(math.log(math.abs(x)) / log2)
	if e > 0 then
		-- Why not x / 2^e? Because for large-but-still-legal values of e this
		-- ends up rounding to inf and the wheels come off.
		x = x * 2^-e
	else
		x = x / 2^e
	end
	-- Normalize to the range [0.5,1)
	if math.abs(x) >= 1.0 then
		x,e = x/2,e+1
	end
	return x,e
end
local function ldexp(x, exp)
	return x * 2^exp
end
local function pack(format, ...)
  local stream = {}
  local vars = {...}
  local endianness = true

  for i = 1, format:len() do
	local opt = format:sub(i, i)

	if opt == '<' then
	  endianness = true
	elseif opt == '>' then
	  endianness = false
	elseif opt:find('[bBhHiIlL]') then
	  local n = opt:find('[hH]') and 2 or opt:find('[iI]') and 4 or opt:find('[lL]') and 8 or 1
	  local val = tonumber(table.remove(vars, 1))

	  local bytes = {}
	  for j = 1, n do
		table.insert(bytes, string.char(val % (2 ^ 8)))
		val = math.floor(val / (2 ^ 8))
	  end

	  if not endianness then
		table.insert(stream, string.reverse(table.concat(bytes)))
	  else
		table.insert(stream, table.concat(bytes))
	  end
	elseif opt:find('[fd]') then
	  local val = tonumber(table.remove(vars, 1))
	  local sign = 0

	  if val < 0 then
		sign = 1
		val = -val
	  end

	  local mantissa, exponent = frexp(val)
	  if val == 0 then
		mantissa = 0
		exponent = 0
	  else
		mantissa = (mantissa * 2 - 1) * ldexp(0.5, (opt == 'd') and 53 or 24)
		exponent = exponent + ((opt == 'd') and 1022 or 126)
	  end

	  local bytes = {}
	  if opt == 'd' then
		val = mantissa
		for i = 1, 6 do
		  table.insert(bytes, string.char(math.floor(val) % (2 ^ 8)))
		  val = math.floor(val / (2 ^ 8))
		end
	  else
		table.insert(bytes, string.char(math.floor(mantissa) % (2 ^ 8)))
		val = math.floor(mantissa / (2 ^ 8))
		table.insert(bytes, string.char(math.floor(val) % (2 ^ 8)))
		val = math.floor(val / (2 ^ 8))
	  end

	  table.insert(bytes, string.char(math.floor(exponent * ((opt == 'd') and 16 or 128) + val) % (2 ^ 8)))
	  val = math.floor((exponent * ((opt == 'd') and 16 or 128) + val) / (2 ^ 8))
	  table.insert(bytes, string.char(math.floor(sign * 128 + val) % (2 ^ 8)))
	  val = math.floor((sign * 128 + val) / (2 ^ 8))

	  if not endianness then
		table.insert(stream, string.reverse(table.concat(bytes)))
	  else
		table.insert(stream, table.concat(bytes))
	  end
	elseif opt == 's' then
	  table.insert(stream, tostring(table.remove(vars, 1)))
	  table.insert(stream, string.char(0))
	elseif opt == 'c' then
	  local n = format:sub(i + 1):match('%d+')
	  local str = tostring(table.remove(vars, 1))
	  local len = tonumber(n)
	  if len <= 0 then
		len = str:len()
	  end
	  if len - str:len() > 0 then
		str = str .. string.rep(' ', len - str:len())
	  end
	  table.insert(stream, str:sub(1, len))
	  i = i + n:len()
	end
  end

  return table.concat(stream)
end
local function unpack(format, stream, pos)
  local vars = {}
  local iterator = pos or 1
  local endianness = true

  for i = 1, format:len() do
	local opt = format:sub(i, i)

	if opt == '<' then
	  endianness = true
	elseif opt == '>' then
	  endianness = false
	elseif opt:find('[bBhHiIlL]') then
	  local n = opt:find('[hH]') and 2 or opt:find('[iI]') and 4 or opt:find('[lL]') and 8 or 1
	  local signed = opt:lower() == opt

	  local val = 0
	  for j = 1, n do
		local byte = string.byte(stream:sub(iterator, iterator))
		if endianness then
		  val = val + byte * (2 ^ ((j - 1) * 8))
		else
		  val = val + byte * (2 ^ ((n - j) * 8))
		end
		iterator = iterator + 1
	  end

	  if signed and val >= 2 ^ (n * 8 - 1) then
		val = val - 2 ^ (n * 8)
	  end

	  table.insert(vars, math.floor(val))
	elseif opt:find('[fd]') then
	  local n = (opt == 'd') and 8 or 4
	  local x = stream:sub(iterator, iterator + n - 1)
	  iterator = iterator + n

	  if not endianness then
		x = string.reverse(x)
	  end

	  local sign = 1
	  local mantissa = string.byte(x, (opt == 'd') and 7 or 3) % ((opt == 'd') and 16 or 128)
	  for i = n - 2, 1, -1 do
		mantissa = mantissa * (2 ^ 8) + string.byte(x, i)
	  end

	  if string.byte(x, n) > 127 then
		sign = -1
	  end

	  local exponent = (string.byte(x, n) % 128) * ((opt == 'd') and 16 or 2) + math.floor(string.byte(x, n - 1) / ((opt == 'd') and 16 or 128))
	  if exponent == 0 then
		table.insert(vars, 0.0)
	  else
		mantissa = (math.ldexp(mantissa, (opt == 'd') and -52 or -23) + 1) * sign
		table.insert(vars, math.ldexp(mantissa, exponent - ((opt == 'd') and 1023 or 127)))
	  end
	elseif opt == 's' then
	  local bytes = {}
	  for j = iterator, stream:len() do
		if stream:sub(j,j) == string.char(0) or  stream:sub(j) == '' then
		  break
		end

		table.insert(bytes, stream:sub(j, j))
	  end

	  local str = table.concat(bytes)
	  iterator = iterator + str:len() + 1
	  table.insert(vars, str)
	elseif opt == 'c' then
	  local n = format:sub(i + 1):match('%d+')
	  local len = tonumber(n)
	  if len <= 0 then
		len = table.remove(vars)
	  end

	  table.insert(vars, stream:sub(iterator, iterator + len - 1))
	  iterator = iterator + len
	  i = i + n:len()
	end
  end

  table.insert(vars, iterator)

  return table.unpack(vars)
end

-- ==========================================
-- Wrapper for struct packing/unpacking
-- ==========================================
local Stream = {}
Stream.__index = Stream

function Stream:new(stream)
	local o = {}
	setmetatable(o, Stream)
	o.stream = stream
	o.pos = 1
	return o
end

function Stream:read(format)
	local results = {unpack(format, self.stream, self.pos)}
	local n = #results

	-- Update position data
	self.pos = results[n]
	return table.unpack(results, 1, n - 1)
end

----------------------------------------------
-- User code --
----------------------------------------------
local TYPE_REQ_ENCODERS = 1
local TYPE_RESP_ENCODERS = 2
local function ExtractEncoderRequest(conn)
	-- IPC_STRUCT {
	-- 	unsigned int page;
	-- 	unsigned int channel;
	-- } EncoderRequest[8];

	local encoders = {}
	local pages = {} -- Trak which pages have been requested (unique pages)

	for i = 1, 8 do
		local page, channel = conn.stream:read("<II")
		Printf("Page: " .. tostring(page)   .. " Channel: " .. tostring(channel))
		local req = {}
		req["page"] = page
		req["channel"] = channel
		table.insert(encoders, req)

		if not pages[page] then
			pages[page] = true
		end
	end

	return encoders, pages
end

local function GetExecutersFromChannel(page, channel)
	local _400, _300, _200, _100
	local executerTable = {}
	local bchActive = 0
	for i = 0, 3 do
		local channel_id = channel + (i * 100)
		local executor = page:Ptr(channel_id)
		if executor then
			bchActive = 1
			if i == 3 then
			    _400 = executor
			elseif i == 2 then
			    _300 = executor
			elseif i == 1 then
			    _200 = executor
			elseif i == 0 then
			    _100 = executor
			end
		end
	end

	table.insert(executerTable, _400)
	table.insert(executerTable, _300)
	table.insert(executerTable, _200)
	table.insert(executerTable, _100)

	return bchActive, executerTable
end

local function SendEncoderHeader(connection, arrbEncoderActive, seq)
	-- IPC_STRUCT {
	-- 	unsigned int master; // Master fader
	-- 	bool channelActive[8]; // True if channel/playback has any active encoders or keys
	-- } EncoderHeader; // Followed by ChannelData packets

	local packet_data = pack("<IIf", TYPE_RESP_ENCODERS, seq, Root().ShowData.Masters.Grand.Master:GetFader({})) 
	for k, v in ipairs(arrbEncoderActive) do
		packet_data = packet_data .. pack("<B", v)
	end
	connection.conn:sendto(packet_data, connection.ip, connection.port)
end

local function SendEncoderData(connection, encoderObj)
	-- struct ChannelData  {
	-- 	uint16_t page;
	-- 	uint8_t channel; // eg x01, x02, x03
	-- 	struct {
	-- 		bool isActive;
	-- 		char key_name[8];
	-- 		float value;
	-- 	} Encoders[3]; // 4xx, 3xx, 2xx encoders
	-- 	bool keysActive[4]; // 4xx, 3xx, 2xx, 1xx keys are being used
	-- };
	Printf("encoderObj -- page: " .. tostring(encoderObj.page) .. " channel: " .. tostring(encoderObj.channel))
	local packet_data = pack("<HB", encoderObj.page, encoderObj.channel) 

	-- Encoders
	for i=1, 3 do
		local encoder = encoderObj.unsafeEncoders[i]
		if encoder == nil or encoder["FADER"] == "" then
			Printf("Encoder is nil on page " .. tostring(encoderObj.page) .. " channel " .. tostring(encoderObj.channel))
			packet_data = packet_data .. pack("<Bc8f", 0, "        ", 0)
		else
			if encoder["FADER"] == "" then
				Printf("empty text")
			end
			Printf("Encoder is not nil on page " .. tostring(encoderObj.page) .. " channel " .. tostring(encoderObj.channel))
			Printf("Encoder name: " .. encoder["FADER"] .. " value: " .. encoder:GetFader({}))
			packet_data = packet_data .. pack("<Bc8f", 1, string.sub(encoder["FADER"], 1, 8), encoder:GetFader({}))
		end
	end

	-- keysActive
	for i=1, 4 do
		local encoder = encoderObj.unsafeEncoders[i]
		if encoder == nil or encoder["KEY"] == "" then
			packet_data = packet_data .. pack("<B", 0)
		else
			packet_data = packet_data .. pack("<B", 1)
		end
	end

	connection.conn:sendto(packet_data, connection.ip, connection.port)
end

local function REQ_ENCODERS(connection, seq)
	-- Collect all requests, and create a set of pages to request.
	-- The later is to avoid loading the same page multiple times if 
	-- the page is not valid.
	local requests, unique_pages = ExtractEncoderRequest(connection)


	-- Get all pages requested, and cache their pointers
	local page_cache = {}
	for k, v in pairs(unique_pages) do
		-- Using 'default' datapool for now. Is this an issue in the future?
		local page = Root().ShowData.DataPools.Default.Pages:Ptr(k)
		page_cache[k] = page
	end

	-- Collect all encoder data
	local arrbEncoderActive = {}
	local arrEncoders = {}
	for k, v in ipairs(requests) do
		Printf("Processing request -- page " .. tostring(v["page"]) .. " channel " .. tostring(v["channel"]))
		local page_ptr = page_cache[v["page"]]
		if page_ptr == nil then
			table.insert(arrbEncoderActive, 0)
			Printf("[" .. tostring(k) .. "] false")
			goto continue
		end

		local bchActive, encoders = GetExecutersFromChannel(page_ptr, v["channel"])
		table.insert(arrbEncoderActive, bchActive)
		if bchActive == 1 then
			local wrappedEncoder = {
				page = v["page"],
				channel = v["channel"],
				unsafeEncoders = encoders -- May contain nil values
			}
			table.insert(arrEncoders, wrappedEncoder)
		end
		
		::continue::
  	end

	-- Next, we send an initial response that indicates how many channels are active, which will tell the client how many more packets to expect.
	-- We also include the value of the grandmaster fader.
	SendEncoderHeader(connection, arrbEncoderActive, seq)

	-- Finally, we send the actual encoder data
	for k, v in ipairs(arrEncoders) do
		SendEncoderData(connection, v)
	end
end

local function HandleConnection(socket, ip, port, data)
	if not data then return end

	local stream = Stream:new(data)
	local connection = {
		conn = socket,
		ip = ip,
		port = port,
		stream = stream
	}
	pkt_type, seq = stream:read("<II")
	-- Handlers
	if pkt_type == TYPE_REQ_ENCODERS then
		Printf("In")
		REQ_ENCODERS(connection, seq)
	end
end

local function BeginListening()
	local socket = require("socket")
	local udp = assert(socket.udp4())
	local port = 9000

	udp:settimeout(0)
	assert(udp:setsockname("*", port))

	Printf("Entering loop")
	while true do
		local data, ip, port = udp:receivefrom()
		HandleConnection(udp, ip, port, data)
		coroutine.yield(.1)
	end
end

return BeginListening