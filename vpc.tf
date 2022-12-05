# Configure the AWS Provider
provider "aws" {
  region     = "ap-south-1"
  access_key = "AKIAQXIQEYSFM43KRBUQ"
  secret_key = "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"
}

# Create VPC
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true

  tags = {
    Name = "demo-vpc"
  }
}

# Create Internet Gateway and Attach it to Demo VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "IGW"
  }
}

# Create Public Subnet
resource "aws_subnet" "public-subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet"
  }
}

# Create Route Table and Add Public Route
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

# Associate Public Subnet to Public Route Table
resource "aws_route_table_association" "public-subnet-route-table-association" {
  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.public-route-table.id
}


# Create Eip or Public IP
resource "aws_eip" "eip" {
  vpc = true
  depends_on = [
    aws_route_table_association.public-subnet-route-table-association,
  ]
}


# Create Private NAT Gateway
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public-subnet.id

  tags = {
    Name = "Nat-GW"
  }

# dependency on the Internet Gateway that Terraform cannot
# automatically infer, so it must be declared explicitly
depends_on = [
    aws_internet_gateway.igw,
  ]
}


# Create Private Subnet
resource "aws_subnet" "private-subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "Private Subnet"
  }
}

# Create Route Table and Add Private Route
resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "Private Route Table"
  }
}

# Associate Private Subnet to Private Route Table
resource "aws_route_table_association" "private-subnet-route-table-association" {
  subnet_id      = aws_subnet.private-subnet.id
  route_table_id = aws_route_table.private-route-table.id
}




# Public Security Group Creation Ingress Security Port 22, 80 and 8000 
resource "aws_security_group" "public-security-group" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "custom-port"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Public Security Group"
  }
}


# Private Security Group Creation Ingress Security Port 22, 80 and 8000 
resource "aws_security_group" "private-security-group" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "custom-port"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "rds-mysql"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Private Security Group"
  }
}


# Create Public Instance
resource "aws_instance" "public-instance" {
  ami               = "ami-063e80fec5976b6e1"
  instance_type     = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name          = "vpc"
  security_groups    = [aws_security_group.public-security-group.id]
  subnet_id         = aws_subnet.public-subnet.id
  
  tags = {
    Name = "FrontEnd Main Server"
  }
}

# Create Private Instance
resource "aws_instance" "private-instance" {
  ami               = "ami-09fc63fc78038d3fd"
  instance_type     = "t2.micro"
  availability_zone = "ap-south-1b"
  key_name          = "vpc"
  security_groups    = [aws_security_group.private-security-group.id]
  subnet_id         = aws_subnet.private-subnet.id
  
  tags = {
    Name = "BackEnd Main Server"
  }
}




# Creating Public Load Balancer
resource "aws_lb" "public-load-balancer" {
  name               = "public-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public-security-group.id]

  enable_deletion_protection = false

  subnet_mapping {
    subnet_id            = aws_subnet.public-subnet.id
  }

  subnet_mapping {
    subnet_id            = aws_subnet.private-subnet.id
  }

  tags = {
    Environment = "production"
  }
}

#Create a Public Listener on Port 80
resource "aws_lb_listener" "public-listener" {
  load_balancer_arn = aws_lb.public-load-balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


# Create Public Target Group
resource "aws_lb_target_group" "public-target-group" {
  name     = "public-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
}


# Creating Private Load Balancer
resource "aws_lb" "private-load-balancer" {
  name               = "private-load-balancer"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.private-security-group.id]

  enable_deletion_protection = false

  subnet_mapping {
    subnet_id            = aws_subnet.public-subnet.id
  }

  subnet_mapping {
    subnet_id            = aws_subnet.private-subnet.id
  }

  tags = {
    Environment = "production"
  }
}

#Create a Private Listener on Port 80
resource "aws_lb_listener" "private-listener" {
  load_balancer_arn = aws_lb.private-load-balancer.arn
  port              = "8000"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


# Create Private Target Group
resource "aws_lb_target_group" "private-target-group" {
  name     = "private-target-group"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
}



# Create Public Launch Configuration 
resource "aws_launch_configuration" "public-launch-configuration" {
  name = "public-launch-configuration"
  image_id = "ami-063e80fec5976b6e1"
  security_groups = [aws_security_group.public-security-group.id]
  instance_type = "t2.micro"
  associate_public_ip_address = true
}

# Create Public Auto Scaling Group 
resource "aws_autoscaling_group" "public-autoscaling-group" {
  name                      = "public-autoscaling-group"
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.public-launch-configuration.id
  vpc_zone_identifier       = [aws_subnet.public-subnet.id, aws_subnet.private-subnet.id]
}


# Create Private Launch Configuration 
resource "aws_launch_configuration" "private-launch-configuration" {
  name = "private-launch-configuration"
  image_id = "ami-09fc63fc78038d3fd"
  security_groups = [aws_security_group.private-security-group.id]
  instance_type = "t2.micro"
  associate_public_ip_address = false
}

# Create Private Auto Scaling Group 
resource "aws_autoscaling_group" "private-autoscaling-group" {
  name                      = "private-autoscaling-group"
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.private-launch-configuration.id
  vpc_zone_identifier       = [aws_subnet.private-subnet.id, aws_subnet.private-subnet.id]
}