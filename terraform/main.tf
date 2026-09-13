terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_caller_identity" "me" {}

resource "aws_s3_bucket" "lectures" {
  bucket        = "lecture-${data.aws_caller_identity.me.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lectures" {
  bucket                  = aws_s3_bucket.lectures.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_user" "worker" {
  name          = "lecture-worker"
  force_destroy = true
}

data "aws_iam_policy_document" "worker" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.lectures.arn]
  }

  # The worker reads the transcript, writes it back, and moves the audio.
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.lectures.arn}/*"]
  }

  statement {
    actions   = ["transcribe:StartTranscriptionJob"]
    resources = ["*"]
  }

  statement {
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:eu-central-1:${data.aws_caller_identity.me.account_id}:inference-profile/eu.amazon.nova-micro-v1:0",
      "arn:aws:bedrock:*::foundation-model/amazon.nova-micro-v1:0",
    ]
  }
}

resource "aws_iam_user_policy" "worker" {
  name   = "lecture-worker"
  user   = aws_iam_user.worker.name
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_iam_access_key" "worker" {
  user = aws_iam_user.worker.name
}

output "bucket" {
  value = aws_s3_bucket.lectures.id
}

output "access_key_id" {
  value = aws_iam_access_key.worker.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.worker.secret
  sensitive = true
}
