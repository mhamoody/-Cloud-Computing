# CISC 886 - Cloud-Based Retail Chatbot

**Group:** CISC886-28  
**Members:** Elofy, Mostafa / Ghanem, Mohamed / Hasan, Mohamed  
**AWS resource prefix:** `25DJT3`  
**Region:** `us-east-1`  
**Dataset:** UCI Online Retail  
**Base model:** `unsloth/Llama-3.2-1B-Instruct`  
**Final Ollama model:** `retail-assistant:latest`

This repository implements an end-to-end AWS chatbot pipeline:

```text
Raw retail data in S3
  -> EMR + PySpark preprocessing
  -> train/eval conversational JSONL in S3
  -> Unsloth QLoRA fine-tuning
  -> GGUF model export
  -> EC2 + Ollama serving
  -> OpenWebUI browser chat interface
```

## 1. Prerequisites

- AWS CLI configured for the class AWS account
- Terraform >= 1.3
- Existing EC2 key pair in `us-east-1`
- Python 3.10+
- Google Colab with GPU for fine-tuning
- Docker and Ollama on the EC2 instance

## 2. AWS resources used

| Resource | Value |
|---|---|
| S3 bucket | `25djt3-cisc886-project` |
| VPC | `25DJT3-vpc` / `vpc-0099c2f011ec8fdf2` |
| VPC CIDR | `10.0.0.0/16` |
| Public subnet | `25DJT3-public-subnet` / `subnet-0857d02f638d2e789` / `10.0.1.0/24` |
| Private subnet | `25DJT3-private-subnet` / `10.0.2.0/24` |
| EC2 security group | `25DJT3-ec2-sg` / `sg-0a63dabc161a24f1d` |
| EMR master SG | `25DJT3-emr-master-sg` / `sg-06848205c01f0570d` |
| EMR core SG | `25DJT3-emr-core-sg` / `sg-0763f4a6bb0f92c11` |
| EMR cluster | `25DJT3-emr-spark` / `j-2RDM6RZJROAW5` |
| EMR release | `emr-7.13.0` |
| Spark version | `Spark 3.5.6` |
| EC2 public IP used in demo | `34.205.90.80` |
| EC2 private IP used in demo | `10.0.1.105` |

## 3. S3 layout

```text
s3://25djt3-cisc886-project/
├── data/
│   ├── raw/
│   │   └── Online Retail.xlsx
│   └── processed/
│       ├── retail_train.jsonl
│       └── retail_eval.jsonl
├── models/
│   ├── Modelfile
│   ├── retail-assistant.Q4_K_M.gguf
│   └── training_artifacts/
└── logs/
    └── emr/
```

## 4. Terraform deployment

Initialize and apply infrastructure:

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

Check outputs:

```bash
terraform output
```

If EC2 quota is limited, disable EC2 while running EMR preprocessing, then enable EC2 later. A typical variable pattern is:

```hcl
variable "enable_ec2" {
  description = "Whether to create the EC2 LLM serving instance."
  type        = bool
  default     = false
}

resource "aws_instance" "llm_server" {
  count = var.enable_ec2 ? 1 : 0
  # ...
}
```

## 5. Upload raw data

```bash
aws s3 cp "Online Retail.xlsx" \
  s3://25djt3-cisc886-project/data/raw/Online\ Retail.xlsx
```

The dataset source is UCI Online Retail: https://archive.ics.uci.edu/dataset/352/online+retail

## 6. Run PySpark preprocessing on EMR

Upload the PySpark script:

```bash
aws s3 cp scripts/retail_to_sft.py \
  s3://25djt3-cisc886-project/scripts/retail_to_sft.py
```

Submit the EMR Spark step:

```bash
aws emr add-steps \
  --cluster-id j-2RDM6RZJROAW5 \
  --steps "Type=Spark,Name=retail-sft-preprocessing,ActionOnFailure=CONTINUE,Args=[--deploy-mode,cluster,s3://25djt3-cisc886-project/scripts/retail_to_sft.py,--input,s3://25djt3-cisc886-project/data/raw/Online Retail.xlsx,--output,s3://25djt3-cisc886-project/data/processed/retail_sft]"
```

Expected output examples:

```text
s3://25djt3-cisc886-project/data/processed/retail_sft/train_jsonl/
s3://25djt3-cisc886-project/data/processed/retail_sft/eval_jsonl/
s3://25djt3-cisc886-project/data/processed/retail_sft/clean_purchases_parquet/
s3://25djt3-cisc886-project/data/processed/retail_sft/stats/
```

