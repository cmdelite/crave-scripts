#!/bin/bash

# Exit immediately on errors and unset variables
set -euo pipefail

# ========== Configuration ==========
# Replace these values with your actual credentials
TG_BOT_TOKEN="your_telegram_bot_token_here"
TG_CHAT_ID="your_telegram_chat_id_here"
GDRIVE_FOLDER_ID="your_google_drive_folder_id_here"  # Found in Google Drive URL

# ========== Dependency Checks ==========
check_dependency() {
  if ! command -v "$1" &> /dev/null; then
    echo "❌ Required command '$1' not found. Aborting." >&2
    [[ "$1" == "gdrive" ]] && echo "Install from: https://github.com/glotlabs/gdrive" >&2
    exit 1
  fi
}

check_dependency curl
check_dependency jq
check_dependency numfmt
check_dependency find
check_dependency stat
check_dependency gdrive

# ========== Environment Validation ==========
if [[ -z "${OUT:-}" ]]; then
  echo "❌ OUT environment variable is not set!" >&2
  echo "Please set OUT to your build output directory" >&2
  exit 1
fi

if [[ ! -d "$OUT" ]]; then
  echo "❌ OUT directory '$OUT' does not exist!" >&2
  exit 1
fi

if [[ -z "$GDRIVE_FOLDER_ID" ]]; then
  echo "❌ GDRIVE_FOLDER_ID is not configured!" >&2
  exit 1
fi

# Validate Google Drive authentication
if ! gdrive about >/dev/null 2>&1; then
  echo "❌ Google Drive authentication failed!" >&2
  echo "Run 'gdrive about' to authenticate first" >&2
  exit 1
fi

# ========== Main Function ==========
upload_latest_zip() {
  local search_path="$1"
  local zip_file=""
  local max_attempts=3
  local attempt=1
  
  echo "🔍 Searching for latest Axion ZIP in $search_path..."
  zip_file=$(find "$search_path" -maxdepth 2 -type f -iname "axion*.zip" -printf "%T@ %p\n" 2>/dev/null | \
             sort -n | tail -n1 | cut -d' ' -f2-)

  if [[ -z "$zip_file" ]]; then
    echo -e "\e[1;31m❌ No Axion ROM .zip found in $search_path\e[0m"
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
      --data-urlencode "chat_id=$TG_CHAT_ID" \
      --data-urlencode "text=❌ *Axion ROM Upload Failed!* 
📦 No .zip file found in \`$search_path\`." \
      --data-urlencode "parse_mode=Markdown" \
      --output /dev/null || true
    return 1
  fi

  local file_name=$(basename "$zip_file")
  local file_size_bytes=$(stat -c%s "$zip_file")
  local file_size_human=$(numfmt --to=iec --suffix=B --format "%.2f" "$file_size_bytes")
  local upload_date=$(date +"%Y-%m-%d %H:%M")

  # Retry loop for upload
  while [[ $attempt -le $max_attempts ]]; do
    echo -e "\e[1;36m⬆ Attempt $attempt/$max_attempts: Uploading Axion ROM ($file_name) to Google Drive...\e[0m"
    
    # Upload to Google Drive using glotlabs/gdrive
    local upload_output
    upload_output=$(gdrive upload --parent "$GDRIVE_FOLDER_ID" "$zip_file" 2>&1)
    local upload_status=$?
    
    # Extract file ID from output
    local file_id=$(echo "$upload_output" | grep -E '^Uploaded' | awk '{print $2}')
    
    if [[ $upload_status -eq 0 && -n "$file_id" ]]; then
      # Make file publicly viewable with direct download capability
      echo "🔓 Making file publicly accessible..."
      if ! gdrive share --role reader --type anyone "$file_id" >/dev/null 2>&1; then
        echo -e "\e[1;33m⚠️ File sharing failed, attempting to set permissions again...\e[0m"
        sleep 2
        gdrive share --role reader --type anyone "$file_id" >/dev/null
      fi
      
      # Create URLs
      local direct_download_url="https://drive.google.com/uc?export=download&id=$file_id"
      local view_url="https://drive.google.com/file/d/$file_id/view"
      
      echo -e "\e[1;32m✅ Axion ROM uploaded successfully!\e[0m"
      echo -e "  🔗 Direct Download: $direct_download_url"
      echo -e "  👁️ View: $view_url"

      # Send Telegram notification
      local telegram_response=$(curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TG_CHAT_ID" \
        --data-urlencode "text=✅ *Axion ROM Uploaded to Google Drive!*

📎 *Filename:* \`$file_name\`
📦 *Size:* $file_size_human
🕓 *Uploaded:* $upload_date

🔗 *Direct Download:*
\`$direct_download_url\`

👁️ *View in Browser:*
$view_url" \
        --data-urlencode "parse_mode=Markdown" \
        -w "%{http_code}" -o /dev/null)

      if [[ "$telegram_response" != "200" ]]; then
        echo -e "\e[1;33m⚠️ Telegram notification failed (HTTP $telegram_response)\e[0m"
      else
        echo -e "\e[1;32m📨 Telegram notification sent successfully!\e[0m"
      fi
      
      return 0
    else
      echo -e "\e[1;31m❌ Upload attempt $attempt failed. Error:\n$upload_output\e[0m"
      ((attempt++))
      sleep $((attempt * 5))  # Exponential backoff
    fi
  done

  # All attempts failed
  echo -e "\e[1;31m❌ All upload attempts failed for $file_name\e[0m"
  
  # Send error notification
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=❌ *Axion ROM Upload Failed!*

📦 *Filename:* \`$file_name\`
📊 *Size:* $file_size_human
🕓 *Attempted:* $upload_date

💥 *Error:*
\`$(echo "$upload_output" | head -c 2000)\`" \
    --data-urlencode "parse_mode=Markdown" \
    --output /dev/null || true
  
  return 1
}

# ========== Main Script ==========
# Search for Axion ROM in the standard OUT directory
echo -e "\e[1;33m🚀 Starting Axion ROM upload process...\e[0m"
start_time=$(date +%s)

upload_latest_zip "$OUT"

end_time=$(date +%s)
duration=$((end_time - start_time))
echo -e "\e[1;32m🏁 Upload process completed in ${duration} seconds.\e[0m"
