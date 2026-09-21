# node_modules is gitignored (a full AWS SDK dependency tree is ~3,300
# files — not something to commit into an otherwise Terraform-only repo),
# so `npm install` in files/ has to be run manually before this can be
# applied. Bundling the SDK ourselves rather than relying on the Lambda
# Node.js runtime's built-in version is AWS's own explicit recommendation
# (https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) —
# the runtime-included version isn't guaranteed stable across automatic
# runtime updates. This precondition turns a missing/forgotten npm install
# into a clear plan-time error instead of a Lambda that fails to
# initialize at invocation time — which, associated with the whole
# /audio/* behavior rather than just Cast traffic, would otherwise mean
# every request on that path failing, not just casting.
data "archive_file" "this" {
  type        = "zip"
  source_dir  = "${path.module}/files"
  output_path = "${path.module}/files/origin-request.zip"
  excludes = [
    "origin-request.test.js",
    "package.json",
    "package-lock.json",
    "origin-request.zip",
  ]

  lifecycle {
    precondition {
      condition     = fileexists("${path.module}/files/node_modules/@aws-sdk/client-s3/package.json")
      error_message = "modules/cast-manifest-rewrite/files/node_modules/@aws-sdk/client-s3 is missing — run `npm install` in modules/cast-manifest-rewrite/files/ first."
    }
  }
}

resource "aws_iam_role" "this" {
  name = "${var.name}-cast-manifest-rewrite"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "s3_read" {
  name = "${var.name}-cast-manifest-rewrite-s3-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${var.media_bucket_arn}/*"
      },
      {
        # Without this, GetObject for a key that doesn't exist returns a
        # generic 403 AccessDenied instead of a 404 — S3 masks the real
        # error when the caller can't list the bucket, which makes a
        # wrong-key bug indistinguishable from an actual permissions
        # problem in the logs. Matches ufb's img-resizer Lambda, which
        # hit exactly this ambiguity (see its serverless.yml).
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.media_bucket_arn
      }
    ]
  })
}

# publish = true because CloudFront's lambda_function_association rejects
# an unqualified ($LATEST) ARN — it needs a specific published version.
# Lambda@Edge also forbids environment variables, VPC config, and reserved
# concurrency on functions associated with CloudFront; this function needs
# none of those anyway.
resource "aws_lambda_function" "this" {
  function_name    = "${var.name}-cast-manifest-rewrite"
  role             = aws_iam_role.this.arn
  handler          = "origin-request.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  publish          = true
  timeout          = 5
  memory_size      = 128
}
