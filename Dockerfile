FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        software-properties-common && \
    apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
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
        rclone \
        rsync \
        vim \
        zip \
        s3cmd \
        s3fs \
        openssh-client \
        swaks && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV DEBIAN_FRONTEND=

# Download and Install Terraform
ARG TERRAFORM_VERSION="1.7.4"
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Install yq
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl

WORKDIR /tmp/app
COPY src/ /tmp/app