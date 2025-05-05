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
  
  # Install prerequisites with explicit verification
  print_message "$YELLOW" "Installing required Python packages..."
  
  # Check if python3-setuptools is already installed
  if ! dpkg -l | grep -q python3-setuptools; then
    print_message "$YELLOW" "Installing python3-setuptools..."
    sudo apt-get install -y python3-setuptools
    if ! dpkg -l | grep -q python3-setuptools; then
      print_message "$RED" "Failed to install python3-setuptools!"
    else
      print_message "$GREEN" "Successfully installed python3-setuptools"
    fi
  else
    print_message "$GREEN" "python3-setuptools is already installed"
  fi
  
  # Install other required packages
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

  # For Python 3.12 issue with docker-compose
  print_message "$YELLOW" "Setting up Python compatibility for docker-compose..."
  sudo apt-get install -y python3-setuptools python3-pkg-resources

  # Create compatibility layer for distutils in Python 3.12+
  sudo mkdir -p /usr/lib/python3/dist-packages/distutils
  sudo touch /usr/lib/python3/dist-packages/distutils/__init__.py
  echo 'from setuptools._distutils.spawn import find_executable' | sudo tee /usr/lib/python3/dist-packages/distutils/spawn.py
  print_message "$GREEN" "Python compatibility setup complete"
  
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

# Get render group ID for docker-compose.yml
RENDER_GROUP_ID=$(getent group render | cut -d: -f3)
if [ -z "$RENDER_GROUP_ID" ]; then
  print_message "$YELLOW" "Render group not found. Using default group ID of 992."
  RENDER_GROUP_ID=992
else
  print_message "$GREEN" "Found render group with ID: $RENDER_GROUP_ID"
fi

# Create required directories
print_message "$YELLOW" "Creating required directories..."
mkdir -p ./ollama_data ./webui_data ./modelfile

# Copy the main Modelfile to the modelfile directory
print_message "$YELLOW" "Setting up Modelfile for custom model..."
mkdir -p ./modelfile
cp ./Modelfile ./modelfile/Modelfile
print_message "$GREEN" "Modelfile copied successfully!"

# Create a script to pull and create the custom model
cat > ./ollama_data/setup_custom_model.sh << 'EOF'
#!/bin/bash
echo "Pulling base model qwen2.5-coder:7b..."
ollama pull qwen2.5-coder:7b
echo "Creating custom model qwen-128k with extended context window..."
ollama create qwen-128k -f /root/.ollama/Modelfile
echo "Setting qwen-128k as default model..."
echo "qwen-128k" > /root/.ollama/default_model.txt
echo "Custom model setup complete!"
EOF
chmod +x ./ollama_data/setup_custom_model.sh
print_message "$GREEN" "Custom model setup script created!"

# Create docker-compose.yml file
print_message "$YELLOW" "Creating docker-compose.yml file..."
cat > ./docker-compose.yml << EOF
version: '3'
services:
  ollama:
    image: ollama/ollama:rocm
    container_name: ollama
    privileged: true
    restart: always
    # Use custom entrypoint to set up the model
    entrypoint: ["/bin/bash", "/root/.ollama/custom_entrypoint.sh"]
    ports:
      - "\${OLLAMA_PORT:-11434}:11434"
    volumes:
      - ./ollama_data:/root/.ollama
      - ./ollama_data/fake_sys/module/amdgpu:/sys/module/amdgpu
    group_add:
      - "${RENDER_GROUP_ID:-992}"
      - "video"
EOF

# Only add render group if it exists
if getent group render >/dev/null; then
  sed -i 's/- "video"/- "video"\n      - "render"/' ./docker-compose.yml
  print_message "$GREEN" "Render group exists, added to docker-compose.yml"
else
  print_message "$YELLOW" "Render group doesn't exist on this system, skipping"
fi

# Continue with the rest of docker-compose.yml
cat >> ./docker-compose.yml << EOF
    devices:
      - "/dev/kfd"
      - "/dev/dri"
    environment:
      - HSA_OVERRIDE_GFX_VERSION=10.3.0
      - HSA_ENABLE_SDMA=1
      - OLLAMA_FLASH_ATTENTION=true
      - OLLAMA_KV_CACHE_TYPE=q8_0
      - OLLAMA_MAX_INPUT_TOKENS=131072
      - OLLAMA_CONTEXT_LENGTH=131072
      - OLLAMA_KEEP_ALIVE=-1
      - ROCM_PATH=/opt/rocm
      - ROCR_VISIBLE_DEVICES=all
      - GPU_MAX_HEAP_SIZE=100
      - GPU_SINGLE_ALLOC_PERCENT=100
      - AMD_GPU=1
      
  open-webui:
    image: \${WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}
    container_name: open-webui
    restart: always
    volumes:
      - ./webui_data:/app/backend/data
    ports:
      - "\${WEBUI_PORT:-8080}:\${WEBUI_PORT_INTERNAL:-8080}"
    environment:
      - OLLAMA_API_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=\${WEBUI_SECRET_KEY:-change_this_to_a_secure_random_string}
      - WEBUI_AUTH=\${WEBUI_AUTH:-true}
      - WEBUI_CORS=\${WEBUI_CORS:-false}
      - WEBUI_HOST=\${WEBUI_HOST:-0.0.0.0}
      - WEBUI_PORT=\${WEBUI_PORT_INTERNAL:-8080}
      - WEBUI_DB=\${WEBUI_DB:-sqlite}
      - WEBUI_ALLOW_PASSWORDLESS_USER_CREATION=\${WEBUI_ALLOW_PASSWORDLESS_USER_CREATION:-false}
    depends_on:
      - ollama
