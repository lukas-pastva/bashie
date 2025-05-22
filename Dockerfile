FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        software-properties-common && \
    apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        bash jq curl gettext git wget unzip apt-transport-https \
        ca-certificates cron apache2-utils libzip-dev msmtp msmtp-mta \
        pcregrep rclone rsync vim zip s3cmd s3fs openssh-client swaks \
        openssl libnet-ssleay-perl libio-socket-ssl-perl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Terraform ────────────────────────────────────────────────────────────────
ARG TERRAFORM_VERSION="1.7.4"
RUN wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/bin \
    && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# ── yq ───────────────────────────────────────────────────────────────────────
RUN wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

# ── kubectl ─────────────────────────────────────────────────────────────────
RUN curl -sL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# ── Argo CD CLI ─────────────────────────────────────────────────────────────
ARG ARGOCD_VERSION="3.0.3"
RUN curl -sSL -o /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64" && \
    chmod +x /usr/local/bin/argocd

# ── Argo Workflows CLI (NEW) ────────────────────────────────────────────────
ARG ARGO_VERSION="3.6.7"
RUN curl -sSL -o /usr/local/bin/argo.gz \
    "https://github.com/argoproj/argo-workflows/releases/download/v${ARGO_VERSION}/argo-linux-amd64.gz" && \
    gunzip /usr/local/bin/argo.gz && \
    chmod +x /usr/local/bin/argo   # `argo version` should now work

WORKDIR /tmp/app
COPY src/ /tmp/app
