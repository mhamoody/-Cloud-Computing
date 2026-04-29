# ============================================================
# Variables
# ============================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "net_id" {
  description = "Queen's University netID prefix for all resources"
  type        = string
  default     = "25DJT3"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (EC2 + OpenWebUI)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet (EMR cluster)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "AZ to deploy resources into"
  type        = string
  default     = "us-east-1a"
}

variable "enable_ec2" {
  description = "Whether to create the EC2 LLM serving instance. Keep false until EC2 quota is available."
  type        = bool
  default     = false
}

variable "enable_emr" {
  description = "Whether to create the EMR Spark cluster. Keep false when deploying only EC2."
  type        = bool
  default     = false
}

variable "ec2_instance_type" {
  description = "EC2 instance type for LLM serving (g4dn.xlarge has 16GB VRAM)"
  type        = string
  default     = "t3.large"
}

variable "emr_master_instance_type" {
  description = "EMR master node instance type"
  type        = string
  default     = "m5.xlarge"
}

variable "emr_core_instance_type" {
  description = "EMR core node instance type"
  type        = string
  default     = "m5.xlarge"
}

variable "emr_core_instance_count" {
  description = "Number of EMR core nodes"
  type        = number
  default     = 0
}

variable "key_pair_name" {
  description = "Name of your existing AWS EC2 key pair for SSH access"
  type        = string
  default     = "25DJT3-keypair"  # Change this to your actual key pair name
}
