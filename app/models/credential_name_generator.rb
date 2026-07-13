# Shared entry point for credential auto-naming. The implementation remains
# compatible with the existing AiCredential::NameGenerator constant while
# both credential models depend on this provider-neutral name.
class CredentialNameGenerator < AiCredential::NameGenerator
end
