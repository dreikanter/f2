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
    def allowed?
      allowed
    end
  end

  # Read-only view of one (policy, subject, limit) bucket, with tokens refilled
  # to the moment the snapshot was taken. Powers the admin rate-limit dashboard.
  # See RateLimit.snapshot and issue #622.
  Snapshot = Data.define(:policy, :subject, :dimension, :window, :available, :burst, :blocked_until) do
    # Share of the bucket spent right now, 0.0 (idle) to 1.0 (empty).
    def fraction_consumed
      return 1.0 if burst.zero?

      (1.0 - available / burst).clamp(0.0, 1.0)
    end

    def percent_consumed
      (fraction_consumed * 100).round
    end

    def blocked?
      blocked_until.present? && blocked_until.future?
    end

    # Seconds left on a server-imposed cooldown, or 0 when not blocked.
    def blocked_for
      blocked? ? (blocked_until - Time.current) : 0.0
    end
  end

  # A single token-bucket rule on one dimension over one window (seconds).
  # `burst` is the bucket capacity; it defaults to the per-window rate.
  Limit = Data.define(:dimension, :window, :rate, :burst) do
    def rate_per_sec
      rate.to_f / window
    end

    def bucket_key
      "#{dimension}/#{window}"
    end
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
    def fail_open(value = true)
      @fail_open = value
    end

    def fail_open?
      @fail_open
    end

    # Every declared limit, across all dimensions and windows (read side).
    def all_limits
      @limits.values.flatten
    end

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
    # Register a policy from a configuration block (see Policy DSL).
    # @param name [Symbol, String] the policy name (e.g. :freefeed)
    # @yield evaluated in the Policy instance to declare `limit`s and `fail_open`
    def define(name, &block)
      policy = Policy.new(name.to_sym)
      policy.instance_eval(&block)
      registry[name.to_sym] = policy
    end

    # Look up a registered policy.
    # @param name [Symbol, String] the policy name
    # @return [Policy]
    # @raise [ArgumentError] if the policy is not registered
    def policy(name)
      registry.fetch(name.to_sym) { raise ArgumentError, "Unknown rate limit policy: #{name}" }
    end

    # Test/boot helper: drop all registered policies.
    def reset!
      @registry = {}
    end

    # Try to reserve `cost`. Never raises for being over limit.
    # @param name [Symbol, String] the policy name
    # @param subject [String] identity that owns the allowance (e.g. "freefeed:7")
    # @param cost [Hash{Symbol=>Numeric}] tokens to spend per dimension
    # @return [Result] allowed? and retry_after (seconds) when not allowed
    def acquire(name, subject:, cost:)
      policy = policy(name)
      buckets = policy.buckets_for(cost)
      result = with_locked_row(name, subject) { |row, now| consume(row, buckets, now) }
      unless result.allowed?
        Rails.logger.info("RateLimit throttled #{name}:#{subject} cost=#{cost.inspect} retry_after=#{result.retry_after.round(2)}s")
      end
      result
    rescue ActiveRecord::ActiveRecordError => e
      Rails.error.report(e, context: { rate_limit_policy: name, subject: subject })
      policy.fail_open? ? Result.new(allowed: true, retry_after: 0.0) : Result.new(allowed: false, retry_after: FAIL_CLOSED_COOLDOWN)
    end

    # Like acquire, but raises when not allowed.
    # @param name [Symbol, String] the policy name
    # @param subject [String] identity that owns the allowance
    # @param cost [Hash{Symbol=>Numeric}] tokens to spend per dimension
    # @return [Result]
    # @raise [Throttled] with retry_after (seconds) when over limit
    def acquire!(name, subject:, cost:)
      result = acquire(name, subject: subject, cost: cost)
      raise Throttled.new(retry_after: result.retry_after) unless result.allowed?

      result
    end

    # Reserve `cost`, then run the block. Raises if there's no room.
    # @param name [Symbol, String] the policy name
    # @param subject [String] identity that owns the allowance
    # @param cost [Hash{Symbol=>Numeric}] tokens to spend per dimension
    # @yield runs only when the reservation succeeds
    # @raise [Throttled] when over limit (the block does not run)
    def throttle(name, subject:, cost:)
      acquire!(name, subject: subject, cost: cost)
      yield
    end

    # Adjust buckets after the fact, when the real cost differs from the
    # estimate (LLM output tokens, actual bytes). No-op if the subject has no
    # state yet.
    # @param name [Symbol, String] the policy name
    # @param subject [String] identity that owns the allowance
    # @param cost [Hash{Symbol=>Numeric}] per-dimension adjustment; positive
    #   consumes more, negative credits tokens back (capped at burst)
    # @return [void]
    def reconcile(name, subject:, cost:)
      policy = policy(name)
      buckets = policy.buckets_for(cost)
      with_locked_row(name, subject, create: false) do |row, now|
        next unless row

        data = row.data
        buckets.each do |limit, amount|
          next unless data.key?(limit.bucket_key)

          # Refill to `now` first (same as acquire) so the delta isn't applied
          # against a stale base or swallowed by the burst cap.
          available = available_tokens(data[limit.bucket_key], limit, now)
          data[limit.bucket_key] = { "tokens" => [available - amount, limit.burst.to_f].min, "refilled_at" => now }
        end
        row.update!(data: data)
      end
    end

    # Record a server-imposed cooldown (e.g. on a real 429). Until it passes,
    # acquire short-circuits to throttled for this subject.
    # @param name [Symbol, String] the policy name
    # @param subject [String] identity that owns the allowance
    # @param retry_after [Numeric] seconds to block the subject for
    # @return [void]
    def penalize(name, subject:, retry_after:)
      with_locked_row(name, subject) do |row, _now|
        row.update!(blocked_until: retry_after.seconds.from_now)
      end
      Rails.logger.warn("RateLimit cooldown #{name}:#{subject} blocked for #{retry_after}s (server throttled us)")
    end

    # Largest cost a single acquire could ever satisfy for a dimension — the
    # smallest bucket capacity (burst) across its windows. A cost above this can
    # never be granted, so callers can reject it instead of throttling forever.
    # @param name [Symbol, String] the policy name
    # @param dimension [Symbol, String] the dimension to check
    # @return [Numeric, nil] the capacity, or nil if the dimension is unlimited
    def capacity(name, dimension)
      policy(name).buckets_for(dimension => 1).map { |limit, _amount| limit.burst }.min
    end

    # Drop a subject's stored state for a policy. Call this when the subject is
    # gone for good (e.g. its access token is deleted) — the only definite signal
    # that a row will never be used again. A later acquire would recreate it.
    # @param name [Symbol, String] the policy name
    # @param subject [String] identity whose allowance to forget
    # @return [void]
    def forget(name, subject:)
      Bucket.where(key: "#{name}:#{subject}").delete_all
    end

    # Current state of every bucket, for observability. A plain read of the
    # buckets table (no locking); tokens are refilled to now so the numbers match
    # what the next acquire would see. One Snapshot per (policy, subject, limit);
    # subjects with a stored row but no declared policy are skipped.
    # @return [Array<Snapshot>] ordered by bucket key
    def snapshot
      now = Time.current.to_f
      Bucket.order(:key).flat_map do |row|
        name, subject = row.key.split(":", 2)
        policy = registry[name.to_sym]
        next [] unless policy

        policy.all_limits.map do |limit|
          Snapshot.new(
            policy: name,
            subject: subject,
            dimension: limit.dimension,
            window: limit.window,
            available: available_tokens(row.data[limit.bucket_key], limit, now),
            burst: limit.burst.to_f,
            blocked_until: row.blocked_until
          )
        end
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
