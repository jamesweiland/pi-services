FROM alpine

RUN apk add --no-cache dcron zsh glab jq curl


COPY ./entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

# crontab is mounted in docker-compose
# cron needs to run in fg for docker, per claude
CMD ["/entrypoint.sh"]
