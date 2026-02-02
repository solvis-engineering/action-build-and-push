# Docker Build and Push Action (Kaniko)

This is a **daemonless** GitHub Action that builds and pushes Docker containers to **AWS ECR** or **GitHub Container Registry (GHCR)** using [Kaniko](https://github.com/GoogleContainerTools/kaniko).

It runs entirely inside a container and does not require the Docker daemon or external action dependencies.

## Features

- **No Docker Daemon Required**: Secure and efficient building using Kaniko.
- **Self-Contained**: No dependencies on `docker/login-action` or `configure-aws-credentials`. Authentication is handled internal to the action.
- **Multi-Registry**: Support for ECR and GHCR.
- **Smart Tagging**: Defaults to the short commit hash.

## Usage

### 1. Push to AWS ECR

You must provide AWS Credentials. Kaniko uses them to push to ECR.

```yaml
steps:
  - uses: actions/checkout@v4
  
  - name: Build and Push to ECR
    uses: ./path-to-action # or owner/repo@tag
    with:
      registry_type: 'ecr'
      aws_region: 'us-east-1'
      aws_access_key_id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws_secret_access_key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      image_name: 'my-app-repo' # OR full URI: 12345.dkr.ecr.us-east-1.amazonaws.com/my-app-repo
      # Optional: Provide account ID to help construct URI if image_name is just repo name
      aws_account_id: ${{ secrets.AWS_ACCOUNT_ID }}
```

### 2. Push to GitHub Container Registry (GHCR)

```yaml
steps:
  - uses: actions/checkout@v4
  
  - name: Build and Push to GHCR
    uses: ./path-to-action
    with:
      registry_type: 'github'
      image_name: 'my-app'
      registry_username: ${{ github.actor }}
      registry_password: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Advanced Usage (Build Args & Custom Tags)

```yaml
steps:
  - uses: actions/checkout@v4
  
  - name: Build and Push
    uses: ./path-to-action
    with:
      registry_type: 'ecr'
      aws_region: 'us-east-1'
      aws_access_key_id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws_secret_access_key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      image_name: 'my-backend'
      tag: 'v1.0.0'
      build_args: |
        ENV=production
        VERSION=1.0.0
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `registry_type` | 'ecr' or 'github' | Yes | |
| `image_name` | Name of the image. For ECR, if just name, provide `aws_account_id`. | Yes | |
| `dockerfile` | Path to Dockerfile | No | `./Dockerfile` |
| `context` | Build context | No | `.` |
| `build_args` | List of build-time variables | No | |
| `tag` | Specific tag. If empty, uses short commit hash. | No | |
| `aws_region` | AWS Region (ECR) | No | |
| `aws_account_id` | AWS Account ID (ECR helper) | No | |
| `aws_access_key_id` | AWS Access Key ID (ECR) | No | |
| `aws_secret_access_key` | AWS Secret Access Key (ECR) | No | |
| `registry_username` | Username (GHCR) | No | |
| `registry_password` | Token/Password (GHCR) | No | |
