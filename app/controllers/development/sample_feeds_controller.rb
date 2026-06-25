class Development::SampleFeedsController < ApplicationController
  # A mock feed source for exercising the add-feed detection and self-test
  # states by hand. Copy development_sample_feed_url(state:) into the add-feed
  # form to see how each outcome renders; the Feed Sandbox page lists them all.
  #
  # Detection fetches this server-side with no session, so it allows
  # unauthenticated access and is kept out of production (see #show) instead of
  # behind a user permission an anonymous fetch can't satisfy.
  allow_unauthenticated_access only: :show

  STATES = {
    "ok" => {
      summary: "Valid RSS feed with five recent items",
      outcome: "RSS is detected and the self-test passes with posts"
    },
    "empty" => {
      summary: "Valid RSS feed with no items",
      outcome: "RSS passes the self-test but is flagged as having no posts yet"
    },
    "atom" => {
      summary: "Valid Atom feed with three entries",
      outcome: "The feed is detected and the self-test passes"
    },
    "malformed" => {
      summary: "Looks like RSS, but the XML is broken",
      outcome: "RSS is detected but the self-test fails, so the option is disabled"
    },
    "not_feed" => {
      summary: "An ordinary HTML page with no feed inside",
      outcome: "Nothing structured matches, so only the AI fallback is offered"
    },
    "not_found" => {
      summary: "Responds with 404 Not Found",
      outcome: "Identification fails — the source responds, but the page is missing"
    },
    "forbidden" => {
      summary: "Responds with 403 Forbidden",
      outcome: "Identification fails — the source responds, but denies access"
    },
    "unauthorized" => {
      summary: "Responds with 401 Unauthorized",
      outcome: "Identification fails — the source responds, but requires sign-in"
    },
    "server_error" => {
      summary: "Responds with 500 Internal Server Error",
      outcome: "Identification fails — the source responds with a server error"
    },
    "slow" => {
      summary: "Hangs well past the fetch timeout (about 20 seconds)",
      outcome: "Identification fails — the request times out"
    },
    "redirect" => {
      summary: "Redirects (302) to the valid feed",
      outcome: "The redirect is followed and the self-test passes"
    },
    "redirect_loop" => {
      summary: "Redirects to itself without end",
      outcome: "Identification fails — too many redirects"
    }
  }.freeze

  DEFAULT_DELAY = 20
  MAX_DELAY = 30

  def show
    return head :not_found if Rails.env.production?

    case params[:state]
    when "empty" then render_source(empty_rss)
    when "atom" then render_source(atom_feed, content_type: "application/atom+xml")
    when "malformed" then render_source(malformed_rss)
    when "not_feed" then render_source(html_page, content_type: "text/html")
    when "not_found" then render_status(:not_found)
    when "forbidden" then render_status(:forbidden)
    when "unauthorized" then render_status(:unauthorized)
    when "server_error" then render_status(:internal_server_error)
    when "slow" then render_slow
    when "redirect" then redirect_to development_sample_feed_path(state: "ok")
    when "redirect_loop" then redirect_to development_sample_feed_path(state: "redirect_loop")
    else render_source(sample_rss)
    end
  end

  private

  def render_source(body, content_type: "application/rss+xml")
    render body: body, content_type: content_type
  end

  def render_status(status)
    render plain: "Sample feed mock: simulated #{status.to_s.humanize.downcase} response.", status: status
  end

  # Holds the connection open past the loader's fetch timeout so detection
  # surfaces the timeout path. Tests pass delay=0 to skip the wait.
  def render_slow
    sleep(params.fetch(:delay, DEFAULT_DELAY).to_i.clamp(0, MAX_DELAY))
    render_source(sample_rss)
  end

  def sample_rss
    items = (1..5).map { |n| rss_item(n) }.join("\n")
    rss_document("Sample Feed (mock)", items)
  end

  def empty_rss
    rss_document("Empty Sample Feed (mock)", "")
  end

  def rss_document(title, items)
    <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>#{title}</title>
          <link>https://example.com</link>
          <description>A mock RSS feed served by the development sandbox.</description>
      #{items}
        </channel>
      </rss>
    RSS
  end

  def rss_item(number)
    published = (Time.current - number.hours).to_fs(:rfc822)
    <<~ITEM.chomp
          <item>
            <title>Sample post ##{number}</title>
            <link>https://example.com/posts/#{number}</link>
            <guid isPermaLink="false">sample-feed-post-#{number}</guid>
            <pubDate>#{published}</pubDate>
            <description>Sample post number #{number}, served by the dev mock feed source.</description>
          </item>
    ITEM
  end

  def atom_feed
    entries = (1..3).map { |n| atom_entry(n) }.join("\n")

    <<~ATOM
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Sample Atom Feed (mock)</title>
        <link href="https://example.com"/>
        <id>urn:dev:sample-atom-feed</id>
        <updated>#{Time.current.iso8601}</updated>
      #{entries}
      </feed>
    ATOM
  end

  def atom_entry(number)
    updated = (Time.current - number.hours).iso8601

    <<~ENTRY.chomp
        <entry>
          <title>Sample entry ##{number}</title>
          <link href="https://example.com/entries/#{number}"/>
          <id>urn:dev:sample-atom-entry-#{number}</id>
          <updated>#{updated}</updated>
          <summary>Sample Atom entry number #{number}, served by the dev mock feed source.</summary>
        </entry>
    ENTRY
  end

  # Carries the <rss> marker so the RSS profile matches, but the body is not
  # valid XML, so parsing blows up and the self-test reports it as unreadable.
  def malformed_rss
    %(<rss version="2.0"> <<< this is not valid XML &amp & %%% </oops>)
  end

  def html_page
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
        <head><title>Just a web page</title></head>
        <body>
          <h1>Hello</h1>
          <p>An ordinary web page with no syndication markup of any kind.</p>
        </body>
      </html>
    HTML
  end
end
