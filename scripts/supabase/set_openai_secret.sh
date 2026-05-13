#!/bin/zsh

set -euo pipefail

PROJECT_REF="yfcmvdijvgeaihvwyssb"
DEFAULT_MODEL="gpt-4.1-mini"
SUPABASE_BIN="${SUPABASE_BIN:-/opt/homebrew/bin/supabase}"

if [[ ! -x "$SUPABASE_BIN" ]]; then
  echo "Supabase CLI not found at $SUPABASE_BIN" >&2
  exit 1
fi

read -r -s "OPENAI_KEY?Paste the OpenAI API key for project ${PROJECT_REF}: "
echo

if [[ -z "$OPENAI_KEY" ]]; then
  echo "No key provided. Nothing was changed." >&2
  exit 1
fi

if [[ "$OPENAI_KEY" != sk-* ]]; then
  echo "The provided value does not look like an OpenAI key." >&2
  exit 1
fi

"$SUPABASE_BIN" secrets set \
  "OPENAI_API_KEY=$OPENAI_KEY" \
  "OPENAI_MODEL=$DEFAULT_MODEL" \
  --project-ref "$PROJECT_REF"

unset OPENAI_KEY

echo "OpenAI secret saved to Supabase project $PROJECT_REF."