variable "region" {}
variable "backend_target_group_name" {}
variable "route53_zone_domain" {} 
variable backend_service_name {   }

variable "task_cpu" {}

variable "task_memory" {}

variable backend_task_cpu {        }
variable backend_task_memory  {}
variable backend_container_port {}  
variable backend_host_port {}   
variable ecs_cluster_name {} 
variable backend_image {} 
variable alb_port {}
variable vpc_name {}
variable subnet1_name {}
variable subnet2_name {}
variable subnet3_name {}

variable frontend_service_name {}
variable frontend_container_port {}
variable frontend_host_port {}
variable frontend_image {}

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

# Security group for alb
resource "aws_security_group" "allow_http" {
  name        = "ecs-demo-backend-security-group"
  description = "Control access to ALB"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"

  tags {
    purpose = "Demo"
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

resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-demo-bakend-task-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.backend_container_port}"
    to_port         = "${var.backend_container_port}"
    security_groups = ["${aws_security_group.allow_http.id}"]
  }

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

# Gather subnets connected to the chosen vpc
data "aws_subnet" "main_subnet1" {
  vpc_id = "${data.aws_vpc.main_vpc.id}"

  filter {
    name   = "tag:Name"
    values = ["${var.subnet1_name}"]
  }
}

data "aws_subnet" "main_subnet2" {
  vpc_id = "${data.aws_vpc.main_vpc.id}"

  filter {
    name   = "tag:Name"
    values = ["${var.subnet2_name}"]
  }
}

data "aws_subnet" "main_subnet3" {
  vpc_id = "${data.aws_vpc.main_vpc.id}"

  filter {
    name   = "tag:Name"
    values = ["${var.subnet3_name}"]
  }
}

output "subnet1_tags" {
  value = "${data.aws_subnet.main_subnet1.tags}"
}

output "subnet2_tags" {
  value = "${data.aws_subnet.main_subnet2.tags}"
}

output "subnet3_tags" {
  value = "${data.aws_subnet.main_subnet3.tags}"
}

# Create alb with vpc, subnets and security groups from previous steps
resource "aws_lb" "main_alb" {
  name = "backend-alb"

  //internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.allow_http.id}"]
  subnets            = ["${data.aws_subnet.main_subnet1.id}", "${data.aws_subnet.main_subnet2.id}", "${data.aws_subnet.main_subnet3.id}"]

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
  subnets            = ["${data.aws_subnet.main_subnet1.id}", "${data.aws_subnet.main_subnet2.id}", "${data.aws_subnet.main_subnet3.id}"]

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
  port        = "80"
  protocol    = "HTTP"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"
  target_type = "ip"
  health_check = {
    path    = "/"
    matcher = "200-299"
    port    = "${var.backend_container_port}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_alb_target_group" "frontend_alb_target_group" {
  name        = "frontend-alb-target-group"
  port        = "80"
  protocol    = "HTTP"
  vpc_id      = "${data.aws_vpc.main_vpc.id}"
  target_type = "ip"

  health_check = {
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
  port              = "${var.alb_port}"
  protocol          = "HTTP"
  #ssl_policy        = "ELBSecurityPolicy-2016-08"
  #certificate_arn   = "TODO_ADD"

  default_action {
    target_group_arn = "${aws_alb_target_group.backend_alb_target_group.id}"
    type             = "forward"
  }
}

resource "aws_alb_listener" "alb_listene_frontend" {
  load_balancer_arn = "${aws_lb.front_alb.id}"
  port              = "${var.alb_port}"
  protocol          = "HTTP"
  #ssl_policy        = "ELBSecurityPolicy-2016-08"
  #certificate_arn   = "TODO_ADD"

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
        "hostPort": ${var.backend_host_port}
      }
    ],
    "environment": [
      {
        "name": "App",
        "value": "backend"
      }
    ]
  },
    {
    "cpu": ${var.backend_task_cpu},
    "image": "${var.frontend_image}",
    "memory": ${var.backend_task_memory},
    "name": "${var.frontend_service_name}",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.frontend_container_port},
        "hostPort": ${var.frontend_host_port}
      }
    ],
    "environment": [
      {
        "name": "App",
        "value": "frontend"
      }
    ]
  }
]
DEFINITION
}

resource "aws_ecs_service" "backend-service" {
  name            = "${var.backend_service_name}"
  task_definition = "${aws_ecs_task_definition.name-generator-backend.arn}"
  cluster         = "${aws_ecs_cluster.ecs_cluster.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true                                                                                                               // Needs to be set to true in a vpc that has public ips
    security_groups  = ["${aws_security_group.ecs_tasks.id}"]
    subnets          = ["${data.aws_subnet.main_subnet1.id}", "${data.aws_subnet.main_subnet2.id}", "${data.aws_subnet.main_subnet3.id}"]
  }

  load_balancer {
    container_name   = "${var.backend_service_name}"
    container_port   = "${var.backend_container_port}"
    target_group_arn = "${aws_alb_target_group.backend_alb_target_group.arn}"
  }

  depends_on = [
    "aws_alb_listener.alb_listener_backend",
  ]
}

resource "aws_ecs_service" "frontend-service" {
  name            = "${var.frontend_service_name}"
  task_definition = "${aws_ecs_task_definition.name-generator-backend.arn}"
  cluster         = "${aws_ecs_cluster.ecs_cluster.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true                                                                                                               // Needs to be set to true in a vpc that has public ips
    security_groups  = ["${aws_security_group.ecs_tasks.id}"]
    subnets          = ["${data.aws_subnet.main_subnet1.id}", "${data.aws_subnet.main_subnet2.id}", "${data.aws_subnet.main_subnet3.id}"]
  }

  load_balancer {
    container_name   = "${var.frontend_service_name}"
    container_port   = "${var.frontend_container_port}"
    target_group_arn = "${aws_alb_target_group.frontend_alb_target_group.arn}"
  }

  depends_on = [
    "aws_alb_listener.alb_listene_frontend",
  ]
}

// Create route 53 entry based on alb
data "aws_route53_zone" "selected" {
  name         = "${var.route53_zone_domain}"
  private_zone = false
}

//// TODO Create A with alias instead of CNAME 
resource "aws_route53_record" "backend_record" {
  zone_id        = "${data.aws_route53_zone.selected.zone_id}"
  name           = "${var.backend_service_name}"
  type           = "CNAME"
  ttl            = "60"
  set_identifier = "${aws_lb.main_alb.dns_name}"
  records        = ["${aws_lb.main_alb.dns_name}"]
  weighted_routing_policy {
    weight = 10
  }
}

resource "aws_route53_record" "frontend_record" {
  zone_id        = "${data.aws_route53_zone.selected.zone_id}"
  name           = "${var.frontend_service_name}"
  type           = "CNAME"
  ttl            = "60"
  set_identifier = "${aws_lb.front_alb.dns_name}"
  records        = ["${aws_lb.front_alb.dns_name}"]
 weighted_routing_policy {
    weight = 10
  }
}

output "backend_service_fqdn" {
  value = "${aws_route53_record.backend_record.fqdn}"
}

output "backend_service_name" {
  value = "${aws_route53_record.backend_record.name}"
}


output "frontend_service_fqdn" {
  value = "${aws_route53_record.frontend_record.fqdn}"
}

output "frontend_service_name" {
  value = "${aws_route53_record.frontend_record.name}"
}