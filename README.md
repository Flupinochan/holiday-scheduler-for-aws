# Holiday scheduler for AWS

## Deploy

```bash
# prepare
terraform init
terraform fmt
terraform validate

# ※初回デプロイ時はECRだけ先に作成
terraform plan -target="aws_ecr_repository.lambda_repo"
terraform apply -target="aws_ecr_repository.lambda_repo"

# 1. Push Image to ECR using Docker (詳しくはECRコンソール画面を見たほうが良い)
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin 247574246160.dkr.ecr.ap-northeast-1.amazonaws.com
TAG=$(date +%Y%m%d%H%M%S)
echo ${TAG}
docker build -t holiday-scheduler .
docker tag holiday-scheduler:latest 247574246160.dkr.ecr.ap-northeast-1.amazonaws.com/holiday-scheduler:${TAG}
docker push 247574246160.dkr.ecr.ap-northeast-1.amazonaws.com/holiday-scheduler:${TAG}

# 2. Terraform Deploy
# 例: terraform apply -var="image_tag=20260331233942"
terraform plan -var="image_tag=タグ名"
terraform apply -var="image_tag=タグ名"

# ※初回はTerraformデプロイ後に設定ファイルをダウンロードして再デプロイ
# outputを参考に、以下のgcloud CLIで設定ファイルをダウンロードし、srcフォルダに格納
terraform output

# 以下をsrc/clientLibraryConfig-aws-provider.jsonに格納
gcloud iam workload-identity-pools create-cred-config `
  projects/プロジェクト番号/locations/global/workloadIdentityPools/プールID/providers/プロバイダーID `
  --service-account=サービスアカウントメール `
  --aws `
  --output-file=clientLibraryConfig-aws-provider.json

# 再デプロイ
TAG=$(date +%Y%m%d%H%M%S)
echo ${TAG}
docker build -t holiday-scheduler .
docker tag holiday-scheduler:latest 247574246160.dkr.ecr.ap-northeast-1.amazonaws.com/holiday-scheduler:${TAG}
docker push 247574246160.dkr.ecr.ap-northeast-1.amazonaws.com/holiday-scheduler:${TAG}
terraform plan -var="image_tag=タグ名"
terraform apply -var="image_tag=タグ名"
```

## Setup Terraform MCP

[Terraform-MCP](https://github.com/hashicorp/terraform-mcp-server) を利用して構築

```bash
# clone repository
git clone https://github.com/hashicorp/terraform-mcp-server.git
cd terraform-mcp-server

# build
make docker-build

# test terraform mcp
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
| docker run -i --rm terraform-mcp-server:dev
```

`.vscode/mcp.json` を作成

```json
{
  "servers": {
    "terraform": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        "-e", "TFE_TOKEN=${input:tfe_token}",
        "-e", "TFE_ADDRESS=${input:tfe_address}",
        "hashicorp/terraform-mcp-server:0.4.0"
      ]
    }
  },
  "inputs": [
    {
      "type": "promptString",
      "id": "tfe_token",
      "description": "Terraform API Token",
      "password": true
    },
    {
      "type": "promptString",
      "id": "tfe_address",
      "description": "Terraform Address",
      "password": false
    }
  ]
}
```

[Available tools](https://developer.hashicorp.com/terraform/mcp-server/reference#available-tools)
