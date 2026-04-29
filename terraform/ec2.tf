# ============================================================
# Section 6 — EC2 Instance for LLM Deployment
# ============================================================

# Fetch the latest Amazon Linux 2023 AMI (GPU-compatible)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User-data script: installs Ollama and OpenWebUI on first boot,
# then configures both to start automatically as systemd services.
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # ---- System update ----
    dnf update -y
    dnf install -y docker git curl

    # ---- Install Ollama ----
    curl -fsSL https://ollama.com/install.sh | sh

    # Create a systemd service for Ollama so it survives reboots
    cat > /etc/systemd/system/ollama.service <<'SERVICE'
    [Unit]
    Description=Ollama LLM Runner
    After=network.target

    [Service]
    ExecStart=/usr/local/bin/ollama serve
    Restart=always
    RestartSec=5
    Environment="OLLAMA_HOST=0.0.0.0:11434"

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable ollama
    systemctl start ollama

    # ---- Install and start OpenWebUI via Docker ----
    systemctl enable docker
    systemctl start docker

    docker run -d \
      --name open-webui \
      --restart always \
      -p 3000:8080 \
      --add-host=host.docker.internal:host-gateway \
      -e OLLAMA_BASE_URL=http://localhost:11434 \
      -v open-webui:/app/backend/data \
      ghcr.io/open-webui/open-webui:main

    echo "Setup complete. OpenWebUI available on port 3000."
  EOF
}

resource "aws_instance" "llm_server" {
  count = var.enable_ec2 ? 1 : 0
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_pair_name

  # 100 GB root volume — needed for model weights (GGUF files are 4–8 GB each)
  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = local.user_data

  tags = {
    Name    = "${var.net_id}-ec2-llm"
    Project = "CISC886"
  }

  depends_on = [aws_internet_gateway.igw]
}
