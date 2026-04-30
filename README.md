# CISC 886 - Cloud-Based Conversational Retail Chatbot

**Group:** CISC886-28
**Members:** Elofy, Mostafa / Ghanem, Mohamed / Hasan, Mohamed
**AWS resource prefix:** `25DJT3`
**Region:** `us-east-1`
**Dataset:** UCI Online Retail
**Base model:** unsloth/Llama-3.2-1B-Instruct
**Final Ollama model:** retail-assistant:latest
This repository contains an end-to-end AWS chatbot pipeline:

1. Terraform provisions the VPC, subnets, S3 bucket, security groups, IAM roles, EMR, and EC2 resources.
2. The raw Online Retail dataset is stored in S3.
3. Apache Spark on Amazon EMR preprocesses the dataset into conversational train/eval JSONL.
4. Unsloth fine-tunes a small instruction model with QLoRA/LoRA adapters.
5. The fine-tuned GGUF model is served on EC2 with Ollama.
6. OpenWebUI provides the browser-based chat interface.

---

## 0. Repository Structure

```text
.
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── networking.tf
│   ├── s3.tf
│   ├── iam.tf
│   ├── emr.tf
│   ├── ec2.tf
│   └── outputs.tf
├── scripts/
│   └── retail_to_sft.py
├── notebooks/
│   └── finetune_unsloth.ipynb
├── report/
│   └── CISC886_Retail_Chatbot_Report.pdf
└── README.md
```
---

## 1. AWS resources used

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

---

## 2. Prerequisites

- AWS account access for the CISC 886 shared environment
- AWS CLI v2 configured with temporary credentials
- Terraform >= 1.3.0
- Existing EC2 key pair in `us-east-1`
- Python 3.10+
- Google Colab or another GPU environment for fine-tuning
- Local SSH client

Verify AWS credentials:

```bash
aws sts get-caller-identity
aws configure get region
```

Expected region:

```text
us-east-1
```

---

## 3. Create or Confirm EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --region us-east-1 \
  --key-name 25DJT3-keypair \
  --query 'KeyMaterial' \
  --output text > 25DJT3-keypair.pem

chmod 400 25DJT3-keypair.pem
```

If the key already exists, keep the existing `.pem` file and do not recreate it.

---

## 4. Terraform Deployment

```bash
cd terraform
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

Useful outputs:

```bash
terraform output
terraform output -raw s3_bucket_name
terraform output -raw ec2_public_ip
terraform output -raw emr_cluster_id
```

Final deployed resource examples:

| Resource | Value |
|---|---|
| VPC | `25DJT3-vpc` |
| Public subnet | `25DJT3-public-subnet`, `10.0.1.0/24` |
| Private subnet | `25DJT3-private-subnet`, `10.0.2.0/24` |
| S3 bucket | `25djt3-cisc886-project` |
| EMR cluster | `25DJT3-emr-spark` |
| EC2 server | `25DJT3-ec2-llm` |

---

## 5. S3 Folder Layout

```text
s3://25djt3-cisc886-project/
├── data/
│   ├── raw/
│   │   └── Online Retail.xlsx
│   └── processed/
│       ├── retail_train.jsonl
│       └── retail_eval.jsonl
├── models/
│   ├── retail-assistant.Q4_K_M.gguf
│   ├── Modelfile
│   └── training_artifacts/
├── scripts/
│   └── retail_to_sft.py
└── logs/
    └── emr/
```

Upload the raw dataset:

```bash
aws s3 cp "Online Retail.xlsx" \
  "s3://25djt3-cisc886-project/data/raw/Online Retail.xlsx"
```

If using a CSV copy for Spark:

```bash
aws s3 cp online_retail.csv \
  s3://25djt3-cisc886-project/data/raw/online_retail.csv
```

Upload the PySpark script:

```bash
aws s3 cp scripts/retail_to_sft.py \
  s3://25djt3-cisc886-project/scripts/retail_to_sft.py
```

---

## 6. EMR + PySpark Data Preprocessing

This project uses Amazon EMR to run a PySpark preprocessing pipeline before model fine-tuning. The Spark job reads the raw UCI Online Retail dataset from S3, cleans the transaction records, separates valid purchases from cancellations/returns, generates chatbot-style training examples, and writes model-ready JSONL files for supervised fine-tuning.

### EMR cluster used

| Field | Value |
|---|---|
| Cluster name | `25DJT3-emr-spark` |
| Cluster ID | `j-2RDM6RZJROAW5` |
| Region | `us-east-1` |
| Amazon EMR release | `emr-7.13.0` |
| Installed applications | Hadoop 3.4.2, Hive 3.1.3, JupyterEnterpriseGateway 2.6.0, Livy 0.8.0, Spark 3.5.6 |
| Capacity used | 1 Primary, 0 Core, 0 Task |
| S3 bucket | `s3://25djt3-cisc886-project` |

### Input and output locations

Raw dataset:

```bash
s3://25djt3-cisc886-project/data/raw/Online_Retail.csv
```

PySpark script:

```bash
s3://25djt3-cisc886-project/scripts/retail_to_sft.py
```

Processed output:

