class SentEmailsController < ApplicationController
  allow_unauthenticated_access

  def index
    @emails = load_emails.sort_by { |e| e[:timestamp] }.reverse
  end

  def show
    # Validate ID format to prevent path traversal (must be timestamp_uuid)
    unless params[:id] =~ /\A\d{8}_\d{6}_\d{3}_[0-9a-f-]{36}\z/
      redirect_to sent_emails_path, alert: "Invalid email ID"
      return
    end

    base_path = emails_dir.join(params[:id])
    yml_path = "#{base_path}.yml"
    txt_path = "#{base_path}.txt"
    html_path = "#{base_path}.html"

    unless File.exist?(yml_path)
      redirect_to sent_emails_path, alert: "Email not found"
      return
    end

    @email = load_email_from_files(yml_path, txt_path, html_path)

    unless @email
      redirect_to sent_emails_path, alert: "Failed to load email"
      return
    end

    @filename = params[:id]
  end

  def purge
    dir = emails_dir  # Validates path before any destructive operation
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir)
    redirect_to sent_emails_path, notice: "All emails purged"
  rescue => e
    redirect_to sent_emails_path, alert: "Failed to purge emails: #{e.message}"
  end

  private

  def emails_dir
    # Compute and validate the emails directory path
    dir = Rails.root.join("tmp", "sent_emails")
    absolute_dir = dir.expand_path

    # Ensure the path is not blank
    raise "Email directory path is blank" if absolute_dir.to_s.blank?

    # Ensure the path is not a dangerous root directory
    dangerous_paths = [
      Pathname.new("/"),
      Rails.root,
      Rails.root.parent
    ]
    if dangerous_paths.any? { |dangerous| absolute_dir == dangerous.expand_path }
      raise "Email directory cannot be a root or parent directory"
    end

    # Ensure the path is inside Rails.root/tmp
    allowed_base = Rails.root.join("tmp").expand_path
    unless absolute_dir.to_s.start_with?(allowed_base.to_s + "/")
      raise "Email directory must be inside #{allowed_base}"
    end

    absolute_dir
  end

  def load_emails
    return [] unless Dir.exist?(emails_dir)

    Dir.glob(emails_dir.join("*.yml")).map do |yml_path|
      filename = File.basename(yml_path, ".yml")
      match = filename.match(/^(\d{8}_\d{6}_\d{3})_([0-9a-f\-]+)$/)

      next unless match

      timestamp_str = match[1]
      timestamp = DateTime.strptime(timestamp_str, "%Y%m%d_%H%M%S_%L")

      # Load metadata
      begin
        metadata = YAML.safe_load_file(yml_path, permitted_classes: [Time, Date, DateTime], aliases: true) || {}
      rescue Psych::SyntaxError
        next
      end

      {
        id: filename,
        subject: metadata["subject"],
        timestamp: timestamp,
        size: File.size(yml_path)
      }
    end.compact
  end

  def load_email_from_files(yml_path, txt_path, html_path)
    # Load metadata from YAML file
    begin
      metadata = YAML.safe_load_file(yml_path, permitted_classes: [Time, Date, DateTime], aliases: true) || {}
    rescue Psych::SyntaxError, Errno::ENOENT, IOError => e
      Rails.logger.error "Failed to load email metadata from #{yml_path}: #{e.message}"
      return nil
    end

    # Load text content
    begin
      text_content = File.exist?(txt_path) ? File.read(txt_path) : ""
    rescue Errno::ENOENT, IOError => e
      Rails.logger.error "Failed to load email text from #{txt_path}: #{e.message}"
      text_content = ""
    end

    # Load HTML content if it exists
    begin
      html_content = File.exist?(html_path) ? File.read(html_path) : nil
    rescue Errno::ENOENT, IOError => e
      Rails.logger.error "Failed to load email HTML from #{html_path}: #{e.message}"
      html_content = nil
    end

    {
      message_id: metadata["message_id"],
      from: metadata["from"],
      to: metadata["to"],
      subject: metadata["subject"],
      date: metadata["date"],
      multipart: metadata["multipart"] || false,
      body: metadata["multipart"] ? "" : text_content,
      text_part: metadata["multipart"] ? text_content : nil,
      html_part: html_content
    }
  end
end
