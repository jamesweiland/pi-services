#!/bin/zsh

set -e
chmod +x /scripts/*.sh
exec crond -f -l 2
