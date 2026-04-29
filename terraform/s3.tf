# ============================================================
# S3 Buckets
# ============================================================
# We use a single bucket with structured prefixes (folders) to
# keep everything organized and avoid cross-bucket IAM complexity.

resource "aws_s3_bucket" "main" {
  bucket        = "${lower(var.net_id)}-cisc886-project"
  force_destroy = true  # Allows terraform destroy to delete non-empty bucket

  tags = {
    Name    = "${var.net_id}-cisc886-project"
    Project = "CISC886"
  }
}

# Block all public access – data stays private
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning to protect against accidental overwrites
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ---- Folder structure via placeholder objects ----
# S3 has no real folders; we create zero-byte objects to represent them.

resource "aws_s3_object" "raw_data" {
  bucket  = aws_s3_bucket.main.id
  key     = "data/raw/.keep"
  content = ""
}

resource "aws_s3_object" "processed_data" {
  bucket  = aws_s3_bucket.main.id
  key     = "data/processed/.keep"
  content = ""
}

resource "aws_s3_object" "models" {
  bucket  = aws_s3_bucket.main.id
  key     = "models/.keep"
  content = ""
}

resource "aws_s3_object" "scripts" {
  bucket  = aws_s3_bucket.main.id
  key     = "scripts/.keep"
  content = ""
}

resource "aws_s3_object" "emr_logs" {
  bucket  = aws_s3_bucket.main.id
  key     = "logs/emr/.keep"
  content = ""
}
