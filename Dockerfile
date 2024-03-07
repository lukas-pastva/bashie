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
        s3cmd \
        automake \
        g++ \
        make \
        libcurl4-gnutls-dev \
        libfuse-dev \
        libssl-dev \
        libxml2-dev \
        fuse && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install s3fs from source
RUN git clone https://github.com/s3fs-fuse/s3fs-fuse.git /usr/src/s3fs-fuse && \
    cd /usr/src/s3fs-fuse && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install && \
    cd / && \
    rm -rf /usr/src/s3fs-fuse

# Download and Install Terraform
ARG TERRAFORM_VERSION="1.7.4"
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]