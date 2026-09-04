#!/bin/sh
# critic.sh -- a second opinion from different weights.
#
#   tools/critic.sh < prompt.txt            # prompt on stdin, answer on stdout
#   tools/critic.sh --check                 # is the model reachable? (exit 0/1)
#
# Talks to the local ollama server (default http://127.0.0.1:11434, model
# qwen3.8:27b-mlx) through its HTTP API rather than the CLI: the CLI's
# spinner and redraws pollute captured output. The model has ZERO project
# context: prompts must be self-contained -- spell out every OT6 term, and
# paste the raw evidence (log lines, diffs, [result] lines), not summaries.
# 16k tokens of context by default; keep excerpts curated.
#
# The prompt shape that has caught every planted contradiction so far:
#   "You are an adversarial auditor. Verify EVERY claim below against the
#    evidence. For each claim answer VERIFIED or CONTRADICTED with the
#    exact evidence line, or UNVERIFIABLE if the evidence does not cover
#    it. Then list what the claims omit."
set -u
HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
MODEL="${CRITIC_MODEL:-qwen3.8:27b-mlx}"
CTX="${CRITIC_CTX:-16384}"
TIMEOUT="${CRITIC_TIMEOUT:-900}"

if [ "${1:-}" = "--check" ]; then
  if curl -s --max-time 5 "$HOST/api/tags" | jq -e --arg m "$MODEL" \
       '.models[]?.name | select(. == $m)' >/dev/null 2>&1
  then echo "critic ready: $MODEL at $HOST"; exit 0
  else echo "critic unavailable: $MODEL not served at $HOST (start ollama; ollama pull $MODEL)" >&2; exit 1
  fi
fi

jq -n --rawfile p /dev/stdin --arg m "$MODEL" --argjson c "$CTX" \
  '{model:$m, prompt:$p, stream:false, options:{num_ctx:$c}}' |
curl -s --max-time "$TIMEOUT" "$HOST/api/generate" -d @- |
jq -r 'if .error then ("critic error: " + .error | halt_error(1)) else .response end'
