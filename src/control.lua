script.on_init(function ()
    storage.version = 1

    ---@class TrackedRobot
    ---@field entity LuaEntity
    ---@field destroy_when_empty boolean

    ---@type table<integer, TrackedRobot>
    storage.tracked_robots = {}

    ---@type table<integer, LuaPlayer>
    storage.players_with_early_roboport = {}
end)

---@param owner LuaEntity
---@param robot LuaEntity
---@return boolean
local function is_deployed_by(owner, robot)
    return robot.logistic_network and #robot.logistic_network.cells == 1 and robot.logistic_network.cells[1].owner == owner
end

local function look_for_deployed_robots()
    for player_index, player in pairs(storage.players_with_early_roboport) do
        if not player.valid then
            storage.players_with_early_roboport[player_index] = nil
        elseif player.character then
            robots = player.character.surface.find_entities_filtered({
                position = player.character.position,
                radius = 5,
                type = "construction-robot"
            })

            for _, robot in ipairs(robots) do
                if not storage.tracked_robots[robot.unit_number] and is_deployed_by(player.character, robot) then
                    storage.tracked_robots[robot.unit_number] = {
                        entity = robot,
                        destroy_when_empty = false
                    }
                end
            end
        end
    end
end

---@param robot LuaEntity
---@param inventory defines.inventory
---@return boolean
local function robot_has_empty_inventory(robot, inventory)
    local inv = robot.get_inventory(inventory)
    if inv then
        for i=1,#inv do
            local stack = inv[i]
            if stack.count > 0 then
                return false
            end
        end
    end

    return true
end

---@param robot LuaEntity
---@return boolean
local function robot_has_empty_inventories(robot)
    return robot_has_empty_inventory(robot, defines.inventory.robot_cargo) and
        robot_has_empty_inventory(robot, defines.inventory.robot_repair)
end

---@param robot LuaEntity
local function robot_explode(robot)
    robot.surface.create_entity({
        name = "explosion",
        position = robot.position,
        force = robot.force
    })
end

local function update_tracked_robots()
    for unit_number, robot in pairs(storage.tracked_robots) do
        if not robot.entity.valid then
            storage.tracked_robots[unit_number] = nil
        else
            if robot.entity.name == "early-construction-robot" then
                robot.entity.energy = 30000

                if robot.destroy_when_empty then
                    if robot_has_empty_inventories(robot.entity) then
                        robot_explode(robot.entity)
                        robot.entity.destroy({})
                    end
                else
                    if not robot_has_empty_inventories(robot.entity) then
                        robot.destroy_when_empty = true
                    end
                end
            else
                robot.entity.energy = 0
            end
        end
    end
end

script.on_nth_tick(1, function ()
    look_for_deployed_robots()
    update_tracked_robots()
end)

---@param robot LuaEntity
---@param inventory defines.inventory
local function spill_robot_inventory(robot, inventory)
    local inv = robot.get_inventory(inventory)
    if inv then
        robot.surface.spill_inventory({
            position = robot.position,
            inventory = inv,
            allow_belts = false
        })
    end
end

---@param robot LuaEntity
local function spill_robot_inventories(robot)
    spill_robot_inventory(robot, defines.inventory.robot_cargo)
    spill_robot_inventory(robot, defines.inventory.robot_repair)
end

script.on_event(defines.events.on_worker_robot_expired, function (event)
    if event.robot.name == "early-construction-robot" then
        robot_explode(event.robot)
        spill_robot_inventories(event.robot)
    end
end)

---@param inv LuaInventory
local function remove_robot_from_inventory(inv)
    for i=1,#inv do
        local stack = inv[i]
        if stack.name == "early-construction-robot" then
            stack.clear()
        end
    end
end

script.on_event(defines.events.on_player_mined_entity, function (event)
    if storage.tracked_robots[event.entity.unit_number] then
        robot_explode(event.entity)
        remove_robot_from_inventory(event.buffer)
        storage.tracked_robots[event.entity.unit_number] = nil
    end
end, {{ filter = "name", name = "early-construction-robot" }})

---@param inv LuaInventory
---@return boolean
local function has_early_construction_armor(inv)
    for i=1,#inv do
        local stack = inv[i]
        if stack.count > 0 and
            (stack.name == "early-construction-light-armor" or
            stack.name == "early-construction-heavy-armor")
        then
            return true
        end
    end

    return false
end

script.on_event(defines.events.on_player_armor_inventory_changed, function (event)
    local player = game.players[event.player_index]
    local inv = player.get_inventory(defines.inventory.character_armor)

    if inv and has_early_construction_armor(inv) then
        storage.players_with_early_roboport[player.index] = player
    else
        storage.players_with_early_roboport[player.index] = nil
    end
end)

script.on_event(defines.events.on_player_removed, function (event)
    storage.players_with_early_roboport[event.player_index] = nil
end)

script.on_configuration_changed(function (event)
    if event.mod_startup_settings_changed or event.mod_changes["early_construction"] then
        for _, force in pairs(game.forces) do
            if force.technologies["early-construction-light-armor"].researched then
                log(("[early_construction] resetting technology effects for force %q"):format(force.name))
                force.reset_technology_effects()
            end
        end
    end
end)