# ============================================================
# Outputs — printed after terraform apply
# ============================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID (EC2)"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID (EMR)"
  value       = aws_subnet.private.id
}

output "s3_bucket_name" {
  description = "S3 bucket for all project data"
  value       = aws_s3_bucket.main.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.main.arn
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 LLM server. Null when enable_ec2=false."
  value       = try(aws_instance.llm_server[0].public_ip, null)
}

output "ec2_public_dns" {
  description = "Public DNS of the EC2 LLM server. Null when enable_ec2=false."
  value       = try(aws_instance.llm_server[0].public_dns, null)
}

output "openwebui_url" {
  description = "URL to access OpenWebUI chat interface. Null when enable_ec2=false."
  value       = try("http://${aws_instance.llm_server[0].public_ip}:3000", null)
}

output "ollama_api_url" {
  description = "Ollama API endpoint. Null when enable_ec2=false."
  value       = try("http://${aws_instance.llm_server[0].public_ip}:11434", null)
}

output "emr_cluster_id" {
  description = "EMR cluster ID. Null when enable_emr=false."
  value       = try(aws_emr_cluster.spark[0].id, null)
}

output "emr_master_dns" {
  description = "EMR master node DNS (for SSH)"
  value       = try(aws_emr_cluster.spark[0].master_public_dns, null)
}

output "s3_raw_data_path" {
  description = "S3 path to upload your raw retail dataset"
  value       = "s3://${aws_s3_bucket.main.bucket}/data/raw/"
}

output "s3_processed_data_path" {
  description = "S3 path where Spark will write preprocessed data"
  value       = "s3://${aws_s3_bucket.main.bucket}/data/processed/"
}