```bash
s3://25djt3-cisc886-project/data/processed/
```

Final model-ready files:

```bash
s3://25djt3-cisc886-project/data/processed/retail_train.jsonl
s3://25djt3-cisc886-project/data/processed/retail_eval.jsonl
```

### 1. Convert XLSX to CSV if needed

The original UCI dataset is provided as an Excel file. The Spark script expects CSV input, so the Excel file can be converted locally before upload:

```bash
python - <<'PY'
import pandas as pd

xlsx_path = "data/raw/Online_Retail.xlsx"
csv_path = "data/raw/Online_Retail.csv"

df = pd.read_excel(xlsx_path)
df.to_csv(csv_path, index=False)

print("Rows:", len(df))
print("Saved:", csv_path)
PY
```

### 2. Upload raw data and PySpark script to S3

```bash
aws s3 cp data/raw/Online_Retail.csv \
  s3://25djt3-cisc886-project/data/raw/Online_Retail.csv

aws s3 cp scripts/retail_to_sft.py \
  s3://25djt3-cisc886-project/scripts/retail_to_sft.py
```

Verify upload:

```bash
aws s3 ls s3://25djt3-cisc886-project/data/raw/
aws s3 ls s3://25djt3-cisc886-project/scripts/
```

### 3. Submit the PySpark job to EMR

Set variables:

```bash
BUCKET=25djt3-cisc886-project
CLUSTER_ID=j-2RDM6RZJROAW5
```

Submit the Spark step:

```bash
aws emr add-steps \
  --region us-east-1 \
  --cluster-id "$CLUSTER_ID" \
  --steps '[
    {
      "Type": "Spark",
      "Name": "retail-sft-preprocessing",
      "ActionOnFailure": "CONTINUE",
      "Args": [
        "--deploy-mode", "cluster",
        "s3://25djt3-cisc886-project/scripts/retail_to_sft.py",
        "--input", "s3://25djt3-cisc886-project/data/raw/Online_Retail.csv",
        "--output", "s3://25djt3-cisc886-project/data/processed",
        "--max_orders", "10000",
        "--max_products", "3000",
        "--max_recs", "3000",
        "--max_cancellations", "2000",
        "--max_items_per_basket", "50"
      ]
    }
  ]'
```

The command returns a step ID such as:

```text
s-XXXXXXXXXXXXX
```

Save this step ID for monitoring.

### 4. Monitor the EMR step

Replace `<STEP_ID>` with the returned step ID:

```bash
aws emr describe-step \
  --region us-east-1 \
  --cluster-id "$CLUSTER_ID" \
  --step-id <STEP_ID> \
  --query "Step.Status"
```

A successful run should eventually show:

```text
"State": "COMPLETED"
```

The same status can also be checked in the AWS Console:

```text
Amazon EMR -> EMR on EC2 Clusters -> 25DJT3-emr-spark -> Steps
```

### 5. Verify processed output in S3

```bash
aws s3 ls s3://25djt3-cisc886-project/data/processed/ --recursive
```

Expected important outputs:

```text
data/processed/retail_train.jsonl
data/processed/retail_eval.jsonl
data/processed/clean_purchases_parquet/
data/processed/examples_with_type_parquet/
data/processed/stats/
```

The JSONL files are used for fine-tuning. Each line has this chat format:

```json
{"messages":[{"role":"system","content":"You are a helpful ecommerce shopping assistant..."},{"role":"user","content":"..."},{"role":"assistant","content":"..."}]}
```

### 6. Download processed files for local validation or fine-tuning

```bash
aws s3 cp s3://25djt3-cisc886-project/data/processed/retail_train.jsonl \
  data/processed/retail_train.jsonl

aws s3 cp s3://25djt3-cisc886-project/data/processed/retail_eval.jsonl \
  data/processed/retail_eval.jsonl
```

Validate JSONL locally:

```bash
python - <<'PY'
import json

for path in ["data/processed/retail_train.jsonl", "data/processed/retail_eval.jsonl"]:
    rows = 0
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            assert "messages" in obj
            assert [m["role"] for m in obj["messages"]] == ["system", "user", "assistant"]
            rows += 1
    print(path, rows, "valid rows")
PY
```

### 7. EDA outputs

The preprocessing pipeline also produced EDA figures used in the report:

```text
figures/figure_1_split_example_counts.png
figures/figure_2_token_length_distribution.png
figures/figure_3_top_countries.png
figures/figure_4_top_products.png
```

These figures summarize:

1. The number of generated supervised fine-tuning examples by split and example type.
2. The approximate token length distribution of JSONL examples.
3. The top countries by clean purchase line count.
4. The top products by historical order count.

### 8. Terminate the EMR cluster after preprocessing

The project requires proof that the EMR cluster was terminated after the preprocessing job.

```bash
aws emr terminate-clusters \
  --region us-east-1 \
  --cluster-ids "$CLUSTER_ID"
```

Check status:

```bash
aws emr describe-cluster \
  --region us-east-1 \
  --cluster-id "$CLUSTER_ID" \
  --query "Cluster.Status.State"
```

Expected final status:

```text
"TERMINATED"
```

