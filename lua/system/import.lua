-- Copyright © 2005 Gas Powered Games, Inc.  All rights reserved.
--
-- Implement import()

-- note that actual modules cannot upvalued because upvalues are not reset when we load a save file
local FileCollapsePath = FileCollapsePath
local doscript = doscript
local pcall = pcall
local setmetatable = setmetatable

local LOG = LOG
local SPEW = SPEW
local WARN = WARN
local error = error

--- Table of all loaded modules, indexed by name.
__modules = {}

--- Common metatable used by all modules, which forwards global references to _G
---@class Module
---@field __moduleinfo ModuleInfo
__module_metatable = {
    __index = _G
}

---@class ModuleInfo
---@field name string
---@field used_by table<string, true>
---@field track_imports boolean

-- these values can be adjusted by hooking into this file
local informDevOfLoad = false

--- The global import function used to keep track of modules
---@param name FileName path to the module to load
---@return Module
function import(name)
    local modules = __modules -- global to local

    -- attempt to find the module without lowering the string
    local existing = modules[name]
    if existing then
        return existing
    end

    -- caching: if it exists then we return the previous version
    name = name:lower()
    existing = modules[name]
    if existing then
        return existing
    end

    -- inform the devs that we're loading this module for the first time
    if informDevOfLoad then
        SPEW("Loading module '", name, "'")
    end

    ---@type ModuleInfo
    local moduleinfo = {
        name = name,
        used_by = {},
        track_imports = true,
    }

    -- set up an environment for the new module
    ---@type Module
    local module
    module = {
        __moduleinfo = moduleinfo,

        -- Define a new 'import' function customized for the module, to track import dependencies
        import = function(name2)
            if name2:sub(1, 1) != '/' then
                name2 = FileCollapsePath(name .. '/../' .. name2)
            end
            local module2 = import(name2) -- this will use the global import
            if __modules[name].__moduleinfo.track_imports then
                module2.__moduleinfo.used_by[name] = true
            end
            return module2
        end,
    }

    -- set the meta table so that if it can't find an index it searches in _G
    setmetatable(module, __module_metatable)

    -- add ourselves to prevent loops
    modules[name] = module

    -- try to add content to the environment
    local ok, msg = pcall(doscript, name, module)
    if not ok then
        -- we failed: report back
        modules[name] = nil
        WARN(msg)
        error("Error importing '" .. name .. "'", 2)
    end

    -- Once we've imported successfully, stop tracking dependencies. This means that importing from
    -- within a function will not create a dependency, which is usually what you want. (You can
    -- explicitly set __moduleinfo.track_imports = true to switch tracking back on.)
    moduleinfo.track_imports = false
    return module
end


-- Clear out a module from the table of loaded modules, so that on the next import attempt it will
-- get reloaded from scratch
function dirty_module(name, why)
    local modules = __modules
    local module = modules[name]
    if module then
        if why then LOG("Module '", name, "' changed on disk") end
        LOG("  marking '", name, "' for reload")
        modules[name] = nil
        local deps = module.__moduleinfo.used_by
        if deps then
            for k, _ in deps do
                dirty_module(k)
            end
        end
    end
end

table.insert(__diskwatch, dirty_module)
