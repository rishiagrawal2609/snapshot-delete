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
  cutoff_date_local = timeadd(timestamp(), "${-(var.cutoff_days * 86400)}s")
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
    command = <<-EOF
#!/bin/bash
# Define the cutoff date, filter tag key, and filter tag value
cutoff_date=${local.cutoff_date_local}  # Example cutoff date
filter_tag_key=${var.filter_tag_key}       # Replace with your tag key
filter_tag_value=${var.filter_tag_value}   # Replace with your tag value

echo "Fetching snapshots older than ${local.cutoff_date_local}..."
snapshot_ids=$(aws ec2 describe-snapshots \
    --filters "Name=tag:${var.filter_tag_key},Values=${var.filter_tag_value}" \
    --query "Snapshots[?StartTime<'${local.cutoff_date_local}'].SnapshotId" \
    --output text)

echo "Found snapshots: $snapshot_ids"

if [ -z "$snapshot_ids" ]; then
    echo "No snapshots found to delete."
    exit 0
fi

for snapshot_id in $snapshot_ids; do
    echo "Attempting to delete snapshot: $snapshot_id"
    aws ec2 delete-snapshot --snapshot-id $snapshot_id
    if [ $? -eq 0 ]; then
        echo "Successfully deleted snapshot: $snapshot_id"
    else
        echo "Failed to delete snapshot: $snapshot_id"
    fi
done
EOF
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




