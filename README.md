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
