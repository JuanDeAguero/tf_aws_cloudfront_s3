variable "hosted_zone_id" {
  type = string
}

variable "cert_arn" {
  type = string
}

locals {
  s3_bucket_name = "restify-bucket"
  domain         = "restify.ca"
}

resource "aws_s3_bucket" "main" {
  bucket = local.s3_bucket_name
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  aliases             = [local.domain]
  default_root_object = "index.html"
  is_ipv6_enabled     = true
  wait_for_deployment = true

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    target_origin_id       = aws_s3_bucket.main.bucket
    viewer_protocol_policy = "redirect-to-https"
  }

  origin {
    domain_name              = aws_s3_bucket.main.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
    origin_id                = aws_s3_bucket.main.bucket
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.cert_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
}

resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "restify-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "cloudfront_oac_access" {
  statement {
    principals {
      identifiers = ["cloudfront.amazonaws.com"]
      type        = "Service"
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/*"]

    condition {
      test     = "StringEquals"
      values   = [aws_cloudfront_distribution.main.arn]
      variable = "AWS:SourceArn"
    }
  }
}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.cloudfront_oac_access.json
}

resource "aws_route53_record" "main" {
  name    = local.domain
  type    = "A"
  zone_id = var.hosted_zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
  }
}