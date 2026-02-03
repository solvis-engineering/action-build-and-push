#!/bin/bash
set -e

# --- Input Handling ---
# GitHub Actions inputs are passed as env vars named INPUT_<NAME_UPPERCASE>
REGISTRY_TYPE="${INPUT_REGISTRY_TYPE}"
IMAGE_NAME="${INPUT_IMAGE_NAME}"
DOCKERFILE="${INPUT_DOCKERFILE:-./Dockerfile}"
CONTEXT="${INPUT_CONTEXT:-.}"
TAG="${INPUT_TAG}"
BUILD_ARGS="${INPUT_BUILD_ARGS}"
AWS_REGION="${INPUT_AWS_REGION}"
AWS_ACCESS_KEY_ID="${INPUT_AWS_ACCESS_KEY_ID}"
AWS_SECRET_ACCESS_KEY="${INPUT_AWS_SECRET_ACCESS_KEY}"
REGISTRY_USERNAME="${INPUT_REGISTRY_USERNAME}"
REGISTRY_PASSWORD="${INPUT_REGISTRY_PASSWORD}"

echo "Starting Docker Build and Push Action (Kaniko)..."

# --- Validation ---
if [ -z "$REGISTRY_TYPE" ]; then
  echo "Error: registry_type is required (ecr or github)"
  exit 1
fi

if [ -z "$IMAGE_NAME" ]; then
  echo "Error: image_name is required"
  exit 1
fi

# --- Tag Logic ---
if [ -z "$TAG" ]; then
  echo "No tag provided. Attempting to use short commit hash..."
  # Mark directory as safe for git if needed (often needed in containerized actions running on mounted volumes)
  git config --global --add safe.directory "*"

  if [ -d ".git" ] || git rev-parse --git-dir > /dev/null 2>&1; then
    TAG=$(git rev-parse --short HEAD)
    echo "Using tag: $TAG"
  else
    echo "Error: No tag provided and not a git repository. Cannot determine default tag."
    exit 1
  fi
else
  echo "Using provided tag: $TAG"
fi

# --- Authentication ---
mkdir -p /kaniko/.docker

if [ "$REGISTRY_TYPE" == "ecr" ]; then
  echo "Configuring AWS ECR credentials..."

  if [ -z "$AWS_REGION" ]; then
    echo "Error: aws_region is required for ECR"
    exit 1
  fi

  # Configure AWS Credentials for Kaniko (ECR helper)
  # Kaniko looks for standard AWS env vars or ~/.aws/credentials

  if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Using provided AWS Access Keys."
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="$AWS_REGION"
    export AWS_REGION="$AWS_REGION"
  else
    echo "No explicit AWS keys provided. Assuming IAM Role (OIDC) or inherited credentials..."
    # If standard AWS env vars are present in the runner environment, Kaniko picks them up.
    # If OIDC is used, AWS_WEB_IDENTITY_TOKEN_FILE etc should be set by the workflow before calling this,
    # OR passed in via env.
  fi

  # Determine Account ID for full URI construction
  # We might need it if the user only gave repo name.
  # Actually, usually users provide full repo URI or just name?
  # Implementation plan said: "Login to AWS ECR". Kaniko does this automatically if configured.
  # But we need the Destination URI.
  # If user provided just "my-app", we need {account}.dkr.ecr.{region}.amazonaws.com/my-app

  # Attempt to get account ID if not provided in image name
  if [[ "$IMAGE_NAME" != *".dkr.ecr."* ]]; then
     echo "Constructing ECR URI..."
     # Try to get account ID. With keys/role, we can try `aws sts get-caller-identity`?
     # But we don't have aws cli installed to keep image small.
     # We can try to use inputs or require full URI?
     # Let's assume user might not provide it.
     # WAIT: We can use `aws_account_id` input? Not in our list.
     # Let's Rely on `aws_access_key_id` to imply we might not know account id easily without API call.
     # Simpler approach: Require user to pass full URI in `image_name` OR add `aws_account_id` input?
     # Or, since we have `curl`, we could try to query metadata if on EC2, but this is GitHub Actions.

     # Let's add a check: If image name doesn't look like a URL, warn or error?
     # Actually, let's keep it simple for v1: ECR Image Name SHOULD probably be the full URI or we add an input.
     # The PLAN said "image_name: Name of the image".
     # Let's assume we need to handle "repo-name" -> "1234.dkr.ecr.us-east-1.amazonaws.com/repo-name"
     # But we don't know "1234".
     # Let's update `action.yml` to ask for `aws_account_id` IF `image_name` is not full URI?
     # OR, just ask user to provide full URI in `image_name` if they want.
     # Re-reading prompt: "pipeline should enable the user set the destination".
     # Let's add `aws_account_id` as an optional input to make it robust.
     # Adding logic:
     if [ -n "${INPUT_AWS_ACCOUNT_ID}" ]; then
        DESTINATION="${INPUT_AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}:${TAG}"
     elif [[ "$IMAGE_NAME" == *".dkr.ecr."* ]]; then
        DESTINATION="${IMAGE_NAME}:${TAG}"
     else
        echo "Error: For ECR, either provide full URI in image_name or provide aws_account_id input."
        exit 1
     fi
  else
     DESTINATION="${IMAGE_NAME}:${TAG}"
  fi

elif [ "$REGISTRY_TYPE" == "github" ]; then
  echo "Configuring GHCR credentials..."
  if [ -z "$REGISTRY_USERNAME" ] || [ -z "$REGISTRY_PASSWORD" ]; then
    echo "Error: registry_username and registry_password are required for GHCR"
    exit 1
  fi

  # Generate auth config for Kaniko
  AUTH=$(echo -n "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" | base64)
  cat > /kaniko/.docker/config.json <<EOF
{
  "auths": {
    "ghcr.io": {
      "auth": "${AUTH}"
    }
  }
}
EOF
  DESTINATION="ghcr.io/${REGISTRY_USERNAME}/${IMAGE_NAME}:${TAG}"
else
  echo "Error: Invalid registry_type: $REGISTRY_TYPE"
  exit 1
fi

echo "Destination: $DESTINATION"

# --- Build Arguments ---
BUILD_ARGS_FLAGS=""
if [ -n "$BUILD_ARGS" ]; then
  # Split multiline string into array
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      BUILD_ARGS_FLAGS+=" --build-arg $line"
    fi
  done <<< "$BUILD_ARGS"
fi

# --- Execution ---
echo "Running Kaniko..."
# Note: Kaniko executor path is /kaniko/executor
# We use --force to overwrite if needed (not strictly needed for new tags)
# --cache=true is good default? Let's leave optional for now.

/kaniko/executor \
  --context "$CONTEXT" \
  --dockerfile "$DOCKERFILE" \
  --destination "$DESTINATION" \
  $BUILD_ARGS_FLAGS

echo "Build and push completed successfully!"
REPOSITORY_URI="${DESTINATION%:*}"
echo "repository_uri=${REPOSITORY_URI}" >> $GITHUB_OUTPUT
echo "image_uri=$DESTINATION" >> $GITHUB_OUTPUT
