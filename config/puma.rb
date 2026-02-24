bind        "tcp://0.0.0.0:#{ENV.fetch('PORT', 39482)}"

# SQLite serializes writes; multiple workers only contend on the lock.
workers     0

# Pre-warm thread pool. Tune based on expected concurrent request load.
threads     5, 5

environment ENV.fetch('RACK_ENV', 'production')
