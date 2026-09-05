class AiCredentials::ValidationsController < ValidationsController
  include StatePolling

  self.validated_class = AiCredential
end
