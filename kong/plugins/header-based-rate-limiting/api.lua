local crud = require "kong.api.crud_helpers"
local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"
local utils = require "kong.tools.utils"
local base64 = require "base64"

local function decode_header_composition(header_based_rate_limit)
    local result = {}

    for key, value in pairs(header_based_rate_limit) do
        if key == "header_composition" then
            local individual_headers = utils.split(header_based_rate_limit.header_composition, ":")

            local decoded_headers = {}

            for _, header in ipairs(individual_headers) do
                table.insert(decoded_headers, base64.decode(header))
            end

            result["header_composition"] = decoded_headers
        else
            result[key] = value
        end
    end

    return result
end

local function encode_header_composition(header_based_rate_limit)
    local result = {}

    for key, value in pairs(header_based_rate_limit) do
        if key == "header_composition" then
            local encoded_headers = {}

            for _, header in ipairs(value) do
                table.insert(encoded_headers, base64.encode(header))
            end

            result["header_composition"] = table.concat(encoded_headers, ":")
        else
            result[key] = value
        end
    end

    return result
end

return {
    ["/plugins/:plugin_id/redis-ping"] = {
        before = function(self, dao_factory, helpers)
            crud.find_plugin_by_filter(self, dao_factory, {
                id = self.params.plugin_id
            }, helpers)
        end,

        GET = function(self, dao_factory, helpers)
            if self.plugin.name ~= "header-based-rate-limiting" then
                return helpers.responses.send_HTTP_BAD_REQUEST("Plugin is not of type header-based-rate-limiting")
            end

            local success, redis_or_error = pcall(RedisFactory.create, self.plugin.config.redis)

            if not success then
                return helpers.responses.send_HTTP_BAD_REQUEST(redis_or_error.message)
            end

            local result = redis_or_error:ping()

            helpers.responses.send_HTTP_OK(result)
        end
    },

    ['/header-based-rate-limits'] = {
        POST = function(self, dao_factory, helpers)
            local params_with_encoded_header_composition = encode_header_composition(self.params)
            crud.post(params_with_encoded_header_composition, dao_factory.header_based_rate_limits, decode_header_composition)
        end,

        GET = function(self, dao_factory, helpers)
            crud.paginated_set(self, dao_factory.header_based_rate_limits, decode_header_composition)
        end
    }
}
