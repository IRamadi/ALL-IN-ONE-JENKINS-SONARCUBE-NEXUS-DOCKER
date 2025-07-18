#!/bin/bash

# DevOps Stack Setup Script with Custom Domains
# Run with: sudo bash setup-devops-stack.sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ----------------------------------
# 1. System Configuration
# ----------------------------------
echo -e "${YELLOW}[1/7] Updating system and installing dependencies...${NC}"
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
    net-tools \
    openssl

# ----------------------------------
# 2. Docker Installation
# ----------------------------------
echo -e "${YELLOW}[2/7] Installing Docker and Docker Compose...${NC}"
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
echo -e "${YELLOW}[3/7] Configuring Docker...${NC}"
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
echo -e "${YELLOW}[4/7] Setting up project directories...${NC}"
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
chown -R 1000:1000 jenkins sonarqube registry/data
chown -R 200:200 nexus-data  # Fixed Nexus permissions
chmod -R 775 sonarqube

# ----------------------------------
# 5. Nginx Reverse Proxy Setup
# ----------------------------------
echo -e "${YELLOW}[5/7] Configuring Nginx reverse proxy with custom domains...${NC}"

# Create self-signed SSL certificates
mkdir -p nginx/certs
cd nginx/certs

DOMAINS=("jenkins" "sonarqube" "nexus")
for DOMAIN in "${DOMAINS[@]}"; do
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout $DOMAIN.local.key \
        -out $DOMAIN.local.crt \
        -subj "/CN=$DOMAIN.local/O=$DOMAIN Local" 2>/dev/null
done
cd $PROJECT_DIR

# Create Nginx configuration with DNS resolver
cat > nginx/conf.d/devops.conf <<'EOF'
# Docker DNS resolver
resolver 127.0.0.11 valid=10s;

server {
    listen 80;
    server_name jenkins.local sonarqube.local nexus.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name jenkins.local;
    
    ssl_certificate /etc/nginx/certs/jenkins.local.crt;
    ssl_certificate_key /etc/nginx/certs/jenkins.local.key;
    
    location / {
        proxy_pass http://jenkins:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 443 ssl;
    server_name sonarqube.local;
    
    ssl_certificate /etc/nginx/certs/sonarqube.local.crt;
    ssl_certificate_key /etc/nginx/certs/sonarqube.local.key;
    
    location / {
        proxy_pass http://sonarqube:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 443 ssl;
    server_name nexus.local;
    
    ssl_certificate /etc/nginx/certs/nexus.local.crt;
    ssl_certificate_key /etc/nginx/certs/nexus.local.key;
    
    location / {
        proxy_pass http://nexus:8081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Nexus requires these headers
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
    }
}
EOF

# Add domains to /etc/hosts
if ! grep -q "devops-stack-local" /etc/hosts; then
    echo -e "\n# devops-stack-local" >> /etc/hosts
    echo "127.0.0.1   jenkins.local sonarqube.local nexus.local" >> /etc/hosts
fi

# ----------------------------------
# 6. Docker Configuration Files
# ----------------------------------
echo -e "${YELLOW}[6/7] Creating Docker configuration files...${NC}"

# Create docker-compose.yml without version and with SonarQube port
cat > docker-compose.yml <<'EOF'
services:
  jenkins:
    image: jenkins/jenkins:lts-jdk17
    container_name: jenkins
    restart: unless-stopped
    user: "1000:1000"
    ports:
      - "8080:8080"
      - "50000:50000"
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
      - "9000:9000"  # Expose SonarQube port
    networks:
      - devops-net

  nexus:
    image: sonatype/nexus3:latest
    container_name: nexus
    restart: unless-stopped
    environment:
      - INSTALL4J_ADD_VM_PARAMS=-Xms1g -Xmx2g -XX:MaxDirectMemorySize=2g
    volumes:
      - ./nexus-data:/nexus-data
      - ./nexus-tmp:/tmp
    networks:
      - devops-net
    user: "root"
    ports:
      - "8081:8081"
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
    ports:
      - "27017:27017"
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

USER root
RUN mkdir -p /opt/sonarqube/data \
    && mkdir -p /opt/sonarqube/extensions \
    && mkdir -p /opt/sonarqube/logs \
    && mkdir -p /opt/sonarqube/temp \
    && chown -R 1000:1000 /opt/sonarqube \
    && chmod -R 775 /opt/sonarqube

USER 1000
EOF

# ----------------------------------
# 7. Launch DevOps Stack
# ----------------------------------
echo -e "${YELLOW}[7/7] Starting DevOps Stack...${NC}"
cd $PROJECT_DIR
docker compose build --no-cache sonarqube
docker compose up -d

# Wait for Jenkins to initialize
echo -e "${YELLOW}Waiting for Jenkins to initialize (this may take 3-5 minutes)...${NC}"
while [ ! -f $PROJECT_DIR/jenkins/secrets/initialAdminPassword ]; do
    sleep 10
    docker logs jenkins --tail 20 | grep "Jenkins is fully up and running" && break
done

# ----------------------------------
# Completion Message
# ----------------------------------
echo -e "${GREEN}\nDevOps Stack Setup Complete!${NC}"
echo -e "Access services via:"
echo -e "- Jenkins:     https://jenkins.local (use Chrome or accept SSL warning)"
echo -e "- SonarQube:   https://sonarqube.local or http://$(hostname -I | awk '{print $1}'):9000"
echo -e "- Nexus:       https://nexus.local"
echo -e "- MongoDB:     mongodb://admin:admin123@localhost:27017"
echo -e "- Registry:    http://localhost:5000\n"

echo -e "${YELLOW}Important Notes:${NC}"
echo "1. Add SSL exceptions in your browser:"
echo "   - Visit https://jenkins.local first and accept the security warning"
echo "   - Repeat for sonarqube.local and nexus.local"
echo "2. Jenkins initial admin password:"
echo "   sudo cat ${PROJECT_DIR}/jenkins/secrets/initialAdminPassword"
echo "3. Nexus initial admin password:"
echo "   sudo cat ${PROJECT_DIR}/nexus-data/admin.password"
echo "4. Services may take 2-3 minutes to start completely"
echo "5. To access from other devices, add these lines to /etc/hosts:"
echo "   $(hostname -I | awk '{print $1}')   jenkins.local sonarqube.local nexus.local"
echo "6. If reverse proxy doesn't work, access services directly:"
echo "   - Jenkins:     http://$(hostname -I | awk '{print $1}'):8080"
echo "   - SonarQube:   http://$(hostname -I | awk '{print $1}'):9000"
echo "   - Nexus:       http://$(hostname -I | awk '{print $1}'):8081"
