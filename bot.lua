-- config
local config = {
  storage = "/tmp/zbx4tg.json",
  tmpdir = "/tmp",
  ttl_priority = 5, -- priority 5 spam every > 25 min, priority 0 > 60 min
  min_event_age = 5, -- min event age in min
  admins = { "username" },
  http = {
    zabbix = {
--     proxy = "",
--     insecure_ssl = false,
--     basic_auth_user = "",
--     basic_auth_password = "",
    },
    telegram = {
--      proxy = "http://192.168.184.28:3128",
--      insecure_ssl = true,
    },
  },
  zabbix = {
    url = "http://zabbix.url",
    user = "username",
    password = "password",
  },
  telegram = {
    token = "XXXX:XXXXXXX"
  }
}

local telegram = require("telegram")
local zabbix = require("zabbix")
local http = require("http")
local time = require("time")
local storage = require("storage")
local inspect = require("inspect")
local strings = require("strings")
local filepath = require("filepath")

-- init storage
local cache, err = storage.open(config.storage)
if err then error(err) end

-- init http clients
local tg_http_client = http.client(config.http.telegram)
local zbx_http_client = http.client(config.http.zabbix)

-- create bots
local tg = telegram.bot(config.telegram.token, tg_http_client)
local zbx = zabbix.new(config.zabbix, zbx_http_client)

-- zabbix priority map
local zabbix_priority = {}
zabbix_priority["0"] = "NOT CLASSIFIED"
zabbix_priority["1"] = "INFO"
zabbix_priority["2"] = "WARN"
zabbix_priority["3"] = "AVERAGE"
zabbix_priority["4"] = "HIGH"
zabbix_priority["5"] = "DISASTER"

-- default chat settings
local default_settings = {
  priority = "5",
  filter = ".*"
}

-- process zabbix triggers
function zabbix_triggers()
  -- get all registered chats
  local chats, found, err = cache:get("chats.registered")
  if err then error(err) end
  if not found then return end
  -- get chat settings
  local settings, found, err = cache:get("chats.settings")
  if err then error(err) end
  if not found then return end

  local response, err = zbx:request("trigger.get", {
    output = "extend", sortfield = "priority", sortorder = "DESC",
    filter = {value = 1, status = 0},
    expandData = 1, expandDescription = 1, skipDependent = 1,
    withLastEventUnacknowledged = 1, selectGroups = "extend",
    selectTriggers = "extend", selectHosts = "extend",
    selectItems = "extend", selectLastEvent = "extend",
    limit = 1000, active = 1, monitored = 1,
  })
  if err then error(err) end
  for _, chat_id in pairs(chats) do
    local min_priority = tonumber(settings[tostring(chat_id)].priority)
    for _, tr in pairs(response) do
      local tr_priority = tonumber(tr.priority)
      if tr_priority >= min_priority then
        zabbix_trigger_send(tr, chat_id)
      end
    end
  end
end

