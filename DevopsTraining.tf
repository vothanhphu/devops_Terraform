# Terraform HCL

variable "aws_region" {
    description = "aws region where will create a vpc"
    default     = "ap-southeast-1"
}

variable "availability_zones" {
    description = "A list of available zone which to create subnets"
    type        = list(string)
    default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "base_cidr_block" {
    description = "CIDR range that the VPC will use."
    default     = "10.0.0.0/16"
}

data "aws_ami" "ubuntu_latest" {
    most_recent  = true
    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
    }
    #099720109477 is Canonical, the publisher of Unbuntu
    owners      = ["099720109477"]
}

provider "aws" {
    region         = var.aws_region
    access_key     = ""
    secret_key     = ""
}

resource "aws_vpc" "phuvo_vpc" {
    cidr_block = var.base_cidr_block
}

resource "aws_subnet" "phuvo_subnet" {
    count             = length(var.availability_zones)
    availability_zone = var.availability_zones[count.index]
    vpc_id            = aws_vpc.phuvo_vpc.id
    cidr_block        = cidrsubnet(aws_vpc.phuvo_vpc.cidr_block, 4, count.index)
}

resource "aws_internet_gateway" "phuvo_igw" {
    vpc_id  = aws_vpc.phuvo_vpc.id
    tags    = {
       Name = "PV_IGW"
    }
}

resource "aws_security_group" "phuvo_stg" {
    vpc_id          = aws_vpc.phuvo_vpc.id
    name            = "Phu Vo security group"
    description     = "Phu Vo security group that created by terraform"
    #allow ungress of port
    ingress {
        cidr_blocks     = [var.base_cidr_block]
        from_port       = 22
        to_port         = 22
        protocol        = "tcp"
    }
    #allow engress for all port
    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }
    tags = {
        Name        = "PV_STG"
        Description = "Security group created by terraform"
    }
}

resource "aws_network_acl" "phuvo_acl" {
    vpc_id    = aws_vpc.phuvo_vpc.id

    #allow ingress port 22
    ingress {
        protocol    = "tcp"
        rule_no     = 100
        action      = "allow"
        cidr_block  = var.base_cidr_block
        from_port   = 22
        to_port     = 22
    }
    #allow ingress port 80
    ingress {
        protocol    = "tcp"
        rule_no     = 100
        action      = "allow"
        cidr_block  = var.base_cidr_block
        from_port   = 80
        to_port     = 80
    }
    tags = {
        Name = "PV_ACL"
    }
}

resource "aws_route_table" "phuvo_routetable" {
    vpc_id  = aws_vpc.phuvo_vpc.id
    tags    = {
        Name = "PV_RT"
    }
}

#create internet access
resource "aws_route" "phuvo_route" {
    route_table_id         = aws_route_table.phuvo_routetable.id
    destination_cidr_block = var.base_cidr_block
    gateway_id             = aws_internet_gateway.phuvo_igw.id
}

#associate the route table with subnet
resource "aws_route_table_association" "phuvo_association" {
    count           = length(var.availability_zones)
    subnet_id       = element(aws_subnet.phuvo_subnet.*.id, count.index)
    route_table_id  = aws_route_table.phuvo_routetable.id
}

resource "aws_placement_group" "phuvo_cluster" {
    name     = "aws cluster create by terraform"
    strategy = "cluster"
}

resource "aws_autoscaling_group" "phuvo_asg" {
    name                      = "autoscaling group test terraform"
    max_size                  = 2
    min_size                  = 1
    health_check_grace_period = 300
    health_check_type         = "ELB"
    desired_capacity          = 4
    force_delete              = true
    placement_group           = aws_placement_group.phuvo_cluster.id
    tags                      = [
        {
            "Key": "env",
            "Value": "prod",
            "PropagateAtLaunch": true,
            "ResourceId": "phuvo_asg",
            "ResourceType": "auto-scaling-group"
        }
    ]
}

resource "aws_instance" "phuvo_ec2" {
    ami                    = data.aws_ami.ubuntu_latest.id
    instance_type          = "t2.micro"
    vpc_security_group_ids = [aws_security_group.phuvo_stg.id]
    depends_on             = [aws_internet_gateway.phuvo_igw]
    tags                   = {
       Name = "PV_EC2"
    }
}