region = "eu-west-1"


backend_target_group_name = "ecs-demo-backend-target-group"


route53_zone_domain = "aws5.tv2.no."


task_cpu = 4096
task_memory = 8192

backend_service_name  = "generator"


backend_task_cpu = 2048

backend_task_memory = 4096

backend_container_port = 5000
backend_host_port = 5000
   
ecs_cluster_name = "ecs-demo"





alb_port = 80

vpc_name = "Default VPC"

services = [
    {
        "id" = 1,
        "name" = "generator"
        "container_port" = 5000,
        "host_port" = 5000,
        "image" = "coderpews/name-generator:1.4",
        "tier"  = "backend",
        "cpu" = "2048",
        "memory" = "4096"


    },
    {
        "id" = 2,
        "name" = "frontend"
        "container_port" = 80,
        "host_port" = 80
        "image" = "coderpews/name-generator-front:2.0",
        "tier" = "frontend",
        "cpu" = "2048"
        "memory" = "4096"


    }
]


subnet_names = ["Default subnet for eu-west-1c", "Default subnet for eu-west-1a", "Default subnet for eu-west-1b"]
