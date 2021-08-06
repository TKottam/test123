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

variable "availability_zone_names" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"] // Put it manually instead of auto picking active ones due to availability issues of the instance types
}

resource "aws_vpc" "demo" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "demo" {
  count                   = length(var.availability_zone_names)
  availability_zone       = var.availability_zone_names[count.index]
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.demo.id
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id
  tags = {
    Name = "terraform-eks"
  }
}

resource "aws_route_table" "demo" {
  vpc_id = aws_vpc.demo.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }
}

resource "aws_route_table_association" "demo" {
  count          = length(var.availability_zone_names)
  subnet_id      = aws_subnet.demo.*.id[count.index]
  route_table_id = aws_route_table.demo.id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "17.1.0"

  cluster_name    = "test"
  cluster_version = "1.20"
  vpc_id          = aws_vpc.demo.id
  subnets         = aws_subnet.demo[*].id

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

resource "kubernetes_deployment" "kottam-cicd" {
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
          name  = "kottam-cicd"

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

resource "kubernetes_service" "kottam-cicd" {
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

output "kottam-cicd" {
  value = "${kubernetes_service.kottam-cicd.status[0].load_balancer[0].ingress[0].hostname}:${kubernetes_service.kottam-cicd.spec[0].port[0].port}"
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

data "kubernetes_service" "grafana" {
  depends_on = [helm_release.grafana]
  metadata {
    name = "grafana"
  }
}

output "grafana" {
  value = "${data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].hostname}:${data.kubernetes_service.grafana.spec[0].port[0].port}"
}

data "kubernetes_service" "kube-prometheus" {
  depends_on = [helm_release.kube-prometheus]
  metadata {
    name = "kube-prometheus-prometheus"
  }
}

output "kube-prometheus" {
  value = "${data.kubernetes_service.kube-prometheus.status[0].load_balancer[0].ingress[0].hostname}:${data.kubernetes_service.kube-prometheus.spec[0].port[0].port}"
}