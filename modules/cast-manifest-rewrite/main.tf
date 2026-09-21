data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/files/origin-response.js"
  output_path = "${path.module}/files/origin-response.zip"
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

# publish = true because CloudFront's lambda_function_association rejects
# an unqualified ($LATEST) ARN — it needs a specific published version.
# Lambda@Edge also forbids environment variables, VPC config, and reserved
# concurrency on functions associated with CloudFront; this function needs
# none of those anyway, since it only rewrites the body/query string
# CloudFront already handed it.
resource "aws_lambda_function" "this" {
  function_name    = "${var.name}-cast-manifest-rewrite"
  role             = aws_iam_role.this.arn
  handler          = "origin-response.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  publish          = true
  timeout          = 5
  memory_size      = 128
}
