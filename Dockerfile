FROM ruby:3.3-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'test' \
    && bundle install --jobs 4

FROM ruby:3.3-slim

RUN groupadd -r app -g 1000 \
    && useradd -r -u 1000 -g app app \
    && mkdir -p /app /data \
    && chown -R app:app /app /data

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --chown=app:app . .
RUN chmod +x docker-entrypoint.sh

USER app

EXPOSE 39482

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
