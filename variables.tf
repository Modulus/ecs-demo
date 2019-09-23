variable "containers" {
    type = "list"
} 

variable "vpc_name" { 
    type = "string"
    default = "Default VPC"
}

variable "subnet_names" {
  type = "list"
}


variable "ecs_cluster_name" {
    default ="ecs-demo"
    type = "string"
}

variable "region" {
    type = "string"
    default = "eu-west-1" 
}

variable "alb_port" {
  default = 80
}

variable "route53_zone_domain" {
  type = "string"
  default = ""
}


variable "task_cpu" {
  default = 4096
} 

variable "task_memory" {
  default = 8192
} 

variable "backend_host_port" {
  default = 5000
}


