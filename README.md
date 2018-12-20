## Info

Bot that sends zabbix triggers to telegram.

## Install

`go get -tags 'purego' github.com/vadv/zbx4tg`

## Configure

### Telegram

You need telegram bot token, if you don't have it: register telegram [@BotFather](tg://@BotFather)

Change token in `bot.lua`:

```lua
  telegram = {
    token = "XXX:XXXX"
  }
``

Update admins to your username:

```lua
  admins = { "username" },
```

### Zabbix

Register user in zabbix web with api access

Change zabbix settings in `bot.lua` like this:

```lua
  zabbix = {
    url = "http://zabbix.url",
    user = "user",
    password = "password",
  },
```

## Run

./zbx4tg --script bot.lua

## Configure

* Add bot to your chat

* Set minimal priority

<a href="/images/minimal_priority.png"><img src="/images/minimal_priority.png" height="100" ></a>

* Enable messages in this chat

<a href="/images/chat_status.png"><img src="/images/chat_status.png" height="100" ></a>

* Get messages

<a href="/images/ack.png"><img src="/images/ack.png" height="100" ></a>

* Send ack

<a href="/images/ack_sended.png"><img src="/images/ack_sended.png" height="100" ></a>

