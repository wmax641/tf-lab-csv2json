resource "aws_s3_bucket" "bucket" {
  bucket = var.base_name
  tags   = merge({ "Name" = "${var.base_name}" }, var.common_tags)
}
resource "aws_s3_bucket_acl" "bucket_acl" {
  acl    = "private"
  bucket = aws_s3_bucket.bucket.id
}

resource "aws_s3_object" "datafiles" {
  for_each = fileset("datafiles/", "*.{csv,md5}")

  bucket = aws_s3_bucket.bucket.id
  key    = "${each.value}"
  source = "datafiles/${each.value}"
  etag   = filemd5("datafiles/${each.value}")
}

resource "aws_s3_object" "example" {
  for_each = fileset("datafiles/example/", "*")

  bucket = aws_s3_bucket.bucket.id
  key    = "example/${each.value}"
  source = "datafiles/example/${each.value}"
  etag   = filemd5("datafiles/example/${each.value}")
}

data "aws_iam_policy_document" "lambda_assume_role_policy_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_read_role" {
  name               = "${var.base_name}-LambdaReadRole"
  path               = "/service/"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy_doc.json
  inline_policy {
    name = "listLambdaPolicy"
    policy = jsonencode({
      Statement = [
        {
          Sid = "LambdaReadRolePolicy"
          Resource = [
            aws_s3_bucket.bucket.arn,
            "${aws_s3_bucket.bucket.arn}/*"
          ]
          Action = [
            "s3:GetObject",
            "s3:ListBucket"
          ]
          Effect = "Allow"
        }
      ]
    })
  }
  tags = merge({ "Name" = "${var.base_name}-LambdaReadRole" }, var.common_tags)
}

resource "aws_iam_role" "lambda_write_role" {
  name               = "${var.base_name}-LambdaWriteRole"
  path               = "/service/"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy_doc.json
  inline_policy {
    name = "uploadLinkLambdaPolicy"
    policy = jsonencode({
      Statement = [
        {
          Sid = "LambdaWriteRolePolicy"
          Resource = [
            aws_s3_bucket.bucket.arn,
            "${aws_s3_bucket.bucket.arn}/*"
          ]
          Action = ["s3:putObject"]
          Effect = "Allow"
        },
        {
          Sid = "LambdaWriteRolePolicyInverse"
          Resource = [
            for key in values(aws_s3_object.datafiles)[*].id : "${aws_s3_bucket.bucket.arn}/${key}"
          ]
          Action = ["*"]
          Effect = "Deny"
        }
      ]
    })
  }
  tags = merge({ "Name" = "${var.base_name}-LambdaWriteRole" }, var.common_tags)
}


data "archive_file" "list" {
  type             = "zip"
  source_file      = "${path.module}/lambda/list.py"
  output_file_mode = "0666"
  output_path      = "${path.module}/lambda/list.py.zip"
}

data "archive_file" "upload_link" {
  type             = "zip"
  source_file      = "${path.module}/lambda/uploadLink.py"
  output_file_mode = "0666"
  output_path      = "${path.module}/lambda/uploadLink.py.zip"
}

resource "aws_lambda_function" "list" {
  filename      = data.archive_file.list.output_path
  function_name = "${var.base_name}-list-lambda"
  role          = aws_iam_role.lambda_read_role.arn
  handler       = "list.lambda_handler"

  source_code_hash = filebase64sha256(data.archive_file.list.output_path)

  runtime = "python3.9"

  environment {
    variables = {
      BUCKET_NAME     = aws_s3_bucket.bucket.id
      PROTECTED_FILES = var.protected_file_list
    }
  }
  tags = merge({ "Name" = "${var.base_name}-list-lambda" }, var.common_tags)
}

resource "aws_lambda_function" "upload_link" {
  filename      = data.archive_file.upload_link.output_path
  function_name = "${var.base_name}-uploadLink-lambda"
  role          = aws_iam_role.lambda_write_role.arn
  handler       = "uploadLink.lambda_handler"

  source_code_hash = filebase64sha256(data.archive_file.upload_link.output_path)

  runtime = "python3.9"

  environment {
    variables = {
      BUCKET_NAME     = aws_s3_bucket.bucket.id
      PROTECTED_FILES = var.protected_file_list
    }
  }
  tags = merge({ "Name" = "${var.base_name}-uploadLink-lambda" }, var.common_tags)
}

resource "aws_apigatewayv2_api" "api_gateway" {
  name          = var.base_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_route" "list" {
  api_id    = aws_apigatewayv2_api.api_gateway.id
  route_key = "GET /list"

  target = "integrations/${aws_apigatewayv2_integration.list.id}"
}
resource "aws_apigatewayv2_route" "upload_link" {
  api_id    = aws_apigatewayv2_api.api_gateway.id
  route_key = "GET /uploadLink"

  target = "integrations/${aws_apigatewayv2_integration.upload_link.id}"
}

resource "aws_apigatewayv2_integration" "list" {
  api_id           = aws_apigatewayv2_api.api_gateway.id
  integration_type = "AWS_PROXY"

  connection_type      = "INTERNET"
  description          = "GET list Lambda"
  integration_method   = "POST"
  integration_uri      = aws_lambda_function.list.invoke_arn
  passthrough_behavior = "WHEN_NO_MATCH"
}
resource "aws_apigatewayv2_integration" "upload_link" {
  api_id           = aws_apigatewayv2_api.api_gateway.id
  integration_type = "AWS_PROXY"

  connection_type      = "INTERNET"
  description          = "GET uploadLink Lambda"
  integration_method   = "POST"
  integration_uri      = aws_lambda_function.upload_link.invoke_arn
  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_apigatewayv2_deployment" "deployment" {
  api_id      = aws_apigatewayv2_api.api_gateway.id
  description = "deployment!!"

  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_apigatewayv2_route.list,
    aws_apigatewayv2_route.upload_link
  ]
}

resource "aws_apigatewayv2_stage" "v1" {
  api_id        = aws_apigatewayv2_api.api_gateway.id
  name          = "v1"
  auto_deploy   = true
  deployment_id = aws_apigatewayv2_deployment.deployment.id
}

resource "aws_lambda_permission" "lambda_permission_list" {
  statement_id  = "allow_api_gateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api_gateway.execution_arn}/*"
}

resource "aws_lambda_permission" "lambda_permission_upload_link" {
  statement_id  = "allow_api_gateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_link.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api_gateway.execution_arn}/*"
}
