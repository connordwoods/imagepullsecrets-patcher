# The credentials should be supplied as a base64 encoded string.
# .docker/config.json stores credentials locally as base64
# or they can be generated through command line: $ echo “username:password” | base64
variable "auth_base64" {
  description = "The BASE64-ENCODED (!!!!!!!) auth credentials for the registry, in the decoded form it is `username:password`, but you MUST provide it Base64-encoded, otherwise you will break ALL docker image pulls from all registries!"
  type        = string
  sensitive   = true
}

# The registry URL is set to docker but can be modified for other registries if desired.
variable "url" {
  description = "The URL of the private registry. Can be provided as a full URL or just the domain name (e.g. docker.pkg.github.com)."
  type        = string
  default     = "https://index.docker.io/v2/"
}

variable "check_interval" {
  description = "The interval to periodically check for new service accounts to patch"
  type        = string
  default     = "30s"
}

variable "excluded_namespaces" {
  description = "List of namespaces to exclude from patching their service accounts with the private registry configuration"
  type        = list(string)
  default = [
    # These initial namespaces are excluded from the patcher as seen here https://github.com/titansoft-pte-ltd/imagepullsecret-patcher/issues/21
    "kube-node-lease",
    "kube-public"
  ]
}