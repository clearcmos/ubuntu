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

# PART 2: AMD GPU / ROCm SETUP FOR UBUNTU 24.04 (NOBLE)
print_message "$YELLOW" "Setting up AMD GPU support for Ubuntu 24.04 (Noble Numbat)..."

# Check for AMD GPU
if lspci | grep -i amd | grep -i vga > /dev/null; then
  print_message "$GREEN" "AMD GPU detected. Installing latest supported AMD GPU drivers..."
  
  # Setup proper repository keys
  if [ ! -f "/etc/apt/keyrings/rocm.gpg" ]; then
    print_message "$YELLOW" "Setting up ROCm repository keys..."
    sudo mkdir -p /etc/apt/keyrings
    wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/rocm.gpg
  fi
  
  # Use the latest supported AMDGPU installer
  print_message "$YELLOW" "Downloading and installing AMDGPU installer for Ubuntu 24.04..."
  AMDGPU_VERSION="6.4.60400-1"
  INSTALLER_URL="https://repo.radeon.com/amdgpu-install/6.4/ubuntu/noble/amdgpu-install_${AMDGPU_VERSION}_all.deb"
  
  wget $INSTALLER_URL -O /tmp/amdgpu-install.deb || {
    print_message "$YELLOW" "Unable to download Noble-specific AMDGPU installer. Using most recent available version..."
    # If Noble package is not available, try to download from the latest path
    INSTALLER_URL="https://repo.radeon.com/amdgpu-install/latest/ubuntu/noble/amdgpu-install_latest_all.deb"
    wget $INSTALLER_URL -O /tmp/amdgpu-install.deb || {
      print_message "$RED" "Failed to download AMDGPU installer. Please check Internet connection."
      exit 1
    }
  }
  
  sudo apt install -y /tmp/amdgpu-install.deb || {
    print_message "$RED" "Failed to install AMDGPU installer package."
    exit 1
  }
  
  sudo apt update
  
  # Install ROCm components but not with DKMS to avoid kernel module issues
  print_message "$YELLOW" "Installing ROCm components (without DKMS)..."
  sudo amdgpu-install --usecase=rocm --no-dkms -y || {
    print_message "$RED" "Failed to install ROCm components."
    print_message "$YELLOW" "Trying alternative installation method..."
    sudo amdgpu-install --usecase=rocm,hip,opencl --no-dkms -y || {
      print_message "$RED" "Failed to install AMD GPU drivers. Continuing with basic ROCm optimization variables."
    }
  }
  
  # Set up AMD GPU optimizations in shell profile
  SHELL_PROFILE="$HOME/.bashrc"
  OPTIMIZATION_VARS="export OLLAMA_FLASH_ATTENTION=1\nexport OLLAMA_KV_CACHE_TYPE=q8_0\nexport OLLAMA_MAX_INPUT_TOKENS=131072\nexport OLLAMA_CONTEXT_LENGTH=131072\nexport OLLAMA_ROCM=1"
else
  # Set up standard memory optimizations
  SHELL_PROFILE="$HOME/.bashrc"
  OPTIMIZATION_VARS="export OLLAMA_FLASH_ATTENTION=1\nexport OLLAMA_KV_CACHE_TYPE=q8_0\nexport OLLAMA_MAX_INPUT_TOKENS=131072\nexport OLLAMA_CONTEXT_LENGTH=131072"
fi

# Check if optimizations are already in shell profile
if ! grep -q "OLLAMA_FLASH_ATTENTION" "$SHELL_PROFILE" || ! grep -q "OLLAMA_KV_CACHE_TYPE" "$SHELL_PROFILE" || ! grep -q "OLLAMA_MAX_INPUT_TOKENS" "$SHELL_PROFILE" || (lspci | grep -i amd | grep -i vga > /dev/null && ! grep -q "OLLAMA_ROCM" "$SHELL_PROFILE"); then
  print_message "$YELLOW" "Adding optimization variables to $SHELL_PROFILE..."
  echo -e "\n# Ollama optimizations for large context windows" >> "$SHELL_PROFILE"
  echo -e "$OPTIMIZATION_VARS" >> "$SHELL_PROFILE"
  print_message "$GREEN" "Optimization variables added to $SHELL_PROFILE."
  print_message "$YELLOW" "Please run 'source $SHELL_PROFILE' to apply these changes to your current shell."
else
  print_message "$GREEN" "Optimization variables are already in $SHELL_PROFILE."
fi

# PART 3: OPENWEBUI SETUP
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

