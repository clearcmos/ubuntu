# Ollama & Open WebUI Deployment With 6800XT AMD GPU on Ubuntu 24.04.2 LTS

## Prerequisites
Before proceeding, ensure you have the following:
- A machine running Ubuntu.
- An AMD GPU that supports ROCm.
- Basic knowledge of Docker and command line operations.

## Step 1: Update System and Install radeontop for Monitoring GPU Usage
```sh
sudo apt update && sudo apt upgrade -y && sudo apt -y install radeontop
```

## Step 2: Install the AMDGPU Installer Package
```sh
sudo apt update
wget https://repo.radeon.com/amdgpu-install/6.4/ubuntu/noble/amdgpu-install_6.4.60400-1_all.deb
sudo apt install ./amdgpu-install_6.4.60400-1_all.deb
sudo apt update
```

## Step 3: Install the ROCm Stack
```sh
sudo amdgpu-install --usecase=graphics,rocm --no-dkms
```

## Step 4: Add User to Groups (Create Them If Needed)
```sh
if ! getent group render > /dev/null 2>&1; then
    sudo groupadd render
fi
# Check if 'video' group exists, if not, create it
if ! getent group video > /dev/null 2>&1; then
    sudo groupadd video
fi
sudo usermod -a -G render,video $LOGNAME
```

## Step 5: Install Docker (If Not Already Installed)
```sh
sudo apt install docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $LOGNAME
```

## Step 6: Reboot Your System
```sh
sudo reboot
```

## Step 7: Create docker-compose.yml File for Ollama and Open WebUI
Create a file named `docker-compose.yml` with the following content:
```yaml
version: '3.8'
services:
  ollama:
    image: ollama/ollama:rocm
    container_name: ollama
    restart: always
    ports:
      - "11434:11434"
    volumes:
      - ./data/ollama:/root/.ollama
      - ./modelfile:/modelfile
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    group_add:
      - "${RENDER_GROUP_ID:-992}"
      - "video"
    environment:
      - HSA_OVERRIDE_GFX_VERSION=10.3.0
      - HCC_AMDGPU_TARGET=gfx1030
    # Comment out the environment variables above if your AMD GPU has native ROCm support

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: always
    ports:
      - "8080:8080"
    volumes:
      - ./data/webui:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    depends_on:
      - ollama

volumes:
  ollama:
  webui:
```

## Step 8: Create Necessary Directories
```sh
mkdir -p data/ollama data/webui modelfile
```

## Step 9: Create Modelfile
Create a file named `modelfile/qwen-coder-60k.modelfile` with the following content:
```yaml
FROM qwen2.5-coder:7b
# Set a higher context window (60K)
PARAMETER num_ctx 60000
# Adjust model parameters for better performance
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
# System prompt to optimize for code tasks
SYSTEM """
You are a helpful AI programming assistant with expertise in software development.
You excel at code generation, debugging, and providing detailed explanations.
Provide concise, clean, and well-documented code.
"""
```

## Step 10: Launch the Containers
```sh
docker-compose up -d
```

## Step 11: Create the Custom Model
```sh
docker exec -it ollama ollama create qwen-coder-60k -f /modelfile/qwen-coder-60k.modelfile
```

## Step 12: Checking the Model Info
Launch Ollama within the container:
```sh
docker exec -it ollama ollama run qwen-coder-60k
Then type:
>>> /show info
```

## Troubleshooting
If you encounter issues, check the following:
- Ensure all dependencies are installed.
- Verify that your AMD GPU is correctly recognized by ROCm.
- Check Docker logs for any errors: `docker-compose logs`.

You should now be able to access Open WebUI via `http://localhost:8080`.
