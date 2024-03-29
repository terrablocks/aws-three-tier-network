data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Create VPC
resource "aws_vpc" "vpc" {
  # checkov:skip=CKV2_AWS_12: All traffic restricted from within the security group
  # checkov:skip=CKV2_AWS_1: Separate NACLs will be create per subnet group
  cidr_block                       = var.cidr_block
  enable_dns_support               = var.enable_dns_support
  enable_dns_hostnames             = var.enable_dns_hostnames
  instance_tenancy                 = var.instance_tenancy
  assign_generated_ipv6_cidr_block = var.assign_ipv6_cidr_block

  tags = merge({
    Name = var.network_name
  }, var.tags)
}

resource "aws_default_network_acl" "this" {
  default_network_acl_id = aws_vpc.vpc.default_network_acl_id
  tags                   = var.tags
}

locals {
  vpc_mask = element(split("/", var.cidr_block), 1)
}

# Create public subnet
resource "aws_subnet" "pub_sub" {
  # checkov:skip=CKV_AWS_130: Public IP required for resources in public subnet
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = var.map_public_ip_for_public_subnet
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

  tags = merge({
    Name = "${var.network_name}-pub-rtb"
  }, var.tags)
}

resource "aws_route" "pub_rtb" {
  route_table_id         = aws_route_table.pub_rtb.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "pub_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.pub_sub[count.index].id
  route_table_id = aws_route_table.pub_rtb.id
}

# Create EIP for private NAT gateway
resource "aws_eip" "nat_eip" {
  # checkov:skip=CKV2_AWS_19: EIP associated to NAT Gateway
  count = var.create_pvt_nat && length(var.pvt_nat_eip_id) == 0 ? (var.pvt_nat_ha_mode ? length(var.azs) : 1) : 0
  vpc   = true

  tags = merge({
    Name = "${var.network_name}-pvt-nat-eip"
  }, var.tags)
}

# Create NAT gateway for private subnet
resource "aws_nat_gateway" "nat_gw" {
  count         = var.create_pvt_nat ? (var.pvt_nat_ha_mode ? length(var.azs) : 1) : 0
  subnet_id     = aws_subnet.pub_sub[count.index].id
  allocation_id = length(var.pvt_nat_eip_id) == 0 ? aws_eip.nat_eip[count.index].id : var.pvt_nat_eip_id[count.index]

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
  count  = var.create_pvt_nat ? (var.pvt_nat_ha_mode ? length(var.azs) : 1) : 0
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.network_name}-pvt-rtb"
  }, var.tags)
}

resource "aws_route" "pvt_nat_rtb" {
  count                  = var.create_pvt_nat ? (var.pvt_nat_ha_mode ? length(var.azs) : 1) : 0
  route_table_id         = aws_route_table.pvt_nat_rtb[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw[count.index].id
}

resource "aws_route_table_association" "pvt_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.pvt_sub[count.index].id
  route_table_id = var.create_pvt_nat ? (var.pvt_nat_ha_mode ? aws_route_table.pvt_nat_rtb[count.index].id : join(", ", aws_route_table.pvt_nat_rtb.*.id)) : join(", ", aws_route_table.pvt_rtb.*.id)
}

# Create EIP for data NAT gateway
resource "aws_eip" "data_nat_eip" {
  # checkov:skip=CKV2_AWS_19: EIP associated to NAT Gateway
  count = var.create_data_nat && length(var.data_nat_eip_id) == 0 ? (var.data_nat_ha_mode ? length(var.azs) : 1) : 0
  vpc   = true

  tags = merge({
    Name = "${var.network_name}-data-nat-eip"
  }, var.tags)
}

# Create NAT gateway for data subnet
resource "aws_nat_gateway" "data_nat_gw" {
  count         = var.create_data_nat ? (var.data_nat_ha_mode ? length(var.azs) : 1) : 0
  subnet_id     = aws_subnet.pub_sub[count.index].id
  allocation_id = length(var.data_nat_eip_id) == 0 ? aws_eip.data_nat_eip[count.index].id : var.data_nat_eip_id[count.index]

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
  count  = var.create_data_nat ? (var.data_nat_ha_mode ? length(var.azs) : 1) : 0
  vpc_id = aws_vpc.vpc.id

  tags = merge({
    Name = "${var.network_name}-data-rtb"
  }, var.tags)
}

