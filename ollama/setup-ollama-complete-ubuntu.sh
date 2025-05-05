#!/bin/bash

# Combined script to set up Ollama with Qwen2.5-Coder:7b (128k context) and OpenWebUI for Ubuntu 24.04
# This script is idempotent and will stop on any errors

set -e  # Exit immediately if a command exits with a non-zero status

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

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
  print_message "$RED" "Error: This script is intended for Ubuntu only."
  exit 1
fi

# Check for necessary privileges
if [ "$(id -u)" -eq 0 ]; then
  print_message "$RED" "Error: Please do not run this script as root or with sudo."
  print_message "$YELLOW" "The script will use sudo when necessary."
  exit 1
fi

# Update package lists
print_message "$YELLOW" "Updating package lists..."
sudo apt update || { print_message "$RED" "Failed to update package lists."; exit 1; }

# Ensure necessary dependencies are installed
if ! command_exists curl || ! command_exists pip; then
  print_message "$YELLOW" "Installing curl and pip..."
  sudo apt install -y curl python3-pip || { 
    print_message "$RED" "Failed to install dependencies."
    exit 1
  }
fi

# PART 1: OLLAMA SETUP
# Check if Ollama is installed
if ! command_exists ollama; then
  print_message "$YELLOW" "Ollama is not installed. Installing..."
  
  # Install dependencies if needed
  sudo apt install -y build-essential ca-certificates || {
    print_message "$RED" "Failed to install dependencies."
    exit 1
  }
  
  # Use the Ollama install script
  curl -fsSL https://ollama.com/install.sh | sh
  
  # Check if installation was successful
  if ! command_exists ollama; then
    print_message "$RED" "Failed to install Ollama. Please try installing manually."
    exit 1
  fi
  
  print_message "$GREEN" "Ollama installed successfully!"
else
  print_message "$GREEN" "Ollama is already installed."
fi

# Check if Ollama service is running
if ! pgrep -x "ollama" > /dev/null; then
  print_message "$YELLOW" "Ollama service is not running. Starting Ollama..."
  ollama serve > /dev/null 2>&1 &
  
  # Wait for Ollama service to start
  for i in {1..10}; do
    if curl -s http://localhost:11434/api/version > /dev/null; then
      break
    fi
    if [ "$i" -eq 10 ]; then
      print_message "$RED" "Failed to start Ollama service. Please try running 'ollama serve' manually."
      exit 1
    fi
    sleep 1
  done
  
  print_message "$GREEN" "Ollama service started."
else
  print_message "$GREEN" "Ollama service is already running."
fi

# Check if qwen2.5-coder:7b model is already pulled
if ! ollama list | grep -q "qwen2.5-coder:7b"; then
  print_message "$YELLOW" "Pulling qwen2.5-coder:7b model. This may take a while..."
  ollama pull qwen2.5-coder:7b
  
  # Check if pull was successful
  if ! ollama list | grep -q "qwen2.5-coder:7b"; then
    print_message "$RED" "Failed to pull qwen2.5-coder:7b model."
    exit 1
  fi
  
  print_message "$GREEN" "qwen2.5-coder:7b model pulled successfully!"
else
  print_message "$GREEN" "qwen2.5-coder:7b model is already available."
fi

# Create a temporary directory for the Modelfile
TEMP_DIR=$(mktemp -d)
MODELFILE_PATH="$TEMP_DIR/Modelfile"

# Create Modelfile
cat > "$MODELFILE_PATH" << 'EOF'
FROM qwen2.5-coder:7b
PARAMETER num_ctx 131072
EOF

print_message "$YELLOW" "Creating qwen2.5-coder-128k model with extended context window..."

# Check if the extended model already exists
if ollama list | grep -q "qwen2.5-coder-128k"; then
  print_message "$GREEN" "qwen2.5-coder-128k model already exists."
else
  # Create the extended model
  ollama create qwen2.5-coder-128k -f "$MODELFILE_PATH"
  
  # Check if creation was successful
  if ! ollama list | grep -q "qwen2.5-coder-128k"; then
    print_message "$RED" "Failed to create qwen2.5-coder-128k model."
    rm -rf "$TEMP_DIR"
    exit 1
  fi
  
  print_message "$GREEN" "qwen2.5-coder-128k model created successfully!"
fi

# Clean up temp directory
rm -rf "$TEMP_DIR"

