require "test_helper"

class SchemaHealerTest < ActiveSupport::TestCase
  test "#call should pass a Hash through unchanged" do
    assert_equal({ "items" => [] }, SchemaHealer.call({ "items" => [] }))
  end

  test "#call should parse a plain JSON object string" do
    assert_equal({ "a" => 1 }, SchemaHealer.call('{"a":1}'))
  end

  test "#call should parse a top-level JSON array" do
    assert_equal [1, 2], SchemaHealer.call("[1, 2]")
  end

  test "#call should strip a fenced json code block" do
    raw = "```json\n{\"a\": 1}\n```"
    assert_equal({ "a" => 1 }, SchemaHealer.call(raw))
  end

  test "#call should strip a bare fenced code block" do
    raw = "```\n{\"a\": 1}\n```"
    assert_equal({ "a" => 1 }, SchemaHealer.call(raw))
  end

  test "#call should extract an object embedded in prose" do
    raw = %(Here are the results: {"a": 1, "b": [2, 3]} — hope that helps!)
    assert_equal({ "a" => 1, "b" => [2, 3] }, SchemaHealer.call(raw))
  end

  test "#call should raise when there is no recoverable JSON" do
    assert_raises(SchemaHealer::Error) { SchemaHealer.call("I could not complete this request.") }
  end

  test "#call should raise on blank input" do
    assert_raises(SchemaHealer::Error) { SchemaHealer.call("") }
  end
end
