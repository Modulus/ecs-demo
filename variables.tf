variable "containers" {
    type = "list"
} 

variable "vpc_name" { 
    type = "string"
    default = "Default VPC"
}

variable "ecs_cluster_name" {
    default ="fargate-demo"
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

variable "cpu_low_threshold" {
  default = "20"
}

variable "cpu_high_threshold" {
  default = "80"
}

variable "scale_down_min_capacity" {
  default = 1
}
variable "scale_down_max_capacity" {
  default = 3
}
