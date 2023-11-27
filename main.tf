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
