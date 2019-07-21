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

backend_image = "coderpews/name-generator:1.4"

frontend_service_name = "name"
frontend_container_port = 80
frontend_host_port = 80
frontend_image = "coderpews/name-generator-front:2.0"

alb_port = 80

vpc_name = "Default VPC"

services = [
    {
        "id" = 1,
        "name" = "generator"
        "container_port" = 5000,
        "host_port" = 5000,
        "image" = "coderpews/name-generator:1.4"

    },
    {
        "id" = 2,
        "name" = "frontend"
        "container_port" = 80,
        "host_port" = 80
        "image" = "coderpews/name-generator-front:2.0"

    }
]

subnet1_name = "Default subnet for eu-west-1c"
subnet2_name = "Default subnet for eu-west-1a"
subnet3_name = "Default subnet for eu-west-1b"