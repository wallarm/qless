FROM ruby:3.1-alpine

RUN gem update --system && \
    apk add --update --no-cache less git build-base curl jq mc

WORKDIR /app
