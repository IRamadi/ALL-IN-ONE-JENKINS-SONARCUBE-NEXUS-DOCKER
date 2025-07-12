#!/bin/bash

# DevOps Stack Setup Script
# Run with: sudo bash setup-devops-stack.sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ----------------------------------
# 1. System Configuration
# ----------------------------------
echo -e "${YELLOW}[1/6] Updating system and installing dependencies...${NC}"
apt update -y
apt upgrade -y
apt install -y \
    curl \
    wget \
    git \
    gnupg \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    make \
    jq \
    tree \
    unzip \
    htop \
    net-tools

# ----------------------------------
# 2. Docker Installation
# ----------------------------------
echo -e "${YELLOW}[2/6] Installing Docker and Docker Compose...${NC}"
# Remove old versions
apt remove -y docker docker-engine docker.io containerd runc

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# ----------------------------------
# 3. Post-Installation Setup
# ----------------------------------
echo -e "${YELLOW}[3/6] Configuring Docker...${NC}"
# Add user to docker group
usermod -aG docker $SUDO_USER

# Docker daemon configuration
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Enable and restart Docker
systemctl enable docker.service
systemctl enable containerd.service
systemctl restart docker

# ----------------------------------
# 4. Project Setup
# ----------------------------------
echo -e "${YELLOW}[4/6] Setting up project directories...${NC}"
PROJECT_DIR="/opt/devops-stack"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Create directory structure
mkdir -p \
    jenkins \
    postgres/data \
    sonarqube/{data,extensions,logs,temp} \
    nexus-data \
    nexus-tmp \
    mongodb/data \
    nginx/{conf.d,certs,html} \
    registry/data

# Set permissions
chown -R 1000:1000 jenkins sonarqube nexus-data registry/data
chmod -R 775 sonarqube

# ----------------------------------
# 5. Docker Configuration Files
# ----------------------------------
echo -e "${YELLOW}[5/6] Creating Docker configuration files...${NC}"

# Create docker-compose.yml
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  jenkins:
    image: jenkins/jenkins:lts-jdk17
    container_name: jenkins
    restart: unless-stopped
    user: "1000:1000"
    ports:
      - "8080:8080"
    volumes:
      - ./jenkins:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - devops-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 3

  postgres:
    image: postgres:15
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: sonarqube
      POSTGRES_PASSWORD: sonarqube
      POSTGRES_DB: sonarqube
    volumes:
      - ./postgres/data:/var/lib/postgresql/data
    networks:
      - devops-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sonarqube"]
      interval: 30s
      timeout: 10s
      retries: 3

  sonarqube:
    build: 
      context: .
      dockerfile: Dockerfile.sonarqube
    image: codingtechahmed-sonarqube
    container_name: sonarqube
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - SONAR_JDBC_URL=jdbc:postgresql://postgres:5432/sonarqube
      - SONAR_JDBC_USERNAME=sonarqube
      - SONAR_JDBC_PASSWORD=sonarqube
      - SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
      - SONAR_FORCEAUTHENTICATION=false
      - SONAR_WEB_JAVAOPTS=-Xmx512m -Xms128m
    volumes:
      - ./sonarqube/data:/opt/sonarqube/data
      - ./sonarqube/extensions:/opt/sonarqube/extensions
      - ./sonarqube/logs:/opt/sonarqube/logs
      - ./sonarqube/temp:/opt/sonarqube/temp
    user: "1000"
    ports:
      - "9000:9000"
    networks:
      - devops-net

  nexus:
    image: sonatype/nexus3:latest
    container_name: nexus
    restart: unless-stopped
    ports:
      - "8081:8081"
    environment:
      - INSTALL4J_ADD_VM_PARAMS=-Xms1g -Xmx2g -XX:MaxDirectMemorySize=2g
    volumes:
      - ./nexus-data:/nexus-data:Z
      - ./nexus-tmp:/tmp
    networks:
      - devops-net
    user: "root"
    command: >
      bash -c "
      mkdir -p /nexus-data/etc /nexus-data/log /nexus-data/tmp &&
      chown -R root:root /nexus-data /tmp &&
      chmod -R 755 /nexus-data /tmp &&
      exec /opt/sonatype/nexus/bin/nexus run"

  mongodb:
    image: mongo:6
    container_name: mongodb
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: admin123
    volumes:
      - ./mongodb/data:/data/db
    networks:
      - devops-net
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 30s
      timeout: 10s
      retries: 3

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/certs:/etc/nginx/certs
      - ./nginx/html:/usr/share/nginx/html
    depends_on:
      - jenkins
      - sonarqube
      - nexus
    networks:
      - devops-net

  registry:
    image: registry:2
    container_name: registry
    restart: unless-stopped
    ports:
      - "5000:5000"
    volumes:
      - ./registry/data:/var/lib/registry
    networks:
      - devops-net

networks:
  devops-net:
    driver: bridge
EOF

# Create Dockerfile.sonarqube
cat > Dockerfile.sonarqube <<'EOF'
FROM sonarqube:lts-community

# Switch to root to set up permissions
USER root

# Create directories inside the container (not the host)
RUN mkdir -p /opt/sonarqube/data \
    && mkdir -p /opt/sonarqube/extensions \
    && mkdir -p /opt/sonarqube/logs \
    && mkdir -p /opt/sonarqube/temp \
    && chown -R 1000:1000 /opt/sonarqube \
    && chmod -R 775 /opt/sonarqube

# Switch back to sonarqube user
USER 1000
EOF

# ----------------------------------
# 6. Launch DevOps Stack
# ----------------------------------
echo -e "${YELLOW}[6/6] Starting DevOps Stack...${NC}"
docker-compose build --no-cache sonarqube
docker-compose up -d

# ----------------------------------
# Completion Message
# ----------------------------------
echo -e "${GREEN}\nDevOps Stack Setup Complete!${NC}"
echo -e "Access the following services:"
echo -e "- Jenkins:     http://$(hostname -I | awk '{print $1}'):8080"
echo -e "- SonarQube:   http://$(hostname -I | awk '{print $1}'):9000"
echo -e "- Nexus:       http://$(hostname -I | awk '{print $1}'):8081"
echo -e "- MongoDB:     mongodb://admin:admin123@$(hostname -I | awk '{print $1}'):27017"
echo -e "- Registry:    http://$(hostname -I | awk '{print $1}'):5000"
echo -e "- Nginx:       http://$(hostname -I | awk '{print $1}')\n"

echo -e "${YELLOW}Important Notes:${NC}"
echo -e "1. Jenkins initial admin password:"
echo -e "   sudo cat ${PROJECT_DIR}/jenkins/secrets/initialAdminPassword"
echo -e "2. Nexus initial admin password:"
echo -e "   sudo cat ${PROJECT_DIR}/nexus-data/admin.password"
echo -e "3. It may take a few minutes for all services to start completely"
