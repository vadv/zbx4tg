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
![status](/images/minimal_priority.png)

* Enable messages in this chat
![status](/images/chat_status.png)

* Get messages
![status](/images/ack.png)

* Ack
![status](/images/ack_sended.png)
