# Set global variables
AWS_REGION=eu-central-1
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"
PUBLIC_SUBNET_CIDR2="10.0.3.0/24"
PRIVATE_SUBNET_CIDR2="10.0.4.0/24"
OUTPOST_ARN="arn:aws:outposts:eu-central-1:157534414404:outpost/op-01959d4727998a00f"
OUTPOST_AZ1="eu-central-1a"
OUTPOST_ARN2="arn:aws:outposts:eu-central-1:157534414404:outpost/op-07d9c91d86a49bb5a"
OUTPOST_AZ2="eu-central-1a"
OUTPOST_EC2_TYPE="m5.xlarge"
LAB_NAME=op-ecs-lab

# Duplicated tag information due inconsistent AWS APIs
EC2_TAG_ESPECIFICATIONS='{Key=Environment,Value="Lab"},{Key=Owner,Value="davcgar@amazon.com"}'
ECS_TAGS="key=Environment,value=Lab key=Owner,value=davcgar@amazon.com"
AS_TAGS="Key=Environment,Value=Lab Key=Owner,Value=davcgar@amazon.com"

# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --region $AWS_REGION --tag-specifications ResourceType=vpc,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-vpc\"\}] --query 'Vpc.VpcId' --output text)

#  Create public subnet on AZ1
PUBLIC_SUBNET1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_CIDR --availability-zone $OUTPOST_AZ1 --outpost-arn $OUTPOST_ARN --tag-specifications ResourceType=subnet,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-public-subnet1\"\}] --query 'Subnet.SubnetId' --output text)

# Create private subnet AZ1
PRIVATE_SUBNET1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET_CIDR --availability-zone $OUTPOST_AZ1 --outpost-arn $OUTPOST_ARN --tag-specifications ResourceType=subnet,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-private-subnet1\"\}] --query 'Subnet.SubnetId' --output text)

# Create public subnet on AZ2
PUBLIC_SUBNET2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_CIDR2 --availability-zone $OUTPOST_AZ2 --outpost-arn $OUTPOST_ARN2 --tag-specifications ResourceType=subnet,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-public-subnet2\"\}] --query 'Subnet.SubnetId' --output text)

# Create private subnet AZ2
PRIVATE_SUBNET2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET_CIDR2 --availability-zone $OUTPOST_AZ2 --outpost-arn $OUTPOST_ARN2 --tag-specifications ResourceType=subnet,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-private-subnet2\"\}] --query 'Subnet.SubnetId' --output text)

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications ResourceType=internet-gateway,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-igw\"\}] --query 'InternetGateway.InternetGatewayId' --output text)

# Attach Internet Gateway to VPC
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --query 'Return' --output text

# Create route table for public subnet AZ1
PUBLIC_RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications ResourceType=route-table,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-public-rt\"\}] --query 'RouteTable.RouteTableId' --output text)

# Create route to Internet Gateway for public subnet AZ1
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --query 'Return' --output text

# Associate public subnet AZ1 with public route table
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET1_ID --route-table-id $PUBLIC_RT_ID --query 'Return' --output text
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET2_ID --route-table-id $PUBLIC_RT_ID --query 'Return' --output text

# Create NAT Gateway for private subnet AZ1
ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --tag-specifications ResourceType=elastic-ip,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-natgw-eip\"\}] --query 'AllocationId' --output text)
NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET1_ID --allocation-id $ALLOCATION_ID --tag-specifications ResourceType=natgateway,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-natgw\"\}] --query 'NatGateway.NatGatewayId' --output text)

# Wait for NAT Gateway to become available
while true; do
    STATUS=$(aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GW_ID --query 'NatGateways[0].State' --output text)
    if [[ "$STATUS" == "available" ]]; then
        echo "NAT Gateway is available."
        break
    elif [[ "$STATUS" == "failed" ]]; then
        echo "Failed to create NAT Gateway."
        exit 1
    else
        echo "Current status: $STATUS. Waiting..."
        sleep 30
    fi
done

