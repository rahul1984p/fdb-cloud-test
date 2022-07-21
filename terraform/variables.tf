variable "public_key_path" {
  description = "Path to the SSH public key to be used for authentication."
  default = "~/.ssh/terraform.pub"
}

variable "private_key_path" {
  description = "Path to the SSH private key"
  default = "~/.ssh/terraform"
}

variable "key_name" {
   default = "terraform"
}

variable "subnet_name_tag" {
   default = "fdb-subnet"
}

variable "aws_access_key" {}
variable "aws_secret_key" {}

variable "aws_region" {
  default = "us-east-1"
  description = "AWS region to launch servers."
}

variable "aws_availability_zone" {
  default = "us-east-1b"
}


// instance store options: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html

# good options:
# i3.large - will use local NVMe SSD
# m3.large - will use local instance store

variable "aws_fdb_size" {
  default = "t2.micro"
  description = "machine type to run FoundationDB servers"
}
variable "fdb_procs_per_machine" {
  default = 2
  description = "number of FDB processes per machine"
}
# using only 1 machine will conflict with the default cluster config
# 'configure new memory double'
variable "aws_fdb_count" {
  default = 3
  description = "Number of machines in a cluster. Minimum 2"
}
