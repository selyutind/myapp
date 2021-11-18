-- модуль проверки аргументов в функциях
local checks = require('checks')
local errors = require('errors')
-- класс ошибок дуступа к хранилищу
local err_storage = errors.new_class("Storage error")

-- Функция преобразующая кортеж в таблицу согласно схеме хранения
local function tuple_to_table(format, tuple)
    local map = {}
    for i, v in ipairs(format) do
        map[v.name] = tuple[i]
    end
    return map
end

-- Функция заполняющая недостающие поля таблицы minor из таблицы major
local function complete_table(major, minor)
    for k, v in pairs(major) do
        if minor[k] == nil then
            minor[k] = v
        end
    end
end

local function init_space()
    local city = box.schema.space.create(
        'city', -- имя спейса для хранения городов
        {
            -- формат хранимых кортежей
            format = {
                {'city_id', 'unsigned'},
                {'bucket_id', 'unsigned'},
                {'name', 'string'},
                {'country', 'string'},
                {'airport', 'string'}
            },

            -- создадим спейс, только если его не было
            if_not_exists = true,
        }
    )

    -- создадим индекс по id
    city:create_index('city_id', {
        parts = {'city_id'},
        if_not_exists = true,
    })

    city:create_index('bucket_id', {
        parts = {'bucket_id'},
        unique = false,
        if_not_exists = true,
    })
end

local function city_add(city)
    checks('table')

    -- Проверяем существование города с таким id
    local exist = box.space.city:get(city.city_id)
    if exist ~= nil then
        return {ok = false, error = err_storage:new("City already exist")}
    end

    box.space.city:insert(box.space.city:frommap(city))

    return {ok = true, error = nil}
end

local function city_update(id, changes)
    checks('number', 'table')

    local exists = box.space.city:get(id)

    if exists == nil then
        return {city = nil, error = err_storage:new("City not found")}
    end

    exists = tuple_to_table(box.space.city:format(), exists)

    complete_table(exists, changes)

    box.space.city:replace(box.space.city:frommap(changes))

    return {city = changes, error = nil}
end

local function city_get(id)
    checks('number')

    local city = box.space.city:get(id)
    if city == nil then
        return {city = nil, error = err_storage:new("City not found")}
    end

    city = tuple_to_table(box.space.city:format(), city)

    return {city = city, error = nil}
end

local function city_delete(id)
    checks('number')

    local exists = box.space.city:get(id)
    if exists == nil then
        return {ok = false, error = err_storage:new("City not found")}
    end

    box.space.city:delete(id)
    return {ok = true, error = nil}
end

local function init(opts)
    if opts.is_master then
        init_space()

        box.schema.func.create('city_add', {if_not_exists = true})
        box.schema.func.create('city_get', {if_not_exists = true})
        box.schema.func.create('city_update', {if_not_exists = true})
        box.schema.func.create('city_delete', {if_not_exists = true})
    end

    rawset(_G, 'city_add', city_add)
    rawset(_G, 'city_get', city_get)
    rawset(_G, 'city_update', city_update)
    rawset(_G, 'city_delete', city_delete)

    return true
end

return {
    role_name = 'storage',
    init = init,
    utils = {
        city_add = city_add,
        city_update = city_update,
        city_get = city_get,
        city_delete = city_delete,
    },
    dependencies = {
        'cartridge.roles.vshard-storage'
    }
}
