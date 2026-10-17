locals {
  environments = {
    staging    = aws_instance.staging.id
    production = aws_instance.production.id
  }
}

resource "aws_cloudwatch_log_group" "staging" {
  name              = "/lacrei/staging"
  retention_in_days = 7

  tags = {
    Name = "/lacrei/staging"
  }
}

resource "aws_cloudwatch_log_group" "production" {
  name              = "/lacrei/production"
  retention_in_days = 30

  tags = {
    Name = "/lacrei/production"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.environments

  alarm_name          = "lacrei-${each.key}-cpu-high"
  alarm_description   = "CPU above 80% for ${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  for_each = local.environments

  alarm_name          = "lacrei-${each.key}-status-check-failed"
  alarm_description   = "EC2 status check failed for ${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "api" {
  dashboard_name = "lacrei-api"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title   = "EC2 CPU"
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          period  = 300
          stat    = "Average"
          metrics = [
            for environment, instance_id in local.environments :
            ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id, { label = environment }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          title   = "EC2 Status Checks"
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          period  = 60
          stat    = "Maximum"
          metrics = [
            for environment, instance_id in local.environments :
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", instance_id, { label = environment }]
          ]
        }
      }
    ]
  })
}
