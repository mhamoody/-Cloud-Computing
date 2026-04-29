#!/bin/bash
set -euo pipefail

MODEL_NAME="retail-assistant"
MODEL_FILE="/home/ec2-user/models/retail-assistant.Q4_K_M.gguf"
OPENWEBUI_PORT="3000"
OLLAMA_PORT="11434"

echo "[1/8] Installing system packages..."
sudo dnf update -y
sudo dnf install -y docker curl

echo "[2/8] Starting Docker..."
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user || true

echo "[3/8] Installing Ollama if missing..."
if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

echo "[4/8] Configuring Ollama to listen on all interfaces..."
sudo mkdir -p /etc/systemd/system/ollama.service.d

sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:${OLLAMA_PORT}"
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama

echo "[5/8] Waiting for Ollama API..."
for i in {1..30}; do
  if curl -s "http://localhost:${OLLAMA_PORT}/api/tags" >/dev/null; then
    echo "Ollama is ready."
    break
  fi
  echo "Waiting for Ollama..."
  sleep 3
done

echo "[6/8] Creating Ollama model if GGUF exists..."
mkdir -p /home/ec2-user/models

if [ -f "$MODEL_FILE" ]; then
  cd /home/ec2-user/models

  cat > Modelfile <<'EOF'
FROM ./retail-assistant.Q4_K_M.gguf

PARAMETER num_ctx 512
PARAMETER num_predict 80
PARAMETER temperature 0.3
PARAMETER top_p 0.9
PARAMETER num_thread 2

SYSTEM """
You are a helpful ecommerce shopping assistant trained on historical retail transaction data.
Answer briefly and practically.
Help users with shopping questions, order-style inquiries, returns, cancellations, and product recommendations.
Do not invent live inventory, shipping status, or real-time prices.
"""
EOF

  ollama rm "$MODEL_NAME" 2>/dev/null || true
  ollama create "$MODEL_NAME" -f Modelfile
else
  echo "WARNING: Model file not found at $MODEL_FILE"
  echo "Upload the GGUF file later, then run:"
  echo "cd /home/ec2-user/models && ollama create retail-assistant -f Modelfile"
fi

echo "[7/8] Starting OpenWebUI Docker container..."
docker rm -f open-webui 2>/dev/null || true

docker run -d \
  --name open-webui \
  --restart always \
  -p "${OPENWEBUI_PORT}:8080" \
  -e OLLAMA_BASE_URL="http://host.docker.internal:${OLLAMA_PORT}" \
  -e WEBUI_AUTH=False \
  --add-host=host.docker.internal:host-gateway \
  -v open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:main

echo "[8/8] Final status..."
docker ps
ollama list || true

echo "OpenWebUI should be available at:"
echo "http://<EC2_PUBLIC_IP>:${OPENWEBUI_PORT}"
