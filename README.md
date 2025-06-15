## this was just a fun project. i am no longer working on this.


#  bash-discord

a sleek terminal-based discord client made with pure `bash` + `curl` + `jq` ,  

---

## 🌐 welcome to discord terminal

```
🌐 welcome to discord terminal, user  
📖 type 'help' for available commands

user@discord:$ help
📖 available commands:
  help                       - show this help menu
  setchan <id>               - set default channel for all commands
  send [chan] <msg>          - send message to channel (default: )
  reply <msg_id> <msg>       - reply to a message in current channel
  react <user> latest <emoji> - react to user's last message
  react <msg_id> <emoji>     - react to specific message
  trackreact                 - enable reaction tracking in current watch channel
  dm <user_id> <msg>         - send direct message
  status <text>              - set your custom status
  watch [chan]               - watch a channel for new messages
  stopwatch                  - stop watching current channel
  lastmsg <user>             - show user's last message in current channel
  purge <num>                - delete last x messages (max 10)
  tui                        - enter enhanced TUI mode (ctrl+c to exit)
  channels                   - list available channels
  exit                       - exit the terminal

🔄 most commands use the default channel if set (current: none)  
💡 put usernames with spaces in quotes like "example user"
user@discord:$
```

---

## ⚙️ features

- realtime message + reaction logging 🔁  
- message sending, replying, and reacting 🗣️  
- dms + custom statuses 💬  
- reaction tracking 🔍  
- tui mode for cleaner output (ctrl+c to exit) 🖥️  

---

## 🚀 getting started

1. clone the repo:
```bash
git clone https://github.com/hsdcc/bash-discord.git
cd bash-discord
```

2. run it:
```bash
bash hsd.sh
```
  **or :**
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/hsdcc/bash-discord/main/bash-discord.sh)" // one-time-use
```
---

## ❗ disclaimer

this project uses your **user token**, which is against discord’s ToS.  
use it **at your own risk**. this is for **educational purposes only**.
