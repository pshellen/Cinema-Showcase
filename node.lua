gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local font = resource.load_font("font.ttf")
local placeholder = resource.load_image("poster-placeholder.png")
local white = resource.create_colored_texture(1, 1, 1, 1)
local status_bars = {
    now_showing = resource.create_colored_texture(0.15, 0.78, 0.72, 1),
    leaving_soon = resource.create_colored_texture(0.92, 0.30, 0.32, 1),
    starts_tomorrow = resource.create_colored_texture(0.98, 0.78, 0.20, 1),
    coming_soon = resource.create_colored_texture(0.95, 0.55, 0.18, 1),
}
local offline_logo = resource.load_image("offline-logo.png")
local connection_ok = true
util.json_watch("connection.json", function(state)
    connection_ok = state.ok ~= false
end)
local config = {
    venue_name = "Our Cinema",
    movie_duration = 12,
    interstitial_playlist = {},
    additional_playlists = {},
    show_coming_soon = true,
}
local movies = {}
local posters = {}
local qrs = {}
local media_images = {}
local active_video = nil
local active_video_name = nil
local sequence = {}
local sequence_signature = ""
local sequence_index = 1
local sequence_started = sys.now()
local screen_transform = util.screen_transform(0)
local canvas_width = NATIVE_WIDTH
local canvas_height = NATIVE_HEIGHT

local function schedule_is_active(item)
    local schedule = item.schedule
    if schedule == nil or schedule == "always" then
        return true
    elseif schedule == "never" then
        return false
    end
    if type(schedule) == "number" and config.__schedules and config.__schedules.expanded then
        schedule = config.__schedules.expanded[schedule + 1]
    end
    if type(schedule) ~= "table" then
        return true
    end
    local now = os.time()
    if now < 10000000 then return false end
    for _, range in ipairs(schedule) do
        local starts, duration = range[1], range[2]
        if starts and duration and starts <= now and now < starts + duration then
            return true
        end
    end
    return false
end