function zabbix_trigger_send(trg, chat_id)
  -- get hostname
  local hostname = ""
  if trg.hosts and trg.hosts[1] and trg.hosts[1].host then
    hostname = trg.hosts[1].host
  end
  -- get event_id
  local event_id = ""
  if trg.lastEvent then event_id = trg.lastEvent.eventid end
  -- get trigger_id
  local trigger_id = trg.triggerid
  -- get last value, value type
  local value, item_id = "", 0
  local value_type = "4" -- text
  if trg.items and trg.items[1] then
    value = trg.items[1].lastvalue
    value_type = trg.items[1].value_type
    item_id = trg.items[1].itemid
  end
  -- check if sended
  local _, found, err = cache:get("spam.event."..tostring(chat_id)..":"..tostring(event_id))
  if err then error(err) end
  if found then return end
  -- process
  local value_is_numeric = (value_type == "0" or value_type == "3")
  -- get description
  local description = trg.description
  -- get human priority
  local human_priority = "NOT CLASSIFIED"
  if zabbix_priority[trg.priority] then human_priority = zabbix_priority[trg.priority] end
  -- build reply markup
  local reply_markup = {}
  reply_markup.inline_keyboard = {
    {
      { text = "acknowledge", callback_data = "a:"..tostring(chat_id)..":"..tostring(event_id)..":"..tostring(trigger_id) },
      { text = "event details", url = config.zabbix.url.."/".."tr_events.php?triggerid="..tostring(trigger_id).."&eventid="..tostring(event_id) }
    }
  }
  -- build text
  local message_template = [[
EventID:   %s
Host:      %s
Priority:  *%s*
Desc:      `%s`
Value:     `%s`
]]
  if not(value_is_numeric) then if strings.contains(description, value) then value = "--" end end
  local message = string.format(
    message_template,
    event_id,
    hostname,
    human_priority,
    description,
    value)
  -- send message
  if value_is_numeric then
    -- download graph and sendPhoto
    local tmpfile = filepath.join(config.tmpdir, tostring(itemid).."."..tostring(time.unix())..".png")
    local err = zbx:save_graph(tonumber(item_id), tmpfile)
    if err then error(err) end
    local _, err = tg:sendPhoto({
      chat_id = tonumber(chat_id),
      caption = message,
      photo = tmpfile,
      reply_markup = reply_markup,
      parse_mode = "Markdown"
    })
    if err then error(err) end
    os.remove(tmpfile)
  else
    -- only text message
    local _, err = tg:sendMessage({
      chat_id = tonumber(chat_id),
      text = message,
      reply_markup = reply_markup,
      parse_mode = "Markdown"
    })
  end
  -- set ttl
  local ttl = (10 - (tonumber(trg.priority))*2 + 1) * 60
  ttl = ttl + math.random(100)*2
  ttl = ttl * config.ttl_priority
  local err = cache:set("spam.event."..tostring(chat_id)..":"..tostring(event_id), "done", ttl)
  if err then error(err) end
end

-- process telegram getUpdates
function telegram_updates()
  local updates, err = tg:getUpdates()
  if err then error(err) end
  for _, upd in pairs(updates) do
    if upd.callback_query then
      telegram_callback(upd)
    elseif upd.message and upd.message.entities and upd.message.entities[1] then
      if upd.message.entities[1].type == "bot_command" then
        telegram_command(upd)
      else
        print(inspect(upd))
      end
    else
      print(inspect(upd))
    end
  end
end

function telegram_callback(upd)
  local data = upd.callback_query.data
  print("process callback data: ", data)
  if strings.has_prefix(data, "p:") then
    telegram_callback_priority(upd)
  elseif strings.has_prefix(data, "a:") then
    telegram_callback_ack(upd)
  elseif strings.has_prefix(data, "c:") then
    telegram_callback_chat_status(upd)
  else
    print("unknown callback data: ", data)
  end
end

-- main functions for telegram command
function telegram_command(upd)
  local command = upd.message.text
  print("process command", command)
  if strings.has_prefix(command,     "/help") then
    telegram_command_help(upd)
  elseif strings.has_prefix(command, "/chat_id") then
    telegram_command_chat_id(upd)
  elseif strings.has_prefix(command, "/config") then
    telegram_command_config(upd)
  elseif strings.has_prefix(command, "/priority") then
    telegram_command_priority(upd)
  elseif strings.has_prefix(command, "/status") then
    telegram_command_status_chat(upd)
  end
end

function telegram_command_help(upd)
  local _, err = tg:sendMessage({
    chat_id = upd.message.chat.id,
    text = [[
/help          - this message
/chat_id       - get chat id
/config        - print bot's config
/priority      - print priority chat settings
/status        - (un)register messages in this chat
]]
  })
  if err then error(err) end
end

-- found value in list
function found_in_list(list, value)
  local found = false
  for _, v in pairs(list) do if value == v then found = true end end
  return found
end

-- check permissions, return true if ok
function is_admin(upd)
  local from = "unknown"
  if upd.message and upd.message.from and upd.message.from.username then
    from = upd.message.from.username
  else
    if upd.callback_query and upd.callback_query.from and upd.callback_query.from.username then
      from = upd.callback_query.from.username
    else
      return false
    end
  end
  if not found_in_list(config.admins, from) then
    local _, err = tg:sendMessage({
      chat_id = upd.message.chat.id,
      reply_to_message_id = upd.message.message_id,
      text = "to @"..from.. " : only admins allowed to this operation"
    })
    if err then error(err) end
    return false
  end
  return true
