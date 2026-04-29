# ============================================================
# IAM Roles
# ============================================================

# --- EMR Service Role ---
# Allows the EMR service itself to manage cluster resources on your behalf.
resource "aws_iam_role" "emr_service_role" {
  name = "${var.net_id}-emr-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "elasticmapreduce.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.net_id}-emr-service-role" }
}

resource "aws_iam_role_policy_attachment" "emr_service_policy" {
  role       = aws_iam_role.emr_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

# --- EMR EC2 Instance Profile Role ---
# Applied to the EC2 nodes within the EMR cluster.
# Grants access to S3, CloudWatch logs, etc.
resource "aws_iam_role" "emr_ec2_role" {
  name = "${var.net_id}-emr-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.net_id}-emr-ec2-role" }
}

resource "aws_iam_role_policy_attachment" "emr_ec2_policy" {
  role       = aws_iam_role.emr_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

# Additional S3 policy scoped to our bucket
resource "aws_iam_role_policy" "emr_s3_access" {
  name = "${var.net_id}-emr-s3-access"
  role = aws_iam_role.emr_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.main.arn,
        "${aws_s3_bucket.main.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "emr_ec2_profile" {
  name = "${var.net_id}-emr-ec2-profile"
  role = aws_iam_role.emr_ec2_role.name
}

# --- EC2 Role (for the LLM serving instance) ---
# Allows the EC2 instance to pull models and outputs from S3.
resource "aws_iam_role" "ec2_role" {
  name = "${var.net_id}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.net_id}-ec2-role" }
}

resource "aws_iam_role_policy" "ec2_s3_access" {
  name = "${var.net_id}-ec2-s3-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.main.arn,
        "${aws_s3_bucket.main.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.net_id}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
