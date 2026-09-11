module JsonResponseTestHelpers
  def json(body, status: 200)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end
end
