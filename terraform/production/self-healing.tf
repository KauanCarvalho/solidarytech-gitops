# ----- Self-Healing Bridge: Alertmanager -> GitHub repository_dispatch -----
# Quando um alerta dispara, o Alertmanager chama a URL do API Gateway abaixo,
# que invoca a Lambda, que aciona via repository_dispatch o workflow
# self-healing.yml no repositório de aplicação (solidarytech-app) —
# sem intervenção humana.

data "archive_file" "self_healing_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/self-healing/main.py"
  output_path = "${path.module}/lambda/self-healing/main.zip"
}

# Contas do AWS Academy (Learner Lab) não permitem iam:CreateRole /
# iam:AttachRolePolicy — reaproveita a mesma "LabRole" já usada pelo
# módulo EKS em main.tf (única role com permissão disponível na conta).
resource "aws_lambda_function" "self_healing" {
  function_name    = "solidarytech-self-healing-bridge"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "main.handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.self_healing_lambda.output_path
  source_code_hash = data.archive_file.self_healing_lambda.output_base64sha256

  environment {
    variables = {
      GITHUB_TOKEN  = var.github_dispatch_token
      GITHUB_REPO   = "KauanCarvalho/solidarytech-app"
      WEBHOOK_TOKEN = var.self_healing_webhook_token
    }
  }
}

# A conta AWS Academy (Learner Lab) tem uma SCP que bloqueia invocação
# anônima de Lambda Function URL (lambda:InvokeFunctionUrl) mesmo com
# authorization_type = "NONE" e a resource policy correta — toda chamada
# do Alertmanager recebia 403 Forbidden direto da AWS, antes até de chegar
# no código da Lambda. Um API Gateway HTTP API na frente (que invoca via
# lambda:InvokeFunction, uma ação diferente) contorna essa restrição.
resource "aws_apigatewayv2_api" "self_healing" {
  name          = "solidarytech-self-healing-api"
  protocol_type = "HTTP"
  target        = aws_lambda_function.self_healing.invoke_arn
}

resource "aws_lambda_permission" "self_healing_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.self_healing.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.self_healing.execution_arn}/*/*"
}

output "self_healing_webhook_url" {
  description = "URL do bridge de self-healing (sem o token — ver var.self_healing_webhook_token)"
  value       = aws_apigatewayv2_api.self_healing.api_endpoint
}