resource "aws_route" "data_nat_rtb" {
  count                  = var.create_data_nat ? (var.data_nat_ha_mode ? length(var.azs) : 1) : 0
  route_table_id         = aws_route_table.data_nat_rtb[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.data_nat_gw[count.index].id
}

resource "aws_route_table_association" "data_rtb_assoc" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.data_sub[count.index].id
  route_table_id = var.create_data_nat ? (var.data_nat_ha_mode ? aws_route_table.data_nat_rtb[count.index].id : join(", ", aws_route_table.data_nat_rtb.*.id)) : join(", ", aws_route_table.data_rtb.*.id)
}

# Create public NACL
resource "aws_network_acl" "pub_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.pub_sub.*.id
  ingress    = var.pub_nacl_ingress
  egress     = var.pub_nacl_egress

  tags = merge({
    Name = "${var.network_name}-pub-nacl"
  }, var.tags)
}

# Create private NACL
resource "aws_network_acl" "pvt_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.pvt_sub.*.id
  ingress    = var.pvt_nacl_ingress
  egress     = var.pvt_nacl_egress

  tags = merge({
    Name = "${var.network_name}-pvt-nacl"
  }, var.tags)
}

# Create data NACL
resource "aws_network_acl" "data_nacl" {
  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.data_sub.*.id
  ingress    = var.data_nacl_ingress
  egress     = var.data_nacl_egress

  tags = merge({
    Name = "${var.network_name}-data-nacl"
  }, var.tags)
}

# Restrict default security group to deny all traffic
resource "aws_default_security_group" "default" {
  # checkov:skip=CKV2_AWS_5: Attaching this security group to a resource depends on user
  vpc_id = aws_vpc.vpc.id
  tags   = var.tags
}

# Create private security group
resource "aws_security_group" "pvt_sg" {
  # checkov:skip=CKV2_AWS_5: Attaching this security group to a resource depends on user
  # checkov:skip=CKV_AWS_23: Rule description not required
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.network_name}-private-sg"
  description = "Security group allowing communication within the VPC for ingress"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block]
    description = "Allow all incoming connections within internal network"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing connections within internal network"
  }

  tags = merge({
    Name = "${var.network_name}-private-sg"
  }, var.tags)
}

# Create protected security group for all communications strictly within the VPC
resource "aws_security_group" "protected_sg" {
  # checkov:skip=CKV2_AWS_5: Attaching this security group to a resource depends on user
  # checkov:skip=CKV_AWS_23: Rule description not required
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.network_name}-protected-sg"
  description = "Security group allowing all communications strictly within the VPC"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block]
    description = "Allow all incoming connections within internal network"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block]
    description = "Allow all outgoing connections within internal network"
  }

  tags = merge({
    Name = "${var.network_name}-protected-sg"
  }, var.tags)
}

# Create security group for public facing web servers or load balancer
resource "aws_security_group" "pub_sg" {
  # checkov:skip=CKV2_AWS_5: Attaching this security group to a resource depends on user
  # checkov:skip=CKV_AWS_23: Rule description not required
  # checkov:skip=CKV_AWS_260: 80 ingress required
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.network_name}-pub-web-sg"
  description = "Security group allowing 80 and 443 from outer world"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming http connections"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming https connections"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing connections"
  }

  tags = merge({
    Name = "${var.network_name}-pub-web-sg"
  }, var.tags)
}

# Create security group for internal web/app servers
resource "aws_security_group" "pvt_web_sg" {
  # checkov:skip=CKV2_AWS_5: Attaching this security group to a resource depends on user
  # checkov:skip=CKV_AWS_23: Rule description not required
  count       = var.create_sgs ? 1 : 0
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.network_name}-pvt-web-sg"
  description = "Security group allowing 80 and 443 internally for app servers"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = aws_security_group.pub_sg.*.id
    description     = "Allow incoming http connections from public sg"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = aws_security_group.pub_sg.*.id
    description     = "Allow incoming https connections from public sg"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing connections"
  }

  tags = merge({
    Name = "${var.network_name}-pvt-web-sg"
  }, var.tags)
}

