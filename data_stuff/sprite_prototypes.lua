-- Constants
local sprite_goal_size = 512 -- Sprites that have a different size will be scaled to this size.
local use_blacklist = not settings.startup["visible-planets-override-show-planets"].value -- If true, override and *DON'T* use blacklist. I got it backwards.
local use_planetslib_compat = settings.startup["visible-planets-planetslib-compat"].value -- If true, add PlanetsLib layers to planets and moons.
local planetslib_scale = settings.startup["visible-planets-planetslib-scale"].value
local planetslib_x = settings.startup["visible-planets-planetslib-x"].value
local planetslib_y = settings.startup["visible-planets-planetslib-y"].value
local planetslib_tint = settings.startup["visible-planets-planetslib-tint"].value

-- Create SpritePrototype for each planet
local planet_overrides = vp_get_planet_overrides() -- Defined in separate file
local function create_planet_sprite_prototype(planet)
    local icon = planet.starmap_icon
    local icon_size = planet.starmap_icon_size
    local scale_override = 1; -- Default change nothing.
    local overrides = planet_overrides[planet.name]
    if overrides then -- Handle overrides, if any.
        if overrides.filepath then
            log("Overriding filepath for " .. planet.name .. " to " .. overrides.filepath)
            icon = overrides.filepath
            icon_size = overrides.size
        end
        if overrides.scale then
            log("Overriding scale for " .. planet.name .. " to " .. overrides.scale)
            scale_override = overrides.scale
        end
    end
    if not icon then
        log("Skipping visible-planets for " .. planet.name .. "; Starmap icon missing.")
        return
    end
    if not icon_size then
        log("Skipping visible-planets for " .. planet.name .. "; Starmap icon size missing.")
        return
    end
    -- Create SpritePrototype
    log("Adding visible-planets for " .. planet.name)
    local name = "visible-planets-" .. planet.name
    local sprite_prototype = {
        type = "sprite",
        name = name,
        layers = {}, -- Added below
    }
    local main_layer = { -- Large planet render
        filename = icon,
        size = icon_size,
        scale = scale_override * (sprite_goal_size/icon_size), -- Scale down large sprites. Shouldn't reduce resolution.
        flags = { "linear-minification", "linear-magnification" }, -- Prevent pixels showing.
    }

    if use_planetslib_compat and mods["PlanetsLib"] then
        local orbit = planet.orbit
        if orbit and orbit.parent and orbit.parent.type and orbit.parent.type == "planet" and orbit.parent.name then
            local parent = data.raw["planet"][orbit.parent.name]
            if parent.starmap_icon == nil then
                log("Skipping PlanetsLib compat for moon " .. planet.name .. " orbiting " .. parent.name .. "; Parent starmap icon missing.")
            else
                log("Adding PlanetsLib compat for moon " .. planet.name .. " orbiting " .. parent.name)
                table.insert(sprite_prototype.layers, {
                    filename = parent.starmap_icon,
                    size = parent.starmap_icon_size,
                    scale = 0.2 * (sprite_goal_size/parent.starmap_icon_size),
                    flags = { "linear-minification", "linear-magnification" },
                    tint = { r = 0.5, g = 0.5, b = 0.5, a = 1 }, -- Darken
                })
            end
        end
        -- Find all children:
        for _, child in pairs(data.raw["planet"]) do
            if child.orbit and child.orbit.parent and child.orbit.parent.type and child.orbit.parent.type == "planet" and child.orbit.parent.name == planet.name then
                if child.starmap_icon == nil then
                    log("Skipping PlanetsLib compat for " .. planet.name .. " with moon " .. child.name .. "; Moon starmap icon missing.")
                else
                    log("Adding PlanetsLib compat for " .. planet.name .. " with moon " .. child.name)
                    table.insert(sprite_prototype.layers, {
                        filename = child.starmap_icon,
                        size = child.starmap_icon_size,
                        scale = planetslib_scale * (sprite_goal_size/child.starmap_icon_size),
                        flags = { "linear-minification", "linear-magnification" },
                        tint = { r = planetslib_tint, g = planetslib_tint, b = planetslib_tint, a = 1 }, -- Darken
                    })
                end
            end
        end
        -- Arrange bodies around main body.
        local num_children = #sprite_prototype.layers
        local shift_x = planetslib_x -- Initial shift, top left corner.
        local shift_y = planetslib_y
        for _,child in pairs(sprite_prototype.layers) do -- Rotate background bodies about main body.
            child.shift = {shift_x, shift_y}
            local shift_x_old = shift_x
            shift_x = (shift_x_old * math.cos(math.pi/num_children)) - (shift_y * math.sin(math.pi/num_children))
            shift_y = (shift_x_old * math.sin(math.pi/num_children)) - (shift_y * math.cos(math.pi/num_children))
        end
    end

    -- Add main planet as top layer
    table.insert(sprite_prototype.layers, main_layer)

    if settings.startup["visible-planets-enable-blur"].value == true then
        --Apply blur effect to planet by layering many nearly-transparent copies of sprites shifted slightly from primary sprites.
        --TODO: Add settings to modify blur intensity that aren't difficult to understand.
        local blur_count = 8
        local blur_shift_max = 0.25
        local blur_shift_start = 0.05
        local blur_shift_steps= 0.05
        local brightness_modifier = 1
        local sprites_list = table.deepcopy(sprite_prototype.layers)
        sprite_prototype.layers = {}
        --local shift_x = blur_shift -- Initial shift, top left corner.
        --local shift_y = blur_shift
        for _,entry in pairs(sprites_list) do
            local copy = table.deepcopy(entry)
            copy.tint = {0,0,0} --black mask to ensure that none of the sprite is transparent where it shouldn't be
            table.insert(sprite_prototype.layers,copy)
        end
        local n = blur_count*(1+(blur_shift_max-blur_shift_start)/blur_shift_steps)
        for i = 1,blur_count do
            for blur_shift = blur_shift_start,blur_shift_max,blur_shift_steps do
                local shift_x = blur_shift * math.cos(i*2*math.pi/blur_count)
                local shift_y = blur_shift * math.sin(i*2*math.pi/blur_count)
                for _,child_original in pairs(sprites_list) do -- Rotate background bodies about main body.
                    local child = table.deepcopy(child_original)
                    if child.shift then
                        if not child.shift[1] then
                            child.shift[1] = shift_x
                        else
                            child.shift[1] = child.shift[1] + shift_x
                        end
                        if not child.shift[2] then
                            child.shift[2] = shift_y
                        else
                            child.shift[2] = child.shift[2] + shift_y
                        end
                    else
                        child.shift = {shift_x, shift_y}
                    end
                        --assert(1/n > 0.01, "".. tostring(1/n))
                        child.tint = {brightness_modifier/n,brightness_modifier/n,brightness_modifier/n,brightness_modifier/n}
                        child.blend_mode = "multiplicative-with-alpha"
                        table.insert(sprite_prototype.layers,child)
                        
                    end
            end
            
        end
    end
    

    data:extend{sprite_prototype}
end

-- Create SpritePrototypes for each planet not in the blacklist
local planet_blacklist = vp_get_planet_blacklist() -- Defined in separate file
local function create_for_each(planets)
    for _, planet in pairs(planets) do
        for _, blacklist in pairs(planet_blacklist) do
            if use_blacklist and planet.name == blacklist then
                log("Skipping visible-planets for " .. planet.name .. "; Blacklisted.")
                goto blacklist_skip -- goto feels so *wrong* though.
            end
        end
        create_planet_sprite_prototype(planet)
        ::blacklist_skip::
    end
end
create_for_each(data.raw["planet"])
create_for_each(data.raw["space-location"])