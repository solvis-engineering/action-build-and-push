FROM gcr.io/kaniko-project/executor:debug AS kaniko

FROM alpine:3.19

# Install dependencies required for our logic (git for tagging, bash for script, jq/curl for potential helpers)
RUN apk add --no-cache bash git jq curl ca-certificates

# Copy Kaniko executor and config from the official image
COPY --from=kaniko /kaniko /kaniko

# Add Kaniko to PATH
ENV PATH $PATH:/kaniko
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG /kaniko/.docker/

# Create working directory
WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
