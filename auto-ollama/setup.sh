#!/bin/bash
# Setup script for Ollama with AMD GPU support and OpenWebUI

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print messages
print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Detect OS distribution
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME=$ID
  OS_VERSION=$VERSION_ID
  print_message "$GREEN" "Detected OS: $OS_NAME $OS_VERSION"
else
  print_message "$YELLOW" "Could not detect OS distribution, assuming Debian/Ubuntu compatible"
  OS_NAME="unknown"
fi

# Function to install Docker on Debian/Ubuntu
install_docker() {
  print_message "$YELLOW" "Installing Docker..."
  
  # Update package lists
  sudo apt-get update
  
  # Install prerequisites
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  
  # Add Docker's official GPG key
  curl -fsSL https://download.docker.com/linux/$OS_NAME/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  
  # Set up the stable repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_NAME $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # Install Docker Engine
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  
  # Add current user to docker group to avoid using sudo
  sudo usermod -aG docker $USER
  
  print_message "$GREEN" "Docker installed successfully! You may need to log out and back in for group changes to take effect."
}

# Function to install Docker Compose
install_docker_compose() {
  print_message "$YELLOW" "Installing Docker Compose..."
  
  # Install Docker Compose
  sudo apt-get update
  sudo apt-get install -y docker-compose-plugin
  
  # Create symbolic link for compatibility with older scripts
  if [ ! -f /usr/local/bin/docker-compose ]; then
    sudo ln -s /usr/bin/docker-compose /usr/local/bin/docker-compose
  fi
  
  print_message "$GREEN" "Docker Compose installed successfully!"
}

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
  print_message "$YELLOW" "Docker is not installed. Installing now..."
  install_docker
else
  print_message "$GREEN" "Docker is already installed."
fi

# Check if Docker Compose is installed
if ! command -v docker-compose >/dev/null 2>&1; then
  print_message "$YELLOW" "Docker Compose is not installed. Installing now..."
  install_docker_compose
else
  print_message "$GREEN" "Docker Compose is already installed."
fi

# Check for AMD GPU devices
if [ ! -d "/dev/dri" ] || [ ! -e "/dev/kfd" ]; then
  print_message "$YELLOW" "Warning: AMD GPU devices not found or not accessible."
  print_message "$YELLOW" "The container will use CPU only, which will be significantly slower."
  print_message "$YELLOW" "If you have an AMD GPU, please check your drivers installation."
fi

# Create required directories
print_message "$YELLOW" "Creating required directories..."
mkdir -p ./ollama_data ./webui_data ./modelfile

# Create Modelfile if it doesn't exist
if [ ! -f "./modelfile/Modelfile" ]; then
  print_message "$YELLOW" "Creating Modelfile..."
  cat > ./modelfile/Modelfile << 'EOF'
FROM qwen2.5-coder:7b
PARAMETER num_ctx 131072
EOF
  print_message "$GREEN" "Modelfile created successfully!"
else
  print_message "$GREEN" "Modelfile already exists."
fi

# Check if .env file exists, create it if not
if [ ! -f "./.env" ]; then
  print_message "$YELLOW" "Creating .env file with default values..."
  cat > ./.env << 'EOF'
# Ollama configuration
OLLAMA_IMAGE=ollama/ollama:rocm
OLLAMA_PORT=11434

# AMD GPU optimization settings for RDNA2 (AMD 6800 XT)
HSA_OVERRIDE_GFX_VERSION=10.3.0
HSA_ENABLE_SDMA=1
GPU_MAX_HEAP_SIZE=100
GPU_SINGLE_ALLOC_PERCENT=100
OLLAMA_ROCM=1
OLLAMA_FLASH_ATTENTION=1
OLLAMA_KV_CACHE_TYPE=q8_0
OLLAMA_MAX_INPUT_TOKENS=131072
OLLAMA_CONTEXT_LENGTH=131072
OLLAMA_KEEP_ALIVE=-1

# OpenWebUI configuration
WEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
WEBUI_PORT=8080
WEBUI_PORT_INTERNAL=8080
WEBUI_HOST=0.0.0.0
WEBUI_SECRET_KEY=change_this_to_a_secure_random_string
WEBUI_AUTH=true
WEBUI_CORS=false
WEBUI_DB=sqlite
WEBUI_ALLOW_PASSWORDLESS_USER_CREATION=false
EOF
  print_message "$GREEN" ".env file created successfully!"
  print_message "$YELLOW" "⚠️ Please edit the .env file and change WEBUI_SECRET_KEY to a secure random string!"
else
  print_message "$GREEN" ".env file already exists."
fi

# Make sure we have access to GPU devices
print_message "$YELLOW" "Checking for AMD GPU devices..."
if [ ! -d "/dev/dri" ] || [ ! -e "/dev/kfd" ]; then
  print_message "$RED" "Warning: AMD GPU devices not found or not accessible. Please make sure your AMD GPU is properly installed."
  print_message "$YELLOW" "The container might still work, but without GPU acceleration."
else
  print_message "$GREEN" "AMD GPU devices found."
fi

# Grant appropriate permissions to the devices
print_message "$YELLOW" "Setting device permissions..."
if [ -e "/dev/kfd" ]; then
  sudo chmod 666 /dev/kfd
fi
if [ -d "/dev/dri" ]; then
  sudo chmod -R 666 /dev/dri/*
fi

# Start the containers
print_message "$YELLOW" "Starting Ollama and OpenWebUI containers..."
docker-compose up -d

# Check if containers are running
print_message "$YELLOW" "Checking container status..."
sleep 5
if docker-compose ps | grep -q "Up"; then
  print_message "$GREEN" "✅ Containers are running successfully!"
  
  # Extract the IP address for better user guidance
  IP_ADDRESS=$(hostname -I | awk '{print $1}')
  WEBUI_PORT=$(grep WEBUI_PORT .env | cut -d '=' -f2)
  OLLAMA_PORT=$(grep OLLAMA_PORT .env | cut -d '=' -f2)
  
  print_message "$GREEN" "You can access OpenWebUI at http://${IP_ADDRESS}:${WEBUI_PORT:-8080}"
  print_message "$GREEN" "Ollama API is available at http://${IP_ADDRESS}:${OLLAMA_PORT:-11434}"
  print_message "$YELLOW" "Note: The model installation may take some time in the background."
  print_message "$YELLOW" "Check the logs with: docker-compose logs -f ollama-model-init"
else
  print_message "$RED" "Some containers might not be running. Please check with 'docker-compose ps'"
fi

print_message "$GREEN" "Setup complete! 🚀"
