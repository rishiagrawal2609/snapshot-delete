data "aws_instances" "instances_with_tag" {
  filter {
    name   = "tag:${var.filter_tag_key}"
    values = [var.filter_tag_value]
  }

  filter {
    name   = "instance-state-name"
    values = ["running", "stopped"]
  }
}

data "aws_instance" "filtered_instances" {
  for_each   = toset(data.aws_instances.instances_with_tag.ids)
  instance_id = each.key
}

locals {
  cutoff_date_local = "2025-01-03T12:00:00Z"
  #timeadd(timestamp(), "${-(var.cutoff_days * 86400)}s")
}

resource "aws_ebs_snapshot" "snapshots" {
  for_each = toset(flatten([
    for instance in data.aws_instance.filtered_instances :
    concat(
      [for root in instance.root_block_device : root.volume_id],
      [for ebs in instance.ebs_block_device : ebs.volume_id]
    )
  ]))
  
  volume_id = each.value
  tags = {
    "${var.filter_tag_key}" = var.filter_tag_value
  }
}

resource "null_resource" "delete_old_snapshots" {
  provisioner "local-exec" {
    interpreter = [ "bash","-c" ]
    command = <<EOT
      aws ec2 describe-snapshots \
        --filters "Name=start-time,Values=lt:2025-01-03T12:00:00Z" \
        | jq -r '.Snapshots[] | .SnapshotId'
    EOT
  }
}

output "instance_ids" {
  value = data.aws_instances.instances_with_tag.ids
}

output "volume_ids" {
  value = flatten([
    for inst in data.aws_instance.filtered_instances : 
    [for bd in inst.ebs_block_device : bd.volume_id]
  ])
}

output "snapshot_ids" {
  value = [for snapshot in aws_ebs_snapshot.snapshots : snapshot.id]
}

output "cutoff_date" {
  value = local.cutoff_date_local
}




