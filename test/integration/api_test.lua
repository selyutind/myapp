local t = require('luatest')
local g = t.group('integration_api')

local helper = require('test.helper')
local cluster = helper.cluster

g.before_all = function()
    g.cluster = helper.cluster
    g.cluster:start()
end

g.after_all = function()
    helper.stop_cluster(g.cluster)
end

g.before_each = function()
    -- helper.truncate_space_on_cluster(g.cluster, 'Set your space name here')
end

local deepcopy = require('table').deepcopy

local test_city = {
    city_id = 1,
    name = 'Moscow',
    country = 'Russia',
    airport = 'DME'
}

g.test_sample = function()
    local server = cluster.main_server
    local response = server:http_request('post', '/admin/api', {json = {query = '{ cluster { self { alias } } }'}})
    t.assert_equals(response.json, {data = { cluster = { self = { alias = 'api' } } }})
    t.assert_equals(server.net_box:eval('return box.cfg.memtx_dir'), server.workdir)
end

g.test_metrics = function()
    local server = cluster.main_server
    local response = server:http_request('get', '/metrics')
    t.assert_equals(response.status, 200)
    t.assert_equals(response.reason, "Ok")
end

g.test_on_get_not_found = function()
    helper.assert_http_json_request('get', '/city/1', {body = {info = "city not found"}, status = 404})
end

g.test_on_post_ok = function ()
    helper.assert_http_json_request('post', '/city', {body = {info = "Successfully created"}, status=201})
end

g.test_on_post_conflict = function()
    helper.assert_http_json_request('post', '/city', {body = {info = "city already exist"}, status=409})
end

g.test_on_get_ok = function ()
    helper.assert_http_json_request('get', '/city/1', {body = test_city, status = 200})
end

g.test_on_get_unauthorized = function()
    helper.assert_http_json_request('get', '/city/1', {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_put_not_found = function()
    helper.assert_http_json_request('put', '/city/2', {changes = {msgs_count = 115}},
    {body = {info = "city not found"}, status = 404})
end

g.test_on_put_unauthorized = function()
    helper.assert_http_json_request('put', '/city/1', {changes = {msgs_count = 115}},
    {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_put_ok = function()
    local changed_city = deepcopy(test_city)
    changed_city.msgs_count = 115
    helper.assert_http_json_request('put', '/city/1', {changes = {msgs_count = 115}}, {body = changed_city, status = 200})
end

g.test_on_delete_not_found = function ()
    helper.assert_http_json_request('delete', '/city/2', {body = {info = "city not found"}, status = 404})
end

g.test_on_delete_unauthorized = function ()
    helper.assert_http_json_request('delete', '/city/1', {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_delete_ok = function()
    helper.assert_http_json_request('delete', '/city/1', {body = {info = "Deleted"}, status = 200})
end
