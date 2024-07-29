# Dockerfile

# Base image
FROM ubuntu:20.04

# Update system and install dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2 python3-pip pwgen docker-compose

# Install Docker
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable' && \
    apt-get update && \
    apt-get install -y docker-ce

# Create directories
RUN mkdir -p /marketing_solution/custom_bot

# Copy custom bot files
COPY custom_bot/bot.py /marketing_solution/custom_bot/
COPY custom_bot/requirements.txt /marketing_solution/custom_bot/

# Install Python dependencies for custom bot
RUN pip3 install -r /marketing_solution/custom_bot/requirements.txt

# Copy docker-compose.yml
COPY docker-compose.yml /marketing_solution/

# Workdir
WORKDIR /marketing_solution

# CMD to run Docker Compose
CMD ['docker-compose', 'up']
