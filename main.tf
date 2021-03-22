# Create VPC
resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true

  tags = merge({
    Name = var.network_name
  }, var.tags)
}

locals {
  vpc_mask = element(split("/", var.cidr_block), 1)
}

# Create public subnet
resource "aws_subnet" "pub_sub" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = true
  cidr_block = cidrsubnet(
    var.cidr_block,
    var.pub_subnet_mask - local.vpc_mask,
    count.index,
  )
  availability_zone = element(var.azs, count.index)

  tags = merge({
    Name = "${var.network_name}-pub-sub-${element(var.azs, count.index)}"
    Tier = "public"
  }, var.tags, var.add_eks_tags ? { "kubernetes.io/role/elb" : "1" } : {})
}

# Create private subnet
resource "aws_subnet" "pvt_sub" {
  count  = length(var.azs)
  vpc_id = aws_vpc.vpc.id
  cidr_block = cidrsubnet(
    var.cidr_block,
    var.pvt_subnet_mask - local.vpc_mask,
    count.index + length(var.azs),
  )
  availability_zone = element(var.azs, count.index)

  tags = merge({
    Name = "${var.network_name}-pvt-sub-${element(var.azs, count.index)}"
    Tier = "private"
  }, var.tags, var.add_eks_tags ? { "kubernetes.io/role/internal-elb" : "1" } : {})
}

# Create data subnet
resource "aws_subnet" "data_sub" {
  count  = length(var.azs)
  vpc_id = aws_vpc.vpc.id
  cidr_block = cidrsubnet(
    var.cidr_block,
    var.data_subnet_mask - local.vpc_mask,
    count.index + length(var.azs) * 2,
  )
  availability_zone = element(var.azs, count.index)

  tags = merge({
    Name = "${var.network_name}-data-sub-${element(var.azs, count.index)}"
    Tier = "private"
  }, var.tags)
}

# Create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.network_name}-igw"
  }, var.tags)
}

# Create public route table
resource "aws_route_table" "pub_rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge({
    Name = "${var.network_name}-pub-rtb"
  }, var.tags)
}

resource "aws_route_table_association" "pub_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.pub_sub[count.index].id
  route_table_id = aws_route_table.pub_rtb.id
}

# Create EIP for private NAT gateway
resource "aws_eip" "nat_eip" {
  count = var.create_pvt_nat || var.create_data_nat ? 1 : 0
  vpc   = true

  tags = merge({
    Name = "${var.network_name}-nat-eip"
  }, var.tags)
}

# Create NAT gateway for private subnet
resource "aws_nat_gateway" "nat_gw" {
  count         = var.create_pvt_nat ? 1 : 0
  subnet_id     = aws_subnet.pub_sub[0].id
  allocation_id = join(", ", aws_eip.nat_eip.*.id)

  tags = merge({
    Name = "${var.network_name}-pvt-nat-gw"
  }, var.tags)
}

# Create private route table
resource "aws_route_table" "pvt_rtb" {
  count  = var.create_pvt_nat == false ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.network_name}-pvt-rtb"
  }, var.tags)
}

resource "aws_route_table" "pvt_nat_rtb" {
  count  = var.create_pvt_nat ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = join(", ", aws_nat_gateway.nat_gw.*.id)
  }

  tags = merge({
    Name = "${var.network_name}-pvt-rtb"
  }, var.tags)
}

resource "aws_route_table_association" "pvt_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.pvt_sub[count.index].id
  route_table_id = var.create_pvt_nat ? join(", ", aws_route_table.pvt_nat_rtb.*.id) : join(", ", aws_route_table.pvt_rtb.*.id)
}

# Create EIP for data NAT gateway
resource "aws_eip" "data_nat_eip" {
  count = var.create_data_nat ? 1 : 0
  vpc   = true

  tags = merge({
    Name = "${var.network_name}-data-nat-eip"
  }, var.tags)
}

# Create NAT gateway for data subnet
resource "aws_nat_gateway" "data_nat_gw" {
  count         = var.create_data_nat ? 1 : 0
  subnet_id     = aws_subnet.pub_sub[1].id
  allocation_id = join(", ", aws_eip.data_nat_eip.*.id)

  tags = merge({
    Name = "${var.network_name}-data-nat-gw"
  }, var.tags)
}

# Create data route table
resource "aws_route_table" "data_rtb" {
  count  = var.create_data_nat == false ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.network_name}-data-rtb"
  }, var.tags)
}

resource "aws_route_table" "data_nat_rtb" {
  count  = var.create_data_nat ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = join(", ", aws_nat_gateway.data_nat_gw.*.id)
  }

  tags = merge({
    Name = "${var.network_name}-data-rtb"
  }, var.tags)
}

