# ============================================================
# Section 4 — EMR Cluster (Apache Spark)
# ============================================================
# The EMR cluster is used ONLY for the Spark preprocessing job.
# It must be terminated after the job completes (required by rubric).
# Instance type: m5.xlarge (4 vCPU, 16 GB RAM) — good balance for Spark.
# 1 master + 2 core nodes = enough parallelism for a 10M row dataset.
# Use existing AWS Academy / account-approved default EMR roles.

data "aws_iam_role" "emr_default_role" {
  name = "EMR_DefaultRole"
}

data "aws_iam_instance_profile" "emr_ec2_default_profile" {
  name = "EMR_EC2_DefaultRole"
}

resource "aws_emr_cluster" "spark" {
  count = var.enable_emr ? 1 : 0
  name          = "${var.net_id}-emr-spark"
  release_label = "emr-6.15.0"   # Latest stable EMR with Spark 3.4
  applications  = ["Spark", "Hadoop", "Hive", "JupyterEnterpriseGateway"]

  # Place EMR in the PRIVATE subnet (no public exposure needed)
  ec2_attributes {
    subnet_id                         = aws_subnet.private.id
    emr_managed_master_security_group = aws_security_group.emr_master_sg.id
    emr_managed_slave_security_group  = aws_security_group.emr_core_sg.id
    service_access_security_group     = aws_security_group.emr_service_access_sg.id
    instance_profile                  = data.aws_iam_instance_profile.emr_ec2_default_profile.arn
    key_name                          = var.key_pair_name
  }

  master_instance_group {
    instance_type = var.emr_master_instance_type
    name          = "${var.net_id}-emr-master"
  }

#  core_instance_group {
#    instance_type  = var.emr_core_instance_type
#    instance_count = var.emr_core_instance_count
#    name           = "${var.net_id}-emr-core"
#  }

  service_role = data.aws_iam_role.emr_default_role.arn

  # Store EMR logs to S3 for debugging
  log_uri = "s3://${aws_s3_bucket.main.bucket}/logs/emr/"

  # Auto-terminate after all steps complete — avoids runaway costs
  auto_termination_policy {
    idle_timeout = 3600  # Terminate if idle for 1 hour
  }

  configurations_json = jsonencode([
    {
      Classification = "spark"
      Properties = {
        "maximizeResourceAllocation" = "true"
      }
    },
    {
      Classification = "spark-defaults"
      Properties = {
        "spark.sql.adaptive.enabled"              = "true"
        "spark.sql.adaptive.coalescePartitions.enabled" = "true"
        "spark.driver.memory"                     = "4g"
        "spark.executor.memory"                   = "4g"
      }
    }
  ])

  tags = {
    Name    = "${var.net_id}-emr-spark"
    Project = "CISC886"
  }

  # Important: depends on S3 bucket existing first (for logs)
  depends_on = [
    aws_s3_bucket.main,
    aws_vpc_endpoint.s3,
    aws_security_group.emr_service_access_sg
  ]
}
