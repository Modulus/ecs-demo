variable "region" {}
variable "backend_target_group_name" {}
variable "route53_zone_domain" {}
variable backend_service_name {}

variable "task_cpu" {}

variable "task_memory" {}

variable backend_task_cpu {}
variable backend_task_memory {}
variable backend_container_port {}
variable backend_host_port {}
variable ecs_cluster_name {}
variable backend_image {}
variable alb_port {}
variable vpc_name {}
variable frontend_service_name {}
variable frontend_container_port {}
variable frontend_host_port {}
variable frontend_image {}

variable "services" {

}

variable backend_service_dns_name {}
variable frontend_service_dns_name {}

variable frontend_task_cpu {
  default = 2048
}
variable frontend_task_memory {
  default = 4096
}

