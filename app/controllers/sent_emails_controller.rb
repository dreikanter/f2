class SentEmailsController < ApplicationController
  allow_unauthenticated_access
  before_action :ensure_development_mode

  def index
    @emails = load_emails.sort_by { |e| e[:timestamp] }.reverse
  end

  def show
    filename = "#{params[:id]}.txt"
    filepath = emails_dir.join(filename)

    unless File.exist?(filepath)
      redirect_to sent_emails_path, alert: "Email not found"
      return
    end

    @email = parse_email_file(filepath)
    @filename = filename
  end

  def purge
    FileUtils.rm_rf(emails_dir)
    FileUtils.mkdir_p(emails_dir)
    redirect_to sent_emails_path, notice: "All emails purged"
  end

  private

  def ensure_development_mode
    unless Rails.env.development? || Rails.env.test?
      render plain: "Not available in #{Rails.env} mode", status: :forbidden
    end
  end

  def emails_dir
    Rails.root.join("tmp", "sent_emails")
  end

  def load_emails
    return [] unless Dir.exist?(emails_dir)

    Dir.glob(emails_dir.join("*.txt")).map do |filepath|
      filename = File.basename(filepath)
      match = filename.match(/^(\d{8}_\d{6}_\d{3})_([0-9a-f\-]+)\.txt$/)

      next unless match

      timestamp_str = match[1]
      timestamp = DateTime.strptime(timestamp_str, "%Y%m%d_%H%M%S_%L")

      # Parse email file to get subject
      email = parse_email_file(filepath)

      {
        id: filename.delete_suffix(".txt"),
        filename: filename,
        subject: email[:subject],
        timestamp: timestamp,
        size: File.size(filepath)
      }
    end.compact
  end

  def parse_email_file(filepath)
    content = File.read(filepath)

    # Parse YAML frontmatter
    if content.start_with?("---\n")
      parts = content.split(/^---\s*$/, 3)
      begin
        frontmatter = YAML.safe_load(parts[1], permitted_classes: [Time, Date, DateTime], aliases: true) || {}
      rescue Psych::SyntaxError => e
        Rails.logger.error "Failed to parse YAML in #{filepath}: #{e.message}"
        frontmatter = {}
      end
      body_content = parts[2]&.strip || ""
    else
      # Fallback for old format (backward compatibility)
      return parse_legacy_email_file(content)
    end

    email = {
      message_id: frontmatter["message_id"],
      from: frontmatter["from"],
      to: frontmatter["to"],
      subject: frontmatter["subject"],
      date: frontmatter["date"],
      multipart: frontmatter["multipart"] || false,
      body: "",
      text_part: nil,
      html_part: nil
    }

    # Parse body
    if email[:multipart]
      if body_content.include?("TEXT:") && body_content.include?("HTML:")
        text_start = body_content.index("TEXT:")
        html_start = body_content.index("HTML:")

        email[:text_part] = body_content[text_start + 5...html_start].strip
        email[:html_part] = body_content[html_start + 5..-1].strip
      end
    else
      email[:body] = body_content
    end

    email
  end

  def parse_legacy_email_file(content)
    lines = content.lines

    email = {
      message_id: nil,
      from: nil,
      to: nil,
      subject: nil,
      date: nil,
      body: "",
      text_part: nil,
      html_part: nil,
      multipart: false
    }

    # Parse headers
    idx = 0
    while idx < lines.length && lines[idx].strip != ""
      line = lines[idx]
      case line
      when /^From: (.+)/
        email[:from] = $1.strip
      when /^To: (.+)/
        email[:to] = $1.strip
      when /^Subject: (.+)/
        email[:subject] = $1.strip
      when /^Date: (.+)/
        email[:date] = $1.strip
      end
      idx += 1
    end

    # Skip empty line after headers
    idx += 1

    # Parse body
    if content.include?("--- TEXT PART ---")
      email[:multipart] = true
      text_start = content.index("--- TEXT PART ---")
      html_start = content.index("--- HTML PART ---")

      if text_start && html_start
        email[:text_part] = content[text_start + "--- TEXT PART ---".length...html_start].strip
        email[:html_part] = content[html_start + "--- HTML PART ---".length..-1].strip
      end
    else
      email[:body] = lines[idx..-1].join
    end

    email
  end
end
