FROM ubuntu:latest

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends -o=Dpkg::Use-Pty=0 \
        bash \
        jq \
        curl \
        gettext \
        git \
        wget \
        unzip \
        apt-transport-https \
        ca-certificates \
        cron \
        apache2-utils \
        libzip-dev \
        msmtp \
        msmtp-mta \
        pcregrep \
        vim \
        zip \
        s3cmd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and Install Terraform
ARG TERRAFORM_VERSION="1.7.4"
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Copy the entrypoint script to the container
COPY entrypoint.sh /entrypoint.sh

# Set the entrypoint script
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]