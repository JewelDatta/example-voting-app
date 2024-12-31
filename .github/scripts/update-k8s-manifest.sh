#!/bin/bash

# Strict error handling
set -euo pipefail
IFS=$'\n\t'

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# Function to handle errors
error_handler() {
    local line_no=$1
    local error_code=$2
    log "Error (line $line_no): Command exited with status $error_code"
    exit "$error_code"
}

# Set error handler
trap 'error_handler ${LINENO} $?' ERR

# Function to validate inputs
validate_inputs() {
    local missing_vars=()
    
    [[ -z "${SERVICE_NAME:-}" ]] && missing_vars+=("SERVICE_NAME")
    [[ -z "${IMAGE_NAME:-}" ]] && missing_vars+=("IMAGE_NAME")
    [[ -z "${IMAGE_TAG:-}" ]] && missing_vars+=("IMAGE_TAG")
    [[ -z "${GITHUB_TOKEN:-}" ]] && missing_vars+=("GITHUB_TOKEN")
    [[ -z "${GITHUB_REPOSITORY:-}" ]] && missing_vars+=("GITHUB_REPOSITORY")
    [[ -z "${GITHUB_ACTOR:-}" ]] && missing_vars+=("GITHUB_ACTOR")
    
    if (( ${#missing_vars[@]} > 0 )); then
        log "Error: Missing required environment variables:"
        printf '%s\n' "${missing_vars[@]}"
        exit 1
    fi
}

# Function to setup git authentication using the GitHub CLI
setup_git_auth() {
    local git_url="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
    
    # Configure git
    git config --global user.email "${GITHUB_ACTOR}@users.noreply.github.com"
    git config --global user.name "${GITHUB_ACTOR}"
    
    # Update origin URL with token
    git remote set-url origin "${git_url}"
    
    # Verify authentication
    if ! git ls-remote &>/dev/null; then
        log "Error: Failed to authenticate with GitHub"
        exit 1
    fi
}

# Function to update manifest
update_manifest() {
    local manifest_file="k8s-specifications/${SERVICE_NAME}-deployment.yaml"
    local new_image="${IMAGE_NAME}:${IMAGE_TAG}"
    
    # Check if manifest exists
    if [[ ! -f "${manifest_file}" ]]; then
        log "Error: Manifest file ${manifest_file} not found"
        exit 1
    fi
    
    # Create a new branch
    local branch_name="update-${SERVICE_NAME}-$(date +%s)"
    git checkout -b "${branch_name}"
    
    # Update the manifest
    if ! sed -i "s|image:.*|image: ${new_image}|g" "${manifest_file}"; then
        log "Error: Failed to update manifest file"
        exit 1
    fi
    
    # Check if there are changes
    if git diff --quiet; then
        log "No changes detected in manifest"
        return 0
    fi
    
    # Commit and push changes
    git add "${manifest_file}"
    git commit -m "Update ${SERVICE_NAME} deployment to image tag ${IMAGE_TAG}"
    
    # Push changes with retry logic
    local max_retries=3
    local retry_count=0
    
    while (( retry_count < max_retries )); do
        if git push origin "${branch_name}"; then
            break
        fi
        retry_count=$((retry_count + 1))
        log "Push failed, retrying (${retry_count}/${max_retries})..."
        sleep 5
    done
    
    if (( retry_count == max_retries )); then
        log "Error: Failed to push changes after ${max_retries} attempts"
        exit 1
    fi
}

# Main execution
main() {
    log "Starting manifest update process"
    
    validate_inputs
    setup_git_auth
    update_manifest
    
    log "Successfully updated manifest"
}

# Execute main function
main "$@" 