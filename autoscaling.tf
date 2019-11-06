resource "aws_appautoscaling_target" "app_scale_target" {
    count = "${length(var.containers)}"
    service_namespace = "ecs"
    resource_id = "service/${var.ecs_cluster_name}/${lookup(var.containers[count.index], "name")}"
    scalable_dimension = "ecs:service:DesiredCount"
    min_capacity = 0
    max_capacity = 3
}


resource "aws_appautoscaling_policy" "app_up" {
  count = "${length(var.containers)}"
  name               = "app-scale-up"
  service_namespace  = "${lookup(aws_appautoscaling_target.app_scale_target[count.index], "service_namespace")}"
  resource_id        = "${lookup(aws_appautoscaling_target.app_scale_target[count.index], "resource_id")}"
  scalable_dimension = "${lookup(aws_appautoscaling_target.app_scale_target[count.index], "scalable_dimension")}"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
    count = "${length(var.containers)}"

    alarm_name = "${lookup(var.containers[count.index], "name")}-cpu-high"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods  = "1"
    metric_name         = "CPUUtilization"
    namespace           = "AWS/ECS"
    period              = "60"
    statistic           = "Average"
    threshold           = "${var.cpu_high_threshold}"

    dimensions = {
        ClusterName = "${var.ecs_cluster_name}"
        ServiceName = "${lookup(var.containers[count.index], "name")}"
    }

    alarm_actions = ["${lookup(aws_appautoscaling_policy.app_up[count.index], "arn")}"]
}


# Automatically scale capacity down by one
resource "aws_appautoscaling_policy" "down" {
    count = "${length(var.containers)}"
    name = "${lookup(var.containers[count.index], "name")}-cpu-high"
    service_namespace  = "ecs"
    resource_id        = "service/${var.ecs_cluster_name}/${lookup(var.containers[count.index], "name")}"
    scalable_dimension = "ecs:service:DesiredCount"

    step_scaling_policy_configuration {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 60
        metric_aggregation_type = "Maximum"

        step_adjustment {
            metric_interval_lower_bound = 0
            scaling_adjustment          = -1
        }
  }

  # depends_on = [aws_appautoscaling_target.app_scale_target]
}


# CloudWatch alarm that triggers the autoscaling down policy
resource "aws_cloudwatch_metric_alarm" "service_cpu_low" {
    count = "${length(var.containers)}"
    alarm_name          = "cb_cpu_utilization_low"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods  = "2"
    metric_name         = "CPUUtilization"
    namespace           = "AWS/ECS"
    period              = "60"
    statistic           = "Average"
    threshold           = "${var.cpu_low_threshold}"

    dimensions = {
        ClusterName = "${var.ecs_cluster_name}"
        ServiceName = "${lookup(var.containers[count.index], "name")}"
    }

    alarm_actions = ["${lookup(aws_appautoscaling_policy.down[count.index], "arn")}"]
}


