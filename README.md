# Create a three tier AWS VPC network

![License](https://img.shields.io/github/license/terrablocks/aws-three-tier-network?style=for-the-badge) ![Tests](https://img.shields.io/github/actions/workflow/status/terrablocks/aws-three-tier-network/tests.yml?branch=main&label=Test&style=for-the-badge) ![Checkov](https://img.shields.io/github/actions/workflow/status/terrablocks/aws-three-tier-network/checkov.yml?branch=main&label=Checkov&style=for-the-badge) ![Commit](https://img.shields.io/github/last-commit/terrablocks/aws-three-tier-network?style=for-the-badge) ![Release](https://img.shields.io/github/v/release/terrablocks/aws-three-tier-network?style=for-the-badge)

## **Note:** Please use [aws-vpc](https://github.com/terrablocks/aws-vpc) and [aws-subnets](https://github.com/terrablocks/aws-subnets) modules instead of this for better management of your network stack

This terraform module will deploy the following services:
- VPC
  - Subnets
  - Internet Gateway
  - NAT Gateway
  - Route Tables
  - NACLs
  - Security Groups (Optional)
  - Flow Logs (Optional)
- Route53
  - Private Hosted Zone (Optional)
- CloudWatch Log Group (Optional)
- S3 Bucket (Optional)

# Usage Instructions
## Example
```terraform
module "network" {
  source = "github.com/terrablocks/aws-three-tier-network.git"

  network_name     = "pvt-network"
  azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
  pub_subnet_mask  = 24
  pvt_subnet_mask  = 22
  data_subnet_mask = 24
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 0.15 |
| aws | >= 4.0.0 |
| random | >= 3.1.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| network_name | Name to be used for VPC resources | `string` | n/a | yes |
| cidr_block | CIDR block for VPC | `string` | `"10.0.0.0/16"` | no |
| additional_cidr_blocks | Additional CIDR block to assicate with VPC | `list(string)` | `[]` | no |
| enable_dns_support | Whether to enable/disable DNS support in the VPC | `bool` | `true` | no |
| enable_dns_hostnames | Whether to enable/disable DNS hostnames in the VPC | `bool` | `true` | no |
| instance_tenancy | Tenancy option for instances launched into the VPC. **Valid values:** default, dedicated | `string` | `"default"` | no |
| assign_ipv6_cidr_block | Requests an Amazon-provided IPv6 CIDR block with a /56 prefix length for the VPC | `bool` | `false` | no |
| azs | List of availability zones to be used for launching resources | `list(string)` | <pre>[<br>  "us-east-1a",<br>  "us-east-1b"<br>]</pre> | no |
| map_public_ip_for_public_subnet | Auto assign public IP to resources launched in public subnet | `bool` | `true` | no |
| pub_subnet_mask | Subnet mask to use for public subnet | `number` | `24` | no |
| pvt_subnet_mask | Subnet mask to use for private subnet | `number` | `24` | no |
| data_subnet_mask | Subnet mask to use for data subnet | `number` | `24` | no |
| create_pvt_nat | Whether to create NAT gateway for private subnet | `bool` | `true` | no |
| pvt_nat_ha_mode | This option will create NAT gateway for private subnet in each availability zone | `bool` | `true` | no |
| pvt_nat_eip_id | List of allocation ID of EIP to attach to NAT gateway in private subnet. If creating NAT in HA mode count of EIP ID must match AZ count otherwise, count of EIP ID should be 1. Leave it blank to create new EIP(s) | `list(string)` | `[]` | no |
| create_data_nat | Whether to create NAT gateway for data subnet | `bool` | `true` | no |
| data_nat_ha_mode | This option will create NAT gateway for data subnet in each availability zone | `bool` | `true` | no |
| data_nat_eip_id | List of allocation ID of EIP to attach to NAT gateway in data subnet. If creating NAT in HA mode count of EIP ID must match AZ count otherwise, count of EIP ID should be 1. Leave it blank to create new EIP(s) | `list(string)` | `[]` | no |
| pub_nacl_ingress | List of ingress rules to attach to public subnet NACL | `list(any)` | <pre>[<br>  {<br>    "action": "allow",<br>    "cidr_block": "0.0.0.0/0",<br>    "from_port": 0,<br>    "icmp_code": null,<br>    "icmp_type": null,<br>    "ipv6_cidr_block": null,<br>    "protocol": "-1",<br>    "rule_no": 100,<br>    "to_port": 0<br>  }<br>]</pre> | no |
| pub_nacl_egress | List of egress rules to attach to public subnet NACL | `list(any)` | <pre>[<br>  {<br>    "action": "allow",<br>    "cidr_block": "0.0.0.0/0",<br>    "from_port": 0,<br>    "icmp_code": null,<br>    "icmp_type": null,<br>    "ipv6_cidr_block": null,<br>    "protocol": "-1",<br>    "rule_no": 100,<br>    "to_port": 0<br>  }<br>]</pre> | no |
| pvt_nacl_ingress | List of ingress rules to attach to private subnet NACL | `list(any)` | <pre>[<br>  {<br>    "action": "allow",<br>    "cidr_block": "0.0.0.0/0",<br>    "from_port": 0,<br>    "icmp_code": null,<br>    "icmp_type": null,<br>    "ipv6_cidr_block": null,<br>    "protocol": "-1",<br>    "rule_no": 100,<br>    "to_port": 0<br>  }<br>]</pre> | no |
| pvt_nacl_egress | List of egress rules to attach to private subnet NACL | `list(any)` | <pre>[<br>  {<br>    "action": "allow",<br>    "cidr_block": "0.0.0.0/0",<br>    "from_port": 0,<br>    "icmp_code": null,<br>    "icmp_type": null,<br>    "ipv6_cidr_block": null,<br>    "protocol": "-1",<br>    "rule_no": 100,<br>    "to_port": 0<br>  }<br>]</pre> | no |
| data_nacl_ingress | List of ingress rules to attach to data subnet NACL | `list(any)` | <pre>[<br>  {<br>    "action": "allow",<br>    "cidr_block": "0.0.0.0/0",<br>    "from_port": 0,<br>    "icmp_code": null,<br>    "icmp_type": null,<br>    "ipv6_cidr_block": null,<br>    "protocol": "-1",<br>    "rule_no": 100,<br>    "to_port": 0<br>  }<br>]</pre> | no |
| data_nacl_egress | List of egress rules to attach to data subnet NACL | `list(any)` | <pre>[<br>  {<br>    "action": "allow",<br>    "cidr_block": "0.0.0.0/0",<br>    "from_port": 0,<br>    "icmp_code": null,<br>    "icmp_type": null,<br>    "ipv6_cidr_block": null,<br>    "protocol": "-1",<br>    "rule_no": 100,<br>    "to_port": 0<br>  }<br>]</pre> | no |
| create_flow_logs | Whether to enable flow logs for VPC | `bool` | `true` | no |
| flow_logs_destination | Destination to store VPC flow logs. Possible values: s3, cloud-watch-logs | `string` | `"cloud-watch-logs"` | no |
| flow_logs_log_format | Specify the fields using the ${field-id} format, separated by spaces to include in the flow log record. E.g: ${version} ${account-id}. Leave it to `null` to use the AWS default format. Refer to [AWS doc](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html#flow-logs-fields) to learn what all fields can be included in the flow logs | `string` | `null` | no |
| flow_logs_retention | Time period for which you want to retain VPC flow logs in CloudWatch log group. Default is 0 which means logs never expire. Possible values are 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653 | `number` | `90` | no |
| flow_logs_cw_log_group_arn | ARN of CloudWatch Log Group to use for storing VPC flow logs | `string` | `""` | no |
| cw_log_group_kms_key_arn | ARN of KMS key to use for Cloudwatch Log Group SSE | `string` | `null` | no |
| flow_logs_bucket_arn | ARN of S3 to use for storing VPC flow logs | `string` | `""` | no |
| flow_logs_s3_file_format | The format of log file delivered to the S3 bucket. **Valid values:** plain-text, parquet | `string` | `"plain-text"` | no |
| flow_logs_s3_hive_compatible_partitions | Whether to use Hive-compatible S3 prefixes to simplify the loading of new data into your Hive-compatible tools | `bool` | `false` | no |
| flow_logs_s3_per_hour_partition | Partition your logs per hour to reduce your query costs and get faster response if you have a large volume of logs and typically run queries targeted to a specific hour timeframe. Setting it to `false` will partition logs every 24 hours | `bool` | `true` | no |
| s3_force_destroy | Delete bucket content before deleting bucket | `bool` | `true` | no |
| s3_kms_key | Alias/ID/ARN of KMS key to use for encrypting S3 bucket content | `string` | `"alias/aws/s3"` | no |
| create_private_zone | Whether to create private hosted zone for VPC | `bool` | `false` | no |
| private_zone_domain | Domain name to be used for private hosted zone | `string` | `"server.internal.com"` | no |
| create_sgs | Whether to create few widely used security groups for controlling traffic | `bool` | `false` | no |
| tags | Map of key-value pair to associate with resources | `map(any)` | `{}` | no |
| add_eks_tags | Add `kubernetes.io/role/elb: 1` and `kubernetes.io/role/internal-elb: 1` tags to public and private subnets respectively for load balancer | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | ID of VPC created |
| cidr | CIDR block of VPC created |
| public_subnet_ids | List of public subnets id |
| public_subnet_cidrs | List of public subnet CIDR block |
| public_subnet_rtb | ID of public route table created |
| private_subnet_ids | List of private subnet id |
| private_subnet_cidrs | List of private subnet CIDR block |
| private_subnet_rtb | ID of private route table created |
| data_subnet_ids | List of data subnet id |
| data_subnet_cidrs | List of data subnet CIDR block |
| data_subnet_rtb | ID of data route table created |
| pvt_nat_public_ip | List of Elastic IP associated to Private NAT gateway(s) |
| data_nat_public_ip | List of Elastic IP associated to Data NAT gateway(s) |
| pvt_sg | ID of private security group |
| protected_sg | ID of security group allowing all communications strictly within the VPC |
| public_web_dmz_sg | Security group ID for public facing web servers or load balancer |
| private_web_dmz_sg | Security group ID for internal web/app servers |
| private_zone_id | Route53 private hosted zone id |
| private_zone_ns | List of private hosted zone name servers |