For the submitted demo, the final train/eval files are available under:

```text
s3://25djt3-cisc886-project/data/processed/retail_train.jsonl
s3://25djt3-cisc886-project/data/processed/retail_eval.jsonl
```

## 7. Fine-tune with Unsloth

The fine-tuning notebook uses:

| Parameter | Value |
|---|---|
| Base model | `unsloth/Llama-3.2-1B-Instruct` |
| Method | QLoRA / LoRA |
| Training examples | 6,000 |
| Eval examples | 500 |
| Max steps | 500 |
| Learning rate | `2e-4` |
| Effective batch size | 8 |
| LoRA rank | 16 |
| LoRA alpha | 16 |
| Optimizer | `adamw_8bit` |
| Export | `GGUF Q4_K_M` |

Representative training snippet:

```python
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=train_data,
    eval_dataset=eval_data,
    dataset_text_field="text",
    max_seq_length=1024,
    packing=True,
    args=TrainingArguments(
        per_device_train_batch_size=2,
        gradient_accumulation_steps=4,
        max_steps=500,
        warmup_steps=20,
        learning_rate=2e-4,
        fp16=not is_bfloat16_supported(),
        bf16=is_bfloat16_supported(),
        logging_steps=10,
        eval_strategy="steps",
        eval_steps=100,
        save_strategy="steps",
        save_steps=50,
        save_total_limit=3,
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="linear",
        output_dir=CHECKPOINT_DIR,
        report_to="none",
    ),
)
trainer.train(resume_from_checkpoint=last_checkpoint)
```

Export GGUF:

```python
model.save_pretrained_gguf(
    "/content/drive/MyDrive/cisc886-retail-chatbot/retail_assistant_gguf",
    tokenizer,
    quantization_method="q4_k_m",
)
```

## 8. Upload model artifacts

```bash
aws s3 cp retail-assistant.Q4_K_M.gguf \
  s3://25djt3-cisc886-project/models/retail-assistant.Q4_K_M.gguf

aws s3 cp Modelfile \
  s3://25djt3-cisc886-project/models/Modelfile
```

## 9. Deploy on EC2 with Ollama

SSH:

```bash
ssh -i /c/Users/DPQUAI250128/25DJT3-keypair.pem ec2-user@34.205.90.80
```

Install Ollama:

```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable --now ollama
```

Copy the model to EC2 if S3 list/download is restricted:

```bash
scp -i /c/Users/DPQUAI250128/25DJT3-keypair.pem \
  /e/Subs/Cloud/Proj/fine/retail-assistant.Q4_K_M.gguf \
  ec2-user@34.205.90.80:/home/ec2-user/retail-assistant.Q4_K_M.gguf
```

Create Ollama model:

```bash
mkdir -p ~/models
mv ~/retail-assistant.Q4_K_M.gguf ~/models/
cd ~/models

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
Do not invent live inventory, shipping status, or real-time prices.
"""
EOF

ollama rm retail-assistant || true
ollama create retail-assistant -f Modelfile
ollama list
```

Curl test:

```bash
curl http://localhost:11434/api/generate \
  -d '{"model":"retail-assistant","prompt":"Say hello in one short sentence.","stream":false}'
```

## 10. Deploy OpenWebUI

Make Ollama reachable from Docker:

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Run OpenWebUI:

```bash
docker rm -f open-webui || true

docker run -d \
  --name open-webui \
  --restart always \
  -p 3000:8080 \
  -e OLLAMA_BASE_URL=http://10.0.1.105:11434 \
  -e WEBUI_AUTH=False \
  -v open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:main
```

Open in browser:

```text
http://34.205.90.80:3000
```

Select `retail-assistant:latest` and test a retail prompt.

## 11. Teardown

Terminate EMR after preprocessing:

```bash
aws emr terminate-clusters --cluster-ids j-2RDM6RZJROAW5
```

Destroy Terraform-managed infrastructure when finished:

```bash
terraform destroy
```

## 13. Cost notes

| Service | Cost control |
|---|---|
| S3 | Low storage usage; raw data, JSONL, GGUF, logs. |
| EMR | Terminate immediately after preprocessing. |
| EC2 | Stop/destroy after usage. |
| Data transfer | Efficient utilization. |