# Create route table for private subnet AZ1
PRIVATE_RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications ResourceType=route-table,Tags=[$EC2_TAG_ESPECIFICATIONS,\{Key=Name,Value=\"$LAB_NAME-private-rt\"\}] --query 'RouteTable.RouteTableId' --output text)

# Create route to NAT Gateway for private subnet AZ1
aws ec2 create-route --route-table-id $PRIVATE_RT_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID --query 'Return' --output text

# Associate private subnet AZ1 with private route table
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET1_ID --route-table-id $PRIVATE_RT_ID --query 'Return' --output text
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET2_ID --route-table-id $PRIVATE_RT_ID --query 'Return' --output text

# Create Security Group for the EC2 Container Instances
EC2_SG_ID=$(aws ec2 create-security-group --group-name "$LAB_NAME-ec2-sg" --description "Security group for ECS Container Instances (EC2)" --vpc-id $VPC_ID --query 'GroupId' --output text)

# Add inbound rules for SSH 22 from VPC CIDR
aws ec2 authorize-security-group-ingress --group-id $EC2_SG_ID --protocol tcp --port 22 --cidr $VPC_CIDR --query 'Return' --output text

# Add inbound rules for all traffic coming from the same SG
aws ec2 authorize-security-group-ingress --group-id $EC2_SG_ID --protocol -1 --port all --source-group $EC2_SG_ID --query 'Return' --output text

# Create the IAM Role to be used with the ECS Container Instance  EC2
EC2_ROLE_NAME=$LAB_NAME-ec2-role
aws iam create-role --role-name $EC2_ROLE_NAME --query 'Role.Arn' --output text --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# Attach necessary managed policies required for ECS
aws iam attach-role-policy --role-name $EC2_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
aws iam attach-role-policy --role-name $EC2_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam attach-role-policy --role-name $EC2_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Create the instance profile for the ECS Container Instances EC2
INSTANCE_PROFILE_NAME=$LAB_NAME-ec2-instance-profile
aws iam create-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME

# Add the role to the instance profile
aws iam add-role-to-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --role-name $EC2_ROLE_NAME

# Create the ECS cluster with CloudWatch Container Insights enabled
ECS_CLUSTER_NAME=$LAB_NAME-cluster
ECS_CLUSTER_ARN=$(aws ecs create-cluster --cluster-name $ECS_CLUSTER_NAME --settings "name=containerInsights,value=enabled" --tags $ECS_TAGS --query 'cluster.clusterArn' --output text)

# Retrieve the AMI ID for the ECS Optimized image on Amazon Linux 2023
OPTIMIZED_ECS_AMI_ID=$(aws ssm get-parameters --names /aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id --query 'Parameters[0].Value' --output text)

# Create EC2 Launch Teamplate to be used with the ECS Container Instance EC2 Capacity Provider
cat <<EOF > user-data.txt
#!/bin/bash
echo ECS_CLUSTER=$ECS_CLUSTER_NAME >> /etc/ecs/ecs.config
ECS_CONTAINER_INSTANCE_PROPAGATE_TAGS_FROM=ec2_instance
EOF

LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name "$LAB_NAME-ec2-launch-template" \
  --version-description "ECS EC2 Capacity Provider with AL2023" \
  --launch-template-data '{
    "ImageId": "'$OPTIMIZED_ECS_AMI_ID'",
    "InstanceType": "m5.xlarge",
    "IamInstanceProfile": {
        "Name": "'$INSTANCE_PROFILE_NAME'"
    },
    "NetworkInterfaces": [
      {
        "DeviceIndex": 0,
        "Groups": ["'$EC2_SG_ID'"],
        "DeleteOnTermination": true
      }
    ],
    "BlockDeviceMappings": [
      {
        "DeviceName": "/dev/xvda",
        "Ebs": {
          "VolumeSize": 30,
          "VolumeType": "gp2",
          "DeleteOnTermination": true
        }
      }
    ],
    "UserData": "'$(cat user-data.txt | base64)'"
}' \
  --query 'LaunchTemplate.LaunchTemplateId' \
  --output text)

sleep 5

# Create the EC2 ASG using the Launch Template in the Private Subnet 1
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name $LAB_NAME-asg-az1 \
    --launch-template LaunchTemplateId=$LAUNCH_TEMPLATE_ID,Version='$Latest' \
    --min-size 1 \
    --max-size 2 \
    --desired-capacity 1 \
    --vpc-zone-identifier "$PRIVATE_SUBNET1_ID" \
    --new-instances-protected-from-scale-in \
    --tags $AS_TAGS Key=OutpostAZ,Value=1 Key=Name,Value=$LAB_NAME-container-instance-az1

ASG_AZ1_ARN=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $LAB_NAME-asg-az1 --query 'AutoScalingGroups[0].AutoScalingGroupARN' --output text)

# Create the EC2 ASG using the Launch Template in the Private Subnet 2
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name $LAB_NAME-asg-az2 \
    --launch-template LaunchTemplateId=$LAUNCH_TEMPLATE_ID,Version='$Latest' \
    --min-size 1 \
    --max-size 2 \
    --desired-capacity 1 \
    --vpc-zone-identifier "$PRIVATE_SUBNET2_ID" \
    --new-instances-protected-from-scale-in \
    --tags $AS_TAGS Key=OutpostAZ,Value=2 Key=Name,Value=$LAB_NAME-container-instance-az2

ASG_AZ2_ARN=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $LAB_NAME-asg-az2 --query 'AutoScalingGroups[0].AutoScalingGroupARN' --output text)