# Create cloudwatch log group for vpc flow logs
resource "aws_cloudwatch_log_group" "cw_log_group" {
  count             = var.create_flow_logs && var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? 1 : 0
  name              = "${var.network_name}-flow-logs-group"
  retention_in_days = var.flow_logs_retention
  kms_key_id        = var.cw_log_group_kms_key_arn

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

data "aws_kms_key" "s3" {
  key_id = var.s3_kms_key
}

# Create S3 bucket for flow logs storage
resource "aws_s3_bucket" "flow_logs_bucket" {
  # checkov:skip=CKV_AWS_19: Default SSE is in place
  # checkov:skip=CKV_AWS_18: Access logging needs to be defined by user
  # checkov:skip=CKV2_AWS_41: Access logging needs to be defined by user
  # checkov:skip=CKV_AWS_144: CRR needs to be defined by user
  # checkov:skip=CKV_AWS_145: Default SSE is in place
  # checkov:skip=CKV2_AWS_40: Default SSE is in place
  # checkov:skip=CKV_AWS_52: MFA delete needs to be defined by user
  # checkov:skip=CKV_AWS_21: Versioning needs to be defined by user
  # checkov:skip=CKV2_AWS_37: Versioning needs to be defined by user
  # checkov:skip=CKV2_AWS_61: Llifecycle configuration needs to be defined by user
  # checkov:skip=CKV2_AWS_62: Event notifications needs to be defined by user
  count         = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? 1 : 0
  bucket        = "${var.network_name}-flow-logs-${random_id.id.hex}"
  force_destroy = var.s3_force_destroy

  tags = merge({
    Name = "${var.network_name}-flow-logs-${random_id.id.hex}"
  }, var.tags)
}

resource "aws_s3_bucket_ownership_controls" "flow_logs_bucket" {
  count  = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? 1 : 0
  bucket = join(",", aws_s3_bucket.flow_logs_bucket.*.id)

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs_bucket" {
  count  = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? 1 : 0
  bucket = join(",", aws_s3_bucket.flow_logs_bucket.*.id)

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_kms_key == "alias/aws/s3" ? "AES256" : "aws:kms"
      kms_master_key_id = var.s3_kms_key == "alias/aws/s3" ? null : data.aws_kms_key.s3.id
    }
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

data "aws_iam_policy_document" "flow_logs_bucket" {
  count = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? 1 : 0
  statement {
    sid    = "AllowSSLRequestsOnly"
    effect = "Deny"
    actions = [
      "s3:*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      join(",", aws_s3_bucket.flow_logs_bucket.*.arn),
      "${join(",", aws_s3_bucket.flow_logs_bucket.*.arn)}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = [
      "${join(",", aws_s3_bucket.flow_logs_bucket.*.arn)}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${local.region}:${local.account_id}:*"]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl"
    ]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = [
      join(",", aws_s3_bucket.flow_logs_bucket.*.arn)
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${local.region}:${local.account_id}:*"]
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs_bucket" {
  count  = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? 1 : 0
  bucket = join(",", aws_s3_bucket.flow_logs_bucket.*.id)
  policy = join(",", data.aws_iam_policy_document.flow_logs_bucket.*.json)
}

resource "aws_s3_bucket_public_access_block" "flow_logs_bucket" {
  count                   = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? 1 : 0
  bucket                  = join(",", aws_s3_bucket.flow_logs_bucket.*.id)
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

locals {
  flow_logs_log_group_arn = var.create_flow_logs && var.flow_logs_destination == "cloud-watch-logs" && var.flow_logs_cw_log_group_arn == "" ? aws_cloudwatch_log_group.cw_log_group[0].arn : var.flow_logs_cw_log_group_arn
  flow_logs_bucket_arn    = var.create_flow_logs && var.flow_logs_destination == "s3" && var.flow_logs_bucket_arn == "" ? aws_s3_bucket.flow_logs_bucket[0].arn : var.flow_logs_bucket_arn
}

# Create VPC flow logs
resource "aws_flow_log" "flow_logs" {
  count                = var.create_flow_logs ? 1 : 0
  iam_role_arn         = var.flow_logs_destination == "cloud-watch-logs" ? aws_iam_role.flow_logs_role[0].arn : null
  log_destination      = var.flow_logs_destination == "cloud-watch-logs" ? local.flow_logs_log_group_arn : local.flow_logs_bucket_arn
  log_destination_type = var.flow_logs_destination
  log_format           = var.flow_logs_log_format
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.vpc.id

  dynamic "destination_options" {
    for_each = var.create_flow_logs && var.flow_logs_destination == "s3" ? [0] : []
    content {
      file_format                = var.flow_logs_s3_file_format
      hive_compatible_partitions = var.flow_logs_s3_hive_compatible_partitions
      per_hour_partition         = var.flow_logs_s3_per_hour_partition
    }
  }

  tags = merge({
    Name = "${var.network_name}-flow-logs"
  }, var.tags)
}

# Create private hosted zone
resource "aws_route53_zone" "private" {
  # checkov:skip=CKV2_AWS_39: Query logging
  # checkov:skip=CKV2_AWS_38: DNSSEC logging
  count = var.create_private_zone == true ? 1 : 0
  name  = var.private_zone_domain

  vpc {
    vpc_id = aws_vpc.vpc.id
  }

  tags = merge({
    Name = "${var.network_name}-pvt-zone"
  }, var.tags)
}
