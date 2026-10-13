resource "aws_iam_user" "github_actions" {
  name = "lacrei-github-actions"

  tags = {
    Name = "lacrei-github-actions"
  }
}

data "aws_iam_policy_document" "github_ecr_push" {
  statement {
    sid = "ECRAuthentication"

    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid = "ECRPush"

    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]

    resources = [
      aws_ecr_repository.api.arn
    ]
  }
}

resource "aws_iam_user_policy" "github_ecr_push" {
  name = "lacrei-ecr-push"

  user = aws_iam_user.github_actions.name

  policy = data.aws_iam_policy_document.github_ecr_push.json
}

data "aws_iam_policy_document" "github_ssm_deploy" {
  statement {
    sid    = "FindDeployInstances"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ssm:DescribeInstanceInformation"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "SendDeployCommand"
    effect = "Allow"

    actions = [
      "ssm:SendCommand"
    ]

    resources = [
      "arn:aws:ssm:us-east-1::document/AWS-RunShellScript",
      aws_instance.staging.arn,
      aws_instance.production.arn
    ]
  }

  statement {
    sid    = "ReadDeployCommandResult"
    effect = "Allow"

    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "github_ssm_deploy" {
  name = "lacrei-ssm-deploy"

  user = aws_iam_user.github_actions.name

  policy = data.aws_iam_policy_document.github_ssm_deploy.json
}

data "aws_iam_policy_document" "github_sns_notifications" {
  statement {
    sid    = "PublishDeployNotification"
    effect = "Allow"

    actions = [
      "sns:Publish"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "github_sns_notifications" {
  name = "lacrei-sns-notifications"

  user = aws_iam_user.github_actions.name

  policy = data.aws_iam_policy_document.github_sns_notifications.json
}
