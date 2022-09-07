#module "global-vars" {
#  source = "../../../../tf-global-vars"
#}

#module "env-vars" {
#  source = "../../tf-env-vars"
#}

locals {
  imagepullsecrets_patcher_name = "imagepullsecrets-patcher"
  imagepullsecrets_patcher_namespace = "kube-system"
}

provider "kubernetes" {
  host = module.env-vars.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(file(module.env-vars.eks_cluster_ca_cert_file))
  exec {
    # Authentication via TokenReview - v1beta1 will be deprecated in k8 v1.22
    # https://kubernetes.io/docs/reference/using-api/deprecation-guide/#tokenreview-v122
    api_version = "client.authentication.k8s.io/v1"
    args = ["eks", "get-token", "--cluster-name", module.env-vars.eks_cluster_name]
    command     = "aws"
  }
  experiments {
    manifest_resource = true
  }
}

terraform {
  backend "s3" {
    bucket = "TO_BE_CHANGED_UNIQUE_BUCKET_NAME_GLOBAL"
    # this key must be unique to the module
    key = "TO_BE_CHANGED_TFSTATE_KEY"
    region = "TO_BE_CHANGED_REGION_AWS"
    dynamodb_table = "TO_BE_CHANGE_DYNAMODB_TABLE_NAME_AWS"
    encrypt = true
  }
}

provider "aws" {
  region = module.env-vars.aws_region
}

resource "kubernetes_cluster_role" "image_pull_secrets" {
  metadata {
    name = local.imagepullsecrets_patcher_name
    labels = {
      k8s-app = local.imagepullsecrets_patcher_name
    }
  }

  rule {
    api_groups = [""]
    resources  = ["secrets", "serviceaccounts"]
    verbs      = ["list", "get", "patch", "create", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["list", "get"]
  }
}

resource "kubernetes_cluster_role_binding" "image_pull_secrets" {
  metadata {
    name = local.imagepullsecrets_patcher_name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.image_pull_secrets.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = local.imagepullsecrets_patcher_namespace
  }
}

resource "kubernetes_secret" "image_pull_secrets" {
  metadata {
    name      = "docker-reg-cred-patcher"
    namespace = local.imagepullsecrets_patcher_namespace
  }

  # We write a JSON file similar to what we have in ~/.docker/config.json to allow access to private registries
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      "auths" : {
        (var.url) : {
          auth = var.auth_base64
        }
      }
    })
  }
}

resource "kubernetes_deployment" "image_pull_secrets" {
  metadata {
    name      = local.imagepullsecrets_patcher_name
    namespace = local.imagepullsecrets_patcher_namespace
    labels = {
      name = local.imagepullsecrets_patcher_name
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = local.imagepullsecrets_patcher_name
      }
    }
    template {
      metadata {
        labels = {
          name = local.imagepullsecrets_patcher_name
        }
      }
      spec {
        automount_service_account_token = true
        service_account_name            = "default"
        container {
          name  = "imagepullsecrets-patcher"
          image = "quay.io/titansoft/imagepullsecret-patcher:v0.14"
          resources {
            requests = {
              cpu    = "100m"
              memory = "15Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "30Mi"
            }
          }
          env {
            # false = only change the default service account in each namespace
            # true = change each service account in each namespace
            # keeping only default as it is the fallback for any namespace otherwise unassigned
            name  = "CONFIG_ALLSERVICEACCOUNT"
            value = false
          }
          env {
            name  = "CONFIG_EXCLUDED_NAMESPACES"
            value = join(",", var.excluded_namespaces)
          }
          env {
            name  = "CONFIG_LOOP_DURATION"
            value = var.check_interval
          }
          env {
            name  = "CONFIG_SECRETNAME"
            value = kubernetes_secret.image_pull_secrets.metadata[0].name
          }
          env {
            name  = "CONFIG_DOCKERCONFIGJSONPATH"
            value = "/app/secrets/.dockerconfigjson"
          }
          volume_mount {
            name       = "src-dockerconfigjson"
            mount_path = "/app/secrets"
            read_only  = true
          }
        }

        volume {
          name = "src-dockerconfigjson"
          secret {
            secret_name = kubernetes_secret.image_pull_secrets.metadata[0].name
          }
        }
      }
    }
  }
}