# Install uv using the official installer script
if ! command_exists uv; then
  print_message "$YELLOW" "Installing uv package manager..."
  curl -LsSf https://astral.sh/uv/install.sh | sh || {
    print_message "$RED" "Failed to install uv. Please install it manually."
    exit 1
  }
  
  # Source the environment to make uv available in the current shell session
  if [ -f "$HOME/.local/bin/env" ]; then
    print_message "$YELLOW" "Sourcing environment to add uv to PATH..."
    source "$HOME/.local/bin/env"
  else
    # Fallback PATH update if env file doesn't exist
    print_message "$YELLOW" "Adding uv to PATH manually..."
    export PATH="$HOME/.local/bin:$PATH"
  fi
  
  # Verify uv is now in PATH
  if ! command_exists uv; then
    print_message "$RED" "Failed to add uv to PATH. Please run the script again after running 'source $HOME/.local/bin/env'"
    exit 1
  fi
else
  print_message "$GREEN" "uv package manager is already installed."
fi

# Check if a virtual environment already exists
if [[ ! -d "open-webui" ]]; then
  print_message "$YELLOW" "Setting up a new virtual environment..."
  uv venv --python 3.11 --seed open-webui || {
    print_message "$RED" "Failed to create virtual environment."
    exit 1
  }
else
  print_message "$GREEN" "Virtual environment already exists."
fi

# Activate the virtual environment with error handling for broken pipe
print_message "$YELLOW" "Activating virtual environment..."
{ source open-webui/bin/activate > /dev/null 2>&1 || true; } 
# Check if activation was successful by verifying Python path
if [[ "$(which python)" != *"open-webui"* ]]; then
  print_message "$RED" "Failed to activate virtual environment. Trying alternative method..."
  # Alternative activation method
  ACTIVATE_SCRIPT="$PWD/open-webui/bin/activate"
  if [ -f "$ACTIVATE_SCRIPT" ]; then
    set +e  # Don't exit on error temporarily
    . "$ACTIVATE_SCRIPT"
    set -e  # Restore exit on error
  else
    print_message "$RED" "Cannot find activation script. Virtual environment may be corrupted."
    exit 1
  fi
fi

# Check if Open WebUI is installed - with broken pipe handling
print_message "$YELLOW" "Checking Open WebUI installation status..."
if ! { pip list 2>/dev/null || python -m pip list 2>/dev/null; } | grep -q "open-webui"; then
  print_message "$YELLOW" "Installing Open WebUI..."
  set +e  # Temporarily disable exit on error
  uv pip install open-webui
  PIP_RESULT=$?
  set -e  # Re-enable exit on error
  
  if [ $PIP_RESULT -ne 0 ]; then
    print_message "$YELLOW" "Primary installation method failed, trying alternative method..."
    python -m pip install open-webui || {
      print_message "$RED" "Failed to install Open WebUI."
      exit 1
    }
  fi
else
  print_message "$GREEN" "Open WebUI is already installed. Checking for updates..."
  set +e  # Temporarily disable exit on error
  uv pip install --upgrade open-webui
  UPGRADE_RESULT=$?
  set -e  # Re-enable exit on error
  
  if [ $UPGRADE_RESULT -ne 0 ]; then
    print_message "$YELLOW" "Could not upgrade Open WebUI with uv, trying with pip..."
    python -m pip install --upgrade open-webui || {
      print_message "$YELLOW" "Could not upgrade Open WebUI, continuing with installed version."
    }
  fi
fi

# Return to the original directory
cd - > /dev/null

print_message "$GREEN" "✅ Setup complete!"
print_message "$GREEN" "Ollama is set up with Qwen2.5-Coder with 128k context window."
print_message "$GREEN" "OpenWebUI is installed and ready to use."

# Display AMD-specific message if AMD GPU was detected
if lspci | grep -i amd | grep -i vga > /dev/null; then
  print_message "$GREEN" "AMD GPU support has been configured for Ubuntu 24.04."
  print_message "$YELLOW" "Note: The ROCm/AMDGPU support for Ubuntu 24.04 is still evolving."
  print_message "$YELLOW" "If you encounter issues, please check for updates from AMD for Ubuntu 24.04."
fi

print_message "$YELLOW" "To run the model directly: ollama run qwen2.5-coder-128k"
print_message "$YELLOW" "To run Open WebUI, go to $OPENWEBUI_DIR, activate the environment and run:"
print_message "$YELLOW" "cd $OPENWEBUI_DIR && source open-webui/bin/activate && open-webui serve"
print_message "$YELLOW" "Then access Open WebUI at http://localhost:8080"
print_message "$YELLOW" "For Ubuntu, be cautious with very large contexts as they may require significant memory."
