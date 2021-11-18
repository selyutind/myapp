local cartridge = require('cartridge')
local errors = require('errors')
local log = require('log')

local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")

local function json_response(req, json, status)
    local resp = req:render({json = json})
    resp.status = status
    return resp
end

local function internal_error_response(req, error)
    local resp = json_response(req, {
        info = "Internal error",
        error = error
    }, 500)
    return resp
end

local function city_not_found_response(req)
    local resp = json_response(req, {
        info = "City not found"
    }, 404)
    return resp
end

local function city_conflict_response(req)
    local resp = json_response(req, {
        info = "City already exist"
    }, 409)
    return resp
end

local function city_unauthorized(req)
    local resp = json_response(req, {
        info = "Unauthorized"
    }, 401)
    return resp
end

local function storage_error_response(req, error)
    if error.err == "City already exist" then
        return city_conflict_response(req)
    elseif error.err == "City not found" then
        return city_not_found_response(req)
    elseif error.err == "Unauthorized" then
        return city_unauthorized(req)
    else
        return internal_error_response(req, error)
    end
end

local function http_city_add(req)
    local city = req:json()

    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id(city.city_id)
    city.bucket_id = bucket_id

    local resp, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'write',
        'city_add',
        {city}
    )

    if error then
        return internal_error_response(req, error)
    end
    if resp.error then
        return storage_error_response(req, resp.error)
    end

    return json_response(req, {info = "Successfully created"}, 201)
end

local function http_city_update(req)
    local city_id = tonumber(req:stash('city_id'))
    local data = req:json()
    local changes = data.changes

    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id(city_id)

    local resp, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'read',
        'city_update',
        {city_id, changes}
    )

    if error then
        return internal_error_response(req,error)
    end
    if resp.error then
        return storage_error_response(req, resp.error)
    end

    return json_response(req, resp.city, 200)
end

local function http_city_get(req)
    local city_id = tonumber(req:stash('city'))
    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id(city_id)

    local resp, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'read',
        'city_get',
        {city_id}
    )

    if error then
        return internal_error_response(req, error)
    end
    if resp.error then
        return storage_error_response(req, resp.error)
    end

    return json_response(req, resp.city, 200)
end

local function http_city_delete(req)
    local city_id = tonumber(req:stash('city_id'))
    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id(city_id)

    local resp, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'write',
        'city_delete',
        {city_id}
    )

    if error then
        return internal_error_response(req, error)
    end
    if resp.error then
        return storage_error_response(req, resp.error)
    end

    return json_response(req, {info = "Deleted"}, 200)
end

local function init(opts)
    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write',
            'universe',
            nil, { if_not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, err_httpd:new("not found")
    end

    log.info("Starting httpd")
    -- Навешиваем функции-обработчики
    httpd:route(
        { path = '/city', method = 'POST', public = true },
        http_city_add
    )
    httpd:route(
        { path = '/city/:city_id', method = 'GET', public = true },
        http_city_get
    )
    httpd:route(
        { path = '/city/:city_id', method = 'PUT', public = true },
        http_city_update
    )
    httpd:route(
        {path = '/city/:city_id', method = 'DELETE', public = true},
        http_city_delete
    )

    log.info("Created httpd")
    return true
end

return {
    role_name = 'api',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-router'
    }
}
