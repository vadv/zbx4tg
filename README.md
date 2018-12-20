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

* Enable messages in this chat

* Get messages

* Send ack

![priority](/images/minimal_priority.png | width=100)
![status](/images/chat_status.png | width=100)
![ack](/images/ack.png | width=100)
![ack sended](/images/ack_sended.png | width=100)
