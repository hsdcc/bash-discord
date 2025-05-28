#!/bin/bash

# discord-bash
# Features: Enhanced TUI with message sending, Improved channel handling
# Requirements: jq, curl

# Clear screen and show welcome
clear
echo "================================================"
echo "                  bash-discord                  "
echo "================================================"
echo

# Global variables
DEFAULT_CHANNEL=""
CURRENT_CHANNEL=""
REACTION_TRACKING=()
TUI_MODE=false
USER_NAME=""
USER_ID=""
LAST_WATCH_PID=""
LAST_WATCH_CHANNEL=""
LAST_SEND_CHANNEL=""
MESSAGE_HISTORY=()
HISTORY_INDEX=0
INPUT_BUFFER=""

# API configuration
API_BASE="https://discord.com/api/v9"
MAX_MESSAGES=50

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Reaction tracking data structure
declare -A REACTION_DATA

function init_reaction_tracking() {
  local channel_id="$1"
  REACTION_TRACKING+=("$channel_id")
  echo -e "${GREEN}👀 tracking reactions in channel $channel_id${NC}"
}

function update_reaction_data() {
  local key="$1-$2"
  REACTION_DATA["$key"]="$3"
}

function get_reaction_changes() {
  local channel_id="$1"
  local message_id="$2"
  local current_reactions="$3"
  local key="$channel_id-$message_id"
  local previous_reactions="${REACTION_DATA[$key]}"

  if [[ -z "$previous_reactions" ]]; then
    echo -e "${GREEN}🆕 new reactions: $current_reactions${NC}"
    return
  fi

  if [[ "$previous_reactions" != "$current_reactions" ]]; then
    echo -e "${YELLOW}🔄 reactions changed: $current_reactions${NC}"
  fi
}

function get_user_info() {
  local res=$(curl -s -X GET "$API_BASE/users/@me" \
    -H "Authorization: $TOKEN")
  
  USER_NAME=$(echo "$res" | jq -r '.username')
  USER_ID=$(echo "$res" | jq -r '.id')
  
  if [[ -z "$USER_NAME" || "$USER_NAME" == "null" ]]; then
    echo -e "${RED}❌ Failed to authenticate with provided token${NC}"
    exit 1
  fi
}

function show_prompt() {
  if [[ -n "$USER_NAME" ]]; then
    if [[ -n "$CURRENT_CHANNEL" ]]; then
      echo -ne "${BLUE}$USER_NAME@discord:${PURPLE}$CURRENT_CHANNEL${NC}$ "
    else
      echo -ne "${BLUE}$USER_NAME@discord:${NC}$ "
    fi
  else
    echo -ne "> "
  fi
}

function send_message() {
  local channel="$1"
  local msg="$2"

  if [[ -z "$channel" ]]; then
    echo -e "${RED}❌ No channel specified${NC}"
    return 1
  fi

  if [[ -z "$msg" ]]; then
    echo -e "${RED}❌ Message cannot be empty${NC}"
    return 1
  fi

  res=$(curl -s -X POST "$API_BASE/channels/$channel/messages" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"$msg\"}")

  id=$(echo "$res" | jq -r '.id')
  if [[ -z "$id" || "$id" == "null" ]]; then
    echo -e "${RED}❌ Failed to send message${NC}"
    return 1
  fi

  echo -e "${GREEN}✅ Message sent to channel $channel${NC}"
  return 0
}

