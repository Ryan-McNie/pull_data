FROM ubuntu:22.04

# Install dependencies (adjust as needed)
# Install AWS CLI v2
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    python3 \
    lftp \
    gzip \
    tar

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws \
    && rm -rf /var/lib/apt/lists/*


# Set working directory
WORKDIR /app

# Copy everything into the container
COPY . /app/

# Make scripts executable
RUN chmod +x *.sh entrypoint.sh scripts/check_data/* scripts/manipulate_data/* scripts/pull_data/*

# Set the entrypoint
ENTRYPOINT ["./entrypoint.sh"]
