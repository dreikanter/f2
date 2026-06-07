# Generalized token-bucket rate limiter.
#
# Policies are declared up front (see RateLimit.define); each policy holds one or
# more limits, and a limit is a token bucket on a (dimension, window). A call
# spends `cost` tokens per dimension; it's allowed only if every bucket it
# touches has room. State lives in a single PostgreSQL table, one row per
# (policy, subject), with all of that subject's buckets in a JSONB column.
#
# See docs/rate-limiting.md for the design.
module RateLimit
  # Raised by acquire! / throttle when a call can't proceed.
  class Throttled < StandardError
    attr_reader :retry_after

    def initialize(retry_after:)
      @retry_after = retry_after
      super("Rate limited; retry after #{retry_after.round(2)}s")
    end
  end

  # Outcome of an acquire attempt.
  Result = Data.define(:allowed, :retry_after) do
    def allowed? = allowed
  end

  # A single token-bucket rule on one dimension over one window (seconds).
  # `burst` is the bucket capacity; it defaults to the per-window rate.
  Limit = Data.define(:dimension, :window, :rate, :burst) do
    def rate_per_sec = rate.to_f / window

    def bucket_key = "#{dimension}/#{window}"
  end

  # A named provider profile: its limits (grouped by dimension) and how it
  # behaves when the limiter's own storage is unavailable.
  class Policy
    attr_reader :name

    def initialize(name)
      @name = name
      @limits = Hash.new { |h, k| h[k] = [] }
      @fail_open = true
    end

    # DSL: declare a limit. Called multiple times for the same dimension to add
    # extra windows (e.g. per-minute and per-day).
    def limit(dimension, rate, per:, burst: nil)
      dimension = dimension.to_sym
      @limits[dimension] << Limit.new(dimension: dimension, window: per.to_i, rate: rate, burst: burst || rate)
    end

    # DSL: fail open (allow) or closed (throttle) on a limiter storage error.
    def fail_open(value = true) = @fail_open = value

    def fail_open? = @fail_open

    # All limits touched by the given cost, as [limit, amount] pairs. Dimensions
    # without a declared limit are unlimited and contribute nothing.
    def buckets_for(cost)
      cost.flat_map do |dimension, amount|
        @limits.fetch(dimension.to_sym, []).map { |limit| [limit, amount] }
      end
    end
  end

  # Cooldown applied when failing closed on a storage error.
  FAIL_CLOSED_COOLDOWN = 60.0

  class << self
    def define(name, &block)
      policy = Policy.new(name.to_sym)
      policy.instance_eval(&block)
      registry[name.to_sym] = policy
    end

    def policy(name)
      registry.fetch(name.to_sym) { raise ArgumentError, "Unknown rate limit policy: #{name}" }
    end

    # Test/boot helper: drop all registered policies.
    def reset!
      @registry = {}
    end

    # Try to reserve `cost`. Returns a Result; never raises for being over limit.
    def acquire(name, subject:, cost:)
      policy = policy(name)
      buckets = policy.buckets_for(cost)
      with_locked_row(name, subject) { |row, now| consume(row, buckets, now) }
    rescue ActiveRecord::ActiveRecordError => e
      Rails.error.report(e, context: { rate_limit_policy: name, subject: subject })
      policy.fail_open? ? Result.new(allowed: true, retry_after: 0.0) : Result.new(allowed: false, retry_after: FAIL_CLOSED_COOLDOWN)
    end

    # Like acquire, but raises Throttled when not allowed.
    def acquire!(name, subject:, cost:)
      result = acquire(name, subject: subject, cost: cost)
      raise Throttled.new(retry_after: result.retry_after) unless result.allowed?

      result
    end

    # Reserve `cost` and run the block, raising Throttled if there's no room.
    def throttle(name, subject:, cost:)
      acquire!(name, subject: subject, cost: cost)
      yield
    end

    # Adjust buckets after the fact, when the real cost differs from the
    # estimate (LLM output tokens, actual bytes). A positive amount consumes
    # more; a negative amount credits tokens back (capped at burst).
    def reconcile(name, subject:, cost:)
      policy = policy(name)
      buckets = policy.buckets_for(cost)
      with_locked_row(name, subject, create: false) do |row, _now|
        next unless row

        data = row.data
        buckets.each do |limit, amount|
          state = data[limit.bucket_key]
          next unless state

          data[limit.bucket_key] = { "tokens" => [state["tokens"] - amount, limit.burst.to_f].min, "refilled_at" => state["refilled_at"] }
        end
        row.update!(data: data)
      end
    end

    # Record a server-imposed cooldown (e.g. on a real 429). Until it passes,
    # acquire short-circuits to throttled for this subject.
    def penalize(name, subject:, retry_after:)
      with_locked_row(name, subject) do |row, _now|
        row.update!(blocked_until: retry_after.seconds.from_now)
      end
    end

    private

    def registry
      @registry ||= {}
    end

    def with_locked_row(name, subject, create: true)
      key = "#{name}:#{subject}"
      # Ensure the row exists before locking. Doing find-or-create inside the
      # locking transaction would abort it on a concurrent insert (Postgres),
      # surfacing as a StatementInvalid that fail-open would wrongly admit.
      # create_or_find_by handles the race in its own savepoint.
      Bucket.create_or_find_by!(key: key) if create
      Bucket.transaction do
        row = Bucket.lock.find_by(key: key)
        yield(row, Time.current.to_f)
      end
    end

    def consume(row, buckets, now)
      return Result.new(allowed: false, retry_after: row.blocked_until.to_f - now) if blocked?(row, now)

      data = row.data
      new_states = {}
      shortfalls = []

      buckets.each do |limit, amount|
        available = available_tokens(data[limit.bucket_key], limit, now)
        if available >= amount
          new_states[limit.bucket_key] = { "tokens" => available - amount, "refilled_at" => now }
        else
          shortfalls << (amount - available) / limit.rate_per_sec
        end
      end

      return Result.new(allowed: false, retry_after: shortfalls.max) if shortfalls.any?

      row.update!(data: data.merge(new_states))
      Result.new(allowed: true, retry_after: 0.0)
    end

    def blocked?(row, now)
      row.blocked_until.present? && row.blocked_until.to_f > now
    end

    def available_tokens(state, limit, now)
      state ||= { "tokens" => limit.burst.to_f, "refilled_at" => now }
      elapsed = now - state["refilled_at"]
      [limit.burst.to_f, state["tokens"] + (elapsed * limit.rate_per_sec)].min
    end
  end
end
