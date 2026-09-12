module OpenaiModelsTestHelpers
  def stub_openai_models(key:, fixture: "listed", status: 200, &block)
    response = { status: status, body: file_fixture("openai_models/#{fixture}.json").read,
                 headers: { "Content-Type" => "application/json" } }
    request = stub_request(:get, "https://api.openai.com/v1/models")
      .with(headers: { "Authorization" => "Bearer #{key}" })
    if block
      request.to_return { |req| block.call(req); response }
    else
      request.to_return(response)
    end
  end
end
