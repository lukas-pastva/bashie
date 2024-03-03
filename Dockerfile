FROM alpine:latest

# Install bash, jq, curl, git, wget, and unzip
RUN apk add --no-cache bash jq curl git wget unzip

# Download and Install Terraform
ARG TERRAFORM_VERSION="1.7.4"
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Copy the entrypoint script to the container
COPY entrypoint.sh /entrypoint.sh

# Set the entrypoint script
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
