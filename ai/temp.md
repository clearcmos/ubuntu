# Ollama & Open WebUI Deployment With AMD GPU on Ubuntu 

## Update system and install radeontop for monitoring GPU usage

`sudo apt update && sudo apt upgrade -y && sudo apt -y install radeontop`

## Install the AMDGPU installer package

```sh
sudo apt update
wget https://repo.radeon.com/amdgpu-install/6.4/ubuntu/noble/amdgpu-install_6.4.60400-1_all.deb
sudo apt install ./amdgpu-install_6.4.60400-1_all.deb
sudo apt update
```

## Install the ROCm stack

`sudo amdgpu-install --usecase=graphics,rocm --no-dkms`

## Add user to groups (create them if needed)

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

## Install Docker (if not already installed)

```sh
sudo apt install docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $LOGNAME
```

## Reboot your system

`sudo reboot`

## Create docker-compose.yml file for Ollama and Open WebUI

docker-compose.yml
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


## Create necessary dirs in docker-compose.yml location

`mkdir -p data/ollama data/webui modelfile`

## Create Modelfile

Create this file:
`nano modelfile/qwen-coder-60k.modelfile`

Add this:
```
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

## Launch the containers

`docker-compose up -d`

## Create the custom model

`docker exec -it ollama ollama create qwen-coder-60k -f /modelfile/qwen-coder-60k.modelfile`

## Done

You should now be able to access Open WebUI via http://localhost:8080

## Checking the model info

Launch ollama within the container:
`docker exec -it ollama ollama run qwen-coder-60k`

Then type:
`>>> /show info`
