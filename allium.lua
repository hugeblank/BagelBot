-- Allium by hugeblank

-- Dependency Loading
local raisin, color, semver, mojson, json, nap = require("lib.raisin"), require("lib.color"), require("lib.semver"), require("lib.mojson"), require("lib.json"), require("lib.nap")

-- Internal definitions
local allium, plugins, group = {}, {}, {thread = raisin.group(1), command = raisin.group(2)}

-- Get executing path
local path = "/"
for str in string.gmatch(shell.getRunningProgram(), ".+[/]") do
	path = path..str
end
-- Defining custom print
local function aprint(prefix, wcText, ...) -- Magical function that takes in a table and changes the text color/writes at the same time
	local c = term.getTextColor()
	local function writeColor(cdata)
		for i = 1, #cdata do
			if type(cdata[i]) == "string" then
				write(cdata[i])
			else
				term.setTextColor(cdata[i])
			end
		end
		term.setTextColor(c)
	end
	writeColor(prefix)
	if wcText then
		writeColor({...})
		_G.print()
	else
		_G.print(...)
	end
end

local function getData(name) -- Extract data on user from data command
	local suc, data = commands.exec("data get entity "..name)
	if not suc then return suc, data end
	data = data[1]:sub(data[1]:find("{"), -1)
	local data = mojson.parseList(data)
	if not data then return false end
	return data
end

local function deep_copy(table) -- Recursively copy a module
	local out = {}
	for name, func in pairs(table) do
		if type(func) == "table" then
			out[name] = deep_copy(func)
		else
			out[name] = func
		end
	end
	return out
end

local function assert(condition, message, level)
	if not condition then error(message, (level or 0)+3) end
end

