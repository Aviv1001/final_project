#!/bin/sh
##############
# Version 0.0.1
# written by Aviv
# date 29\08\2026
##############
set -eu

log() { printf '%s\n' "$*"; }

# nginx returns 403 when index.html is missing, so build the page once first.
python3 /app/render.py "$LIBRARY"

while true; do
  aws s3api list-objects-v2 --bucket "$BUCKET" --prefix inbox/ > /tmp/inbox.json
  jq -r '.Contents[]?.Key | select(endswith("/") | not)' /tmp/inbox.json > /tmp/keys

  while IFS= read -r key; do
    name="${key##*/}"
    lecture="${name%.*}"

    # Job names are unique per AWS account, so AWS refuses the second start.
    # That is how several workers share one inbox without doing the same file.
    if aws transcribe start-transcription-job \
        --transcription-job-name "$lecture" \
        --language-code en-US \
        --media "MediaFileUri=s3://$BUCKET/$key" \
        --output-bucket-name "$BUCKET" \
        --output-key "text/$lecture.json" > /dev/null
    then
      log "$lecture: transcribing"
    # A worker that died mid-job leaves the audio here with the job done.
    elif aws s3api head-object --bucket "$BUCKET" --key "text/$lecture.json" \
        > /dev/null 2>&1
    then
      log "$lecture: transcript is already there, finishing it"
    else
      log "$lecture: AWS refused the job, skipping"
      continue
    fi

    # 720 tries, 5 seconds apart, is one hour. A 90 minute lecture takes five.
    tries=0
    while [ "$tries" -lt 720 ]; do
      if aws s3api head-object --bucket "$BUCKET" --key "text/$lecture.json" \
          > /dev/null 2>&1
      then
        break
      fi
      tries=$((tries + 1))
      sleep 5
    done

    if [ "$tries" -ge 720 ]; then
      log "$lecture: no transcript after one hour, giving up"
      aws s3 mv "s3://$BUCKET/$key" "s3://$BUCKET/failed/$name"
      continue
    fi

    aws s3 cp "s3://$BUCKET/text/$lecture.json" /tmp/transcript.json
    mkdir -p "$LIBRARY/$lecture"
    jq -r '.results.transcripts[0].transcript' /tmp/transcript.json \
      > "$LIBRARY/$lecture/transcript.txt"

    # A transcript contains quotes and newlines, so jq builds the request.
    jq -n --rawfile t "$LIBRARY/$lecture/transcript.txt" \
      '[{role: "user", content: [{text: ("Summarise this lecture for a student who missed it. Five short bullet points.\n\n" + $t)}]}]' \
      > /tmp/prompt.json

    if aws bedrock-runtime converse --model-id "$MODEL_ID" \
        --messages file:///tmp/prompt.json > /tmp/summary.json
    then
      jq -r '.output.message.content[0].text' /tmp/summary.json \
        > "$LIBRARY/$lecture/summary.txt"
    else
      log "$lecture: no summary this time"
    fi

    python3 /app/render.py "$LIBRARY"

    if aws s3 mv "s3://$BUCKET/$key" "s3://$BUCKET/done/$name" > /dev/null
    then
      log "$lecture: published"
    else
      log "$lecture: another worker published it first"
    fi
  done < /tmp/keys

  sleep "${POLL_INTERVAL:-60}"
done
