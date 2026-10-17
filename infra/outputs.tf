output "deploy_log_group" {
  value = aws_cloudwatch_log_group.deploy.name
}

output "cloudwatch_dashboard_name" {
  value = aws_cloudwatch_dashboard.api.dashboard_name
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}