# Set up memory optimizations in shell profile
SHELL_PROFILE="$HOME/.bashrc"
OPTIMIZATION_VARS="export OLLAMA_FLASH_ATTENTION=1\nexport OLLAMA_KV_CACHE_TYPE=q8_0\nexport OLLAMA_MAX_INPUT_TOKENS=131072\nexport OLLAMA_CONTEXT_LENGTH=131072"

# Check if optimizations are already in shell profile
if ! grep -q "OLLAMA_FLASH_ATTENTION" "$SHELL_PROFILE" || ! grep -q "OLLAMA_KV_CACHE_TYPE" "$SHELL_PROFILE" || ! grep -q "OLLAMA_MAX_INPUT_TOKENS" "$SHELL_PROFILE"; then
  print_message "$YELLOW" "Adding memory optimization variables to $SHELL_PROFILE..."
  echo -e "\n# Ollama memory optimizations for large context windows" >> "$SHELL_PROFILE"
  echo -e "$OPTIMIZATION_VARS" >> "$SHELL_PROFILE"
  print_message "$GREEN" "Memory optimization variables added to $SHELL_PROFILE."
  print_message "$YELLOW" "Please run 'source $SHELL_PROFILE' to apply these changes to your current shell."
else
  print_message "$GREEN" "Memory optimization variables are already in $SHELL_PROFILE."
fi

# PART 2: OPENWEBUI SETUP
# Create openwebui directory if it doesn't exist
OPENWEBUI_DIR="$HOME/openwebui"
if [[ ! -d "$OPENWEBUI_DIR" ]]; then
  print_message "$YELLOW" "Creating openwebui directory at $OPENWEBUI_DIR"
  mkdir -p "$OPENWEBUI_DIR"
else
  print_message "$GREEN" "OpenWebUI directory already exists at $OPENWEBUI_DIR"
fi

# Change to the openwebui directory
cd "$OPENWEBUI_DIR"
print_message "$GREEN" "Changed to directory: $(pwd)"

# Install uv if not already installed
if ! command_exists uv; then
  print_message "$YELLOW" "Installing uv package manager..."
  pip install uv || {
    print_message "$RED" "Failed to install uv. Trying with sudo..."
    sudo pip install uv || {
      print_message "$RED" "Failed to install uv. Please install it manually."
      exit 1
    }
  }
else
  print_message "$GREEN" "uv package manager is already installed."
fi

# Check if a virtual environment already exists
if [[ ! -d ".venv" ]]; then
  print_message "$YELLOW" "Setting up a new virtual environment..."
  uv init --python=3.11 . || {
    print_message "$RED" "Failed to initialize virtual environment."
    exit 1
  }
  uv venv || {
    print_message "$RED" "Failed to create virtual environment."
    exit 1
  }
else
  print_message "$GREEN" "Virtual environment already exists."
fi

# Activate the virtual environment
print_message "$YELLOW" "Activating virtual environment..."
source .venv/bin/activate || {
  print_message "$RED" "Failed to activate virtual environment."
  exit 1
}

# Check if Open WebUI is installed
if ! pip list | grep -q "open-webui"; then
  print_message "$YELLOW" "Installing Open WebUI..."
  uv pip install open-webui || {
    print_message "$RED" "Failed to install Open WebUI."
    exit 1
  }
else
  print_message "$GREEN" "Open WebUI is already installed. Checking for updates..."
  uv pip install --upgrade open-webui || {
    print_message "$YELLOW" "Could not upgrade Open WebUI, continuing with installed version."
  }
fi

# Return to the original directory
cd - > /dev/null

print_message "$GREEN" "✅ Setup complete!"
print_message "$GREEN" "Ollama is set up with Qwen2.5-Coder with 128k context window."
print_message "$GREEN" "OpenWebUI is installed and ready to use."
print_message "$YELLOW" "To run the model directly: ollama run qwen2.5-coder-128k"
print_message "$YELLOW" "To run Open WebUI, go to $OPENWEBUI_DIR, activate the environment and run:"
print_message "$YELLOW" "cd $OPENWEBUI_DIR && source .venv/bin/activate && open-webui serve"
print_message "$YELLOW" "Then access Open WebUI at http://localhost:8080"
print_message "$YELLOW" "For Ubuntu, be cautious with very large contexts as they may require significant memory."