local g_persistence
do -- Metadata magic table setup
	local permdata, dummy
	local function update()
		local file = fs.open(fs.combine(path, "cfg/metadata.lson"), "r")
		permdata = textutils.unserialise(file.readAll())
		if not permdata then permdata = {} end
		file.close()
	end
	local function scope(kt)
		dummy = permdata
		for i = 1, #kt do
			dummy = dummy[kt[i]]
		end
	end

	local function makemt(keytbl)
		return {
			-- Dear Lua, make __modindex a thing. Sincerely, hugeblank
			__index = function(_, k)
				scope(keytbl)
				if type(dummy[k]) == "table" then
					local newkeytbl = {}
					for i = 1, #keytbl do
						newkeytbl[#newkeytbl+1] = keytbl[i]
					end
					newkeytbl[#newkeytbl+1] = k
					return setmetatable({}, makemt(newkeytbl))
				else
					return dummy[k]
				end
			end,
			__newindex = function(_, k, v)
				scope(keytbl)
				dummy[k] = v
				local file = fs.open(fs.combine(path, "cfg/metadata.lson"), "w")
				assert(file, "Failed to open metadata file. Is the disk full?")
				file.write(textutils.serialise(permdata))
				file.close()
			end,
			__call = function()
				scope(keytbl)
				return dummy
			end
		}
	end

	update()
	scope({})

	g_persistence = setmetatable({}, makemt({}))
end

local g_updates = {}
do
	do -- Standard github update methods, written for you <3
		local github = {}
		local sha
		github[1] = function(data) -- Update checker function
			local github = nap("https://api.github.com")
			if data.user and data.repo and data.branch then
				local response = github.repos[data.user][data.repo].commits[data.branch]({ method = "GET" })
				if not response then return false end
				local parsed = json.decode(response.readAll())
				if not parsed then return false end
				if not data.sha then data.sha = parsed.sha end
				if data.sha ~= parsed.sha then
					sha = parsed.sha
					return true
				end
			end
			return false
		end

		github[2] = function(data) -- Update executor function
			local null = function() end -- Please forgive me for this sin of a bodge
			os.run({
					term = {
						write=null,
						setCursorPos=null,
						getCursorPos=function() return 1, 1 end
					},
					print = null,
					write = null,
					shell = {
						getRunningProgram = function() return fs.combine(path, "/lib/gget.lua") end
					}
				},
				fs.combine(path, "/lib/gget.lua"),
				data.user,
				data.repo,
				data.branch,
				data.path or fs.combine(path, "plugins")
			)
			data.sha = sha
		end

		g_updates.github = function()
			return table.unpack(github)
		end
	end

	do -- Standard pastebin update methods
		local pastebin = {}
		local p = fs.combine(path, "plugins")
		pastebin[1] = function(data) -- Update checker function
			if not (data.id and data.path and http.checkURL("https://pastebin.com/raw/"..data.id) and fs.exists(fs.combine(p, data.path))) then
				return false
			end
			local content, file = http.get("https://pastebin.com/raw/"..data.id), fs.open(fs.combine(p, data.path), "r")
			if not (content and file) then
				file.close()
				return false
			end
			local out = content.readAll() ~= file.readAll()
			file.close() content.close()
			return out
		end

		pastebin[2] = function(data) -- Update runner function
			local content, file = http.get("https://pastebin.com/raw/"..data.id), fs.open(fs.combine(p, data.path), "w")
			if not file then
				content.close()
				error("Could not write to file. Is the disk full?")
			end
			file.write(content.readAll())
			file.close() content.close()
		end

		g_updates.pastebin = function()
			return table.unpack(pastebin)
		end
	end
end

local cli = {
	info = {"[", colors.lime, "I", colors.white, "] "}, 
	warn = {"[", colors.yellow, "W", colors.white, "] "},
	error = {"[", colors.red, "E", colors.white, "] "}
}

local config, up = ...
do -- Configuration parsing
	if type(config) ~= "table" then
		printError("Invalid input configuration, make sure you're using the provided init file.")
		return
	end
	local ver, rule = semver.parse(config.version)
	allium.version = ver
	if not allium.version then -- Invalid Allium version
		printError("Could not parse Allium's version (breaks SemVer rule #"..rule..")")
		return
	end
end

local main -- Main terminal window Allium is outputting to
do -- Allium image setup <3
	local image = {
		"  2a2",
		" 2aa6a",
		"26a6aaa",
		"aa66a2a",
		" 6aa62",
		"  ad26",
		"   5",
		"   d",
		"   d",
		"   d",
		"   5",
		"   5",
		"   d",
		"   d"
	}
	term.clear()
	local x, y = term.getSize()
	term.setCursorPos(x-7, 3)
	for i = 1, #image do -- Draw the Allium image on the side
		term.blit(string.rep(" ", #image[i]), string.rep("0", #image[i]), image[i])
		local _, cy = term.getCursorPos()
		term.setCursorPos(x-7, cy+1)
	end
	local win = window.create(term.current(), 1, 1, x-9, y, true) -- Create a window to prevent text from writing over the image
	main = term.redirect(win) -- Redirect the terminal
	term.setCursorPos(1, 1)
	term.setBackgroundColor(colors.black) -- Reset terminal and cursor
	term.setTextColor(colors.white)
	aprint(cli.info, true, "Loading ", colors.magenta, "All", colors.purple, "i", colors.magenta, "um")
	aprint(cli.info, true, "Initializing API")
end

allium.assert = assert

allium.sanitize = function(name)
	assert(type(name) == "string", "Invalid argument #1 (expected string, got "..type(name)..")")
	return name:lower():gsub(" ", "_"):gsub("[^a-z0-9_]", "")
end

-- Logging wrapper functions
allium.log = function(...)
	aprint(cli.info, false, ...)
end

allium.warn = function(...)
	aprint(cli.warn, false, ...)
end

allium.tell = function(name, message, alt_name)
	assert(type(name) == "string", "Invalid argument #1 (expected string, got "..type(name)..")")
	assert(type(message) == "string" or type(message) == "table", "Invalid argument #2 (expected string or table, got "..type(message)..")")
	local out = {}
	if type(message) == "table" then
		for i = 1, #message do
			_, out[#out+1] = commands.async.tellraw(name, json.encode(color.format(message[i])))
		end
	else
		_, out = commands.tellraw(name, json.encode(color.format((function(alt_name) if alt_name == true then return "" elseif alt_name then return alt_name.."&r" else return config.label.."&r" end end)(alt_name)..message)))
	end
    return out
end

allium.execute = function(name, command)
	assert(type(name) == "string", "Invalid argument #1 (string expected, got "..type(name)..")")
	assert(type(command) == "string", "Invalid argument #2 (string expected, got "..type(command)..")")
	os.queueEvent("chat_capture", command, "execute", name)
end

allium.getPlayers = function()
	local didexec, input = commands.exec("list")
	local out = {}
	if not didexec or not input[1]:find(":") then
		return false, input
	end
	for user in string.gmatch(input[1]:sub(input[1]:find(":")+1, -1), "%S+") do
		if user:find(",") then
			out[#out+1] = user:sub(1, -2)
		else
			out[#out+1] = user
		end
	end
	return out
end

allium.getPosition = function(name)
	assert(type(name) == "string", "Invalid argument #1 (string expected, got "..type(name)..")")
	local data = getData(name)
	assert(data, "Failed to get data on user ".. name)
	return {
		position = data.Pos,
		rotation = data.Rotation,
		dimension = data.Dimension
	}
end

allium.forEachPlayer = function(func)
	assert(type(func) == "function", "Invalid argument #1 (function expected, got "..type(func)..")")
	local threads = {}
	local players = allium.getPlayers()
	local mentioned, error = false
	for i = 1, #players do 
		threads[#threads+1] = function()
			local suc, err = pcall(func, players[i])
			if not suc and not mentioned then
				error = err
				mentioned = true
			end
		end
	end
	parallel.waitForAll(unpack(threads))
	if not mentioned then
		return true
	else
		return false, error
	end
end

allium.getInfo = function(plugin) -- Get the information of all plugins, or a single plugin
	assert(plugin == nil or type(plugin) == "string", "Invalid argument #1 (nil or string expected, got"..type(plugin)..")")
	if plugin then
		plugin = allium.sanitize(plugin)
		assert(plugins[plugin], "Invalid argument #1 (plugin "..plugin.." does not exist)")
		local res = {[plugin] = {}}
		for name, command_data in pairs(plugins[plugin].commands) do
			res[plugin][name] = {info = command_data.info, usage = command_data.usage}
		end
		return res
	else
		local res = {}
		for p_name, plugin in pairs(plugins) do
			res[p_name] = {}
			for c_name, command_data in pairs(plugin.commands) do
				res[p_name][c_name] = {info = command_data.info, usage = command_data.usage}
			end
		end
		return res
	end
end

allium.getName = function(plugin)
	assert(type(plugin) == "string", "Invalid argument #1 (string expected, got "..type(plugin)..")")
	if plugins[plugin] then
		return plugins[plugin].name
	end
end

allium.register = function(p_name, version, fullname)
	assert(type(p_name) == "string", "Invalid argument #1 (string expected, got "..type(p_name)..")")
	local real_name = allium.sanitize(p_name)
	assert(plugins[real_name] == nil, "Invalid argument #1 (plugin exists under name "..real_name..")")
	local version, rule = semver.parse(version)
	assert(type(version) == "table", "Invalid argument #2 (malformed SemVer, breaks rule "..(rule or "")..")")
	local loaded = {}
	plugins[real_name] = {commands = {}, loaded = loaded, name = fullname or p_name, version = version}
	local funcs, this = {}, plugins[real_name]

	-- Redefining persistence locally
	if not g_persistence[real_name] then
		g_persistence[real_name] = {}
	end
	local persistence = g_persistence[real_name]
	this.persistence = persistence

	funcs.command = function(c_name, command, info) -- name: name | command: executing function | info: help information
		-- Add a command for the user to execute
		assert(type(c_name) == "string", "Invalid argument #1 (string expected, got "..type(c_name)..")")
		local real_name = allium.sanitize(c_name)
		assert(type(command) == "function", "Invalid argument #2 (function expected, got "..type(command)..")")
		assert(this.commands[real_name] == nil, "Invalid argument #2 (command "..c_name.." already exists)")
		assert(type(info) == "string" or type(info) == "table" or not info, "Invalid argument #3 (string, or table expected, got "..type(info)..")")
		if type(info) == "string" then info = {info} end
		assert(info[1], "Invalid argument #3 (info formatted table expected)")
		this.commands[real_name] = {command = command, info = info}
	end

	funcs.thread = function(thread)
		-- Add a thread that repeatedly iterates
		assert(type(thread) == "function", "Invalid argument #1 (function expected, got "..type(thread)..")")
		local wrapper = function()
			local s, e = pcall(thread)
			if not s then
				allium.warn("Thread in "..real_name.." | "..e)
			end
		end
		return raisin.thread(wrapper, 0, group.thread)
	end

	funcs.loadConfig = function(default)
		assert(type(default) == "table", "Invalid argument #1 (table expected, got "..type(default)..")") 
		local file = fs.combine(path, "/cfg/"..real_name..".lson")
		if not fs.exists(file) then
			local setting = fs.open(file,"w")
			setting.write(textutils.serialise(default))
			setting.close()
			return default
		end
		local setting = fs.open(file, "r")
		local config = setting.readAll()
		setting.close()
		config = textutils.unserialise(config)
		if type(config) ~= "table" then
			return default
		end
		local checkForKeys
		checkForKeys = function(default, test)
			for key, value in pairs(default) do
				if not test[key] then
					test[key] = value
				elseif type(test[key]) == "table" then
					checkForKeys(value, test[key])
				end
			end
		end
		checkForKeys(default, config)
		return config
	end

	do -- Library Managment micro service
		local apis = {}

		local loadAPI = function(url, name)
			assert(type(url) == "string", "Invalid argument #1 (expected string got "..type(url)..")")
			assert(type(name) == "string", "Invalid argument #2 (expected string got "..type(name)..")")
			name = allium.sanitize(name) -- Remove invalid characters
			if not persistence.libs then persistence.libs = {} end -- Create entry for plugin
			local api -- Variable to put loaded lib
			local fileName = fs.combine(path, "lib/plugins/"..real_name.."/"..name..".lua") -- Path for file
			-- Handle updates
			if persistence.libs[name] ~= url then -- If this is an updated version of the library
				persistence.libs[name] = nil -- Clear the entry from metadata to add later
			end
			-- Handle downloading/loading
			if not persistence.libs[name] then -- If there is no entry for this library
				local handle = http.get(url) -- Download handle, make file name
				if not handle then
					handle.close()
					return false
				end -- If download failed, leave
				local apiFile, contents = fs.open(fileName, "w"), handle.readAll() -- Create local file, get response contents
				local s, e = load(contents, name, nil, _ENV) -- Compile program
				if not s then
					apiFile.close() handle.close() -- Close handles
					return false, e
				end -- Leave if it errored
				api = s
				apiFile.write(contents) -- Save handle
				persistence.libs[name] = url -- Add library entry
				apiFile.close() handle.close() -- Close handles
			else -- OTHERWISE the library entry exists, load locally.
				local s, e = loadfile(fileName) -- Load the file. Duh.
				if not s then return false, e end -- Exit if there was an error loading it
				api = s
			end
			apis[name] = true -- Mark library as loaded
			return pcall(api) -- Safely load the library
		end
		local done = function() -- Do API cleaning
			for name in pairs(persistence.libs) do
				if not apis[name] then
					persistence.libs[name] = nil
					local fileName = fs.combine(path, "lib/plugins/"..real_name.."/"..name..".lua") -- Path for file
					fs.delete(fileName)
				end
			end
		end

		funcs.loadLibs = function(t)
			assert(type(t) == "table", "Invalid argument #1 (expected table got "..type(t)..")")
			local out = {}
			for name, url in pairs(t) do
				assert(type(url) == "string", "Invalid URL "..tostring(url).." (expected string got "..type(url)..")")
				assert(type(name) == "string", "Invalid name "..tostring(name).." (expected string got "..type(name)..")")
				local temp = {loadAPI(url, name)}
				table.remove(temp, 1)
				out[name] = temp
			end
			done()
			return out
		end
	end

	do -- Plugin self-update micro service
		funcs.update = {
			default = g_updates
		}
		-- Magic table for the update micro API.
		if not persistence.update then persistence.update = {} end
		funcs.update.cache = persistence.update

		funcs.update.setMethods = function(check, update)
			if not up.check.plugins then up.check.plugins = {} end
			if not up.run.plugins then up.run.plugins = {} end
			up.check.plugins[real_name] = check
			up.run.plugins[real_name] = update
		end
	end

	-- Magic table specifically for caching things that the user shouldn't see
	if not persistence.cache then persistence.cache = {} end
	funcs.cache = persistence.cache

	funcs.module = function(container)
		if type(funcs.module) == "function" then -- Prevent overwriting the module
			-- A container for all external functionality that other programs can utilize
			assert(type(container) == "table", "Invalid argument #1 (table expected, got "..type(container)..")")
			this.module = container
			funcs.module = container
		end
	end

	funcs.import = function(p_name) -- request the API from a specific plugin
		assert(type(p_name) == "string", "Invalid argument #1 (string expected, got "..type(p_name)..")")
		p_name = allium.sanitize(p_name)
		assert(p_name == real_name, real_name.." attempted to load self. What made you think you could do this?")
		local timer = os.startTimer(config.import_timeout or 5)
		parallel.waitForAny(function()
			repeat
				local e = {os.pullEvent()}
			until (e[1] == "timer" and e[2] == timer) or (plugins[p_name] and plugins[p_name].module)
		end, function()
			repeat
				sleep()
			until plugins[p_name].module
		end)
		if not plugins[p_name].module then
			return false
		end
		for i = 1, #plugins[p_name].loaded do
			if plugins[p_name].loaded[i] == real_name then
				error("Cannot import "..p_name.."Circular dependencies with "..real_name.." and "..plugins[p_name].loaded[i])
			end
		end
		loaded[#loaded+1] = p_name
		return deep_copy(plugins[p_name].module)
	end

	return funcs
end

allium.verify = function(param) -- Verification code ripped from DepMan instance
	assert(type(param) == "string", "Invalid argument #1 (string expected, got "..type(param)..")")
	local function convert(str) -- Use the semver API to convert. Provide a detailed error if conversion fails
		if type(str) ~= "string" then
			error("Could not convert "..tostring(str))
		end
		local ver, rule = semver.parse(str:gsub("%s", ""))
		if not ver then
			error("Could not parse "..str:gsub("%s", "")..", breaks semver spec rule "..rule)
		end
		return ver
	end
	local function compare(in_str) -- compare version provided in string to input versions, using the operator provided
		local _, split = in_str:find("[><][=]*")
		local lim, op, res = convert(in_str:sub(split+1)), in_str:sub(1, split), nil -- Split operator and version string
		if op == ">" then
			res = allium.version > lim
		elseif op == "<" then
			res =  allium.version < lim
		elseif op == ">=" then
			res = allium.version >= lim
		elseif op == "<=" then
			res = allium.version <= lim
		end
		return res
	end
	local range = param:find("&&") -- Matched a range definition
	local comp = param:find("[><][=]*") -- I do love me some pattern matching
	if range then -- If there's a range beginning definition
		local a, b = compare(param:sub(1, range-1)), compare(param:sub(range+3, -1))
		if a and b then
			return true
		end
	elseif comp then -- Otherwise if there's a comparison operator
		if compare(param) then
			return true
		end
	elseif convert(param) == allium.version then -- Otherwise this is a simple list element
		return true
	end
	return false
end

allium.getVersion = function(plugin)
	assert(type(plugin) == "string", "Invalid argument #1 (string expected, got "..type(plugin)..")")
	if plugins[plugin] then
		return plugins[plugin].version
	end
end

for _, side in pairs(peripheral.getNames()) do -- Finding the chat module
	if peripheral.getMethods(side) then
		for _, method in pairs(peripheral.getMethods(side)) do
			if method == "capture" then
				allium.side = side
				peripheral.call(side, method, "^!")
				break
			end
		end
	end
	if allium.side then break end
end
if not allium.side then
	allium.warn("Allium could not find chat module")
end

-- Packaging the Allium API
if not package.preload["allium"] then
	package.preload["allium"] = function()
		return allium
	end
else
	aprint(cli.error, false, "Another instance of Allium is already running")
	return
end

do -- Plugin loading process
	allium.log("Loading plugins")
	local loader_group = raisin.group(1)
	local function scopeDown(dir)
		for _, plugin in pairs(fs.list(dir)) do
			if (not fs.isDir(dir.."/"..plugin)) and plugin:find(".lua") then
				local file, err = loadfile(dir.."/"..plugin, _ENV)
				if not file then
					aprint(cli.error, false, err)
				else
					local thread = function()
						local suc, err = pcall(file)
						if not suc then
							aprint(cli.error, false, err)
						end
					end
					raisin.thread(thread, 0, loader_group)
				end
			elseif fs.isDir(dir.."/"..plugin) then
				scopeDown(dir.."/"..plugin)
			end
		end
	end
	if fs.exists(fs.combine(path, "/plugins")) then
		scopeDown(fs.combine(path, "/plugins"))
	end
	raisin.manager.runGroup(loader_group)
end

local interpreter = function() -- Main command interpretation thread
	-- Definitions that don't need to be repeated every command
	local function getUsage(fields, info, index)
		index = index or 1
		fields[index] = {}
		for key, info in pairs(info) do
			if type(info) == "table" then
				local match = false
				for i = 1, #fields[index] do
					if key == fields[index][i] then
						match = true
					end
				end
				if not match then
					fields[index][#fields[index]+1] = key
				end
				getUsage(fields, info, index+1)
			end
		end
	end
	while true do
		local _, message, _, name, uuid = os.pullEvent("chat_capture") -- Pull chat messages
		if message:find("!") == 1 then -- Are they for allium?
			local args = {}
			for k in message:gmatch("%S+") do -- Put all arguments spaced out into a table
				args[#args+1] = k
			end
			for i = 1, #args do
				if args[i] then
					local quote = args[i]:sub(1, 1):find("\"") -- Find quotes within arguments
					if quote then
						local j, end_quote = i
						if args[i]:sub(-1, -1) ~= "\"" and #args[i] ~= 1 then -- If the quote isn't found in the same argument
							while not (end_quote or j == #args) do -- Find the quote that matches with this one
								j = j+1
								end_quote = args[j]:sub(-1, -1):find("\"")
							end
						end
						if end_quote then -- If there was an end quote
							local message, size = "", 0
							local function merge(str)
								if #message+#str > size then
									message = message..str.." "
									size = #message
								end
							end
							merge(args[i]:sub(2, -1))
							merge(table.concat(args, " ", i+1, j-1))
							args[i] = message..args[j]:sub(1, -2) -- Overwrite the first argument
							for k = j, i+1, -1 do -- Then remove everything that was used
								table.remove(args, k)
							end
						end
					end
				end
			end
			local cmd = args[1]:sub(2, -1) -- Strip the !
			table.remove(args, 1) -- Remove the first parameter given (!command)
			local splitat, cmd_exec = cmd:find(":"), nil
			if not splitat then -- Did they not specify the plugin source?
				for p_name, plugin in pairs(plugins) do -- Nope... gonna have to find it for them.
					for c_name, data in pairs(plugin.commands) do
						if c_name == cmd then -- Well I found it, but there may be more...
							cmd_exec = {data = data, plugin = p_name, command = c_name} -- Split into command function, plugin name, and command name
							break
						end
					end
					if cmd_exec then break end -- Exit this loop, we've found the command we're looking for
				end
			else -- Hey they did! +1 karma.
				local p_name, c_name = cmd:sub(1, splitat-1), cmd:sub(splitat+1, -1)
				if plugins[p_name] then --check plugin existence
					if plugins[p_name].commands[c_name] then --check command existence
						cmd_exec = {data = plugins[p_name].commands[c_name], plugin = p_name, command = c_name} -- Split it into the function, and then the source
					end
				end
			end
			if cmd_exec then -- Is there really a command?
				local data = { -- Infrequently used data to pass onto the command being executed
					error = function(text) 
						local str, fields = "", {}
						getUsage(fields, cmd_exec.data.info)
						if #fields == 0 then
							str = "Invalid or missing parameter(s)"
						else
							str = "!"..cmd_exec.plugin..":"..cmd_exec.command.." "
							for i = 1, #fields do
								if #fields[i] ~= 0 then
									str = str.."< "..table.concat(fields[i], " | ").." > "
								end
							end
						end
						allium.tell(name, "&c"..(text or str))
					end,
					uuid = uuid
				}
				local function exec_command()
					local cmd_exec = cmd_exec
					local stat, err = pcall(cmd_exec.data.command, name, args, data) -- Let's execute the command in a safe environment that won't kill allium
					if stat == false then -- It crashed...
						allium.tell(name, {
							"&4!"..cmd_exec.command.." crashed! This is likely not your fault, but the developer's. Please contact the developer of &a"..cmd_exec.plugin.."&4. Error:",
							"&c&h(Click here to place error into chat prompt, so you may copy it if needed for an issue report)&s("..err..")"..err.."&r"
						})
						allium.warn(cmd.." | "..err)
					end
				end
				raisin.thread(exec_command, 0, group.command)
    		else -- This isn't even a valid command...
	    		allium.tell(name, "&6Invalid Command, use &c&g(!allium:help)!help&r&6 for assistance.") --bleh!
    		end
	    end
	end
end

local player_scanner = function() -- Login/out scanner thread
    local online = {}
    while true do
        local cur_players = allium.getPlayers()
		local organized = {}
		if cur_players then
			for i = 1, #cur_players do -- Sort players in a way that's useful
				organized[cur_players[i]] = cur_players[i]
			end
			for _, name in pairs(organized) do
				if online[name] == nil then
					online[name] = name
					os.queueEvent("player_join", name)
				end
			end
			for _, name in pairs(online) do
				if organized[name] == nil then
					online[name] = nil
					os.queueEvent("player_quit", name)
				end
			end
		else
			allium.warn("Could not list online players, skipping tick.")
		end
    end
end

local update_interaction = function() -- Update UI scanning and handling thread
	local common = {
		run = {}
	}
	common.refresh = function()
		local done = term.redirect(main)
		local x, y = term.getSize()
		common.bY = y-1
		if #common.run > 0 then
			common.bX = x-6
			term.setCursorPos(x-6, y-1)
			term.blit("TRS \24", "888f8", "14efb")
		else
			common.bX = x-5
			term.setCursorPos(x-5, y-1)
			term.blit("TRS", "888", "14e")
		end
		term.setBackgroundColor(colors.black) -- Reset terminal and cursor
		term.setTextColor(colors.white)
		term.redirect(done)
	end
	parallel.waitForAll(function() -- Update checker on initialize
		if config.updates.notify.dependencies then
			local suc, deps = up.check.dependencies()
			local suffixer
			if suc and type(deps) == "table" and #deps > 0 then
				if #deps == 1 then
					suffixer = {"Utility ", " is"}
				else
					suffixer = {"Utilities: ", " are"}
				end
				allium.log(suffixer[1]..table.concat(deps, ", ")..suffixer[2].." ready to be updated")
				common.run[#common.run+1] = {up.run.dependencies}
			elseif not suc then
				aprint(cli.error, true, "Error in checking for dependency updates: "..table.concat(deps, ", "))
			end
		end
		if config.updates.notify.allium then
			local sha = up.check.allium()
			if sha ~= config.sha then
				allium.log("Allium is ready to be updated")
				common.run[#common.run+1] = {up.run.allium, sha}
			elseif not sha then
				allium.warn("Failed to scan for allium updates")
			end
		end
		if config.updates.notify.plugins then
			local toUpdate = {}
			local suffixer
			for k, v in pairs(up.check.plugins or {}) do
				if g_persistence[k] and g_persistence[k].update and v and up.run.plugins[k] then
					local s, r = pcall(v, g_persistence[k].update)
					if s and r then
						toUpdate[#toUpdate+1] = k
						common.run[#common.run+1] = {up.run.plugins[k], g_persistence[k].update}
					end
				end
			end
			if #toUpdate == 1 then
				suffixer = {"Plugin ", " is"}
			elseif #toUpdate > 1 then
				suffixer = {"Plugins: ", " are"}
			end
			if suffixer then
				allium.log(suffixer[1]..table.concat(toUpdate, ", ")..suffixer[2].." ready to be updated")
			end
		end
		common.refresh()
	end, function() -- User Interface
		common.refresh()
		while true do
			local e = {os.pullEvent("mouse_click")}
			table.remove(e, 1)
			if table.remove(e, 1) == 1 then
				local x = table.remove(e, 1)
				if table.remove(e, 1) == common.bY then
					if x-common.bX == 0 then -- Terminate
						allium.log("Exiting Allium...")
						raisin.manager.halt()
					elseif x-common.bX == 1 then -- Reboot
						allium.log("Rebooting...")
						sleep(1)
						os.reboot()
					elseif x-common.bX == 2 then -- Shutdown
						allium.log("Shutting down...")
						sleep(1)
						os.shutdown()
					elseif x-common.bX == 4 and #common.run > 0 then -- Update
						allium.log("Downloading updates...")
						for i = 1, #common.run do
							local s, err = pcall(table.unpack(common.run[i]))
							if not s then
								aprint(cli.error, true, "Failed to execute an update: "..err)
							end
						end
						allium.log("Rebooting to apply updates...")
						sleep(1)
						os.reboot()
					end
				end
			end
		end
	end)
end

raisin.thread(interpreter, 0)
raisin.thread(player_scanner, 1)
raisin.thread(update_interaction, 1)

if not fs.exists(fs.combine(path, "cfg/metadata.lson")) then --In the situation that this is a first installation, let's do some setup
	local fpers = fs.open(fs.combine(path, "cfg/metadata.lson"), "w")
	fpers.write("{}")
	fpers.close()
end

allium.log("Allium started.")
allium.tell("@a", "&eHello World!")
raisin.manager.run()

package.preload["allium"] = nil