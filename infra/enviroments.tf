data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

resource "aws_instance" "staging" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.allow_http.id]
  subnet_id                   = local.subnet_ids[0]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data = templatefile("${path.module}/user_data.sh", {
    domain = "pedro-lacrei-staging.duckdns.org"
  })
  user_data_replace_on_change = true

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "staging"
  }
}

resource "aws_instance" "production" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.allow_http.id]
  subnet_id                   = local.subnet_ids[1]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data = templatefile("${path.module}/user_data.sh", {
    domain = "pedro-lacrei-production.duckdns.org"
  })
  user_data_replace_on_change = true

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "production"
  }
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic and all outbound traffic"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "allow_http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.allow_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic" {
  security_group_id = aws_security_group.allow_http.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}