function watcher() {
  local chan="$1"
  local last_id=""
  local reaction_check_count=0

  while true; do
    res=$(curl -s -X GET "$API_BASE/channels/$chan/messages?limit=1" \
      -H "Authorization: $TOKEN")

    id=$(echo "$res" | jq -r '.[0].id')
    content=$(echo "$res" | jq -r '.[0].content')
    author=$(echo "$res" | jq -r '.[0].author.username')
    reactions=$(echo "$res" | jq -r '.[0].reactions | if . then map(.emoji.name + "(" + (.count|tostring) + ")") | join(", ") else "" end')

    # Reaction tracking
    if [[ " ${REACTION_TRACKING[@]} " =~ " $chan " ]]; then
      reaction_check_count=$((reaction_check_count + 1))

      if ((reaction_check_count % 5 == 0)); then
        msg_res=$(curl -s -X GET "$API_BASE/channels/$chan/messages?limit=10" \
          -H "Authorization: $TOKEN")

        while read -r msg; do
          msg_id=$(echo "$msg" | jq -r '.id')
          msg_reactions=$(echo "$msg" | jq -r '.reactions | if . then map(.emoji.name + "(" + (.count|tostring) + ")") | join(", ") else "" end')
          changes=$(get_reaction_changes "$chan" "$msg_id" "$msg_reactions")

          if [[ -n "$changes" ]]; then
            author_name=$(echo "$msg" | jq -r '.author.username')
            content_short=$(echo "$msg" | jq -r '.content | if length > 20 then .[0:20] + "..." else . end')
            echo -e "\n✨ ${YELLOW}$author_name: $content_short - $changes${NC}"
            update_reaction_data "$chan" "$msg_id" "$msg_reactions"
          fi
        done < <(echo "$msg_res" | jq -c '.[]')
      fi
    fi

    if [[ "$id" != "$last_id" && "$content" != "null" ]]; then
      echo -e "\n💬 ${BLUE}$author${NC}: $content (id:$id)"
      if [[ -n "$reactions" ]]; then
        echo "   🎭 reactions: $reactions"
      fi
      last_id="$id"
    fi

    sleep 1
  done
}

function start_watcher() {
  if [[ -n "$LAST_WATCH_PID" ]] && kill -0 "$LAST_WATCH_PID" 2>/dev/null; then
    echo -e "${YELLOW}⚠️ watcher already running on channel $LAST_WATCH_CHANNEL (pid: $LAST_WATCH_PID)${NC}"
    return
  fi

  echo -e "${GREEN}📡 starting watcher on channel $LAST_WATCH_CHANNEL...${NC}"
  watcher "$LAST_WATCH_CHANNEL" &
  LAST_WATCH_PID=$!
  disown
  echo -e "${GREEN}✅ watcher started (pid: $LAST_WATCH_PID)${NC}"
}

function stop_watcher() {
  if [[ -n "$LAST_WATCH_PID" ]] && kill -0 "$LAST_WATCH_PID" 2>/dev/null; then
    kill "$LAST_WATCH_PID"
    wait "$LAST_WATCH_PID" 2>/dev/null
    echo -e "${GREEN}🛑 watcher stopped (pid: $LAST_WATCH_PID)${NC}"
    LAST_WATCH_PID=""
  else
    echo -e "${YELLOW}⚠️ no watcher running${NC}"
  fi
}

function get_latest_message_id_by_user() {
  local chan="$1"
  local user="$2"
  local msg_id=$(curl -s -X GET "$API_BASE/channels/$chan/messages?limit=$MAX_MESSAGES" \
    -H "Authorization: $TOKEN" | jq -r --arg user "$user" '.[] | select(.author.username == $user) | .id' | head -n1)
  echo "$msg_id"
}

function show_help() {
  echo -e "${BLUE}📖 available commands:${NC}"
  echo "  help                  - show this help menu"
  echo "  setchan <id>          - set default channel for all commands"
  echo "  send [chan] <msg>     - send message to channel (default: $DEFAULT_CHANNEL)"
  echo "  reply <msg_id> <msg>  - reply to a message in current channel"
  echo "  react <user> latest <emoji> - react to user's last message"
  echo "  react <msg_id> <emoji>      - react to specific message"
  echo "  trackreact            - enable reaction tracking in current watch channel"
  echo "  dm <user_id> <msg>    - send direct message"
  echo "  status <text>         - set your custom status"
  echo "  watch [chan]          - watch a channel for new messages"
  echo "  stopwatch             - stop watching current channel"
  echo "  lastmsg <user>        - show user's last message in current channel"
  echo "  purge <num>           - delete last x messages (max 10)"
  echo "  tui                   - enter enhanced TUI mode (ctrl+c to exit)"
  echo "  channels              - list available channels"
  echo "  exit                  - exit the terminal"
  echo
  echo -e "${YELLOW}🔄 most commands use the default channel if set (current: ${DEFAULT_CHANNEL:-none})${NC}"
  echo -e "${YELLOW}💡 put usernames with spaces in quotes like \"example user\"${NC}"
}

