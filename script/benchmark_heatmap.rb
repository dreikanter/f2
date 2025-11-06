#!/usr/bin/env ruby
# Benchmark script for heatmap rendering strategies
require_relative "../config/environment"
require "benchmark"

# Find a user with posts or create test data
user = User.joins(:feeds).joins("INNER JOIN posts ON posts.feed_id = feeds.id").first

unless user
  puts "No user with posts found. Please create test data first."
  exit 1
end

puts "Benchmarking heatmap rendering for user #{user.id}"
puts "Total posts: #{user.total_imported_posts_count}"
puts "-" * 80

# Number of iterations
ITERATIONS = 100

puts "\n1. No caching (current implementation)"
no_cache_time = Benchmark.realtime do
  ITERATIONS.times do
    data = user.posts_heatmap_data
    builder = HeatmapBuilder.new(
      data: data,
      start_date: Date.current - 365,
      end_date: Date.current,
      month_labels: true,
      day_labels: true
    )
    builder.to_svg
  end
end
puts "Average time per render: #{(no_cache_time / ITERATIONS * 1000).round(2)}ms"
puts "Total time for #{ITERATIONS} iterations: #{no_cache_time.round(2)}s"

puts "\n2. With query result caching"
Rails.cache.clear
query_cache_time = Benchmark.realtime do
  ITERATIONS.times do
    data = Rails.cache.fetch("user:#{user.id}:heatmap_data", expires_in: 1.hour) do
      user.posts_heatmap_data
    end
    builder = HeatmapBuilder.new(
      data: data,
      start_date: Date.current - 365,
      end_date: Date.current,
      month_labels: true,
      day_labels: true
    )
    builder.to_svg
  end
end
puts "Average time per render: #{(query_cache_time / ITERATIONS * 1000).round(2)}ms"
puts "Total time for #{ITERATIONS} iterations: #{query_cache_time.round(2)}s"
puts "Speedup: #{(no_cache_time / query_cache_time).round(2)}x"

puts "\n3. With SVG caching"
Rails.cache.clear
svg_cache_time = Benchmark.realtime do
  ITERATIONS.times do
    Rails.cache.fetch("user:#{user.id}:heatmap_svg", expires_in: 1.hour) do
      data = user.posts_heatmap_data
      builder = HeatmapBuilder.new(
        data: data,
        start_date: Date.current - 365,
        end_date: Date.current,
        month_labels: true,
        day_labels: true
      )
      builder.to_svg
    end
  end
end
puts "Average time per render: #{(svg_cache_time / ITERATIONS * 1000).round(2)}ms"
puts "Total time for #{ITERATIONS} iterations: #{svg_cache_time.round(2)}s"
puts "Speedup: #{(no_cache_time / svg_cache_time).round(2)}x"

puts "\n" + "=" * 80
puts "SUMMARY"
puts "=" * 80
puts "No cache:        #{(no_cache_time / ITERATIONS * 1000).round(2)}ms per render"
puts "Query cache:     #{(query_cache_time / ITERATIONS * 1000).round(2)}ms per render (#{(no_cache_time / query_cache_time).round(2)}x faster)"
puts "SVG cache:       #{(svg_cache_time / ITERATIONS * 1000).round(2)}ms per render (#{(no_cache_time / svg_cache_time).round(2)}x faster)"

# Test cache size
Rails.cache.clear
data = user.posts_heatmap_data
svg = HeatmapBuilder.new(
  data: data,
  start_date: Date.current - 365,
  end_date: Date.current,
  month_labels: true,
  day_labels: true
).to_svg

puts "\nCache size analysis:"
puts "Query result size: ~#{data.to_json.bytesize} bytes"
puts "SVG size: ~#{svg.bytesize} bytes"

puts "\nRecommendation:"
if svg_cache_time < query_cache_time
  puts "✓ Use SVG caching for best performance"
  puts "  - Fastest rendering time"
  puts "  - Good for read-heavy workloads"
  puts "  - Cache invalidation needed when new posts are imported"
else
  puts "✓ Use query caching for balance"
  puts "  - Good performance"
  puts "  - Smaller cache footprint"
  puts "  - Allows for flexible rendering options"
end
