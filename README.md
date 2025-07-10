# DevOps Stack Setup Script

This script automates the deployment of a comprehensive DevOps stack using Docker and Docker Compose. It streamlines the setup process for essential tools like Jenkins, SonarQube, Nexus, MongoDB, Nginx, and a Docker Registry, providing a ready-to-use environment for continuous integration, code quality analysis, artifact management, and more.




## Features

- **Color-coded Output**: Enhances readability of script execution.
- **Health Checks**: Critical services include health checks for reliable operation.
- **Proper Permission Handling**: Ensures correct file and directory permissions for all components.
- **Automatic IP Detection**: Automatically detects the server's IP address for easy access to services.
- **Post-install Instructions**: Provides clear instructions for accessing deployed services and important credentials.
- **Comprehensive Error Handling**: Implicitly handled via `bash -e` for robust execution.




## What the Script Does

This script performs the following actions:

1.  **Updates System Packages and Installs Dependencies**: Ensures your system is up-to-date and has all necessary tools for Docker and other services.
2.  **Installs Docker Engine and Docker Compose**: Sets up the core Docker environment.
3.  **Configures Docker for Optimal Performance**: Applies configurations for better Docker daemon performance and logging.
4.  **Creates Necessary Directory Structure with Correct Permissions**: Establishes the required directories for persistent data and sets appropriate permissions.
5.  **Generates `docker-compose.yml` and `Dockerfile.sonarqube`**: Dynamically creates the Docker Compose configuration and a custom Dockerfile for SonarQube.
6.  **Builds and Launches All Containers**: Compiles the SonarQube image and starts all defined services.
7.  **Provides Access URLs and Important Post-Install Notes**: Outputs direct links to access the deployed services and crucial information like initial passwords.




## Prerequisites

- A fresh Ubuntu 22.04 (or compatible Debian-based) server.
- `sudo` privileges for the user executing the script.
- Internet connectivity to download packages and Docker images.




## Usage

To run the script, simply execute the following command in your terminal:

```bash
sudo bash setup-devops-stack.sh
```

The script will guide you through the installation process and output all necessary access URLs and credentials upon completion.




## Services and Access

After the script completes, the following services will be accessible:

| Service   | Default URL (replace `YOUR_SERVER_IP` with your server's IP) |
|-----------|-----------------------------------------------------------------|
| Jenkins   | `http://YOUR_SERVER_IP:8080`                                    |
| SonarQube | `http://YOUR_SERVER_IP:9000`                                    |
| Nexus     | `http://YOUR_SERVER_IP:8081`                                    |
| MongoDB   | `mongodb://admin:admin123@YOUR_SERVER_IP:27017`                 |
| Registry  | `http://YOUR_SERVER_IP:5000`                                    |
| Nginx     | `http://YOUR_SERVER_IP`                                         |

**Important Notes:**

1.  **Jenkins Initial Admin Password**: You can retrieve the initial admin password for Jenkins by running:
    ```bash
    sudo cat /opt/devops-stack/jenkins/secrets/initialAdminPassword
    ```
2.  **Nexus Initial Admin Password**: The initial admin password for Nexus can be found by running:
    ```bash
    sudo cat /opt/devops-stack/nexus-data/admin.password
    ```
3.  **Service Initialization**: Services may take a few minutes to fully initialize after the script completes. Please be patient.




## Troubleshooting

- If you encounter issues with Docker installation, ensure that all previous Docker versions are completely removed.
- If services are not accessible, check Docker container logs using `docker logs <container_name>`.
- Verify that necessary ports are open in your server's firewall.
- For permission issues, ensure the user running the script has `sudo` privileges and that the `docker` group is correctly configured.




## License

This project is open-source and available under the [MIT License](LICENSE).
