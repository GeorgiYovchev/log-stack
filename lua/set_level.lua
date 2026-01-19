function set_level(tag, timestamp, record)
    local log_message = record["log"]
    local new_level = "info"

    if log_message then
        local lower_log = string.lower(log_message)

        if string.find(lower_log, "error") then
            new_level = "error"
        elseif string.find(lower_log, "warning") then
            new_level = "warning"
        end
    end

    record["level"] = new_level

    local time_field = "@timestamp"
    local new_timestamp = nil

    if record[time_field] then
        new_timestamp = record[time_field]
        record[time_field] = nil
    end

    local parent_key = "kubernetes"
    if record[parent_key] then
        record[parent_key]["docker_id"] = nil
        record[parent_key]["pod_ip"] = nil
        record[parent_key]["container_hash"] = nil
        record["stream"] = nil
        record["partition"] = nil
        record["offset"] = nil
        record["_p"] = nil
        record["topic"] = nil
    end

    if new_timestamp then
        return 1, new_timestamp, record
    end

    return 1, timestamp, record
end