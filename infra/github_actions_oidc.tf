resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:pedro11pucci/desafio-lacrei-saude:ref:refs/heads/master"
      ]
    }
  }
}

data "aws_iam_policy_document" "github_ecr_push" {
  statement {
    sid    = "ECRAuthentication"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
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

resource "aws_iam_role" "github_actions" {
  name = "lacrei-github-actions-role"

  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json

  tags = {
    Name = "lacrei-github-actions-role"
  }
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name = "lacrei-ecr-push"

  role = aws_iam_role.github_actions.id

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

resource "aws_iam_role_policy" "github_ssm_deploy" {
  name = "lacrei-ssm-deploy"

  role = aws_iam_role.github_actions.id

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

resource "aws_iam_role_policy" "github_sns_notifications" {
  name = "lacrei-sns-notifications"

  role = aws_iam_role.github_actions.id

  policy = data.aws_iam_policy_document.github_sns_notifications.json
}
