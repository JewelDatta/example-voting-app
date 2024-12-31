#!/bin/bash

set -x

# Exit immediately if a command exits with a non-zero status
set -e

# Check if all required arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <service-name> <image-name> <image-tag>"
    exit 1
fi

# Variables from arguments
SERVICE_NAME=$1
IMAGE_NAME=$2
IMAGE_TAG=$3

# GitHub specific variables (These environment variables are automatically available in GitHub Actions workflows)
GITHUB_TOKEN=${GITHUB_TOKEN}
REPO_OWNER=${GITHUB_REPOSITORY_OWNER}
REPO_NAME=$(echo ${GITHUB_REPOSITORY} | cut -d'/' -f2)
BRANCH_NAME=${GITHUB_REF_NAME}

# Configure Git globally
git config --global user.email "github-actions@github.com"
git config --global user.name "GitHub Actions"

# Clone the repository to a temporary directory
TEMP_DIR=$(mktemp -d)
git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$TEMP_DIR"

# Navigate to the temporary directory
cd "$TEMP_DIR"

# Ensure we're on the correct branch
git checkout $BRANCH_NAME

# Update the Kubernetes manifest
echo "Updating ${SERVICE_NAME} deployment with image: ${IMAGE_NAME}:${IMAGE_TAG}"
sed -i "s|image:.*|image: ${IMAGE_NAME}:${IMAGE_TAG}|g" k8s-specifications/${SERVICE_NAME}-deployment.yaml

# Check if there are any changes
if git diff --quiet; then
    echo "No changes detected in the manifest files"
    exit 0
fi

# Add and commit changes
git add k8s-specifications/${SERVICE_NAME}-deployment.yaml
git commit -m "Update ${SERVICE_NAME} deployment to image tag ${IMAGE_TAG}"

# Push changes
echo "Pushing changes to repository"
git push origin $BRANCH_NAME

# Cleanup
cd ..
rm -rf "$TEMP_DIR"

echo "Successfully updated Kubernetes manifests"