resource "aws_route_table_association" "data_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.data_sub[count.index].id
  route_table_id = var.create_data_nat ? join(", ", aws_route_table.data_nat_rtb.*.id) : join(", ", aws_route_table.data_rtb.*.id)
}

# Create public NACL
resource "aws_network_acl" "pub_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.pub_sub.*.id

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 999
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = "tcp"
    rule_no    = 999
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = merge({
    Name = "${var.network_name}-pub-nacl"
  }, var.tags)
}

# Create private NACL
resource "aws_network_acl" "pvt_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.pvt_sub.*.id

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge({
    Name = "${var.network_name}-pvt-nacl"
  }, var.tags)
}

# Create data NACL
resource "aws_network_acl" "data_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.data_sub.*.id

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge({
    Name = "${var.network_name}-data-nacl"
  }, var.tags)
}

# Create security group for internal communication
resource "aws_security_group" "int_sg" {
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.network_name}-internal-sg"
  description = "Security group allowing communication internally within the VPC"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${var.network_name}-internal-sg"
  }, var.tags)
}

# Create security group for accepting only SSH connection
resource "aws_security_group" "ssh_sg" {
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.network_name}-ssh-sg"
  description = "Security group allowing only SSH connections"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${var.network_name}-ssh-sg"
  }, var.tags)
}

# Create security group for public facing web servers or load balancer
resource "aws_security_group" "pub_sg" {
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.network_name}-pub-web-sg"
  description = "Security group allowing 80 and 443 from outer world"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${var.network_name}-pub-web-sg"
  }, var.tags)
}

# Create security group for internal web/app servers
resource "aws_security_group" "pvt_sg" {
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.network_name}-pvt-web-sg"
  description = "Security group allowing 22, 80 and 443 internally for instances"

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = aws_security_group.pub_sg.*.id
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = aws_security_group.pub_sg.*.id
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = aws_security_group.pub_sg.*.id
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${var.network_name}-pvt-web-sg"
  }, var.tags)
}

# Create cloudwatch log group for vpc flow logs
resource "aws_cloudwatch_log_group" "cw_log_group" {
  count = var.create_flow_logs && var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? 1 : 0
  name  = "${var.network_name}-flow-logs-group"

  tags = merge({
    Name = "${var.network_name}-flow-logs-group"
  }, var.tags)
}

# Create IAM role for VPC flow logs
resource "aws_iam_role" "flow_logs_role" {
  count = var.create_flow_logs && var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? 1 : 0
  name  = "${var.network_name}-flow-logs-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = merge({
    Name = "${var.network_name}-flow-logs-role"
  }, var.tags)
}

# Create IAM policy for VPC flow logs role
resource "aws_iam_role_policy" "flow_logs_policy" {
  count = var.create_flow_logs && var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? 1 : 0
  name  = "${var.network_name}-flow-logs-policy"
  role  = aws_iam_role.flow_logs_role[0].id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "random_id" "id" {
  byte_length = 8
}

# Create S3 bucket for flow logs storage
resource "aws_s3_bucket" "flow_logs_bucket" {
  count  = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? 1 : 0
  bucket = "${var.network_name}-flow-logs-${random_id.id.hex}"

  tags = merge({
    Name = "${var.network_name}-flow-logs-${random_id.id.hex}"
  }, var.tags)
}

locals {
  flow_logs_log_group_arn = var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? aws_cloudwatch_log_group.cw_log_group[0].arn : var.flow_logs_cw_log_group_arn
  flow_logs_bucket_arn    = var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? aws_s3_bucket.flow_logs_bucket[0].arn : var.flow_logs_bucket_arn
}

# Create VPC flow logs
resource "aws_flow_log" "flow_logs" {
  count                = var.create_flow_logs ? 1 : 0
  iam_role_arn         = var.flow_logs_destination == "cloud-watch-logs" ? aws_iam_role.flow_logs_role[0].arn : ""
  log_destination      = var.flow_logs_destination == "cloud-watch-logs" ? local.flow_logs_log_group_arn : local.flow_logs_bucket_arn
  log_destination_type = var.flow_logs_destination
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.network_name}-flow-logs"
  }, var.tags)
}

# Create private hosted zone
resource "aws_route53_zone" "private" {
  count = var.create_private_zone == true ? 1 : 0
  name  = var.private_zone_domain

  vpc {
    vpc_id = aws_vpc.vpc.id
  }

  tags = merge({
    Name = "${var.network_name}-pvt-zone"
  }, var.tags)
}
