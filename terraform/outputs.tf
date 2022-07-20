
output "fdb_address" {
  value = "${aws_instance.fdb.*.public_dns}"
}