function command_help() {
  case "$1" in
    send)
      echo -e "${BLUE}📖 send command:${NC}"
      echo "  send <message>            - send message to default channel"
      echo "  send <channel_id> <message> - send to specific channel"
      echo "  example: send hello world!"
      echo "  example: send 123456789 hello channel!"
      ;;
    tui)
      echo -e "${BLUE}📖 tui command:${NC}"
      echo "  tui - enter enhanced terminal user interface"
      echo "  features:"
      echo "    - real-time message viewing"
      echo "    - send messages by typing and pressing Enter"
      echo "    - view message reactions"
      echo "    - channel switching"
      echo "  exit with ctrl+c"
      ;;
    *)
      show_help
      ;;
  esac
}

function tui_mode() {
  if [[ -z "$DEFAULT_CHANNEL" ]]; then
    echo -e "${RED}❌ no default channel set. use 'setchan <id>' first${NC}"
    return
  fi

  CURRENT_CHANNEL="$DEFAULT_CHANNEL"
  echo -e "${GREEN}🚀 entering enhanced tui mode...${NC}"
  echo -e "${BLUE}📺 watching channel $CURRENT_CHANNEL${NC}"
  echo -e "${YELLOW}🔒 type your message and press Enter to send | ctrl+c to exit${NC}"
  echo

  # Setup trap to catch CTRL+C
  trap 'TUI_MODE=false; echo; echo -e "${RED}🛑 exiting tui mode${NC}"; return' INT

  TUI_MODE=true
  local last_messages=""
  local input_buffer=""

  # Clear screen
  clear

  while $TUI_MODE; do
    # Get messages
    res=$(curl -s -X GET "$API_BASE/channels/$CURRENT_CHANNEL/messages?limit=10" \
      -H "Authorization: $TOKEN")

    # Process messages
    current_messages=""
    while read -r msg; do
      author=$(echo "$msg" | jq -r '.author.username')
      content=$(echo "$msg" | jq -r '.content')
      msg_id=$(echo "$msg" | jq -r '.id')
      timestamp=$(echo "$msg" | jq -r '.timestamp')
      reactions=$(echo "$msg" | jq -r '.reactions | if . then map(.emoji.name + "(" + (.count|tostring) + ")") | join(", ") else "" end')
      ref_msg=$(echo "$msg" | jq -r '.referenced_message')
      
      # Format timestamp
      timestamp=$(date -d "$timestamp" +"%H:%M:%S")
      
      # Color yourself differently
      if [[ "$author" == "$USER_NAME" ]]; then
        author_col="${GREEN}$author${NC}"
      else
        author_col="${BLUE}$author${NC}"
      fi
      
      # Truncate long messages
      if [[ ${#content} -gt 60 ]]; then
        content="${content:0:57}..."
      fi
      
      # Handle replies
      reply_info=""
      if [[ "$ref_msg" != "null" ]]; then
        reply_author=$(echo "$ref_msg" | jq -r '.author.username')
        reply_content=$(echo "$ref_msg" | jq -r '.content')
        if [[ ${#reply_content} -gt 30 ]]; then
          reply_content="${reply_content:0:27}..."
        fi
        reply_info="\n   ↪ replying to $reply_author: $reply_content"
      fi

      current_messages+="[${timestamp}] $author_col: $content$reply_info\n"
      if [[ -n "$reactions" ]]; then
        current_messages+="   🎭 ${YELLOW}$reactions${NC}\n"
      fi
      current_messages+="\n"
    done < <(echo "$res" | jq -c 'reverse | .[]')

    # Clear and display if changed
    if [[ "$current_messages" != "$last_messages" ]]; then
      clear
      echo -e "=== ${BLUE}discord tui (enhanced)${NC} ==="
      echo -e "channel: ${PURPLE}$CURRENT_CHANNEL${NC}"
      echo -e "user: ${GREEN}$USER_NAME${NC}"
      echo "=========================="
      echo -e "$current_messages"
      echo "=========================="
      echo -e "${YELLOW}Type your message and press Enter to send${NC}"
      echo -e "${CYAN}Current input: ${NC}$input_buffer"
      
      last_messages="$current_messages"
    fi

    # Read input with timeout
    if read -t 1 -n 1 -s char; then
      case "$char" in
        $'\n') # Enter key
          if [[ -n "$input_buffer" ]]; then
            send_message "$CURRENT_CHANNEL" "$input_buffer"
            input_buffer=""
          fi
          ;;
        $'\177') # Backspace
          input_buffer="${input_buffer%?}"
          ;;
        *)
          input_buffer+="$char"
          ;;
      esac
    fi
  done
}

function list_channels() {
  echo -e "${BLUE}📂 Fetching your channels...${NC}"
  
  # Get guilds (servers) first
  guilds=$(curl -s -X GET "$API_BASE/users/@me/guilds" \
    -H "Authorization: $TOKEN")
  
  echo -e "\n${YELLOW}=== Servers ===${NC}"
  while read -r guild; do
    guild_id=$(echo "$guild" | jq -r '.id')
    guild_name=$(echo "$guild" | jq -r '.name')
    echo -e "${GREEN}$guild_name${NC} (id: $guild_id)"
    
    # Get channels for each guild
    channels=$(curl -s -X GET "$API_BASE/guilds/$guild_id/channels" \
      -H "Authorization: $TOKEN" | jq -r '.[] | select(.type == 0) | "  # \(.name) (id: \(.id))"')
    
    echo "$channels"
  done < <(echo "$guilds" | jq -c '.[]')
  
  # Get DMs
  dms=$(curl -s -X GET "$API_BASE/users/@me/channels" \
    -H "Authorization: $TOKEN")
  
  echo -e "\n${YELLOW}=== Direct Messages ===${NC}"
  while read -r dm; do
    dm_id=$(echo "$dm" | jq -r '.id')
    recipient=$(echo "$dm" | jq -r '.recipients[0].username')
    echo -e "  💬 DM with ${GREEN}$recipient${NC} (id: $dm_id)"
  done < <(echo "$dms" | jq -c '.[] | select(.type == 1)')
}

# Main program starts here

# Check for jq
if ! command -v jq &>/dev/null; then
  echo -e "${RED}❌ jq not found. please install it (sudo apt install jq or sudo emerge jq)${NC}"
  exit 1
fi

# Get token
read -rp "🔑 enter your discord token: " TOKEN
echo

# Verify token and get user info
get_user_info

echo -e "${GREEN}🌐 welcome to discord terminal, $USER_NAME${NC}"
echo -e "${BLUE}📖 type 'help' for available commands${NC}"
echo

# Main loop
while true; do
  if ! $TUI_MODE; then
    show_prompt
    read -e -r -a input
    # Store command in history
    if [[ -n "${input[*]}" ]]; then
      MESSAGE_HISTORY+=("${input[*]}")
      HISTORY_INDEX=${#MESSAGE_HISTORY[@]}
    fi
  fi

  if [[ -z "${input[0]}" ]]; then
    continue
  fi

  cmd="${input[0]}"
  arg1="${input[1]}"
  arg2="${input[2]}"
  arg3="${input[3]}"

  case $cmd in
    help)
      if [[ -n "$arg1" ]]; then
        command_help "$arg1"
      else
        show_help
      fi
      ;;

    setchan)
      if [[ -z "$arg1" ]]; then
        echo -e "${RED}❌ usage: setchan <channel_id>${NC}"
        echo -e "${YELLOW}💡 this sets the default channel for all commands${NC}"
        continue
      fi
      DEFAULT_CHANNEL="$arg1"
      CURRENT_CHANNEL="$arg1"
      echo -e "${GREEN}✅ default channel set to $DEFAULT_CHANNEL${NC}"
      ;;

    send)
      if [[ -z "$arg1" ]]; then
        command_help send
        continue
      fi

      if [[ "$arg1" =~ ^[0-9]+$ ]]; then
        channel="$arg1"
        shift
        msg="${input[@]:1}"
      else
        if [[ -z "$DEFAULT_CHANNEL" ]]; then
          echo -e "${RED}❌ no default channel set. use 'setchan <id>' or specify channel${NC}"
          command_help send
          continue
        fi
        channel="$DEFAULT_CHANNEL"
        msg="${input[@]:1}"
      fi

      send_message "$channel" "$msg"
      ;;

    reply)
      if [[ -z "$arg1" || -z "$arg2" ]]; then
        command_help reply
        continue
      fi

      if [[ -z "$DEFAULT_CHANNEL" ]]; then
        echo -e "${RED}❌ no default channel set. use 'setchan <id>' first${NC}"
        continue
      fi

      msg_id="$arg1"
      shift
      shift
      msg="${input[@]:2}"

      res=$(curl -s -X POST "$API_BASE/channels/$DEFAULT_CHANNEL/messages" \
        -H "Authorization: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"$msg\", \"message_reference\":{\"channel_id\":\"$DEFAULT_CHANNEL\",\"message_id\":\"$msg_id\"}}")

      id=$(echo "$res" | jq -r '.id')
      echo -e "${GREEN}✅ replied to message $msg_id (new id:$id)${NC}"
      ;;

    react)
      if [[ -z "$arg1" ]]; then
        command_help react
        continue
      fi

      # react to user's latest message
      if [[ "$arg2" == "latest" ]]; then
        if [[ -z "$DEFAULT_CHANNEL" ]]; then
          echo -e "${RED}❌ no default channel set. use 'setchan <id>' first${NC}"
          continue
        fi

        user="$arg1"
        emoji="$arg3"

        if [[ -z "$emoji" ]]; then
          echo -e "${RED}❌ please specify an emoji${NC}"
          continue
        fi

        msg_id=$(get_latest_message_id_by_user "$DEFAULT_CHANNEL" "$user")
        if [[ -z "$msg_id" || "$msg_id" == "null" ]]; then
          echo -e "${RED}❌ could not find latest message from '$user' in channel $DEFAULT_CHANNEL${NC}"
          continue
        fi

        emoji_encoded=$(jq -rn --arg s "$emoji" '$s|@uri')
        res=$(curl -s -X PUT "$API_BASE/channels/$DEFAULT_CHANNEL/messages/$msg_id/reactions/$emoji_encoded/@me" \
          -H "Authorization: $TOKEN" -o /dev/null -w "%{http_code}")

        if [[ "$res" == "204" ]]; then
          echo -e "${GREEN}✅ reacted with '$emoji' to $user's message (id:$msg_id)${NC}"
        else
          echo -e "${RED}❌ failed to react (HTTP $res)${NC}"
        fi

      # react to specific message
      else
        if [[ -z "$arg2" ]]; then
          command_help react
          continue
        fi

        if [[ -z "$DEFAULT_CHANNEL" ]]; then
          echo -e "${RED}❌ no default channel set. use 'setchan <id>' first${NC}"
          continue
        fi

        msg_id="$arg1"
        emoji="$arg2"
        emoji_encoded=$(jq -rn --arg s "$emoji" '$s|@uri')
        res=$(curl -s -X PUT "$API_BASE/channels/$DEFAULT_CHANNEL/messages/$msg_id/reactions/$emoji_encoded/@me" \
          -H "Authorization: $TOKEN" -o /dev/null -w "%{http_code}")

        if [[ "$res" == "204" ]]; then
          echo -e "${GREEN}✅ reacted with '$emoji' to message $msg_id${NC}"
        else
          echo -e "${RED}❌ failed to react (HTTP $res)${NC}"
        fi
      fi
      ;;

    trackreact)
      if [[ -z "$LAST_WATCH_CHANNEL" ]]; then
        echo -e "${RED}❌ no active watch channel. start watching first with 'watch'${NC}"
        continue
      fi
      init_reaction_tracking "$LAST_WATCH_CHANNEL"
      ;;

    dm)
      if [[ -z "$arg1" || -z "$arg2" ]]; then
        command_help dm
        continue
      fi

      uid="$arg1"
      shift
      shift
      msg="${input[@]:2}"

      chan=$(curl -s -X POST "$API_BASE/users/@me/channels" \
        -H "Authorization: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"recipient_id\":\"$uid\"}" | jq -r .id)

      res=$(curl -s -X POST "$API_BASE/channels/$chan/messages" \
        -H "Authorization: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"$msg\"}")

      id=$(echo "$res" | jq -r '.id')
      echo -e "${GREEN}✅ dm sent to user $uid (id:$id)${NC}"
      ;;

    status)
      if [[ -z "$arg1" ]]; then
        echo -e "${RED}❌ usage: status <text>${NC}"
        echo -e "${YELLOW}💡 sets your custom status${NC}"
        continue
      fi

      shift
      status_msg="${input[@]:1}"

      res=$(curl -s -X PATCH "$API_BASE/users/@me/settings" \
        -H "Authorization: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"custom_status\":{\"text\":\"$status_msg\"}}")
      echo -e "${GREEN}✅ status updated to: $status_msg${NC}"
      ;;

    watch)
      channel="$DEFAULT_CHANNEL"
      if [[ -n "$arg1" ]]; then
        channel="$arg1"
      fi

      if [[ -z "$channel" ]]; then
        echo -e "${RED}❌ no channel specified and no default channel set${NC}"
        command_help watch
        continue
      fi

      LAST_WATCH_CHANNEL="$channel"
      start_watcher
      ;;

    stopwatch)
      stop_watcher
      ;;

    lastmsg)
      if [[ -z "$arg1" ]]; then
        echo -e "${RED}❌ usage: lastmsg <username>${NC}"
        continue
      fi
      if [[ -z "$DEFAULT_CHANNEL" ]]; then
        echo -e "${RED}❌ no default channel set. use 'setchan <id>' first${NC}"
        continue
      fi

      user="$arg1"
      res=$(curl -s -X GET "$API_BASE/channels/$DEFAULT_CHANNEL/messages?limit=50" \
        -H "Authorization: $TOKEN")

      msg=$(echo "$res" | jq -r --arg user "$user" '.[] | select(.author.username == $user) | "\(.author.username) : \(.content) (id:\(.id))"' | head -n1)

      if [[ -z "$msg" ]]; then
        echo -e "${RED}❌ no recent message from $user found in channel $DEFAULT_CHANNEL${NC}"
      else
        echo -e "💬 $msg"
      fi
      ;;

    purge)
      if [[ -z "$arg1" ]]; then
        echo -e "${RED}❌ usage: purge <number>${NC}"
        echo -e "${YELLOW}💡 deletes your last x messages (max 10 at a time)${NC}"
        continue
      fi

      if [[ -z "$DEFAULT_CHANNEL" ]]; then
        echo -e "${RED}❌ no default channel set. use 'setchan <id>' first${NC}"
        continue
      fi

      count="$arg1"
      if [[ "$count" -gt 10 ]]; then
        echo -e "${YELLOW}⚠️ max 10 messages at a time${NC}"
        count=10
      fi

      echo -e "${BLUE}⏳ fetching your last $count messages...${NC}"
      username=$(curl -s -X GET "$API_BASE/users/@me" -H "Authorization: $TOKEN" | jq -r '.username')
      messages=$(curl -s -X GET "$API_BASE/channels/$DEFAULT_CHANNEL/messages?limit=$count" \
        -H "Authorization: $TOKEN" | jq -r --arg user "$username" '.[] | select(.author.username == $user) | .id')

      if [[ -z "$messages" ]]; then
        echo -e "${RED}❌ no recent messages found from you in this channel${NC}"
        continue
      fi

      for msg_id in $messages; do
        res=$(curl -s -X DELETE "$API_BASE/channels/$DEFAULT_CHANNEL/messages/$msg_id" \
          -H "Authorization: $TOKEN" -o /dev/null -w "%{http_code}")
        if [[ "$res" == "204" ]]; then
          echo -e "🗑️ deleted message $msg_id"
        else
          echo -e "${RED}❌ failed to delete $msg_id (HTTP $res)${NC}"
        fi
        sleep 0.5
      done
      echo -e "${GREEN}✅ done purging messages${NC}"
      ;;

    tui)
      tui_mode
      ;;

    channels)
      list_channels
      ;;

    exit)
      stop_watcher
      echo -e "${GREEN}👋 cya!${NC}"
      break
      ;;

    *)
      echo -e "${RED}❌ unknown command. type 'help' for available commands${NC}"
      ;;
  esac

  # Reset input in TUI mode
  if $TUI_MODE; then
    input=()
  fi
done
