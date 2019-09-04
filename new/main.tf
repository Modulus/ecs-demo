terraform {
  backend "s3" {
    bucket = "terrafromstate-johns-dev-knask"
    key = "terraform/ecs-demo"
    region = "eu-west-1"
    skip_region_validation = true
      profile = "aws5_ecs_demo_admin"
  }
}



provider "aws" {
  region     = "${var.region}"
  profile = "aws5_ecs_demo_admin"
  version = "v2.26.0"
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
  #cidr_block = "172.31.0.0/16"
  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}"]
  }
}

data "aws_subnet_ids" "default_subnet_ids" {
  vpc_id = "${data.aws_vpc.main_vpc.id}"
}

output "vpc_cidr_block" {
  value = "${data.aws_vpc.main_vpc.cidr_block}"
}

output "vpc_tags" {
  value = "${data.aws_vpc.main_vpc.tags}"
}


resource "aws_security_group" "allow_http" {
  name        = "${var.ecs_cluster_name}-web-security-group"
  description = "Control access to ALB"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"

  tags = {
    purpose = "Web traffic"
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "subnet_names" {
    value = ["${var.subnet_names}"]
}

# data "aws_subnet" "subnets" {
#    //count  = "${length(var.subnet_names)}"

#     #vpc_id = "{${data.aws_vpc.main_vpc.id}}"
#     filter {
#         name = "tag:Name"
#         values = ["${var.subnet_names}"]
#     }

# }




resource "aws_security_group" "ecs_tasks_sg" {
  count = "${length(var.services)}"
  name        = "${var.ecs_cluster_name}-${lookup(var.services[count.index], "name")}-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${lookup(var.services[count.index], "container_port")}"
    to_port         = "${lookup(var.services[count.index], "container_port")}"
    security_groups = ["${aws_security_group.allow_http.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#NB! Terraform bug kan ikke bruke  tidligere definerte count subnet
data "aws_subnet_ids" "subnet" {
  vpc_id = "${data.aws_vpc.main_vpc.id}"
}
resource "aws_lb" "main_alb" {
  count = "${length(var.services)}"

  //internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.allow_http.id}"]
  subnets            = flatten(data.aws_subnet_ids.subnet.ids)
  enable_deletion_protection = false

  tags = {
    Environment = "production"
    purpose     = "Demo"
    tier = "${lookup(var.services[count.index], "tier")}"
  }
}


resource "aws_alb_target_group" "alb_target_group" {
  count = "${length(var.services)}"
  name        = "${lookup(var.services[count.index], "tier")}-target-group"
  port        = "80"
  protocol    = "HTTP"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"
  target_type = "ip"
  health_check  {
    path    = "/"
    matcher = "200-299"
    port    = "${lookup(var.services[count.index], "container_port")}"
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_alb_listener" "alb_listener_all" {
  count = "${length(var.services)}"
  load_balancer_arn = "${lookup(aws_lb.main_alb[count.index], "arn")}"
  port              = "${var.alb_port}"
  protocol          = "HTTP"
  default_action {
    target_group_arn = "${lookup(aws_alb_target_group.alb_target_group[count.index], "id")}"
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


resource "aws_ecs_task_definition" "ecs-task-definition" {
  count = "${length(var.services)}"
  family                   = "${var.ecs_cluster_name}-${lookup(var.services[count.index], "tier")}-task-definition"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${lookup(var.services[count.index], "cpu")}"
  memory                   = "${lookup(var.services[count.index], "memory")}"
  network_mode             = "awsvpc"
  execution_role_arn       = "${aws_iam_role.ecs_role.arn}"
  task_role_arn            = "${aws_iam_role.ecs_role.arn}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${lookup(var.services[count.index], "cpu")},
    "image": "${lookup(var.services[count.index], "image")}",
    "memory": ${lookup(var.services[count.index],"memory")},
    "name": "${lookup(var.services[count.index], "name")}",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${lookup(var.services[count.index], "container_port")},
        "hostPort": ${lookup(var.services[count.index], "host_port")}
      }
    ],
    "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-group" : "ecs-demo-logs",
          "awslogs-region" : "${var.region}",
          "awslogs-stream-prefix": "${lookup(var.services[count.index], "tier")}-"
        }
    },
    "environment": [
      {
        "name": "App",
        "value": "${lookup(var.services[count.index], "tier")}"
      }
    ]
  }
]
DEFINITION
}

resource "aws_ecs_service" "ecs-service" {
  count = "${length(var.services)}"
  name            = "${lookup(var.services[count.index], "name")}"
  task_definition = "${lookup(aws_ecs_task_definition.ecs-task-definition[count.index], "arn")}"
  cluster         = "${aws_ecs_cluster.ecs_cluster.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true                                                                                                               // Needs to be set to true in a vpc that has public ips
    security_groups  = ["${lookup(aws_security_group.ecs_tasks_sg[count.index], "id")}"]
    subnets          = flatten(data.aws_subnet_ids.default_subnet_ids.ids)
  }

  load_balancer {
    container_name   = "${lookup(var.services[count.index], "name")}"
    container_port   = "${lookup(var.services[count.index], "container_port")}"
    target_group_arn = "${lookup(aws_alb_target_group.alb_target_group[count.index], "arn")}"
  }

  depends_on = [
    "aws_alb_listener.alb_listener_all"
  ]
}

data "aws_route53_zone" "selected" {
  name         = "${var.route53_zone_domain}"
  private_zone = false
}


resource "aws_route53_record" "a_record" {
  count = "${length(var.services)}"
  zone_id = "${data.aws_route53_zone.selected.zone_id}" #"${aws_route53_zone.primary.zone_id}"
  name           = "${lookup(var.services[count.index], "name")}"

  type = "A"

  alias {
    name = "${lookup(aws_lb.main_alb[count.index], "dns_name")}"
    zone_id = "${lookup(aws_lb.main_alb[count.index], "zone_id")}"
    evaluate_target_health = true
  }
}


output "fqdns" {
  value = ["${aws_route53_record.a_record.*.fqdn}"]
}