A screenshot of the EMR console showing `25DJT3-emr-spark` in the `Terminated` state is included in the project evidence.

## 7. Fine-Tuning with Unsloth

Recommended Colab setup:

```python
!pip install -q unsloth
!pip install -q --no-deps trl peft accelerate bitsandbytes datasets
```

Load JSONL:

```python
from datasets import load_dataset

dataset = load_dataset(
    "json",
    data_files={
        "train": "/content/retail_train.jsonl",
        "validation": "/content/retail_eval.jsonl",
    },
)
```

Model and training setup:

```python
from unsloth import FastLanguageModel

model_name = "unsloth/Llama-3.2-1B-Instruct"
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name=model_name,
    max_seq_length=1024,
    dtype=None,
    load_in_4bit=True,
)
```

Main hyperparameters used:

| Hyperparameter | Value |
|---|---|
| Base model | `unsloth/Llama-3.2-1B-Instruct` |
| Method | QLoRA / LoRA adapters |
| Train examples | 6,000 |
| Eval examples | 500 |
| Max steps | 500 |
| Batch size | 2 |
| Gradient accumulation | 4 |
| Learning rate | `2e-4` |
| Optimizer | `adamw_8bit` |
| LoRA rank | 16 |
| LoRA alpha | 16 |
| LoRA dropout | 0 |
| Export | GGUF `Q4_K_M` |

Export to GGUF:

```python
model.save_pretrained_gguf(
    "/content/drive/MyDrive/cisc886-retail-chatbot/retail_assistant_gguf",
    tokenizer,
    quantization_method="q4_k_m",
)
```

Upload final model artifacts:

```bash
aws s3 cp retail-assistant.Q4_K_M.gguf \
  s3://25djt3-cisc886-project/models/retail-assistant.Q4_K_M.gguf

aws s3 cp Modelfile \
  s3://25djt3-cisc886-project/models/Modelfile
```

---

## 8. EC2 Deployment with Ollama

SSH into EC2:

```bash
ssh -i /c/Users/DPQUAI250128/25DJT3-keypair.pem ec2-user@34.205.90.80
```

Install Ollama if not already installed:

```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable --now ollama
```

Make Ollama listen on all interfaces:

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d

sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Copy the GGUF model to EC2. If S3 access is denied by SCP, use `scp`:

```bash
scp -i /c/Users/DPQUAI250128/25DJT3-keypair.pem \
  /path/to/retail-assistant.Q4_K_M.gguf \
  ec2-user@34.205.90.80:/home/ec2-user/retail-assistant.Q4_K_M.gguf
```

Create the Ollama model:

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
Help users with shopping questions, order-style inquiries, returns, cancellations, and product recommendations.
Do not invent live inventory, shipping status, or real-time prices.
"""
EOF

ollama create retail-assistant -f Modelfile
ollama list
```

Test with curl:

```bash
curl http://localhost:11434/api/generate \
  -d '{"model":"retail-assistant","prompt":"Say hello in one short sentence.","stream":false}'
```

---

## 9. OpenWebUI Deployment

Run OpenWebUI on EC2 with Docker:

```bash
docker rm -f open-webui 2>/dev/null || true

docker run -d \
  --name open-webui \
  --restart always \
  -p 3000:8080 \
  -e OLLAMA_BASE_URL=http://10.0.1.105:11434 \
  -e WEBUI_AUTH=False \
  -v open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:main
```

Check status:

```bash
docker ps
docker logs --tail 80 open-webui
```

Open in browser:

```text
http://34.205.90.80:3000
```

Select:

```text
retail-assistant:latest
```

Test prompt:

```text
I like WHITE HANGING HEART T-LIGHT HOLDER. Recommend related products.
```

Security note: for grading, authentication may be disabled. After grading, restrict port `3000` to your own IP or re-enable authentication.

---

## 10. Screenshots in the folder and report for Report

- Architecture diagram
- VPC resource map
- Public subnet details
- EC2 security group inbound rules
- Raw dataset in S3
- Processed output in S3
- Model artifacts in S3
- EMR cluster configuration
- EMR terminated state
- EDA figures: split counts, token length distribution, and product/country distribution
- Unsloth training progress
- Base vs fine-tuned comparison
- Ollama model list and curl response
- OpenWebUI browser interface with model selected
- OpenWebUI sample chat response

---

## 11. Cost Summary

| Service | Approximate cost driver | Mitigation |
|---|---|---|
| S3 | Dataset, model, logs, processed outputs | Keep only final files after grading |
| EMR | Cluster runtime | Terminate immediately after preprocessing |
| EC2 | Ollama/OpenWebUI runtime | Stop or terminate when not testing |
| Data transfer | Model upload/download, browser use | Minimal for project scale |

Estimated project run cost: TODO: insert actual value from AWS Billing/Cost Explorer.

---

## 12. Teardown

Terminate EMR after preprocessing:

```bash
aws emr terminate-clusters --region us-east-1 --cluster-ids <cluster-id>
```

Destroy Terraform resources at the end of the project:

```bash
cd terraform
terraform destroy
```

Check that no unexpected EC2/EMR resources remain running.
