#!/bin/zsh
set -eu

credentials_dir="${HOME}/.config/telegram-mcp"
api_id_file="$credentials_dir/api-id"
api_hash_file="$credentials_dir/api-hash"

umask 077
mkdir -p "$credentials_dir"

read "telegram_api_id?Telegram api_id: "
read -s "telegram_api_hash?Telegram api_hash (input hidden): "
print

if [[ ! "$telegram_api_id" =~ '^[0-9]+$' ]]; then
  print -u2 "api_id must contain digits only."
  exit 1
fi
if [[ ! "$telegram_api_hash" =~ '^[0-9A-Fa-f]{32}$' ]]; then
  print -u2 "api_hash must contain exactly 32 hexadecimal characters."
  exit 1
fi

printf '%s' "$telegram_api_id" > "$api_id_file"
printf '%s' "$telegram_api_hash" > "$api_hash_file"
chmod 600 "$api_id_file" "$api_hash_file"
unset telegram_api_id telegram_api_hash

print "Credentials saved outside Git in $credentials_dir."
