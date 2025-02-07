FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        software-properties-common && \
    add-apt-repository ppa:ondrej/php && \
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
        php8.2-cli \
        php8.2-zip \
        php8.2-curl \
        php8.2-soap \
        php8.2-xml \
        php8.2-gd \
        php8.2-imap \
        php8.2-bcmath \
        openssh-client && \
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

# COMPOSER
ENV COMPOSER_HOME /composer
ENV PATH /composer/vendor/bin:$PATH
ENV COMPOSER_ALLOW_SUPERUSER 1
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /tmp/app
COPY / /
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
