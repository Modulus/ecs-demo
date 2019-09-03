terraform {
  backend "s3" {
    bucket                 = "terrafromstate-johns-dev-knask"
    key                    = "terraform/ecs-demo"
    region                 = "eu-west-1"
    skip_region_validation = true
    profile                = "aws5_ecs_demo_admin"
  }
}



provider "aws" {
  region  = "${var.region}"
  profile = "aws5_ecs_demo_admin"
}


# Logging fra containere
resource "aws_cloudwatch_log_group" "ecs-demo-logs" {
  name = "ecs-demo-logs"

  tags = {
    Environment = "production"
    Application = "name-generator"
  }
}


data "aws_vpc" "main_vpc" {
  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}"]
  }
}

output "vpc_id" {
  value = "${data.aws_vpc.main_vpc.id}"
}


data "aws_subnet_ids" "default_subnet_ids" {
  vpc_id = "${data.aws_vpc.main_vpc.id}"
}

output "subnet_ids" {
  value = "${data.aws_subnet_ids.default_subnet_ids.ids}"
}

# Security group for alb
resource "aws_security_group" "allow_http" {
  name        = "ecs-demo-alb-security-group"
  description = "Control access to ALB"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"

  tags = {
    purpose     = "Demo"
    Environment = "production"
  }

  ingress {
    # TLS (change to whatever ports you need)
    from_port = "${var.alb_port}"
    to_port   = "${var.alb_port}"
    protocol  = "TCP"

    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = ["0.0.0.0/0"] # add a CIDR block here
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "frontend-task-sg" {
  name        = "ecs-demo-frontend-task-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.frontend_container_port}"
    to_port         = "${var.frontend_container_port}"
    security_groups = ["${aws_security_group.allow_http.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "backend-task-sg" {
  name        = "ecs-demo-bakend-task-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.backend_container_port}"
    to_port         = "${var.backend_container_port}"
    security_groups = ["${aws_security_group.allow_http.id}", "${aws_security_group.frontend-task-sg.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create alb with vpc, subnets and security groups from previous steps
resource "aws_lb" "main_alb" {
  name = "backend-alb"

  //internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.allow_http.id}"]
  subnets            = flatten(data.aws_subnet_ids.default_subnet_ids.ids)

  enable_deletion_protection = false

  tags = {
    Environment = "production"
    purpose     = "Demo"
  }
}



resource "aws_lb" "front_alb" {
  name = "frontend-alb"

  //internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.allow_http.id}"]
  subnets            = flatten(data.aws_subnet_ids.default_subnet_ids.ids)

  enable_deletion_protection = false

  tags = {
    Environment = "production"
    purpose     = "Demo"
  }
}

output "alb_dns_entry" {
  value = "${aws_lb.main_alb.dns_name}"
}


resource "aws_alb_target_group" "backend_alb_target_group" {
  name        = "${var.backend_target_group_name}"
  port        = "${var.backend_container_port}"
  protocol    = "HTTP"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"
  target_type = "ip"
  # slow_start = 30
  health_check {
    path    = "/"
    protocol = "HTTP"
    matcher = "200-299"
    port    = "${var.backend_container_port}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_alb_target_group" "frontend_alb_target_group" {
  name        = "${var.frontend_target_group_name}"
  port        = "${var.frontend_container_port}"
  protocol    = "HTTP"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"
  target_type = "ip"
  # slow_start = 30
  health_check {
    protocol = "HTTP"
    path    = "/"
    matcher = "200-299"
    port    = "${var.frontend_container_port}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_alb_listener" "alb_listener_backend" {
  load_balancer_arn = "${aws_lb.main_alb.id}"
  port              = "80"
  protocol          = "HTTP"


  default_action {
    target_group_arn = "${aws_alb_target_group.backend_alb_target_group.id}"
    type             = "forward"
  }
}

resource "aws_alb_listener" "alb_listene_frontend" {
  load_balancer_arn = "${aws_lb.front_alb.id}"
  port              = "80"
  protocol          = "HTTP"


  default_action {
    target_group_arn = "${aws_alb_target_group.frontend_alb_target_group.id}"
    type             = "forward"
  }
}

resource "aws_iam_role" "ecs_role" {
  name = "ecs-demo-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com",
          "ecs.amazonaws.com",
          "ecs-tasks.amazonaws.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "task_policy" {
  role = "${aws_iam_role.ecs_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:Describe*",
        "ecr:*",
        "ecs:*",
        "logs:*"

      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}



resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.ecs_cluster_name}"

  tags = {
    app = "name-generator"
  }
}

# Valid cpu and memory combos: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html
resource "aws_ecs_task_definition" "name-generator-backend" {
  family                   = "${var.backend_service_name}"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.task_cpu}"
  memory                   = "${var.task_memory}"
  network_mode             = "awsvpc"
  execution_role_arn       = "${aws_iam_role.ecs_role.arn}"
  task_role_arn            = "${aws_iam_role.ecs_role.arn}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.backend_task_cpu},
    "image": "${var.backend_image}",
    "memory": ${var.backend_task_memory},
    "name": "${var.backend_service_name}",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.backend_container_port},
        "hostPort": ${var.backend_container_port}
      }
    ],
    "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-group" : "ecs-demo-logs",
          "awslogs-region" : "${var.region}",
          "awslogs-stream-prefix": "backend-"
        }
    },
    "environment": [
      {
        "name": "App",
        "value": "backend"
      }
    ]
  }
]
DEFINITION
}