EOF

# Check if .env file exists, create it if not
if [ ! -f "./.env" ]; then
  print_message "$YELLOW" "Creating .env file with default values..."
  cat > ./.env << 'EOF'
# Ollama configuration
OLLAMA_PORT=11434

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

# Add current user to video and render groups
print_message "$YELLOW" "Adding current user to video and render groups..."
sudo usermod -aG video,render $USER
print_message "$GREEN" "User added to groups! You may need to log out and back in for these changes to take effect."

# Copy main Modelfile to ollama_data for easy access by the container
print_message "$YELLOW" "Copying Modelfile to ollama_data directory..."
cp ./Modelfile ./ollama_data/Modelfile
print_message "$GREEN" "Modelfile copied successfully!"

# Grant appropriate permissions to the devices
print_message "$YELLOW" "Setting device permissions..."
if [ -e "/dev/kfd" ]; then
  sudo chmod a+rw /dev/kfd
fi
if [ -d "/dev/dri" ]; then
  sudo chmod -R a+rw /dev/dri/
fi

# Create a fake amdgpu version file for container mounting
print_message "$YELLOW" "Creating fake amdgpu version directory for Ollama GPU detection..."
mkdir -p ./ollama_data/fake_sys/module/amdgpu
echo "5.18.0" > ./ollama_data/fake_sys/module/amdgpu/version
print_message "$GREEN" "Created fake amdgpu version file successfully!"

# Start the containers
print_message "$YELLOW" "Starting Ollama and OpenWebUI containers..."

# Check which docker compose command to use
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  print_message "$GREEN" "Using Docker Compose V2 (docker compose)..."
  docker compose up -d
elif command -v docker-compose >/dev/null 2>&1; then
  print_message "$GREEN" "Using Docker Compose V1 (docker-compose)..."
  docker-compose up -d
else
  print_message "$RED" "Neither docker compose nor docker-compose is available. Please install Docker Compose."
  exit 1
fi

# Check if containers are running
print_message "$YELLOW" "Checking container status..."
sleep 5

# The custom model setup will be handled by the custom entrypoint script
print_message "$YELLOW" "Custom model qwen-128k will be automatically set up when the container starts..."
print_message "$GREEN" "Note: Model download and creation may take several minutes in the background."

# Use the same docker compose command as determined above
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  CONTAINER_STATUS=$(docker compose ps 2>/dev/null)
  if echo "$CONTAINER_STATUS" | grep -q "Up"; then
    COMPOSE_WORKING="true"
  fi
elif command -v docker-compose >/dev/null 2>&1; then
  CONTAINER_STATUS=$(docker-compose ps 2>/dev/null)
  if echo "$CONTAINER_STATUS" | grep -q "Up"; then
    COMPOSE_WORKING="true"
  fi
fi

if [ "$COMPOSE_WORKING" = "true" ]; then
  print_message "$GREEN" "✅ Containers are running successfully!"
  
  # Extract the IP address for better user guidance
  IP_ADDRESS=$(hostname -I | awk '{print $1}')
  WEBUI_PORT=$(grep WEBUI_PORT .env | cut -d '=' -f2)
  OLLAMA_PORT=$(grep OLLAMA_PORT .env | cut -d '=' -f2)
  
  print_message "$GREEN" "You can access OpenWebUI at http://${IP_ADDRESS}:${WEBUI_PORT:-8080}"
  print_message "$GREEN" "Ollama API is available at http://${IP_ADDRESS}:${OLLAMA_PORT:-11434}"
  print_message "$YELLOW" "Note: The model installation may take some time in the background."
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    print_message "$YELLOW" "Check the logs with: docker compose logs -f ollama"
  else
    print_message "$YELLOW" "Check the logs with: docker-compose logs -f ollama"
  fi
else
  print_message "$RED" "Some containers might not be running."
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    print_message "$RED" "Please check with 'docker compose ps'"
  else
    print_message "$RED" "Please check with 'docker-compose ps'"
  fi
fi

print_message "$GREEN" "Setup complete! 🚀"
print_message "$YELLOW" "You may need to log out and log back in for group permission changes to take effect."