end

function telegram_command_chat_id(upd)
  local _, err = tg:sendMessage({
    chat_id = upd.message.chat.id,
    reply_to_message_id = upd.message.message_id,
    text = tostring(upd.message.chat.id)
  })
  if err then error(err) end
end

-- chat status
function telegram_command_status_chat(upd)
  -- get current chats and check if exists
  local chat_id = upd.message.chat.id
  local chats, found, err = cache:get("chats.registered")
  if err then error(err) end
  local chat_id = upd.message.chat.id
  local current_chat_enabled = (found and found_in_list(chats, chat_id))
  local text_enabled, callback_data_enable = "✅ enabled", "c:"..tostring(chat_id)..":enable"
  local text_disable, callback_data_disable = "disable", "c:"..tostring(chat_id)..":disable"
  if not current_chat_enabled then
    text_enabled = "enable"
    text_disable = "✅ disabled"
  end
  -- make reply_markup
  local reply_markup = {}
  reply_markup.inline_keyboard = {
    {
      { text = text_enabled, callback_data = callback_data_enable  },
      { text = text_disable, callback_data = callback_data_disable },
    }
  }
  local _, err = tg:sendMessage({
    chat_id = upd.message.chat.id,
    text = "Current chat status",
    reply_markup = reply_markup
  })
  if err then error(err) end
end

-- callback chat_status
function telegram_callback_chat_status(upd)
  if not is_admin(upd) then return end
  -- c:chat_id:(enable|disable)
  local data = upd.callback_query.data
  local tbl = strings.split(data, ":")
  local chat_id, command = tonumber(tbl[2]), tbl[3]
  local command_enable_this_chat = (command == "enable")

  local chats, found, err = cache:get("chats.registered")
  if err then error(err) end
  if (not found) and command_enable_this_chat then chats = {} end
  local current_chat_status = found_in_list(chats, chat_id)
  if not(current_chat_status == command_enable_this_chat) then
    -- process
    if command_enable_this_chat then
      -- process enable
      table.insert(chats, chat_id)
    else
      -- process disable
      local new_chats = {}
      for _, v in pairs(chats) do
        if not(v == chat_id) then table.insert(new_chats, v) end
      end
      chats = new_chats
    end
    -- update storage
    local err = cache:set("chats.registered", chats, nil)
    if err then error(err) end
    -- update telegram
    local text_enabled, callback_data_enable = "✅ enabled", "c:"..tostring(chat_id)..":enable"
    local text_disable, callback_data_disable = "disable", "c:"..tostring(chat_id)..":disable"
    if not command_enable_this_chat then
      text_enabled = "enable"
      text_disable = "✅ disabled"
    end
    -- make reply_markup
    local reply_markup = {}
    reply_markup.inline_keyboard = {
      {
        { text = text_enabled, callback_data = callback_data_enable  },
        { text = text_disable, callback_data = callback_data_disable },
      }
    }
    local _, err = tg:editMessageReplyMarkup({
      chat_id = chat_id,
      message_id = upd.callback_query.message.message_id,
      reply_markup = reply_markup
    })
    if err then error(err) end
  end
end

-- print config
function telegram_command_config(upd)
  if not is_admin(upd) then return end
  -- check private mode
  if upd.message.chat.id < 0 then
    local _, err = tg:sendMessage({
      chat_id = upd.message.chat.id,
      reply_to_message_id = upd.message.message_id,
      text = "only in private mode"
    })
    if err then error(err) end
    return
  end
  -- format config
  local chats_registered, _, err = cache:get("chats.registered")
  if err then error(err) end
  local chats_settings, _, err = cache:get("chats.settings")
  if err then error(err) end
  local text = [[
zabbix: %s
telegram: %s
chats.registered: %s
chats.settings: %s
]]
  text = string.format(text,
    inspect(config.zabbix, {newline="", indent=""}),
    inspect(config.telegram, {newline="", indent=""}),
    inspect(chats_registered, {newline="", indent=""}),
    inspect(chats_settings, {newline="", indent=""})
  )
  local _, err = tg:sendMessage({
    chat_id = upd.message.chat.id,
    text = text
  })
  if err then error(err) end
