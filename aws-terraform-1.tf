provider "aws"{
    access_key = var.access_key
    secret_key = var.secret_key
    region = "ap-south-1"
}

resource "aws_vpc" "myvpc" {  #resource 'resouce_name' 'reference_name'

    cidr_block = "10.0.0.0/16"
    instance_tenancy = "default"
    tags = {
        Name = "My-VPC"
    }
}

#create subnets
#public
resource "aws_subnet" "pubsub" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  tags = {
    Name = "My-VPC-PU-SUB"
  }
}
#private
resource "aws_subnet" "prisub" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "My-VPC-PRI-SUB"
  }
}

#internet gateway

resource "aws_internet_gateway" "tigw" {
  vpc_id = aws_vpc.myvpc.id
  tags = {
    Name = "My-VPC-IGW"
  }
}

#route table
#public
resource "aws_route_table" "pubrt" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block = "0.0.0.0/0"  #since its public it must be open to all
    gateway_id = aws_internet_gateway.tigw.id
  } 
  tags = {
    Name = "My-VPC-PUB-RT"
  }
}

#associate public route table with subnet
resource "aws_route_table_association" "pubrtassoc" {
  subnet_id      = aws_subnet.pubsub.id
  route_table_id = aws_route_table.pubrt.id
}

#nat gateway for private subnet
#(youll need elastic ip now, now go create a eip)
resource "aws_eip" "myeip" {   
  domain   = "vpc"
}
resource "aws_nat_gateway" "tnat" {
  allocation_id = aws_eip.myeip.id    
  subnet_id     = aws_subnet.pubsub.id   #nat gateway must be in public subnet

  tags = {
    Name = "My-VPC-NAT"
  }
}
#private
resource "aws_route_table" "prirt" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block = "0.0.0.0/0"  
    gateway_id = aws_nat_gateway.tnat.id  #we use nat gateway here
  } 
  tags = {
    Name = "My-VPC-PRI-RT"
  }
}

#associate private route table with subnet
resource "aws_route_table_association" "prirtassoc" {
  subnet_id      = aws_subnet.prisub.id
  route_table_id = aws_route_table.prirt.id
}

#now we'll move to security groups

resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow nbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp" # -1 for protocols
    cidr_blocks = ["0.0.0.0/0"] # add n no of cidrs using commas (,)   
  }
  ingress{
    from_port   = 80
    to_port     = 80
    protocol    = "tcp" # -1 for protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress{
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "MY-VPC-SG"
  }
}

#public ip ec2 instance
resource "aws_instance" "ec21" {
    ami = var.ami_id
    instance_type = "t2.micro"
    subnet_id = aws_subnet.pubsub.id
    vpc_security_group_ids = [aws_security_group.allow_all.id] #can add multiple security groups using comma (,)
    associate_public_ip_address = true

    tags = {
        Name = "Instance1"
    }
}
resource "aws_instance" "ec22" {
    ami = var.ami_id
    instance_type = "t2.micro"
    subnet_id = aws_subnet.prisub.id
    vpc_security_group_ids = [aws_security_group.allow_all.id] #can add multiple security groups using comma (,)
    associate_public_ip_address = false

    tags = {
        Name = "Instance2"
    }
}



