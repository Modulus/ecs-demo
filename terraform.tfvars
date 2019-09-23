region = "eu-west-1"

route53_zone_domain = "aws5.tv2.no."

ecs_cluster_name = "ecs-demo"

alb_port = 80

containers = [
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
        "name" = "name"
        "container_port" = 80,
        "host_port" = 80
        "image" = "coderpews/name-generator-front:2.2",
        "tier" = "frontend",
        "cpu" = "2048"
        "memory" = "4096"


    }
]

vpc_name = "Default VPC"

subnet_names = ["Default subnet for eu-west-1c", "Default subnet for eu-west-1a", "Default subnet for eu-west-1b"]
