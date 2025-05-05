#!/bin/bash
# build-autoinstall.sh - Generate Ubuntu 24.04 autoinstall.yaml from template
#
# This script processes the autoinstall.yaml template, replacing variables
# defined in the .env file to create a ready-to-use autoinstall configuration.

set -e

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/template"
OUTPUT_DIR="${SCRIPT_DIR}/output"

# Files
ENV_FILE="${SCRIPT_DIR}/.env"
TEMPLATE_FILE="${TEMPLATE_DIR}/autoinstall.yaml"
OUTPUT_FILE="${OUTPUT_DIR}/autoinstall.yaml"

# Color for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Disk selection options
DISK_OPTIONS=(
  "nvme0n1" 
  "nvme0n2" 
  "nvme0n3" 
  "nvme0n4"
  "sda"
  "sdb"
  "sdc"
  "sdd"
  "custom"
)

# Function to select disk for installation
select_disk() {
  echo -e "${GREEN}Please select the target disk for installation:${NC}"
  
  select disk_option in "${DISK_OPTIONS[@]}"; do
    if [[ "$disk_option" == "custom" ]]; then
      echo -e "${YELLOW}Please enter a custom disk identifier (e.g., nvme1n1, vda):${NC}"
      read -r custom_disk
      export target_disk="$custom_disk"
      echo -e "${GREEN}Selected custom disk: ${target_disk}${NC}"
      break
    elif [[ -n "$disk_option" ]]; then
      export target_disk="$disk_option"
      echo -e "${GREEN}Selected disk: ${target_disk}${NC}"
      break
    else
      echo -e "${RED}Invalid selection. Please try again.${NC}"
    fi
  done
}

# Check if .env file exists
if [ ! -f "${ENV_FILE}" ]; then
  echo -e "${RED}Error: .env file not found at ${ENV_FILE}${NC}"
  echo -e "${YELLOW}Please create one from the .env.sample file:${NC}"
  echo -e "  cp ${SCRIPT_DIR}/.env.sample ${ENV_FILE}"
  echo -e "  nano ${ENV_FILE}  # Edit with your settings"
  exit 1
fi

# Check if template file exists
if [ ! -f "${TEMPLATE_FILE}" ]; then
  echo -e "${RED}Error: Template file not found at ${TEMPLATE_FILE}${NC}"
  exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# Select the target disk interactively
select_disk

# Load the environment variables
echo -e "${GREEN}Loading environment variables from ${ENV_FILE}...${NC}"
set -a # automatically export all variables
source "${ENV_FILE}"
set +a

# Check for required variables
required_vars=(
  "network_hostname"
  "network_ip" 
  "network_netmask"
  "network_netmask_cidr"
  "network_gateway"
  "network_dns"
  "username"
  "userpassword_crypted"
  "rootpassword_crypted"
  "target_disk" # Add target_disk as a required variable
)

missing_vars=0
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo -e "${RED}Error: Required variable '${var}' is not set in ${ENV_FILE}${NC}"
    missing_vars=1
  fi
done

if [ $missing_vars -eq 1 ]; then
  exit 1
fi

# Process the template file
echo -e "${GREEN}Processing template ${TEMPLATE_FILE}...${NC}"

# Format the packages variable to have one package per line with hyphens
if [ -n "$packages" ]; then
  # Convert comma-separated list to yaml list format with hyphens
  formatted_packages=""
  IFS=',' read -ra PACKAGES_ARRAY <<< "$packages"
  for pkg in "${PACKAGES_ARRAY[@]}"; do
    formatted_packages="${formatted_packages}
    - $(echo $pkg | xargs)"
  done
  # Trim leading whitespace from the first line if needed
  formatted_packages=$(echo "$formatted_packages" | sed -e '1s/^[[:space:]]*//')
  # Replace the original packages variable with the formatted one
  export packages="$formatted_packages"
fi

# Check if envsubst is available
if ! command -v envsubst &> /dev/null; then
  echo -e "${YELLOW}Warning: 'envsubst' command not found. Using basic variable substitution.${NC}"
  
  # Basic variable substitution using sed
  cp "${TEMPLATE_FILE}" "${OUTPUT_FILE}"
  
  # Replace each variable in the file
  while IFS='=' read -r key value || [ -n "$key" ]; do
    # Skip comments and empty lines
    [[ $key == \#* ]] || [[ -z "$key" ]] && continue
    
    # Clean key (remove any spaces)
    key=$(echo "$key" | tr -d ' ')
    
    # If this is the packages variable, we already formatted it above
    if [[ "$key" == "packages" ]]; then
      # Replace ${packages} with the formatted value using sed with -E for extended regex and properly handle newlines
      formatted_packages_escaped=$(printf '%s\n' "$formatted_packages" | sed -e 's/[\/&]/\\&/g')
      sed -i.bak "s|\\\${$key}|$formatted_packages_escaped|" "${OUTPUT_FILE}"
    else
      # Replace ${KEY} with the value using sed
      sed -i.bak "s|\\\${$key}|$value|g" "${OUTPUT_FILE}"
    fi
  done < "${ENV_FILE}"
  
  # Replace target_disk variable (from interactive selection)
  sed -i.bak "s|\\\${target_disk}|$target_disk|g" "${OUTPUT_FILE}"
  
  # Clean up backup file
  rm -f "${OUTPUT_FILE}.bak"
else
  # Use envsubst for more reliable variable substitution
  envsubst < "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"
fi

echo -e "${GREEN}✓ Successfully generated autoinstall.yaml!${NC}"
echo -e "${GREEN}Output file: ${OUTPUT_FILE}${NC}"

# Start ephemeral web server
start_webserver() {
  local port=8080
  local file_dir="${OUTPUT_DIR}"
  
  echo -e "\n${GREEN}Starting ephemeral web server on port ${port}...${NC}"
  echo -e "${YELLOW}URL: http://localhost:${port}/autoinstall.yaml${NC}"
  echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}\n"
  
  # Try to use Python if available (usually pre-installed on macOS)
  if command -v python3 &> /dev/null; then
    (cd "${file_dir}" && python3 -m http.server ${port})
  elif command -v python &> /dev/null; then
    (cd "${file_dir}" && python -m SimpleHTTPServer ${port})
  # Try to use PHP if available
  elif command -v php &> /dev/null; then
    (cd "${file_dir}" && php -S localhost:${port})
  # Use Ruby (macOS comes with Ruby pre-installed)
  elif command -v ruby &> /dev/null; then
    (cd "${file_dir}" && ruby -run -e httpd . -p ${port})
  else
    echo -e "${RED}Error: No suitable web server found.${NC}"
    echo -e "${YELLOW}macOS should have Python or Ruby pre-installed.${NC}"
    
    # Provide some useful information
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo -e "1. Verify the generated file: cat ${OUTPUT_FILE}"
    echo -e "2. Copy to your Ubuntu installer or HTTP server"
    echo -e "3. Boot Ubuntu installer with 'autoinstall' kernel parameter"
    echo -e "   Example: 'autoinstall ds=nocloud-net;s=http://example.com/'"
    return 1
  fi
}

# Start the web server
start_webserver