local function playlist_media()
    local result = {}
    local sources = {config.interstitial_playlist or {}}
    for _, source in ipairs(config.additional_playlists or {}) do
        table.insert(sources, source.playlist or {})
    end
    local widest = 0
    for _, source in ipairs(sources) do
        widest = math.max(widest, #source)
    end
    for index = 1, widest do
        for _, source in ipairs(sources) do
            local item = source[index]
            if item then
                local asset = item.asset or item.file
                if asset and asset.asset_name and schedule_is_active(item) then
                    local duration = tonumber(item.duration) or 0
                    if duration <= 0 and asset.metadata then
                        duration = tonumber(asset.metadata.duration) or 0
                    end
                    table.insert(result, {
                        kind = "media",
                        asset = asset,
                        duration = math.max(2, duration > 0 and duration or 10),
                    })
                end
            end
        end
    end
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
    local interstitials = playlist_media()
    local widest = math.max(#now_showing, #starts_tomorrow, config.show_coming_soon and #coming_soon or 0, #interstitials)
    for index = 1, widest do
        if now_showing[index] then
            table.insert(sequence, {kind="movie", movie=now_showing[index], duration=config.movie_duration})
        end
        if interstitials[index] then
            table.insert(sequence, interstitials[index])
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
    local signature_parts = {}
    for _, item in ipairs(sequence) do
        if item.kind == "movie" then
            table.insert(signature_parts, table.concat({
                "movie", item.movie.title or "", item.movie.status or "", tostring(item.duration)
            }, ":"))
        elseif item.kind == "media" then
            table.insert(signature_parts, table.concat({
                "media", item.asset.asset_name or "", tostring(item.duration)
            }, ":"))
        else
            table.insert(signature_parts, "empty")
        end
    end
    local updated_signature = table.concat(signature_parts, "|")
    if updated_signature ~= sequence_signature then
        sequence_index = 1
        sequence_started = sys.now()
        sequence_signature = updated_signature
    else
        sequence_index = math.min(sequence_index, #sequence)
    end
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

local function load_media_image(asset)
    if asset and asset.type == "image" and asset.asset_name and not media_images[asset.asset_name] then
        media_images[asset.asset_name] = resource.load_image(asset.asset_name)
    end
end

local function load_playlist_images(playlist)
    for _, item in ipairs(playlist or {}) do
        load_media_image(item.asset or item.file)
    end
end

util.json_watch("config.json", function(updated)
    config = updated
    local rotation = tonumber(config.rotation) or 0
    if rotation ~= 0 and rotation ~= 90 and rotation ~= 180 and rotation ~= 270 then
        rotation = 0
    end
    screen_transform = util.screen_transform(rotation)
    if rotation == 90 or rotation == 270 then
        canvas_width = NATIVE_HEIGHT
        canvas_height = NATIVE_WIDTH
    else
        canvas_width = NATIVE_WIDTH
        canvas_height = NATIVE_HEIGHT
    end
    config.movie_duration = math.max(2, tonumber(config.movie_duration) or 12)
    load_playlist_images(config.interstitial_playlist)
    for _, source in ipairs(config.additional_playlists or {}) do
        load_playlist_images(source.playlist)
    end
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
    elseif media_images[filename] then
        media_images[filename]:dispose()
        media_images[filename] = resource.load_image(file)
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
    if media_images[filename] then
        media_images[filename]:dispose()
        media_images[filename] = nil
    end
    if active_video_name == filename and active_video then
        active_video:dispose()
        active_video = nil
        active_video_name = nil
    end
end)

if util.set_interval then
    util.set_interval(60, rebuild_sequence)
end

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
    local width, height = canvas_width, canvas_height
    local footer = height * 0.84
    local margin = width * 0.04
    local accent = movie.status == "coming_soon" and {0.95, 0.55, 0.18} or (movie.status == "starts_tomorrow" and {0.98, 0.78, 0.20} or (movie.status == "leaving_soon" and {0.92, 0.30, 0.32} or {0.15, 0.78, 0.72}))
    gl.clear(0.025, 0.035, 0.06, 1)
    local poster = movie.poster_file and posters[movie.poster_file]
    if poster and poster:state() == "loaded" then
        util.draw_correct(poster, 0, 0, width, footer, alpha)
    else
        -- Keep missing artwork visible and identifiable instead of a blank screen.
        text_width_limited(movie.title or "Cinema Showcase", margin, height * 0.34, width * 0.07, width - 2 * margin, 1, 1, 1, alpha)
        font:write(margin, height * 0.55, "Poster unavailable", width * 0.035, 0.72, 0.77, 0.84, alpha)
    end
    local bar = status_bars[movie.status] or status_bars.now_showing
    bar:draw(0, footer, width, footer + height * 0.004, alpha)
    local qr = movie.qr_file and qrs[movie.qr_file]
    local has_qr = config.show_qr_codes ~= false and qr and movie.ticket_url and qr:state() == "loaded"
    local qr_size = math.min(width * 0.17, height * 0.10)
    local qr_x = width - margin - qr_size
    local label = movie.status == "coming_soon" and "COMING SOON" or (movie.status == "starts_tomorrow" and "STARTS TOMORROW" or (movie.status == "leaving_soon" and "CATCH IT ON THE BIG SCREEN NOW!" or "NOW SHOWING"))
    local max_label = has_qr and (qr_x - margin * 2) or (width - margin * 2)
    local size = width * 0.047
    size = math.min(size, size * max_label / math.max(1, font:width(label, size)))
    font:write(margin, footer + height * 0.04, label, size, accent[1], accent[2], accent[3], alpha)
    if has_qr then
        local caption = "SCAN FOR TICKETS"
        local caption_size = width * 0.024
        caption_size = math.min(caption_size, caption_size * qr_size / math.max(1, font:width(caption, caption_size)))
        local caption_y = footer + height * 0.018
        local qr_y = caption_y + caption_size * 1.4
        white:draw(qr_x, qr_y, qr_x + qr_size, qr_y + qr_size, alpha)
        qr:draw(qr_x, qr_y, qr_x + qr_size, qr_y + qr_size, alpha)
        font:write(qr_x, caption_y, caption, caption_size, 1, 1, 1, alpha)
    end
end

local function draw_empty()
    gl.clear(0.025, 0.035, 0.06, 1)
    font:write(canvas_width * 0.08, canvas_height * 0.40, config.venue_name or "Cinema Showcase", canvas_height * 0.09, 1, 1, 1, 1)
    font:write(canvas_width * 0.08, canvas_height * 0.55, "Waiting for schedule content", canvas_height * 0.04, 0.55, 0.61, 0.7, 1)
end

local function stop_video()
    if active_video then
        active_video:dispose()
        active_video = nil
        active_video_name = nil
    end
end

local function draw_playlist_resource(res, alpha)
    if config.playlist_scaling == "fill" then
        util.draw_correct(res, 0, 0, canvas_width, canvas_height, alpha)
        return
    end
    local _, media_width, media_height = res:state()
    if not media_width or not media_height or media_width <= 0 or media_height <= 0 then
        return
    end
    local scale = math.min(canvas_width / media_width, canvas_height / media_height)
    local draw_width = media_width * scale
    local draw_height = media_height * scale
    local x1 = (canvas_width - draw_width) / 2
    local y1 = (canvas_height - draw_height) / 2
    res:draw(x1, y1, x1 + draw_width, y1 + draw_height, alpha)
end

local function draw_media(item, alpha)
    local asset = item.asset or {}
    local filename = asset.asset_name
    gl.clear(0, 0, 0, 1)
    if asset.type == "video" and filename then
        if active_video_name ~= filename then
            stop_video()
            active_video = resource.load_video{
                file = resource.open_file(filename),
                audio = config.playlist_audio == true,
                looped = true,
            }
            active_video_name = filename
        end
        if active_video then
            draw_playlist_resource(active_video, alpha)
        end
    elseif asset.type == "image" and filename then
        stop_video()
        load_media_image(asset)
        local image = media_images[filename]
        if image and image:state() == "loaded" then
            draw_playlist_resource(image, alpha)
        end
    else
        stop_video()
    end
end

function node.render()
    screen_transform()
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
        stop_video()
        draw_movie(item.movie, fade)
    elseif item.kind == "media" then
        draw_media(item, fade)
    else
        stop_video()
        draw_empty()
    end
    if not connection_ok then
        local status, iw, ih = offline_logo:state()
        if status == "loaded" and iw and ih and iw > 0 and ih > 0 then
            local size = math.min(canvas_width, canvas_height)
            local h = size * 0.055
            local w = h * iw / ih
            local margin = size * 0.012
            offline_logo:draw(margin, canvas_height-margin-h, margin+w, canvas_height-margin, 0.88)
        end
    end
end
