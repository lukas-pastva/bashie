# Use a base image that includes bash, jq, curl, git, and wget
FROM alpine:latest

# Install bash, jq, curl, git, wget, and unzip
RUN apk add --no-cache bash jq curl git wget unzip

# Download and Install Terraform
ARG TERRAFORM_VERSION="1.7.4"
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Define an entrypoint script that will parse the JSON_DATA environment variable
RUN echo '#!/bin/bash' > /entrypoint.sh \
    && echo 'echo "Parsing JSON_DATA to environment variables..."' >> /entrypoint.sh \
    && echo 'for row in $(echo "${JSON_DATA}" | jq -r "to_entries|map(\"\(.key)=VAR_\(.value|tostring)\")|.[]"); do' >> /entrypoint.sh \
    && echo '  export $row' >> /entrypoint.sh \
    && echo 'done' >> /entrypoint.sh \
    && echo 'echo "Running the passed command..."' >> /entrypoint.sh \
    && echo 'exec "$@"' >> /entrypoint.sh \
    && chmod +x /entrypoint.sh

# Set the entrypoint script
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

# Default command if none is provided to docker run
CMD ["echo", "No command provided."]
