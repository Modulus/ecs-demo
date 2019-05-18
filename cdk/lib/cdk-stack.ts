import cdk = require('@aws-cdk/cdk');
import ec2 = require('@aws-cdk/aws-ec2');
import ecs = require('@aws-cdk/aws-ecs');
//import route53 =  require('@aws-cdk/aws-route53');
import { SubnetType } from '@aws-cdk/aws-ec2';
import elbv2 = require("@aws-cdk/aws-autoscaling");

export class CdkStack extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

      // The code that defines your stack goes here
      const vpc = new ec2.VpcNetwork(this, 'ecs-vpc', {
        maxAZs: 3, // Default is all AZs in region
        cidr: "172.29.29.0/21",
        subnetConfiguration: [
          {
            cidrMask: 24,
            name: 'Ingress',
            subnetType: SubnetType.Public, //SubnetTyp
          }
        ],
      });

    // Create an ECS cluster
    const cluster = new ecs.Cluster(this, 'ecs-demo', {
      vpc,
    });

    const fargateTaskDefinition = new ecs.FargateTaskDefinition(this, 'generator', {
      memoryMiB: "4096",
      cpu: "2048",

    });

    const backendContainer = fargateTaskDefinition.addContainer("generator-backend", {
      // Use an image from DockerHub
      image: ecs.ContainerImage.fromRegistry("coderpews/name-generator:1.4"),
      cpu: 1024,
      memoryLimitMiB: 2048
      // ... other options here ...
    });

    backendContainer.addPortMappings({
        containerPort: 5000,
        hostPort: 5000
    })

    const frontendContainer = fargateTaskDefinition.addContainer("generator-frontend", {
      image: ecs.ContainerImage.fromRegistry("coderpews/name-generator:1.4"),
      cpu: 1024,
      memoryLimitMiB: 2048,
    });

    frontendContainer.addPortMappings({
      containerPort: 80,
      hostPort: 5000,
    })

    
    const service = new ecs.FargateService(this, 'generator-service', {
      cluster,
      fargateTaskDefinition,
      desiredCount: 2
    });


    const lb = new elbv2.ApplicationLoadBalancer(this, 'LB', { vpc, internetFacing: true });
    const listener = lb.addListener('Listener', { port: 80 });
    listener.addTargets('ECS', {
      port: 80,
      targets: [service]
    });
    
  }
}
