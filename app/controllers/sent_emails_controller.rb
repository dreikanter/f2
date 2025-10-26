class SentEmailsController < ApplicationController
  allow_unauthenticated_access

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
    parts = content.split(/^---\s*$/, 3)

    begin
      frontmatter = YAML.safe_load(parts[1], permitted_classes: [Time, Date, DateTime], aliases: true) || {}
    rescue Psych::SyntaxError
      frontmatter = {}
    end

    body_content = parts[2]&.strip || ""

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
end
