--- @since 26.9.1
--- wayclip.yazi - move files between Yazi and the rest of your Wayland desktop.
---
--- Three entry points, selected by the first plugin argument:
---   copy   put the selection on the clipboard as a text/uri-list
---   cut    put the selection on the clipboard marked for moving
---   paste  read the clipboard and copy or move those files into the cwd
---
--- The URI encoding in `encode_uri` follows grappas/wl-clipboard.yazi (MIT).

local DEFAULTS = { timeout = 5 }

local state = ya.sync(function(self)
	return self.timeout or DEFAULTS.timeout
end)

local function notify(content, level)
	ya.notify({ title = "wayclip", content = content, level = level or "info", timeout = state() })
end

--- Percent-encode everything outside the unreserved set so that spaces and
--- non-ASCII filenames survive the round trip.
local function encode_uri(path)
	return (path:gsub("([^%w%-%._~:/])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local selected_or_hovered = ya.sync(function()
	local tab, paths = cx.active, {}
	for _, u in pairs(tab.selected) do
		paths[#paths + 1] = tostring(u)
	end
	if #paths == 0 and tab.current.hovered then
		paths[1] = tostring(tab.current.hovered.url)
	end
	return paths
end)

--- Hand `body` to wl-copy under a single MIME type.
--- wl-copy can only advertise one type per invocation, which is why cut and
--- copy use different types rather than offering both at once.
local function write_clipboard(mime, body)
	-- The payload goes in as an argument rather than over stdin: wl-copy reads
	-- stdin until EOF, and the Command API gives no way to close the pipe, so a
	-- piped payload is never committed. This caps the selection at ARG_MAX,
	-- which is a few thousand paths.
	local child = Command("wl-copy"):arg("--type"):arg(mime):arg(body):spawn()
	if not child then
		return false, "wl-copy not found. Install the wl-clipboard package."
	end

	local status, err = child:wait()
	if not status or not status.success then
		return false, string.format("wl-copy failed (%s)", (status and status.code) or err or "unknown")
	end
	return true
end

--- Read one MIME type back. Returns nil when wl-paste is missing or the
--- clipboard is not offering that type.
local function read_clipboard(mime)
	local output = Command("wl-paste"):arg("--no-newline"):arg("--type"):arg(mime):output()
	if not output or not output.status.success then
		return nil
	end
	return output.stdout ~= "" and output.stdout or nil
end

local function uri_lines(paths)
	local out = {}
	for _, path in ipairs(paths) do
		out[#out + 1] = "file://" .. encode_uri(path)
	end
	return table.concat(out, "\r\n") .. "\r\n"
end

--- Decide what the clipboard is offering, and whether it is a cut.
---
--- GNOME writes "cut\nfile://..." or "copy\nfile://..." to its own type, and
--- some applications offer that type without a text/uri-list, so it doubles as
--- a fallback source of URIs. KDE keeps a plain uri-list and marks the cut in
--- a separate type.
local function read_uri_list()
	local gnome = read_clipboard("x-special/gnome-copied-files")
	local cut = (gnome ~= nil and gnome:match("^cut") ~= nil)
		or read_clipboard("application/x-kde-cutselection") == "1"

	-- A leading "cut" or "copy" line is ignored by the file:// test in
	-- spawn_tasks, so the GNOME payload can be used verbatim.
	return read_clipboard("text/uri-list") or gnome, cut
end

--- Spawn one Yazi task per file:// entry. Using Yazi's own task system rather
--- than shelling out gives progress reporting and conflict prompts for free.
local spawn_tasks = ya.sync(function(_, list, kind)
	cx.tasks.behavior:reset()

	local count = 0
	for line in list:gmatch("[^\r\n]+") do
		if line:sub(1, 7) == "file://" then
			local from = Url(ya.percent_decode(line:sub(8)))
			if from.name then
				local to = cx.active.current.cwd:join(from.name)
				ya.async(function() ya.task(kind, { from = from, to = to }):spawn() end)
				count = count + 1
			end
		end
	end
	return count
end)

local function put(cut)
	ya.emit("escape", { visual = true })

	local paths = selected_or_hovered()
	if #paths == 0 then
		return notify("Nothing selected or hovered.", "warn")
	end

	local body, mime
	if cut then
		-- Only x-special/gnome-copied-files can express a cut, so a cut is
		-- published under that type alone. See "Limitations" in the README.
		mime = "x-special/gnome-copied-files"
		body = "cut\n" .. uri_lines(paths)
	else
		mime = "text/uri-list"
		body = uri_lines(paths)
	end

	local ok, err = write_clipboard(mime, body)
	if not ok then
		return notify(err, "error")
	end
	notify(string.format("%s %d item(s) to the system clipboard", cut and "Cut" or "Copied", #paths))
end

local function paste()
	local list, cut = read_uri_list()
	if not list then
		return notify("Clipboard holds no files. Copy a file in another app first.", "warn")
	end

	local kind = cut and "move" or "copy"
	local count = spawn_tasks(list, kind)

	if count == 0 then
		notify("Clipboard has a uri-list but no local file:// entries.", "warn")
	else
		notify(string.format("%s %d item(s) from the system clipboard", cut and "Moving" or "Copying", count))
	end
end

return {
	setup = function(self, opts)
		self.timeout = (opts or {}).timeout or DEFAULTS.timeout
	end,

	entry = function(_, job)
		local action = (job.args or {})[1] or "copy"
		if action == "copy" then
			put(false)
		elseif action == "cut" then
			put(true)
		elseif action == "paste" then
			paste()
		else
			notify(string.format("Unknown action %q. Use copy, cut or paste.", action), "error")
		end
	end,
}
