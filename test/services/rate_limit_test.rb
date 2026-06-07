require "test_helper"

class RateLimitTest < ActiveSupport::TestCase
  # Isolate the registry per test, but restore the app's real policies (defined
  # in an initializer) afterward so other tests still see them.
  setup do
    @registry_backup = RateLimit.instance_variable_get(:@registry)
    RateLimit.reset!
  end
  teardown { RateLimit.instance_variable_set(:@registry, @registry_backup) }

  def cost(**dims)
    dims
  end

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  test ".forget should delete only the named subject's stored state" do
    RateLimit.define(:t) { limit :requests, 5, per: 60 }
    RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1))
    RateLimit.acquire(:t, subject: "b", cost: cost(requests: 1))

    RateLimit.forget(:t, subject: "a")

    assert_not RateLimit::Bucket.exists?(key: "t:a")
    assert RateLimit::Bucket.exists?(key: "t:b")
  end

  test ".acquire should allow up to burst then throttle" do
    RateLimit.define(:t) { limit :requests, 5, per: 60 }

    5.times { assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed? }
    refute RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
  end

  test ".acquire should meter subjects independently" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }

    assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
    assert RateLimit.acquire(:t, subject: "b", cost: cost(requests: 1)).allowed?
    refute RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
  end

  test ".acquire should refill continuously over time" do
    RateLimit.define(:t) { limit :requests, 60, per: 60 } # 1 token/sec

    # travel_to truncates sub-second precision; a usec-zero base keeps elapsed exact
    travel_to Time.current.change(usec: 0)
    60.times { RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)) }
    refute RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?

    travel_to Time.current + 10.seconds
    assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 10)).allowed?
    refute RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
  end

  test ".acquire should cap accumulation at burst, not rate times idle" do
    RateLimit.define(:t) { limit :requests, 5, per: 60 }

    travel_to Time.current.change(usec: 0)
    5.times { RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)) }

    travel_to Time.current + 1.hour
    5.times { assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed? }
    refute RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
  end

  test ".acquire should support sub-second windows" do
    RateLimit.define(:t) { limit :requests, 1, per: 1 }

    travel_to Time.current.change(usec: 0)
    assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
    refute RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?

    travel_to Time.current + 1.second
    assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
  end

  test ".acquire should be all-or-nothing across dimensions" do
    RateLimit.define(:llm) do
      limit :requests, 10, per: 60
      limit :tokens, 100, per: 60
    end

    assert RateLimit.acquire(:llm, subject: "a", cost: cost(requests: 1, tokens: 100)).allowed?
    # tokens are exhausted; this call must be denied AND must not consume a request
    refute RateLimit.acquire(:llm, subject: "a", cost: cost(requests: 1, tokens: 1)).allowed?
    # proof the request token was not consumed by the denied call
    assert RateLimit.acquire(:llm, subject: "a", cost: cost(requests: 1)).allowed?
  end

  test ".acquire should enforce multiple windows on the same dimension" do
    RateLimit.define(:t) do
      limit :requests, 100, per: 60   # generous per minute
      limit :requests, 3, per: 3600   # tight per hour
    end

    3.times { assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed? }
    refute RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
  end

  test ".acquire should allow dimensions without a declared limit" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }

    assert RateLimit.acquire(:t, subject: "a", cost: cost(other: 999)).allowed?
  end

  test ".acquire should raise for an unknown policy" do
    assert_raises(ArgumentError) do
      RateLimit.acquire(:nope, subject: "a", cost: cost(requests: 1))
    end
  end

  test ".acquire! should raise Throttled with a positive retry_after" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }

    RateLimit.acquire!(:t, subject: "a", cost: cost(requests: 1))
    error = assert_raises(RateLimit::Throttled) do
      RateLimit.acquire!(:t, subject: "a", cost: cost(requests: 1))
    end
    assert error.retry_after > 0
  end

  test ".throttle should yield when allowed and raise when not" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }

    ran = false
    RateLimit.throttle(:t, subject: "a", cost: cost(requests: 1)) { ran = true }
    assert ran

    assert_raises(RateLimit::Throttled) do
      RateLimit.throttle(:t, subject: "a", cost: cost(requests: 1)) { flunk "should not run" }
    end
  end

  test ".reconcile should consume additional tokens for an under-estimate" do
    RateLimit.define(:t) { limit :tokens, 100, per: 60 }

    RateLimit.acquire!(:t, subject: "a", cost: cost(tokens: 10)) # estimated 10
    RateLimit.reconcile(:t, subject: "a", cost: cost(tokens: 90)) # actual was 100

    refute RateLimit.acquire(:t, subject: "a", cost: cost(tokens: 1)).allowed?
  end

  test ".reconcile should credit tokens back for an over-estimate" do
    RateLimit.define(:t) { limit :tokens, 100, per: 60 }

    RateLimit.acquire!(:t, subject: "a", cost: cost(tokens: 100)) # drains the bucket
    RateLimit.reconcile(:t, subject: "a", cost: cost(tokens: -50)) # actual was only 50

    assert RateLimit.acquire(:t, subject: "a", cost: cost(tokens: 50)).allowed?
  end

  test ".reconcile should refill before adjusting, so the delta isn't swallowed by the burst cap" do
    RateLimit.define(:t) { limit :tokens, 60, per: 60, burst: 100 } # 1 token/sec, cap 100

    travel_to Time.current.change(usec: 0)
    RateLimit.acquire!(:t, subject: "a", cost: cost(tokens: 10)) # 90 left
    travel_to Time.current + 60.seconds                          # refills, capped at 100
    RateLimit.reconcile(:t, subject: "a", cost: cost(tokens: 5)) # actually used 5 more

    # refill caps at 100, minus the 5 reconciled => exactly 95 available
    assert RateLimit.acquire(:t, subject: "a", cost: cost(tokens: 95)).allowed?
    refute RateLimit.acquire(:t, subject: "a", cost: cost(tokens: 1)).allowed?
  end

  test ".reconcile should do nothing when the subject has no row" do
    RateLimit.define(:t) { limit :tokens, 100, per: 60 }

    assert_nothing_raised { RateLimit.reconcile(:t, subject: "missing", cost: cost(tokens: 5)) }
  end

  test ".penalize should block acquire until the cooldown passes" do
    RateLimit.define(:t) { limit :requests, 100, per: 60 }

    RateLimit.penalize(:t, subject: "a", retry_after: 30)

    result = RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1))
    refute result.allowed?
    assert_in_delta 30, result.retry_after, 2

    travel 31.seconds do
      assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
    end
  end

  test ".capacity should return the smallest bucket capacity for a dimension" do
    RateLimit.define(:t) do
      limit :requests, 100, per: 60
      limit :requests, 5, per: 3600
    end

    assert_equal 5, RateLimit.capacity(:t, :requests)
  end

  test ".capacity should be nil for a dimension with no declared limit" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }

    assert_nil RateLimit.capacity(:t, :other)
  end

  test ".acquire should log a throttled call" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }
    RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1))

    out = capture_log { RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)) }
    assert_match(/RateLimit throttled t:a/, out)
  end

  test ".acquire should not log an allowed call" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }

    out = capture_log { RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)) }
    refute_match(/RateLimit throttled/, out)
  end

  test ".penalize should log the cooldown" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }

    out = capture_log { RateLimit.penalize(:t, subject: "a", retry_after: 30) }
    assert_match(/RateLimit cooldown t:a blocked for 30s/, out)
  end

  test ".snapshot should report headroom per limit with tokens refilled to now" do
    RateLimit.define(:t) { limit :requests, 10, per: 60 }

    travel_to Time.current.change(usec: 0)
    4.times { RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)) }

    entry = RateLimit.snapshot.find { |s| s.subject == "a" }
    assert_equal "t", entry.policy
    assert_equal :requests, entry.dimension
    assert_equal 60, entry.window
    assert_in_delta 6.0, entry.available, 0.001
    assert_equal 10.0, entry.burst
    assert_equal 40, entry.percent_consumed
    refute entry.blocked?
  end

  test ".snapshot should emit one entry per declared limit" do
    RateLimit.define(:t) do
      limit :requests, 100, per: 60
      limit :requests, 1000, per: 3600
      limit :tokens, 50, per: 60
    end
    RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1))

    entries = RateLimit.snapshot.select { |s| s.subject == "a" }
    assert_equal 3, entries.size
    assert_equal [[:requests, 60], [:requests, 3600], [:tokens, 60]].sort,
                 entries.map { |s| [s.dimension, s.window] }.sort
  end

  test ".snapshot should surface a server-imposed cooldown" do
    RateLimit.define(:t) { limit :requests, 10, per: 60 }
    RateLimit.penalize(:t, subject: "a", retry_after: 30)

    entry = RateLimit.snapshot.find { |s| s.subject == "a" }
    assert entry.blocked?
    assert_in_delta 30.0, entry.blocked_for, 1.0
  end

  test ".snapshot should skip subjects whose policy is no longer registered" do
    RateLimit.define(:t) { limit :requests, 10, per: 60 }
    RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1))
    RateLimit::Bucket.create!(key: "gone:x")

    policies = RateLimit.snapshot.map(&:policy).uniq
    assert_equal ["t"], policies
  end

  test ".snapshot should report a full bucket for an untouched limit" do
    RateLimit.define(:t) do
      limit :post, 10, per: 60
      limit :get, 20, per: 60
    end
    RateLimit.acquire(:t, subject: "a", cost: cost(post: 5))

    get_entry = RateLimit.snapshot.find { |s| s.subject == "a" && s.dimension == :get }
    assert_equal 20.0, get_entry.available
    assert_equal 0, get_entry.percent_consumed
  end

  test ".acquire should fail open by default on a storage error" do
    RateLimit.define(:t) { limit :requests, 1, per: 60 }

    RateLimit::Bucket.stub(:transaction, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      assert RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
    end
  end

  test ".acquire should fail closed when the policy is configured to" do
    RateLimit.define(:t) do
      limit :requests, 1, per: 60
      fail_open false
    end

    RateLimit::Bucket.stub(:transaction, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      refute RateLimit.acquire(:t, subject: "a", cost: cost(requests: 1)).allowed?
    end
  end
end

class RateLimitConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @registry_backup = RateLimit.instance_variable_get(:@registry)
    RateLimit.reset!
    RateLimit.define(:t) { limit :requests, 5, per: 60 }
    RateLimit::Bucket.delete_all
  end

  teardown do
    RateLimit::Bucket.delete_all
    RateLimit.instance_variable_set(:@registry, @registry_backup)
  end

  test "parallel acquire on the same subject does not over-admit" do
    threads = 20.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          RateLimit.acquire(:t, subject: "shared", cost: { requests: 1 }).allowed?
        end
      end
    end

    allowed = threads.map(&:value).count(true)
    assert_equal 5, allowed, "burst is 5, so exactly 5 of 20 concurrent calls should be allowed"
  end
end
