# Use a base image that includes bash, jq, curl, and git
FROM alpine:latest

# Install bash, jq, curl, git, and wget
RUN apk add --no-cache bash jq curl git wget unzip

# Download and Install Terraform
ARG TERRAFORM_VERSION="1.7.4"
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_386.zip \
    && unzip terraform_${TERRAFORM_VERSION}_linux_386.zip -d /usr/bin \
    && rm terraform_${TERRAFORM_VERSION}_linux_386.zip

# Define an environment variable for the script to use
ENV JSON_DATA='{"example":"data"}'

# Prepare the entry script
RUN echo 'echo $JSON_DATA | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" > /env_vars.sh' > /entrypoint.sh \
    && echo 'source /env_vars.sh' >> /entrypoint.sh \
    && echo 'env | grep VAR_' >> /entrypoint.sh \
    && echo "${BASH_SCRIPT_CONTENT}" >> /entrypoint.sh \
    && chmod +x /entrypoint.sh

# Use the entry script to set up environment variables and execute the command
CMD ["/bin/bash", "/entrypoint.sh"]
