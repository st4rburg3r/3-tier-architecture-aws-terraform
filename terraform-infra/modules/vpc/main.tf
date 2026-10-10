#vpc
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
    Name = "${var.project}-${var.environment}-vpc"
  })
}

#internet gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
    Name = "${var.project}-${var.environment}-igw"
  })
}

#public subnets- web tier
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
    Name = "${var.project}-${var.environment}-public-subnet-${count.index + 1}"
    Tier = "web-public"
    })
}
 
 #public Subnet- frontend tier

 resource "aws_subnet" "frontend" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.frontend_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
    Name = "${var.project}-${var.environment}-frontend-subnet-${count.index + 1}"
    Tier = "frontend"
    })
 }


#private subnet-backend tier
resource "aws_subnet" "backend" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.backend_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
    Name = "${var.project}-${var.environment}-backend-subnet-${count.index + 1}"
    Tier = "backend"
    })
  
}

# Database Isolated Subnets (Data Tier)
resource "aws_subnet" "database" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.database_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
    Name = "${var.project}-${var.environment}-database-subnet-${count.index + 1}"
    Tier = "database"
    })
}

#elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

#nat gateway
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      Name = "${var.environment}-${var.project}-nat-gateway-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# 4 route tables for public, frontend, backend, and database subnets
# have to create route tables, routes, and associations for each tier

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project}-${var.environment}-public-rt"
      Tier = "public"
    }
  )
}

#route for public subnets to IGW
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

#associate  the two public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 2 route tables for frontend subnets
resource "aws_route_table" "frontend" {
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project}-${var.environment}-frontend-rt-${count.index + 1}"
      Tier = "frontend"
    }
  )
}

#Route for frontend subnets to NAT Gateway
resource "aws_route" "frontend_nat_access" {
  count                   = var.enable_nat_gateway ? length(var.availability_zones) : 0
  route_table_id          = aws_route_table.frontend[count.index].id
  destination_cidr_block  = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
}

#associate the two frontend subnets with frontend route tables
resource "aws_route_table_association" "frontend" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.frontend[count.index].id
  route_table_id = var.enable_nat_gateway ? aws_route_table.frontend[count.index].id : null
  
}

#route table for backend subnets
resource "aws_route_table" "backend" {
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project}-${var.environment}-backend-rt-${count.index + 1}"
      Tier = "backend"
    }
  )
}

#Route for backend subnets to NAT Gateway
resource "aws_route" "backend_nat_access" {
  count                   = var.enable_nat_gateway ? length(var.availability_zones) : 0
  route_table_id          = aws_route_table.backend[count.index].id
  destination_cidr_block  = "0.0.0.0/0"
  nat_gateway_id          = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
}

#associate the two backend subnets with backend route tables
resource "aws_route_table_association" "backend" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.backend[count.index].id
  route_table_id = var.enable_nat_gateway ? aws_route_table.backend[count.index].id : null
}

#route table for database subnets
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project}-${var.environment}-database-rt"
      Tier = "database"
    }
  )
}

#associate the two database subnets with database route table
resource "aws_route_table_association" "database" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}
