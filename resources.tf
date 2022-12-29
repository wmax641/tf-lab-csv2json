resource "aws_s3_bucket" "bucket" {
  bucket = var.base_name
  tags   = local.common_tags
}
resource "aws_s3_bucket_acl" "bucket_acl" {
  acl    = "private"
  bucket = aws_s3_bucket.bucket.id
}

resource "aws_s3_object" "datafiles" {
  for_each = fileset("datafiles/", "*.{csv,md5}")

  bucket = aws_s3_bucket.bucket.id
  key    = each.value
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

data "aws_iam_policy_document" "lambda_execution_role_policy_doc" {

  statement {
    resources = [
      aws_s3_bucket.bucket.arn,
      "${aws_s3_bucket.bucket.arn}/*"
    ]

    actions = ["s3:*"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.base_name}ServiceRole"
  path               = "/service/"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy_doc.json
  inline_policy {
    name   = "allow_s3"
    policy = data.aws_iam_policy_document.lambda_execution_role_policy_doc.json
  }
  tags = local.common_tags
}


data "archive_file" "lambda_list_objects_zip" {
  type             = "zip"
  source_file      = "${path.module}/lambda/listFiles.py"
  output_file_mode = "0666"
  output_path      = "${path.module}/lambda/listFiles.py.zip"
}

data "archive_file" "lambda_get_put_objects_zip" {
  type             = "zip"
  source_file      = "${path.module}/lambda/getUploadLink.py"
  output_file_mode = "0666"
  output_path      = "${path.module}/lambda/getUploadLink.py.zip"
}

resource "aws_lambda_function" "list_objects" {
  filename      = data.archive_file.lambda_list_objects_zip.output_path
  function_name = "${var.base_name}-listFiles"
  role          = aws_iam_role.lambda_role.arn
  handler       = "listFiles.lambda_handler"

  source_code_hash = filebase64sha256(data.archive_file.lambda_list_objects_zip.output_path)

  runtime = "python3.9"

  environment {
    variables = {
      BUCKET_NAME     = aws_s3_bucket.bucket.id
      PROTECTED_FILES = var.protected_file_list
    }
  }
  tags = local.common_tags
}

resource "aws_lambda_function" "get_put_object_link" {
  filename      = data.archive_file.lambda_get_put_objects_zip.output_path
  function_name = "${var.base_name}-getUploadLink"
  role          = aws_iam_role.lambda_role.arn
  handler       = "getUploadLink.lambda_handler"

  source_code_hash = filebase64sha256(data.archive_file.lambda_get_put_objects_zip.output_path)

  runtime = "python3.9"

  environment {
    variables = {
      BUCKET_NAME     = aws_s3_bucket.bucket.id
      PROTECTED_FILES = var.protected_file_list
    }
  }
  tags = local.common_tags
}



resource "aws_apigatewayv2_api" "api_gateway" {
  name          = var.base_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_route" "list_objects" {
  api_id    = aws_apigatewayv2_api.api_gateway.id
  route_key = "GET /listObjects"

  target = "integrations/${aws_apigatewayv2_integration.list_objects_integration.id}"
}
resource "aws_apigatewayv2_route" "get_put_object_link" {
  api_id    = aws_apigatewayv2_api.api_gateway.id
  route_key = "GET /getPutObjectLink"

  target = "integrations/${aws_apigatewayv2_integration.get_put_object_link.id}"
}

resource "aws_apigatewayv2_integration" "list_objects_integration" {
  api_id           = aws_apigatewayv2_api.api_gateway.id
  integration_type = "AWS_PROXY"

  connection_type      = "INTERNET"
  description          = "listObjects Lambda"
  integration_method   = "POST"
  integration_uri      = aws_lambda_function.list_objects.invoke_arn
  passthrough_behavior = "WHEN_NO_MATCH"
}
resource "aws_apigatewayv2_integration" "get_put_object_link" {
  api_id           = aws_apigatewayv2_api.api_gateway.id
  integration_type = "AWS_PROXY"

  connection_type      = "INTERNET"
  description          = "getPutObjectLinks Lambda"
  integration_method   = "POST"
  integration_uri      = aws_lambda_function.get_put_object_link.invoke_arn
  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_apigatewayv2_deployment" "deployment" {
  api_id      = aws_apigatewayv2_api.api_gateway.id
  description = "deployment!!"

  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_apigatewayv2_route.list_objects,
  aws_apigatewayv2_route.get_put_object_link]
}

resource "aws_apigatewayv2_stage" "v1" {
  api_id        = aws_apigatewayv2_api.api_gateway.id
  name          = "v1"
  auto_deploy   = true
  deployment_id = aws_apigatewayv2_deployment.deployment.id
}

resource "aws_lambda_permission" "lambda_permission_list_objects" {
  statement_id  = "allow_api_gateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_objects.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api_gateway.execution_arn}/*"
}

resource "aws_lambda_permission" "lambda_permission_get_put_object_link" {
  statement_id  = "allow_api_gateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_put_object_link.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api_gateway.execution_arn}/*"
}
