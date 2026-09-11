gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local font = resource.load_font("font.ttf")
local placeholder = resource.load_image("poster-placeholder.png")
local offline_logo = resource.load_image("offline-logo.png")
local connection_ok = true
util.json_watch("connection.json", function(state)
    connection_ok = state.ok ~= false
end)
local config = {
    venue_name = "Our Cinema",
    movie_duration = 12,
    child_duration = 15,
    show_coming_soon = true,
}
local movies = {}
local posters = {}
local qrs = {}
local children = {}
local sequence = {}
local sequence_index = 1
local sequence_started = sys.now()

local function sorted_children()
    local result = {}
    for name, _ in pairs(CHILDS) do
        table.insert(result, name)
    end
    table.sort(result)
    return result
end

local function rebuild_sequence()
    sequence = {}
    local now_showing = {}
    local starts_tomorrow = {}
    local coming_soon = {}
    for _, movie in ipairs(movies) do
        if movie.status == "starts_tomorrow" then
            table.insert(starts_tomorrow, movie)
        elseif movie.status == "coming_soon" then
            table.insert(coming_soon, movie)
        else
            table.insert(now_showing, movie)
        end
    end
    local child_names = sorted_children()
    local widest = math.max(#now_showing, #starts_tomorrow, config.show_coming_soon and #coming_soon or 0, #child_names)
    for index = 1, widest do
        if now_showing[index] then
            table.insert(sequence, {kind="movie", movie=now_showing[index], duration=config.movie_duration})
        end
        if child_names[index] then
            table.insert(sequence, {kind="child", name=child_names[index], duration=config.child_duration})
        end
        if starts_tomorrow[index] then
            table.insert(sequence, {kind="movie", movie=starts_tomorrow[index], duration=config.movie_duration})
        end
        if config.show_coming_soon and coming_soon[index] then
            table.insert(sequence, {kind="movie", movie=coming_soon[index], duration=config.movie_duration})
        end
    end
    if #sequence == 0 then
        table.insert(sequence, {kind="empty", duration=10})
    end
    sequence_index = math.min(sequence_index, #sequence)
    sequence_started = sys.now()
end

local function load_poster(filename)
    if not filename or posters[filename] then return end
    if CONTENTS[filename] then
        posters[filename] = resource.load_image(filename)
    end
end

local function load_qr(filename)
    if not filename or qrs[filename] then return end
    if CONTENTS[filename] then
        qrs[filename] = resource.load_image(filename, false, true)
    end
end

util.json_watch("config.json", function(updated)
    config = updated
    config.movie_duration = math.max(2, tonumber(config.movie_duration) or 12)
    config.child_duration = math.max(2, tonumber(config.child_duration) or 15)
    rebuild_sequence()
end)

util.json_watch("catalog.json", function(catalog)
    movies = catalog.movies or {}
    for _, movie in ipairs(movies) do
        load_poster(movie.poster_file)
        load_qr(movie.qr_file)
    end
    rebuild_sequence()
end)

node.event("content_update", function(filename, file)
    if filename:match("^poster%-.+%.%a+$") then
        if posters[filename] then posters[filename]:dispose() end
        posters[filename] = resource.load_image(file)
    elseif filename:match("^qr%-.+%.png$") then
        if qrs[filename] then qrs[filename]:dispose() end
        qrs[filename] = resource.load_image(file, false, true)
    end
end)

node.event("content_remove", function(filename)
    if posters[filename] then
        posters[filename]:dispose()
        posters[filename] = nil
    end
    if qrs[filename] then
        qrs[filename]:dispose()
        qrs[filename] = nil
    end
end)

node.event("child_add", rebuild_sequence)
node.event("child_remove", rebuild_sequence)

local function text_width_limited(text, x, y, size, max_width, r, g, b, a)
    text = tostring(text or "")
    local current = ""
    local line = 0
    for word in text:gmatch("%S+") do
        local candidate = current == "" and word or current .. " " .. word
        if font:width(candidate, size) > max_width and current ~= "" then
            font:write(x, y + line * size * 1.18, current, size, r, g, b, a)
            line = line + 1
            current = word
            if line >= 3 then break end
        else
            current = candidate
        end
    end
    if current ~= "" and line < 3 then
        font:write(x, y + line * size * 1.18, current, size, r, g, b, a)
    end
end

local function draw_movie(movie, alpha)
    local width, height = NATIVE_WIDTH, NATIVE_HEIGHT
    local accent = movie.status == "coming_soon" and {0.95, 0.55, 0.18} or (movie.status == "starts_tomorrow" and {0.98, 0.78, 0.20} or {0.15, 0.78, 0.72})
    gl.clear(0.025, 0.035, 0.06, 1)
    local poster = movie.poster_file and posters[movie.poster_file]
    local poster_width = width * 0.36
    if poster then
        poster:draw(0, 0, poster_width, height, alpha)
    else
        gl.color(0.08, 0.11, 0.16, alpha)
        util.draw_correct(placeholder, 0, 0, poster_width, height)
        gl.color(1, 1, 1, 1)
    end
    gl.color(accent[1], accent[2], accent[3], alpha)
    gl.rect(poster_width, 0, poster_width + 12, height)
    gl.color(1, 1, 1, 1)
    local x = poster_width + width * 0.055
    local label = movie.status == "coming_soon" and "COMING SOON" or (movie.status == "starts_tomorrow" and "STARTS TOMORROW" or "NOW SHOWING")
    font:write(x, height * 0.13, label, height * 0.045, accent[1], accent[2], accent[3], alpha)
    text_width_limited(movie.title, x, height * 0.23, height * 0.085, width - x - 60, 1, 1, 1, alpha)
    local details = {}
    if movie.rating then table.insert(details, movie.rating) end
    if movie.runtime then table.insert(details, tostring(movie.runtime) .. " min") end
    if movie.auditorium then table.insert(details, movie.auditorium) end
    font:write(x, height * 0.54, table.concat(details, "   •   "), height * 0.035, 0.72, 0.77, 0.84, alpha)
    local times = table.concat(movie.showtimes or {}, "     ")
    if times ~= "" then
        font:write(x, height * 0.67, times, height * 0.047, 1, 1, 1, alpha)
    elseif movie.opens then
        font:write(x, height * 0.67, "Opens " .. tostring(movie.opens), height * 0.047, 1, 1, 1, alpha)
    end
    font:write(x, height * 0.89, config.venue_name or "", height * 0.028, 0.55, 0.61, 0.7, alpha)
    local qr = movie.qr_file and qrs[movie.qr_file]
    if qr and movie.ticket_url then
        local qr_size = math.min(width, height) * 0.19
        local margin = height * 0.035
        local x2 = width - margin
        local y2 = height - margin
        gl.color(1, 1, 1, alpha)
        gl.rect(x2 - qr_size - 12, y2 - qr_size - 12, x2 + 12, y2 + 12)
        gl.color(1, 1, 1, 1)
        qr:draw(x2 - qr_size, y2 - qr_size, x2, y2, alpha)
        font:write(x2 - qr_size, y2 - qr_size - height * 0.045, "SCAN FOR TICKETS", height * 0.025, 1, 1, 1, alpha)
    end
end

local function draw_empty()
    gl.clear(0.025, 0.035, 0.06, 1)
    font:write(NATIVE_WIDTH * 0.08, NATIVE_HEIGHT * 0.40, config.venue_name or "Cinema Showcase", NATIVE_HEIGHT * 0.09, 1, 1, 1, 1)
    font:write(NATIVE_WIDTH * 0.08, NATIVE_HEIGHT * 0.55, "Waiting for schedule content", NATIVE_HEIGHT * 0.04, 0.55, 0.61, 0.7, 1)
end

function node.render()
    local item = sequence[sequence_index]
    if not item then rebuild_sequence(); item = sequence[1] end
    local elapsed = sys.now() - sequence_started
    if elapsed >= (item.duration or 10) then
        sequence_index = sequence_index % #sequence + 1
        sequence_started = sys.now()
        item = sequence[sequence_index]
        elapsed = 0
    end
    local fade = math.min(1, elapsed / 0.5)
    if item.kind == "movie" then
        draw_movie(item.movie, fade)
    elseif item.kind == "child" then
        gl.clear(0, 0, 0, 1)
        local rendered = resource.render_child(item.name)
        rendered:draw(0, 0, NATIVE_WIDTH, NATIVE_HEIGHT, fade)
        rendered:dispose()
    else
        draw_empty()
    end
    if not connection_ok then
        local status, iw, ih = offline_logo:state()
        if status == "loaded" and iw and ih and iw > 0 and ih > 0 then
            local size = math.min(NATIVE_WIDTH, NATIVE_HEIGHT)
            local h = size * 0.055
            local w = h * iw / ih
            local margin = size * 0.012
            offline_logo:draw(margin, NATIVE_HEIGHT-margin-h, margin+w, NATIVE_HEIGHT-margin, 0.88)
        end
    end
end
