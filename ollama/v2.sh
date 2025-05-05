#!/bin/bash
# Improved script to set up Ollama with Qwen2.5-Coder:7b (128k context) and OpenWebUI for Ubuntu 24.04
# This script is idempotent, has better error handling, and properly manages AMD GPU support
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

# Function to check command success
check_success() {
  local command_description=$1
  local exit_code=$2
  if [ $exit_code -ne 0 ]; then
    print_message "$RED" "Error: $command_description failed."
    exit 1
  fi
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
sudo apt update
check_success "Package list update" $?

# Ensure necessary dependencies are installed
if ! command_exists curl || ! command_exists pip || ! command_exists lspci; then
  print_message "$YELLOW" "Installing basic dependencies..."
  sudo apt install -y curl python3-pip pciutils
  check_success "Dependencies installation" $?
fi

# PART 1: OLLAMA SETUP
# Check if Ollama is installed
if ! command_exists ollama; then
  print_message "$YELLOW" "Ollama is not installed. Installing..."
  
  # Install dependencies if needed
  sudo apt install -y build-essential ca-certificates
  check_success "Build essentials installation" $?
  
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
print_message "$YELLOW" "Checking for AMD GPU..."

# Check for AMD GPU
if lspci | grep -qi 'amd\|advanced micro devices.*\[amd\]\|radeon'; then
  print_message "$GREEN" "AMD GPU detected. Setting up ROCm repository and drivers..."
  
  # Install additional dependencies for AMD GPU setup
  print_message "$YELLOW" "Installing additional dependencies for AMD GPU setup..."
  sudo apt install -y wget gpg
  check_success "Installing dependencies" $?
  
  # Setup proper repository keys
  print_message "$YELLOW" "Setting up ROCm repository keys..."
  sudo mkdir -p /etc/apt/keyrings
  wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/rocm.gpg
  check_success "Setting up ROCm repository keys" $?
  
  # Add the ROCm repository
  print_message "$YELLOW" "Adding ROCm repository..."
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.4 ubuntu main" | sudo tee /etc/apt/sources.list.d/rocm.list > /dev/null
  check_success "Adding ROCm repository" $?
  
  # Update package lists again
  sudo apt update
  check_success "Updating package lists" $?
  
  # Install ROCm components
  print_message "$YELLOW" "Installing ROCm components..."
  sudo apt install -y rocm-dev rocm-utils
  check_success "Installing ROCm components" $?
  
  # Add user to required groups
  print_message "$YELLOW" "Adding user to video and render groups..."
  sudo usermod -aG video,render "$USER"
  check_success "Adding user to groups" $?
  
  # Regenerate initramfs
  print_message "$YELLOW" "Regenerating initramfs..."
  sudo update-initramfs -u
  check_success "Regenerating initramfs" $?
  
  # Verify ROCm installation
  print_message "$YELLOW" "Verifying ROCm installation..."
  
  if ! lsmod | grep -q amdgpu; then
    print_message "$RED" "Warning: amdgpu module is not loaded. ROCm may not function properly."
    print_message "$YELLOW" "You might need to reboot your system for the changes to take effect."
  else
    print_message "$GREEN" "amdgpu module is loaded successfully."
  fi
  
  # Try to verify with rocminfo, but don't abort if it fails (might need a reboot)
  if command_exists rocminfo; then
    if rocminfo &>/dev/null; then
      print_message "$GREEN" "ROCm is properly installed and functioning!"
    else
      print_message "$YELLOW" "rocminfo command failed. You might need to reboot your system for ROCm to function properly."
    fi
  else
    print_message "$YELLOW" "rocminfo command not found. ROCm installation might be incomplete."
  fi
  
  # Create systemd service override for Ollama
  print_message "$YELLOW" "Creating systemd service override for Ollama with GPU optimizations..."
  sudo mkdir -p /etc/systemd/system/ollama.service.d/
  
  # Create the override.conf file with all optimization variables
  cat > /tmp/ollama-override.conf << 'EOF'
[Service]
Environment="HSA_OVERRIDE_GFX_VERSION=10.3.0"
Environment="OLLAMA_ROCM=1"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_MAX_INPUT_TOKENS=131072"
Environment="OLLAMA_CONTEXT_LENGTH=131072"
EOF

  # Install the override file
  sudo cp /tmp/ollama-override.conf /etc/systemd/system/ollama.service.d/override.conf
  check_success "Creating systemd override" $?
  
  # Reload systemd and restart Ollama
  print_message "$YELLOW" "Reloading systemd and restarting Ollama service..."
  sudo systemctl daemon-reload
  sudo systemctl restart ollama
  check_success "Restarting Ollama service" $?
  
  print_message "$GREEN" "Ollama systemd service configured for AMD GPU acceleration."
  
  # Define optimization variables for shell profile
  OPTIMIZATION_VARS="export HSA_OVERRIDE_GFX_VERSION=10.3.0\nexport OLLAMA_ROCM=1\nexport OLLAMA_FLASH_ATTENTION=1\nexport OLLAMA_KV_CACHE_TYPE=q8_0\nexport OLLAMA_MAX_INPUT_TOKENS=131072\nexport OLLAMA_CONTEXT_LENGTH=131072"
else
  print_message "$YELLOW" "No AMD GPU detected. Setting up standard memory optimizations only."
  # Set up standard memory optimizations for non-AMD systems
  OPTIMIZATION_VARS="export OLLAMA_FLASH_ATTENTION=1\nexport OLLAMA_KV_CACHE_TYPE=q8_0\nexport OLLAMA_MAX_INPUT_TOKENS=131072\nexport OLLAMA_CONTEXT_LENGTH=131072"
fi

# Add optimization variables to shell profile if not already there
SHELL_PROFILE="$HOME/.bashrc"
if ! grep -q "OLLAMA_MAX_INPUT_TOKENS" "$SHELL_PROFILE"; then
  print_message "$YELLOW" "Adding optimization variables to $SHELL_PROFILE..."
  echo -e "\n# Ollama optimizations for large context windows and AMD GPU" >> "$SHELL_PROFILE"
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
  curl -LsSf https://astral.sh/uv/install.sh | sh
  INSTALL_RESULT=$?
  if [ $INSTALL_RESULT -ne 0 ]; then
    print_message "$RED" "Failed to install uv. Please install it manually."
    exit 1
  fi
  
  # Source the environment to make uv available in the current shell session
  if [ -f "$HOME/.local/bin/env" ]; then
    print_message "$YELLOW" "Sourcing environment to add uv to PATH..."
    source "$HOME/.local/bin/env" || true
  fi
  
  # Fallback PATH update if env file doesn't exist or source failed
  export PATH="$HOME/.local/bin:$PATH"
  
  # Verify uv is now in PATH
  if ! command_exists uv; then
    print_message "$YELLOW" "Adding uv to PATH using alternative method..."
    # Find uv binary and add its directory to PATH
    UV_PATH=$(find $HOME -name "uv" -type f -executable 2>/dev/null | head -1)
    if [ -n "$UV_PATH" ]; then
      UV_DIR=$(dirname "$UV_PATH")
      export PATH="$UV_DIR:$PATH"
    else
      print_message "$RED" "Could not find uv executable. Please run the script again after restarting your shell."
      exit 1
    fi
  fi
else
  print_message "$GREEN" "uv package manager is already installed."
fi

# Check if a virtual environment already exists
if [[ ! -d "open-webui" ]]; then
  print_message "$YELLOW" "Setting up a new virtual environment..."
  uv venv --python 3.11 --seed open-webui
  check_success "Creating virtual environment" $?
else
  print_message "$GREEN" "Virtual environment already exists."
fi

# Activate the virtual environment with error handling
print_message "$YELLOW" "Activating virtual environment..."
ACTIVATE_SCRIPT="$PWD/open-webui/bin/activate"

if [ -f "$ACTIVATE_SCRIPT" ]; then
  set +e  # Don't exit on error temporarily
  source "$ACTIVATE_SCRIPT" 2>/dev/null || . "$ACTIVATE_SCRIPT" 2>/dev/null
  ACTIVATE_RESULT=$?
  set -e  # Restore exit on error
  
  if [ $ACTIVATE_RESULT -ne 0 ]; then
    print_message "$RED" "Failed to activate virtual environment. Trying alternative method..."
    export VIRTUAL_ENV="$PWD/open-webui"
    export PATH="$VIRTUAL_ENV/bin:$PATH"
  fi
else
  print_message "$RED" "Cannot find activation script. Virtual environment may be corrupted."
  exit 1
fi

# Check if Open WebUI is installed
print_message "$YELLOW" "Checking Open WebUI installation status..."
set +e  # Temporarily disable exit on error
python3 -m pip list 2>/dev/null | grep -q "open-webui"
PIP_LIST_RESULT=$?
set -e  # Re-enable exit on error

if [ $PIP_LIST_RESULT -ne 0 ]; then
  print_message "$YELLOW" "Installing Open WebUI..."
  set +e  # Temporarily disable exit on error
  
  # Try multiple installation methods
  uv pip install open-webui
  UV_INSTALL_RESULT=$?
  
  if [ $UV_INSTALL_RESULT -ne 0 ]; then
    print_message "$YELLOW" "Primary installation method failed, trying alternative method..."
    python3 -m pip install open-webui
    PIP_INSTALL_RESULT=$?
    
    if [ $PIP_INSTALL_RESULT -ne 0 ]; then
      print_message "$RED" "Failed to install Open WebUI."
      exit 1
    fi
  fi
  
  set -e  # Re-enable exit on error
  print_message "$GREEN" "Open WebUI installed successfully!"
else
  print_message "$GREEN" "Open WebUI is already installed. Checking for updates..."
  set +e  # Temporarily disable exit on error
  
  # Try to update with uv first, then pip if that fails
  uv pip install --upgrade open-webui
  UV_UPGRADE_RESULT=$?
  
  if [ $UV_UPGRADE_RESULT -ne 0 ]; then
    print_message "$YELLOW" "Could not upgrade Open WebUI with uv, trying with pip..."
    python3 -m pip install --upgrade open-webui
    # We don't check the result of this operation, just continue with the installed version
  fi
  
  set -e  # Re-enable exit on error
  print_message "$GREEN" "Open WebUI is up to date."
fi

# Return to the original directory
cd - > /dev/null

# Final messages section
print_message "$GREEN" "✅ Setup complete!"
print_message "$GREEN" "Ollama is set up with Qwen2.5-Coder with 128k context window."
print_message "$GREEN" "OpenWebUI is installed and ready to use."

# Display AMD-specific message if AMD GPU was detected
if lspci | grep -qi 'amd.*vga'; then
  print_message "$GREEN" "AMD GPU support has been configured using the official ROCm repository."
  print_message "$YELLOW" "NOTE: You should reboot your system to ensure all AMD GPU drivers are properly loaded."
  print_message "$YELLOW" "You can verify GPU usage after reboot with 'rocm-smi' or by installing 'radeontop' (sudo apt install radeontop)."
  print_message "$YELLOW" "If you upgrade your kernel in the future, you may need to re-run this script or reinstall ROCm components."
fi

print_message "$YELLOW" "To run the model directly: ollama run qwen2.5-coder-128k"
print_message "$YELLOW" "To run Open WebUI, go to $OPENWEBUI_DIR, activate the environment and run:"
print_message "$YELLOW" "cd $OPENWEBUI_DIR && source open-webui/bin/activate && open-webui serve"
print_message "$YELLOW" "Then access Open WebUI at http://localhost:8080"
