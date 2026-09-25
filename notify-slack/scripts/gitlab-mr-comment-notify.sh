#!/bin/zsh
# Poll GitLab for new comments on MRs I'm assigned to, ping Slack for each new one.
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"


SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-https://hooks.slack.com/triggers/REPLACE/ME/with-your-webhook}"
STATE_FILE="${STATE_FILE:-$HOME/.local/state/gitlab-mr-comment-notify/seen.txt}"

mkdir -p "$(dirname "$STATE_FILE")"
# First run: seed state silently so we don't flood with pre-existing comments.
FIRST_RUN=0
[ -f "$STATE_FILE" ] || { FIRST_RUN=1; : > "$STATE_FILE"; }

MY_ID="$(glab api user | jq -r '.id')"

seen() { grep -qxF "$1" "$STATE_FILE"; }

notify() {
  # args: note_id author mr_url body
  local id="$1" author="$2" mr_url="$3" body="$4"
  local payload
  payload="$(jq -n \
    --arg mr_url "$mr_url" \
    --arg author "$author" \
    --arg comment_url "${mr_url}#note_${id}" \
    --arg body "$body" \
    '{mr_url:$mr_url, comment_author:$author, comment_url:$comment_url, comment_body:$body}')"
  curl -sf -X POST -H 'Content-Type: application/json' -d "$payload" "$SLACK_WEBHOOK_URL" >/dev/null
}

# All open MRs assigned to me -> "project_id<TAB>iid<TAB>web_url" lines.
glab api --paginate "merge_requests?scope=assigned_to_me&state=opened" \
  | jq -r '.[] | [(.project_id|tostring), (.iid|tostring), .web_url] | @tsv' \
  | while IFS=$'\t' read -r project iid mr_url; do
      # Notes, excluding system notes and my own comments.
      # Emit: note_id<TAB>author<TAB>base64(body)
      glab api --paginate "projects/$project/merge_requests/$iid/notes" \
        | jq -r --argjson me "$MY_ID" \
            '.[] | select(.system == false and .author.id != $me) | [(.id|tostring), .author.username, (.body|@base64)] | @tsv' \
        | while IFS=$'\t' read -r id author body_b64; do
            seen "$id" && continue
            echo "$id" >> "$STATE_FILE"
            [ "$FIRST_RUN" -eq 1 ] && continue
            body="$(printf '%s' "$body_b64" | base64 -d)"
            notify "$id" "$author" "$mr_url" "$body" || echo "notify failed for note $id" >&2
          done
    done
