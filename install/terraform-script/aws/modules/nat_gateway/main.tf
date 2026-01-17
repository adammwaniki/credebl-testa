# Allocate elastic IP for the NAT gateway in AZ1
resource "aws_eip" "eip_for_nat_gateway_az1" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}_${var.environment}_eip1"
  }
}

# Allocate elastic IP for the NAT gateway in AZ2
resource "aws_eip" "eip_for_nat_gateway_az2" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}_${var.environment}_eip2"
  }
}

# Create NAT gateways in the public subnets (AZ1 and AZ2)
resource "aws_nat_gateway" "nat_gateway" {
  count = var.nat_gateway_count

  allocation_id = element([aws_eip.eip_for_nat_gateway_az1.id, aws_eip.eip_for_nat_gateway_az2.id], count.index)

  subnet_id = element(var.public_subnet_ids, count.index)

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-gateway-${count.index + 1}"
  }

  # Ensure proper ordering on internet gateway for the VPC
  depends_on = [aws_eip.eip_for_nat_gateway_az1, aws_eip.eip_for_nat_gateway_az2] # Assuming you have an IGW resource
}

# Update private route tables to use NAT gateways for app subnet
resource "aws_route" "private_nat" {
  count                  = length(local.private_route_table_ids)
  route_table_id         = local.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway[count.index].id

  depends_on = [aws_nat_gateway.nat_gateway]
}
