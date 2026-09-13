terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws]
    }
    null = {
      source = "hashicorp/null"
    }
  }
}
