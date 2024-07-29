#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# --- Install and update dependencies ---

# Function to handle errors
handle_error() {
    echo "Error on line $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

# Prompt for project name and API keys
read -p "Enter your project name: " PROJECT_NAME
prompt_for_api_keys() {
    if [ -z "$OPENAI_API_KEY" ]; then
        read -p "Enter your OpenAI API key: " OPENAI_API_KEY
    fi
    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        read -p "Enter your Telegram bot token: " TELEGRAM_BOT_TOKEN
    fi
}

# Function to prompt for domain or IP
prompt_for_domain_or_ip() {
    if [ -z "$DOMAIN_OR_IP" ]; then
        read -p "Enter your domain or IP address: " DOMAIN_OR_IP
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Update the system and install dependencies
echo "Updating the system and installing dependencies..."
sudo apt-get update && sudo apt-get upgrade -y

# Install required software
if ! command_exists curl || ! command_exists docker || ! command_exists docker-compose || ! command_exists nginx; then
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2 python3-pip nginx libnginx-mod-http-lua
fi

# Install Docker if not already installed
if ! command_exists docker; then
    echo "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Install Docker Compose if not already installed
if ! command_exists docker-compose; then
    echo "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Prompt for API keys if not already set
prompt_for_api_keys

# Prompt for domain or IP
prompt_for_domain_or_ip

# Generate PostgreSQL Password
POSTGRES_PASSWORD=$(openssl rand -base64 12)

# Define environment variables
export POSTGRES_DB="mautic_db"
export POSTGRES_USER="admin"

# --- Create directories and files ---
mkdir -p ~/marketing_solution/{data,rasa_bot/data,scrapy_project/scrapy_project/spiders}

# Save credentials to a file with restricted permissions
cat <<EOF > ~/marketing_solution/credent.txt
POSTGRES_USER=admin
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOF
chmod 600 ~/marketing_solution/credent.txt

# Pull Docker images
sudo docker pull matomo:latest
sudo docker pull n8nio/n8n:latest
sudo docker pull mautic/mautic:latest
sudo docker pull suitecrm/suitecrm:latest
sudo docker pull postgres:latest
sudo docker pull portainer/portainer-ce:latest
sudo docker pull prom/prometheus:latest
sudo docker pull grafana/grafana:latest
sudo docker pull sebp/elk:latest
sudo docker pull nextcloud
sudo docker pull rasa/rasa:latest-full

# Store environment variables in a .env file
cat <<EOF > ~/marketing_solution/marketing_solution.env
OPENAI_API_KEY=$OPENAI_API_KEY
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOF

# --- Create files for custom bot, Rasa bot, and Scrapy project ---
cat <<EOF > ~/marketing_solution/Dockerfile
# Dockerfile

# Base image
FROM ubuntu:20.04

# Update system and install dependencies
RUN apt-get update && apt-get upgrade -y && \\
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2 python3-pip

# Install Docker
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \\
    add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable' && \\
    apt-get update && \\
    apt-get install -y docker-ce

# Create directories
RUN mkdir -p /${PROJECT_NAME}/rasa_bot /${PROJECT_NAME}/scrapy_project

# Copy Rasa bot files
COPY rasa_bot /${PROJECT_NAME}/rasa_bot

# Copy Scrapy project files
COPY scrapy_project /${PROJECT_NAME}/scrapy_project

# Install Python dependencies for Rasa bot and Scrapy
RUN pip3 install -r /${PROJECT_NAME}/rasa_bot/requirements.txt
RUN pip3 install -r /${PROJECT_NAME}/scrapy_project/requirements.txt

# Copy docker-compose.yml
COPY docker-compose.yml /${PROJECT_NAME}/

# Workdir
WORKDIR /${PROJECT_NAME}

# Set environment variables
ENV OPENAI_API_KEY=$OPENAI_API_KEY

# CMD to run Docker Compose
CMD ['docker-compose', 'up']
EOF

cat <<EOF > ~/marketing_solution/docker-compose.yml
version: '3.7'

services:
  postgres:
    image: postgres:latest
    container_name: postgres
    restart: always
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    networks:
      - ${PROJECT_NAME}_network
    volumes:
      - postgres_data:/var/lib/postgresql/data

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - '9000:9000'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - ${PROJECT_NAME}_network

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: always
    ports:
      - '3000:3000'
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    networks:
      - ${PROJECT_NAME}_network
    volumes:
      - grafana_data:/var/lib/grafana

  mautic:
    image: mautic/mautic:latest
    container_name: mautic
    restart: always
    ports:
      - '8090:80'
    environment:
      - MAUTIC_DB_HOST=postgres
      - MAUTIC_DB_NAME=\${POSTGRES_DB}
      - MAUTIC_DB_USER=\${POSTGRES_USER}
      - MAUTIC_DB_PASSWORD=\${POSTGRES_PASSWORD}
    networks:
      - ${PROJECT_NAME}_network

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: always
    ports:
      - '5678:5678'
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=password
    networks:
      - ${PROJECT_NAME}_network

  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    restart: always
    ports:
      - '8080:80'
    volumes:
      - nextcloud_data:/var/www/html
    networks:
      - ${PROJECT_NAME}_network

  rasa:
    image: rasa/rasa:latest-full
    container_name: rasa
    restart: always
EOF

# Additional configurations and services can be added here as needed

# Navigate to project directory
cd ~/marketing_solution

# Build and run Docker containers
echo "Building and starting Docker containers..."
sudo docker-compose up --build --force-recreate --renew-anon-volumes -d

# Print success message
echo "Installation and setup complete!"
echo "Your services are now running:"
echo "- Portainer: http://$DOMAIN_OR_IP/portainer/"
echo "- Grafana: http://$DOMAIN_OR_IP/grafana/"
echo "- Mautic: http://$DOMAIN_OR_IP/mautic/"
echo "- Nextcloud: http://$DOMAIN_OR_IP/nextcloud/"
echo "- n8n: http://$DOMAIN_OR_IP/n8n/"
echo "- Rasa: http://$DOMAIN_OR_IP/rasa/"
