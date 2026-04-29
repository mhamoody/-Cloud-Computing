# ============================================================
# Section 2 — VPC & Networking
# ============================================================

# --- VPC ---
# Custom VPC with a /16 block gives us 65,536 IPs across subnets.
# We avoid the default VPC to maintain full control over routing,
# security groups, and CIDR design.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true   # Required for EMR and S3 endpoint resolution
  enable_dns_hostnames = true   # Required so EC2 instances get public DNS names

  tags = {
    Name = "${var.net_id}-vpc"
  }
}

# --- Public Subnet ---
# Hosts the EC2 instance running Ollama + OpenWebUI.
# Must be public so the web interface is reachable from a browser.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true  # EC2 gets a public IP automatically

  tags = {
    Name = "${var.net_id}-public-subnet"
  }
}

# --- Private Subnet ---
# Hosts the EMR cluster. EMR nodes do NOT need to be internet-facing;
# they communicate with S3 via a VPC Gateway Endpoint (no NAT cost).
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "${var.net_id}-private-subnet"
  }
}

# --- Internet Gateway ---
# Attaches the VPC to the public internet so the EC2 instance and
# the EMR master (if needed for package installs) can reach out.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.net_id}-igw"
  }
}

# --- Public Route Table ---
# Routes all non-local traffic (0.0.0.0/0) through the IGW.
# Associated with the public subnet only.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.net_id}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Private Route Table ---
# The private subnet uses a separate route table with NO IGW route.
# EMR reaches S3 via the Gateway Endpoint below (free, no NAT needed).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.net_id}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# --- S3 VPC Gateway Endpoint ---
# Allows EMR nodes in the private subnet to read/write S3 without
# needing a NAT Gateway. This is cost-free and reduces data transfer fees.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.public.id
  ]

  tags = {
    Name = "${var.net_id}-s3-endpoint"
  }
}

# ============================================================
# Security Groups
# ============================================================

# --- EC2 Security Group ---
# Allows inbound SSH (port 22) for administration and
# port 3000 for OpenWebUI (the chat interface) from anywhere.
# Port 11434 is Ollama's API; restricted to within the VPC only.
resource "aws_security_group" "ec2_sg" {
  name        = "${var.net_id}-ec2-sg"
  description = "Security group for EC2 LLM serving instance"
  vpc_id      = aws_vpc.main.id

  # SSH access – restrict to your IP in production
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # OpenWebUI chat interface
  ingress {
    description = "OpenWebUI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ollama API – internal VPC only (EMR or other services might call it)
  ingress {
    description = "Ollama API (internal)"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound (needed to pull models, install packages)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.net_id}-ec2-sg"
  }
}

# --- EMR Security Group (Master) ---
resource "aws_security_group" "emr_master_sg" {
  name        = "${var.net_id}-emr-master-sg"
  description = "Security group for EMR master node"
  vpc_id      = aws_vpc.main.id

  # SSH access for debugging EMR jobs
  ingress {
    description = "SSH to EMR master"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all intra-cluster communication
  ingress {
    description = "Intra-cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.net_id}-emr-master-sg"
  }
}

# --- EMR Security Group (Core/Worker) ---
resource "aws_security_group" "emr_core_sg" {
  name        = "${var.net_id}-emr-core-sg"
  description = "Security group for EMR core/worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Intra-cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow master to communicate with workers
  ingress {
    description = "From EMR master"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [aws_security_group.emr_master_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.net_id}-emr-core-sg"
  }
}

# --- EMR Service Access Security Group ---
# Required when EMR runs in a private subnet with custom EMR managed security groups.
# This security group is reserved for Amazon EMR service access only.
resource "aws_security_group" "emr_service_access_sg" {
  name        = "${var.net_id}-emr-service-access-sg"
  description = "Service access security group for EMR private subnet"
  vpc_id      = aws_vpc.main.id

  # Required for EMR release 5.30.0 and later:
  # EMR primary node security group -> service access security group on 9443
  ingress {
    description     = "EMR primary to service access"
    from_port       = 9443
    to_port         = 9443
    protocol        = "tcp"
    security_groups = [aws_security_group.emr_master_sg.id]
  }

  # Service access security group -> EMR primary node on 8443
  egress {
    description     = "Service access to EMR primary"
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    security_groups = [aws_security_group.emr_master_sg.id]
  }

  # Service access security group -> EMR core nodes on 8443
  egress {
    description     = "Service access to EMR core"
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    security_groups = [aws_security_group.emr_core_sg.id]
  }

  tags = {
    Name = "${var.net_id}-emr-service-access-sg"
  }
}
