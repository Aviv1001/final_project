FROM alpine:3.23

RUN apk add --no-cache aws-cli jq python3

RUN adduser -D -u 10001 worker
COPY render.py worker.sh /app/
USER 10001
CMD ["/app/worker.sh"]
