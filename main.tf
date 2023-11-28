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

resource "aws_cloudwatch_log_group" "lambda_logging" {
  name              = "/aws/lambda/example-lambda-function"
  retention_in_days = 5
}

resource "aws_lambda_function" "lambda" {
  function_name = "hello_lambda"

  filename         = "${data.archive_file.zip.output_path}"
  source_code_hash = "${data.archive_file.zip.output_base64sha256}"

  role    = "${aws_iam_role.iam_for_lambda.arn}"
  depends_on = [aws_cloudwatch_log_group.lambda_logging]

  handler = "app.lambdaHandler"
  runtime = "nodejs16.x"

  environment {
    variables = {
      greeting = "Hello"
    }
  }
}

# Create REST API
resource "aws_api_gateway_rest_api" "example" {
  name        = "example"
  description = "Example REST API for Lambda"
}

# Create a resource in the API, this is just a logical container.
resource "aws_api_gateway_resource" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_rest_api.example.root_resource_id
  path_part   = "myresource"
}

# Define a GET method on the above resource.
resource "aws_api_gateway_method" "example" {
  rest_api_id   = aws_api_gateway_rest_api.example.id
  resource_id   = aws_api_gateway_resource.example.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = true
}

# Connect the Lambda function to the GET method via an integration.
resource "aws_api_gateway_integration" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example.http_method

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

  source_arn = "${aws_api_gateway_rest_api.example.execution_arn}/*/${aws_api_gateway_method.example.http_method}${aws_api_gateway_resource.example.path}"
}

# The Deploy stage of the API.
resource "aws_api_gateway_deployment" "example" {
  depends_on = [aws_api_gateway_integration.example]

  rest_api_id = aws_api_gateway_rest_api.example.id
  stage_name  = "test"
  description = "This is a test"

  variables = {
    "lambdaFunctionName" = aws_lambda_function.lambda.function_name
  }
}

resource "aws_api_gateway_api_key" "demo_api_key" {
  name = "demo_api_key"
}

resource "aws_api_gateway_usage_plan" "demo_api_usage_plan" {
  name = "demo_usage_plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.example.id
    stage  = "${aws_api_gateway_deployment.example.stage_name}"
  }
}

resource "aws_api_gateway_usage_plan_key" "demo_api_usage_plan_key" {
  key_id        = "${aws_api_gateway_api_key.demo_api_key.id}"
  key_type      = "API_KEY"
  usage_plan_id = "${aws_api_gateway_usage_plan.demo_api_usage_plan.id}"
}



