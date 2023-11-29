provider "aws" {
  region  = "ap-northeast-2"
  profile = "matt"
}

provider "archive" {
}

data "archive_file" "zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/app.js"
  output_path = "${path.module}/lambda/app.zip"
}

data "aws_iam_policy_document" "policy" {
  statement {
    sid    = ""
    effect = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = "${data.aws_iam_policy_document.policy.json}"
}

# This attaches the policy needed for logging to the lambda's IAM role. #3
resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = "${aws_iam_role.iam_for_lambda.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "access_product_image_bucket_policy" {
  name        = "TestS3BucketAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${aws_s3_bucket.product_images.id}/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_lambda_s3_bucket_access" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.access_product_image_bucket_policy.arn
}

resource "aws_cloudwatch_log_group" "lambda_logging" {
  name              = "/aws/lambda/cookstore-lambda"
  retention_in_days = 5
}

resource "aws_lambda_function" "lambda" {
  function_name = "cookstoreLambda"

  filename         = "${path.module}/code.zip"

  role    = "${aws_iam_role.iam_for_lambda.arn}"
  depends_on = [aws_cloudwatch_log_group.lambda_logging]

  handler = "app.lambdaHandler"
  runtime = "nodejs16.x"

  environment {
    variables = {
      UploadBucket = aws_s3_bucket.product_images.id
    }
  }
}

# Create REST API
resource "aws_api_gateway_rest_api" "cookstore_api" {
  name        = "cookstore"
  description = "Cookstore REST API for Lambda"
}

# Create a resource in the API, this is just a logical container.
resource "aws_api_gateway_resource" "product_images" {
  rest_api_id = aws_api_gateway_rest_api.cookstore_api.id
  parent_id   = aws_api_gateway_rest_api.cookstore_api.root_resource_id
  path_part   = "product-images"
}

# Define a POST method on the above resource.
resource "aws_api_gateway_method" "cookstore_api_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.cookstore_api.id
  resource_id   = aws_api_gateway_resource.product_images.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

# Connect the Lambda function to the GET method via an integration.
resource "aws_api_gateway_integration" "cookstore_api_get_method_integration" {
  rest_api_id = aws_api_gateway_rest_api.cookstore_api.id
  resource_id = aws_api_gateway_resource.product_images.id
  http_method = aws_api_gateway_method.cookstore_api_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda.invoke_arn
}

# Allow the API to trigger the Lambda function.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.cookstore_api.execution_arn}/*/${aws_api_gateway_method.cookstore_api_post_method.http_method}${aws_api_gateway_resource.product_images.path}"
}

# The Deploy stage of the API.
resource "aws_api_gateway_deployment" "prod" {
  depends_on = [aws_api_gateway_integration.cookstore_api_get_method_integration]

  rest_api_id = aws_api_gateway_rest_api.cookstore_api.id
  stage_name  = "prod"
  description = "prod stage"

  variables = {
    "lambdaFunctionName" = aws_lambda_function.lambda.function_name
  }
}

resource "aws_api_gateway_api_key" "api_key" {
  name = "cookstore_api_key"
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name = "cookstore_usage_plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.cookstore_api.id
    stage  = "${aws_api_gateway_deployment.prod.stage_name}"
  }
}

resource "aws_api_gateway_usage_plan_key" "api_usage_plan_key" {
  key_id        = "${aws_api_gateway_api_key.api_key.id}"
  key_type      = "API_KEY"
  usage_plan_id = "${aws_api_gateway_usage_plan.api_usage_plan.id}"
}

resource "aws_s3_bucket" "product_images" {
  bucket        = "qafgasfgdg123"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "product_image_bucket_access_block" {
  bucket = aws_s3_bucket.product_images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "product_image_bucket_cors_config" {
  bucket = aws_s3_bucket.product_images.bucket

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["http://localhost:5173"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

}


