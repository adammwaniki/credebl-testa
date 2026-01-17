# Get all availability zones in the region
data "aws_availability_zones" "available_zones" {
  state = "available"
}

# Create VPC
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# Create Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# Configuration for Public Subnets
resource "aws_subnet" "public_subnet" {
  count = length(var.public_subnet_cidr)

  cidr_block        = element(var.public_subnet_cidr, count.index)
  vpc_id            = aws_vpc.vpc.id
  availability_zone = element(data.aws_availability_zones.available_zones.names, count.index % length(data.aws_availability_zones.available_zones.names))

  tags = {
    Name = "${var.project_name}-${var.environment}-public_subnet-${count.index + 1}"
  }
}

# Configuration for Private Subnets for App
resource "aws_subnet" "private_subnet_app" {
  count = length(var.private_app_subnet_cidr)

  cidr_block        = element(var.private_app_subnet_cidr, count.index)
  vpc_id            = aws_vpc.vpc.id
  availability_zone = element(data.aws_availability_zones.available_zones.names, count.index % length(data.aws_availability_zones.available_zones.names))

  tags = {
    Name = "${var.project_name}-${var.environment}-private_app_subnet-${count.index + 1}"
  }
}

# Configuration for Private Subnets for Database
resource "aws_subnet" "private_subnet_db" {
  count = length(var.private_db_subnet_cidr)

  cidr_block        = element(var.private_db_subnet_cidr, count.index)
  vpc_id            = aws_vpc.vpc.id
  availability_zone = element(data.aws_availability_zones.available_zones.names, count.index % length(data.aws_availability_zones.available_zones.names))

  tags = {
    Name = "${var.project_name}-${var.environment}-private_db_subnet-${count.index + 1}"
  }
}

# Create Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public_rt"
  }
}

# Associate Public Subnets to Public Route Table
resource "aws_route_table_association" "public_subnet_route_table_association" {
  count          = length(var.public_subnet_cidr)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create Private Route Table for app
resource "aws_route_table" "private_app_route_table" {
  # Assuming same count for DB and App
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

# Associate Private app Subnets with Private Route Tables
resource "aws_route_table_association" "private_app_subnet_route_table_association" {
  count          = length(var.private_app_subnet_cidr)
  subnet_id      = aws_subnet.private_subnet_app[count.index].id
  route_table_id = aws_route_table.private_app_route_table.id
}

# Create Private Route Table for db
resource "aws_route_table" "private_db_route_table" {
  # Assuming same count for DB and App
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

# Associate Private db Subnets with Private Route Tables
resource "aws_route_table_association" "private_db_subnet_route_table_association" {
  count          = length(var.private_db_subnet_cidr)
  subnet_id      = aws_subnet.private_subnet_db[count.index].id
  route_table_id = aws_route_table.private_db_route_table.id
}