# Create the ECS Capacity Provider using the EC2 ASG AZ1
ECS_CP_AZ1_NAME=$(aws ecs create-capacity-provider \
    --name $LAB_NAME-ec2-cp-az1 \
    --auto-scaling-group-provider autoScalingGroupArn="$ASG_AZ1_ARN",managedScaling='{status="ENABLED",targetCapacity=100,minimumScalingStepSize=1,maximumScalingStepSize=100}',managedTerminationProtection="ENABLED" \
    --region $AWS_REGION \
    --query 'capacityProvider.name' --output text)


# Create the ECS Capacity Provider using the EC2 ASG AZ2
ECS_CP_AZ2_NAME=$(aws ecs create-capacity-provider \
    --name $LAB_NAME-ec2-cp-az2 \
    --auto-scaling-group-provider autoScalingGroupArn="$ASG_AZ2_ARN",managedScaling='{status="ENABLED",targetCapacity=100,minimumScalingStepSize=1,maximumScalingStepSize=100}',managedTerminationProtection="ENABLED" \
    --region $AWS_REGION \
    --query 'capacityProvider.name' --output text)

# Associate the ECS Capacity Provider with the cluster
aws ecs put-cluster-capacity-providers \
    --cluster $ECS_CLUSTER_NAME \
    --capacity-providers $ECS_CP_AZ1_NAME $ECS_CP_AZ2_NAME \
    --default-capacity-provider-strategy capacityProvider=$ECS_CP_AZ1_NAME,weight=1 capacityProvider=$ECS_CP_AZ2_NAME,weight=1 \
    --region $AWS_REGION \
    --query 'Return' --output text

# Create Security Group for the ECS NGINX Task
NGINX_TASK_SG_ID=$(aws ec2 create-security-group --group-name "$LAB_NAME-nginx-task-sg" --description "Security group for ECS NGINX Task" --vpc-id $VPC_ID --query 'GroupId' --output text)

# Add inbound rules for HTTP 80 and HTTPS 443 from VPC CIDR
aws ec2 authorize-security-group-ingress --group-id $NGINX_TASK_SG_ID --protocol tcp --port 80 --cidr $VPC_CIDR --query 'Return' --output text
aws ec2 authorize-security-group-ingress --group-id $NGINX_TASK_SG_ID --protocol tcp --port 443 --cidr $VPC_CIDR --query 'Return' --output text

# Create the IAM Role for the NGINX Task Execution
NGINX_TASK_EXEC_ROLE_NAME=$LAB_NAME-nginx-task-exec-role
NGINX_TASK_EXEC_ROLE_ARN=$(aws iam create-role --role-name $NGINX_TASK_EXEC_ROLE_NAME --query 'Role.Arn' --output text --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}')

# Attach necessary managed policies
aws iam attach-role-policy --role-name $NGINX_TASK_EXEC_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam attach-role-policy --role-name $NGINX_TASK_EXEC_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Create the IAM Role for the NGINX Task
NGINX_TASK_ROLE_NAME=$LAB_NAME-nginx-task-role
NGINX_TASK_ROLE_ARN=$(aws iam create-role --role-name $NGINX_TASK_ROLE_NAME --query 'Role.Arn' --output text --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}')

# Create the ECS Task Definition for the NGINX
NGINX_TASK_DEF_NAME=$LAB_NAME-nginx-sample
cat <<EOF > nginx-task-definition.json
{
  "family": "$NGINX_TASK_DEF_NAME",
  "networkMode": "awsvpc",
  "containerDefinitions": [
    {
      "name": "nginx",
      "image": "public.ecr.aws/nginx/nginx:latest",
      "memory": 512,
      "cpu": 256,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80,
          "protocol": "tcp"
        }
      ],
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost/ || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/$NGINX_TASK_DEF_NAME",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "nginx"
        }
      }
    }
  ],
  "requiresCompatibilities": [
    "EC2"
  ],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$NGINX_TASK_EXEC_ROLE_ARN",
  "taskRoleArn": "$NGINX_TASK_ROLE_ARN"
}
EOF

NGINX_TASK_DEF_ARN=$(aws ecs register-task-definition --query 'taskDefinition.AtaskDefinitionArn' --output text --cli-input-json file://nginx-task-definition.json)

# Create the CloudWatch Log Group for the Task Definition
aws logs create-log-group --log-group-name /ecs/$NGINX_TASK_DEF_NAME
aws logs put-retention-policy --log-group-name /ecs/$NGINX_TASK_DEF_NAME --retention-in-days 7

# Create the ECS Service with the NGINX Task Definition
aws ecs create-service \
  --cluster $ECS_CLUSTER_NAME \
  --service-name nginx-sample \
  --task-definition $NGINX_TASK_DEF_NAME \
  --desired-count 2 \
  --launch-type EC2 \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNET1_ID,$PRIVATE_SUBNET2_ID],securityGroups=[$NGINX_TASK_SG_ID]}" \
  --query 'service.serviceArn' --output text
