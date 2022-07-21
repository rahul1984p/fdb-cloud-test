provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}



// Find our latest available AMI for the fdb node
// TODO: switch to a shared and hosted stable image
data "aws_ami" "fdb" {
  most_recent = true

  filter {
    name = "name"
    values = ["bitgn-fdb"]
  }
  owners = ["self"]
}

data "aws_availability_zones" "available" {}


# Create a VPC to launch our instances into
resource "aws_vpc" "fdb-vpc" {
  cidr_block = "10.20.0.0/16"
  # this will solve sudo: unable to resolve host ip-10-0-xx-xx
  enable_dns_hostnames = true
}


# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "fdb-ig" {
  vpc_id = "${aws_vpc.fdb-vpc.id}"

}
# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.fdb-vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.fdb-ig.id}"
}


resource "aws_subnet" "fdb-subnet" {
  count                   = var.aws_fdb_count
  vpc_id                  = aws_vpc.fdb-vpc.id
  cidr_block              = "10.20.${10 + count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = var.subnet_name_tag
  }
}

# security group with only SSH access
resource "aws_security_group" "fdb_group" {
  name        = "tf_fdb_group"
  description = "Terraform: SSH and FDB"
  vpc_id      = "${aws_vpc.fdb-vpc.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # FDB access from the VPC. We open a port for each process
  ingress {
    from_port   = 4500
    to_port     = "${4500 + var.fdb_procs_per_machine - 1}"
    protocol    = "tcp"
    cidr_blocks = ["10.20.0.0/16"]
  }
  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}


resource "aws_instance" "fdb" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)

  #availability_zone = "${var.aws_availability_zone}"
  instance_type = "${var.aws_fdb_size}"
  count = "${var.aws_fdb_count}"
  # Grab AMI id from the data source
  ami = "${data.aws_ami.fdb.id}"


  # I want a very specific IP address to be assigned. However
  # AWS reserves both the first four IP addresses and the last IP address
  # in each subnet CIDR block. They're not available for you to use.
  private_ip = "${cidrhost(aws_subnet.fdb-subnet[count.index].cidr_block, count.index+1+100)}"


  # The name of our SSH keypair we created above.
  key_name = "${aws_key_pair.auth.id}"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.fdb_group.id}"]

  # We're going to launch into the DB subnet
  subnet_id = element(aws_subnet.fdb-subnet.*.id, count.index)

  tags = {
    Name = "${format("fdb-%03d", count.index + 1)}"
    Project = "TF:bitgn"
  }

  provisioner "file" {
    source      = "init-fdb.sh"
    destination = "/tmp/init-fdb.sh"
    connection {
        # The default username for our AMI
        user = "ubuntu"
        private_key = "${file(var.private_key_path)}"
        # The connection will use the local SSH agent for authentication.
        type        = "ssh"
        host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    connection {
        # The default username for our AMI
        user = "ubuntu"
        private_key = "${file(var.private_key_path)}"
        # The connection will use the local SSH agent for authentication.
        type        = "ssh"
        host        = self.public_ip
    }
    inline = [
      "sudo chmod +x /tmp/init-fdb.sh",
      "sudo /tmp/init-fdb.sh ${var.aws_fdb_size} ${var.aws_fdb_count} ${self.private_ip} ${cidrhost(aws_subnet.fdb-subnet[0].cidr_block, 101)} ${var.fdb_procs_per_machine}",
    ]
  }
}