# Valid cpu and memory combos: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html
resource "aws_ecs_task_definition" "name-generator-frontend" {
  family                   = "${var.frontend_service_name}"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.frontend_task_cpu}"
  memory                   = "${var.frontend_task_memory}"
  network_mode             = "awsvpc"
  execution_role_arn       = "${aws_iam_role.ecs_role.arn}"
  task_role_arn            = "${aws_iam_role.ecs_role.arn}"

  container_definitions = <<DEFINITION
[
    {
    "cpu": ${var.frontend_task_cpu},
    "image": "${var.frontend_image}",
    "memory": ${var.backend_task_memory},
    "name": "${var.frontend_service_name}",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.frontend_container_port},
        "hostPort": ${var.frontend_container_port}
      }
    ],
    "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-group" : "ecs-demo-logs",
          "awslogs-region" : "${var.region}",
          "awslogs-stream-prefix": "frontend-"
        }

    },
    "environment": [
      {
        "name": "App",
        "value": "backend"
      }
    ]
  }
]
DEFINITION
}


resource "aws_ecs_service" "backend-service" {
  name = "${var.backend_service_name}"
  task_definition = "${aws_ecs_task_definition.name-generator-backend.arn}"
  cluster = "${aws_ecs_cluster.ecs_cluster.arn}"
  desired_count = 1
  launch_type = "FARGATE"

  network_configuration {
    assign_public_ip = true // Needs to be set to true in a vpc that has public ips
    security_groups = ["${aws_security_group.backend-task-sg.id}"]
    subnets = flatten(data.aws_subnet_ids.default_subnet_ids.ids)
  }

  load_balancer {
    container_name = "${var.backend_service_name}"
    container_port = "${var.backend_container_port}"
    target_group_arn = "${aws_alb_target_group.backend_alb_target_group.arn}"
  }

  depends_on = [
    "aws_alb_listener.alb_listener_backend",
  ]
}

resource "aws_ecs_service" "frontend-service" {
  name = "${var.frontend_service_name}"
  task_definition = "${aws_ecs_task_definition.name-generator-backend.arn}"
  cluster = "${aws_ecs_cluster.ecs_cluster.arn}"
  desired_count = 1
  launch_type = "FARGATE"

  network_configuration {
    assign_public_ip = true // Needs to be set to true in a vpc that has public ips
    security_groups = ["${aws_security_group.frontend-task-sg.id}"]
    subnets = flatten(data.aws_subnet_ids.default_subnet_ids.ids)
  }

  load_balancer {
    container_name = "${var.frontend_service_name}"
    container_port = "${var.frontend_container_port}"
    target_group_arn = "${aws_alb_target_group.frontend_alb_target_group.arn}"
  }

  depends_on = [
    "aws_alb_listener.alb_listene_frontend",
  ]
}

// Create route 53 entry based on alb
data "aws_route53_zone" "selected" {
  name = "${var.route53_zone_domain}"
  private_zone = false
}

resource "aws_route53_record" "frontend_alias_record" {
  zone_id ="${data.aws_route53_zone.selected.zone_id}"  #"${aws_route53_zone.primary.zone_id}"
  name = "${var.frontend_service_dns_name}"

  type = "A"

  alias {
    name = "${aws_lb.front_alb.dns_name}"
    zone_id = "${aws_lb.front_alb.zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "backend_alias_record" {
  zone_id = "${data.aws_route53_zone.selected.zone_id}" #"${aws_route53_zone.primary.zone_id}"
  name = "${var.backend_service_dns_name}"

  type = "A"

  alias {
    name = "${aws_lb.main_alb.dns_name}"
    zone_id = "${aws_lb.main_alb.zone_id}"
    evaluate_target_health = false
  }
}

output "backend_service_fqdn" {
  value = "${aws_route53_record.backend_alias_record.fqdn}"
}

output "backend_service_name" {
  value = "${aws_route53_record.backend_alias_record.name}"
}


output "frontend_service_fqdn" {
  value = "${aws_route53_record.frontend_alias_record.fqdn}"
}

output "frontend_service_name" {
  value = "${aws_route53_record.frontend_alias_record.name}"
}