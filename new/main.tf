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
}

data "aws_vpc" "main_vpc" {
  #cidr_block = "172.31.0.0/16"
  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}"]
  }
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

  tags {
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

data "aws_subnet" "subnets" {
   # count  = "${length(var.subnet_names)}"

    #vpc_id = "{${data.aws_vpc.main_vpc.id}}"
    filter {
        name = "tag:Name"
        values = ["${var.subnet_names[count.index]}"]
    }

}

output "subnet1_tags" {
  value = "${data.aws_subnet.subnets.*.tags}"
}



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
  subnets            = ["${data.aws_subnet_ids.subnet.ids}"]
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
  health_check = {
    path    = "/"
    matcher = "200-299"
    port    = "${lookup(var.services[count.index], "container_port")}"
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_alb_listener" "alb_listener_backend" {
  count = "${length(var.services)}"
  load_balancer_arn = "${aws_lb.main_alb.*.id}"
  port              = "${var.alb_port}"
  protocol          = "HTTP"
  #ssl_policy        = "ELBSecurityPolicy-2016-08"
  #certificate_arn   = "TODO_ADD"

  default_action {
    target_group_arn = "${aws_alb_target_group.alb_target_group.*.id}"
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
  family                   = "${var.ecs_cluster_name}-task-definition"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.task_cpu}"
  memory                   = "${var.task_memory}"
  network_mode             = "awsvpc"
  execution_role_arn       = "${aws_iam_role.ecs_role.arn}"
  task_role_arn            = "${aws_iam_role.ecs_role.arn}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${lookup(var.services[0], "cpu")},
    "image": "${lookup(var.services[0], "image")}",
    "memory": ${lookup(var.services[0],"memory")},
    "name": "${lookup(var.services[0], "name")}",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${lookup(var.services[0], "container_port")},
        "hostPort": ${lookup(var.services[0], "host_port")}
      }
    ],
    "environment": [
      {
        "name": "App",
        "value": "${lookup(var.services[0], "tier")}"
      }
    ]
  }
  ,
    {
    "cpu": ${lookup(var.services[1], "cpu")},
    "image":  "${lookup(var.services[1], "image")}",
    "memory": ${lookup(var.services[1],"memory")},
    "name": "${lookup(var.services[1], "name")}",
    "networkMode": "awsvpc",
    "portMappings": [
    {
        "containerPort": ${lookup(var.services[1],"container_port")},
        "hostPort": ${lookup(var.services[1],"host_port")}
      }
    ],
    "environment": [
      {
        "name": "App",
        "value": "${lookup(var.services[1], "tier")}"
      }
    ]
  }
]
DEFINITION
}

resource "aws_ecs_service" "ecs-service" {
  count = "${length(var.services)}"
  name            = "${lookup(var.services[count.index], "name")}"
  task_definition = "${aws_ecs_task_definition.ecs-task-definition.arn}"
  cluster         = "${aws_ecs_cluster.ecs_cluster.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true                                                                                                               // Needs to be set to true in a vpc that has public ips
    security_groups  = ["${aws_security_group.ecs_tasks_sg.*.id}"]
    subnets          = ["${data.aws_subnet.subnets.*.id}"]
  }

  load_balancer {
    container_name   = "${lookup(var.services[count.index], "name")}"
    container_port   = "${lookup(var.services[count.index], "container_port")}"
    target_group_arn = "${aws_alb_target_group.alb_target_group.*.arn}"
  }

  # depends_on = [
  #   "aws_alb_listener.alb_listener_backend",
  # ]
}

data "aws_route53_zone" "selected" {
  name         = "${var.route53_zone_domain}"
  private_zone = false
}


resource "aws_route53_record" "route53_record" {
  count = "${length(var.services)}"
  zone_id        = "${data.aws_route53_zone.selected.zone_id}"
  name           = "${lookup(var.services[count.index], "name")}"
  type           = "CNAME"
  ttl            = "60"
  set_identifier = "${aws_lb.main_alb.*.dns_name}"
  records        = ["${aws_lb.main_alb.*.dns_name}"]
  weighted_routing_policy {
    weight = 10
  }
}

output "service_fqdn" {
  value = "${aws_route53_record.route53_record.*.fqdn}"
}

output "service_name" {
  value = "${aws_route53_record.route53_record.*.name}"
}

