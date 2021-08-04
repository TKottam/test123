terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
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
}
