terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    bucket = "mybackendproject-123456789"
    key    = "backend.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "default"
}



module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "17.1.0"

  cluster_name    = "test"
  cluster_version = "1.20"
  vpc_id          = "vpc-5cac4721"
  subnets         = ["subnet-bfb726b1", "subnet-6930ea48", "subnet-2f974849", "subnet-65a3cc28", "subnet-98e139c7"]

  worker_groups = [
    {
      instance_type = "t2.medium"
      asg_max_size  = 3
    }
  ]
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  #   load_config_file       = false
}

# resource "kubernetes_service" "example" {
#   metadata {
#     name = "terraform-example"
#   }
#   spec {
#     selector = {
#       app = kubernetes_pod.example.metadata.0.labels.app
#     }
#     port {
#       port        = 8080
#       target_port = 80
#     }

#     type = "LoadBalancer"
#   }
# }

# resource "kubernetes_pod" "example" {
#   metadata {
#     name = "terraform-example"
#     labels = {
#       app = "MyApp"
#     }
#   }

#   spec {
#     container {
#       image = "nginx:1.7.9"
#       name  = "example"
#     }
#   }
# }

# output "load_balancer_ip" {
#   value = "${kubernetes_pod.example}"
# }

resource "kubernetes_deployment" "example" {
  metadata {
    name = "kottam-cicd"
    labels = {
      env = "prod"
    }
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        env = "prod"
      }
    }

    template {
      metadata {
        labels = {
          env = "prod"
        }
      }

      spec {
        container {
          image = "ashishkr99/kottam-cicd:latest"
          name  = "example"

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "example" {
  metadata {
    name = "kottam-cicd"
  }
  spec {
    selector = {
      env = "prod"
    }
    port {
      port        = 5000
      target_port = 5000
    }

    type = "LoadBalancer"
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

resource "helm_release" "grafana" {
  name = "grafana"

  repository = "https://charts.bitnami.com/bitnami"
  chart      = "grafana"

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "admin.user"
    value = "adminuser"
  }

  set {
    name  = "admin.password"
    value = "password@123"
  }

  set {
    name  = "metrics.enabled"
    value = "true"
  }
}

resource "helm_release" "kube-prometheus" {
  name = "kube-prometheus"

  repository = "https://charts.bitnami.com/bitnami"
  chart      = "kube-prometheus"

  set {
    name  = "prometheus.service.type"
    value = "LoadBalancer"
  }
}

output "grafana" {
  value = "${resourcekubernetes_pod.example}"
}