# AWS VPC with Public & Private Subnets (Terraform)
refer `aws-terraform-1.tf` file  
video ref and credits : https://www.youtube.com/watch?v=xnRRJw_sI8s  
This repository provisions a basic AWS network on **ap-south-1 (Mumbai)** with:

- One **VPC** (`10.0.0.0/16`)
- One **public subnet** (`10.0.1.0/24`) in `ap-south-1a`
- One **private subnet** (`10.0.2.0/24`) in `ap-south-1b`
- An **Internet Gateway** for public egress
- A **NAT Gateway** in the public subnet for private egress
- Separate **route tables** for public and private traffic
- A permissive **security group** (for demo) allowing SSH (22) and HTTP (80)
- Two **EC2 instances**: one in public, one in private

> ⚠️ **Note on security**: Opening SSH (22) and HTTP (80) to `0.0.0.0/0` is convenient for demos but risky in production. Restrict CIDRs and use bastion hosts / VPNs wherever possible.

---

## Architecture Overview

```
+---------------------------- VPC 10.0.0.0/16 ----------------------------+
|                                                                         |
|  [IGW] Internet Gateway                                                 |
|                                                                         |
|  Public Subnet 10.0.1.0/24 (ap-south-1a)                                |
|   - Route Table: 0.0.0.0/0 -> IGW                                       |
|   - NAT Gateway (Elastic IP)                                            |
|   - EC2 (Instance1) – public IP                                         |
|                                                                         |
|  Private Subnet 10.0.2.0/24 (ap-south-1b)                               |
|   - Route Table: 0.0.0.0/0 -> NAT GW                                    |
|   - EC2 (Instance2) – no public IP                                      |
|                                                                         |
+-------------------------------------------------------------------------+
```

---

## Files

- `main.tf` - core resources (VPC, subnets, IGW, NAT GW, route tables, SG, EC2)
- `variables.tf` - input variables and description for below
- `terraform.tfvars` - add access_key, secret_key and ami_id

You can also keep everything in a single `.tf` for quick tests, but splitting improves maintainability.

---

## Prerequisites


Set credentials via environment variables (recommended):

```bash
export AWS_ACCESS_KEY_ID=xxxxxxxx
export AWS_SECRET_ACCESS_KEY=xxxxxxxx
export AWS_DEFAULT_REGION=ap-south-1
```

Or use terrfaorm.tfvars and a variable file

---

## Usage

1. **Initialize** providers and modules:
   ```bash
   terraform init
   ```
2. **Review the plan**:
   ```bash
   terraform plan -var "ami_id=ami-xxxxxxxx" -var "access_key=..." -var "secret_key=..."
   ```
3. **Apply**:
   ```bash
   terraform apply -auto-approve -var "ami_id=ami-xxxxxxxx" -var "access_key=..." -var "secret_key=..."
   ```
4. **Cleanup**:
   ```bash
   terraform destroy
   ```

> 💡 **Tip (cost control)**: NAT Gateways and Elastic IPs incur charges. Destroy resources when not in use.

---

## Explanation of Resources

### Provider
```hcl
provider "aws" {
  access_key = var.access_key
  secret_key = var.secret_key
  region     = "ap-south-1"
}
```
Sets the AWS region and credentials (for demos). Prefer environment variables or shared credentials files in production.

### VPC
```hcl
resource "aws_vpc" "myvpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = { Name = "My-VPC" }
}
```
Creates an isolated network space.

### Subnets
```hcl
resource "aws_subnet" "pubsub" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  tags = { Name = "My-VPC-PU-SUB" }
}

resource "aws_subnet" "prisub" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
  tags = { Name = "My-VPC-PRI-SUB" }
}
```
Public subnet hosts internet-facing resources; private subnet hosts internal workloads.

### Internet Gateway
```hcl
resource "aws_internet_gateway" "tigw" {
  vpc_id = aws_vpc.myvpc.id
  tags = { Name = "My-VPC-IGW" }
}
```
Provides a target for outbound routes from the public subnet to the internet.

### Route Tables
```hcl
resource "aws_route_table" "pubrt" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tigw.id
  }
  tags = { Name = "My-VPC-PUB-RT" }
}

resource "aws_route_table_association" "pubrtassoc" {
  subnet_id      = aws_subnet.pubsub.id
  route_table_id = aws_route_table.pubrt.id
}
```
Public subnet routes default traffic to the Internet Gateway.

### NAT Gateway (for private egress)
```hcl
resource "aws_eip" "myeip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "tnat" {
  allocation_id = aws_eip.myeip.id
  subnet_id     = aws_subnet.pubsub.id
  tags = { Name = "My-VPC-NAT" }
}
```
NAT GW sits in the public subnet with an Elastic IP so private instances can reach the internet for updates without being publicly reachable.

> **Route in private table** should point to the **NAT Gateway**:
```hcl
resource "aws_route_table" "prirt" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.tnat.id
  }
  tags = { Name = "My-VPC-PRI-RT" }
}

resource "aws_route_table_association" "prirtassoc" {
  subnet_id      = aws_subnet.prisub.id
  route_table_id = aws_route_table.prirt.id
}
```

### Security Group
```hcl
resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow inbound SSH and HTTP; allow all outbound"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"   # use tcp, not "http"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "MY-VPC-SG" }
}
```

### EC2 Instances
```hcl
resource "aws_instance" "ec21" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.pubsub.id
  vpc_security_group_ids      = [aws_security_group.allow_all.id]
  associate_public_ip_address = true
  tags = { Name = "Instance1" }
}

resource "aws_instance" "ec22" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.prisub.id
  vpc_security_group_ids      = [aws_security_group.allow_all.id]
  associate_public_ip_address = false
  tags = { Name = "Instance2" }
}
```
Public instance is reachable from the internet; private instance is reachable only within the VPC (or through the public instance/bastion, if configured).

---

## Variables Example (`variables.tf`)
```hcl
variable "access_key" { type = string }
variable "secret_key" { type = string }
variable "ami_id"     { type = string }
```

You can also remove `access_key` & `secret_key` variables if you rely on environment variables or profiles.

---