end

-- print chat settings
function telegram_command_priority(upd)
  if not is_admin(upd) then return end
  local chat_id = upd.message.chat.id
  local chats_settings, found, err = cache:get("chats.settings")
  if err then error(err) end
  if not found then
    chats_settings = {}
    chats_settings[tostring(chat_id)] = default_settings
  end
  -- get settings for this chat
  local current_settings = chats_settings[tostring(chat_id)]
  if not current_settings then current_settings = default_settings end

  -- make reply_markup
  local reply_markup = {}
  reply_markup.inline_keyboard = {}

  -- make priority_line
  local priority_line, count = {}, 1
  for value, human in pairs(zabbix_priority) do
    local callback_data = "p:"..tostring(chat_id)..":"..value
    local text = human
    if value == current_settings.priority then
      text = "✅ "..text
    end
    table.insert(priority_line, {text = text, callback_data = callback_data})
    count = count + 1
    if count > 3 then
      table.insert(reply_markup.inline_keyboard, priority_line)
      priority_line = {}
      count = 1
    end
  end
  -- send settings
  local _, err = tg:sendMessage({
    chat_id = upd.message.chat.id,
    text = "edit minimal priority for this chat",
    resize_keyboard = true,
    reply_to_message_id = upd.message.message_id,
    reply_markup = reply_markup
  })
  if err then error(err) end
end

function telegram_callback_ack(upd)
  -- a:chat_id:event_id:trigger_id
  local data = upd.callback_query.data
  local tbl = strings.split(data, ":")
  local chat_id, event_id, trigger_id = tbl[2], tbl[3], tbl[4]
  -- get username
  local from = upd.callback_query.from.username
  local response, err = zbx:request("event.acknowledge",
    {eventids = event_id, message = "via telegram from @"..tostring(from)})
  if err then error(err) end
  -- build url
  url = config.zabbix.url.."/".."tr_events.php?triggerid="..tostring(trigger_id).."&eventid="..tostring(event_id)
  -- build reply markup
  local reply_markup = {}
  reply_markup.inline_keyboard = {
    {
      { text = "✅ acknowledged (@"..tostring(from)..")", url = url }
    }
  }
  local _, err = tg:editMessageReplyMarkup({
    chat_id = tonumber(chat_id),
    message_id = upd.callback_query.message.message_id,
    reply_markup = reply_markup
  })
  if err then error(err) end
end

function telegram_callback_priority(upd)
  if not is_admin(upd) then return end
  -- parse chat_id and priority
  -- p:chat_id:priority
  local data = upd.callback_query.data
  local tbl = strings.split(data, ":")
  local chat_id, priority = tbl[2], tbl[3]

  local chats_settings, found, err = cache:get("chats.settings")
  if err then error(err) end
  if not found then
    chats_settings = {}
    chats_settings[chat_id] = default_settings
  end
  local not_modified = (priority == chats_settings[chat_id].priority)
  chats_settings[chat_id].priority = priority
  local err = cache:set("chats.settings", chats_settings, nil)
  if err then error(err) end
  -- new reply_markup
  -- try to get message for update msgWithReply
  local reply_markup = {}
  reply_markup.inline_keyboard = {}

  -- make priority_line
  local priority_line, count = {}, 1
  for value, human in pairs(zabbix_priority) do
    local callback_data = "p:"..tostring(chat_id)..":"..value
    local text = human
    if value == chats_settings[chat_id].priority then
      text = "✅ "..text
    end
    table.insert(priority_line, {text = text, callback_data = callback_data})
    count = count + 1
    if count > 3 then
      table.insert(reply_markup.inline_keyboard, priority_line)
      priority_line = {}
      count = 1
    end
  end
  -- edit message
  if not not_modified then
    local _, err = tg:editMessageReplyMarkup({
      chat_id = tonumber(chat_id),
      message_id = upd.callback_query.message.message_id,
      reply_markup = reply_markup
    })
    if err then error(err) end
  end
end

-- main loop
while true do
  local err = zbx:login()
  if err then error(err) end

  zabbix_triggers()
  telegram_updates()

  zbx:logout()
  time.sleep(0.5)
end
