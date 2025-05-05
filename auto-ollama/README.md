# Auto-Ollama with AMD GPU Acceleration

An automated setup for running Ollama with AMD GPU acceleration and Open WebUI, featuring custom high-context models.

![Ollama + Open WebUI](https://raw.githubusercontent.com/ollama/ollama/main/assets/ollama-logo-white-cropped.png)

## Overview

This project provides an automated setup for deploying Ollama with:

- AMD GPU acceleration for faster inference
- Custom Qwen 2.5 Coder model with 128K context window
- Open WebUI for a user-friendly chat interface
- Docker-based deployment for easy setup across machines

Perfect for developers who want a powerful local AI solution with minimal setup.

## Features

- **AMD GPU Acceleration**: Optimized for Radeon cards using ROCm
- **Extended Context Window**: Modified Qwen model with 128K token context
- **User-Friendly UI**: Includes Open WebUI for intuitive interaction
- **Docker-Based**: Easy to deploy on any machine with Docker support
- **Automatic Setup**: One script handles everything from installation to configuration

## Requirements

- Linux operating system (Ubuntu/Debian recommended)
- AMD GPU with ROCm support (Radeon RX 6000/7000 series recommended)
- Docker and Docker Compose
- Minimum 16GB RAM (32GB recommended)
- At least 30GB free disk space

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/auto-ollama.git
   cd auto-ollama
   ```

2. Run the setup script:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

3. Wait for the setup to complete. The script will:
   - Install Docker if not already installed
   - Configure necessary permissions
   - Set up Ollama with AMD GPU support
   - Install Open WebUI
   - Download and configure the Qwen 2.5 Coder model with 128K context

4. Check model status:
   ```bash
   ./check_model_status.sh
   ```

5. Access Open WebUI at:
   ```
   http://localhost:8080
   ```

## Model Configuration

The default model is a custom version of Qwen 2.5 Coder (7B) with:

- 128K token context window (131072 tokens)
- Temperature: 0.7
- Top-p: 0.9
- Repeat penalty: 1.1

This configuration is defined in the `Modelfile` and is automatically applied during setup.

## Troubleshooting GPU Detection

If your AMD GPU isn't properly detected:

### Common Issues

1. **Missing amdgpu Version File**: The setup script automatically creates a workaround for this issue.

2. **Render Group Issues**: If you encounter errors related to the render group, the setup script will handle this automatically.

3. **Docker Compose Issues**: The script now uses direct Docker commands if Docker Compose encounters errors.

### Manual Fixes

If you're still experiencing issues:

1. Check GPU visibility:
   ```bash
   lspci -nnk | grep -A3 VGA | grep AMD
   ```

2. Verify container has access to GPU devices:
   ```bash
   docker exec ollama ls -la /dev/dri/
   docker exec ollama ls -la /dev/kfd
   ```

3. Check Ollama logs:
   ```bash
   docker logs ollama | grep -i gpu
   ```

4. Ensure fake amdgpu version file exists:
   ```bash
   ls -la ./ollama_data/fake_sys/module/amdgpu/version
   ```

## Usage Examples

### Using Ollama CLI

```bash
# Run a basic query
docker exec -it ollama ollama run qwen-128k "Explain quantum computing in simple terms"

# Chat with the model
docker exec -it ollama ollama run qwen-128k
```

### Using API

```bash
# Generate a completion
curl -X POST http://localhost:11434/api/generate -d '{
  "model": "qwen-128k",
  "prompt": "Write a Python function to calculate Fibonacci numbers"
}'

# List available models
curl http://localhost:11434/api/tags | jq
```

### Environment Variables

Customize your deployment by setting these environment variables before running `setup.sh`:

- `OLLAMA_PORT`: Port for Ollama API (default: 11434)
- `WEBUI_PORT`: Port for Open WebUI (default: 8080)
- `WEBUI_SECRET_KEY`: Security key for Open WebUI (change this!)
- `WEBUI_AUTH`: Enable authentication (default: true)

## Monitoring and Logs

### Check Model Installation Status

```bash
./check_model_status.sh
```

### View Logs

```bash
# Ollama logs
docker logs ollama

# WebUI logs
docker logs open-webui

# Model setup logs
docker exec ollama cat /root/.ollama/model_setup.log
```

## Custom Models

To create additional custom models:

1. Create a new Modelfile:
   ```
   FROM llama3:8b
   PARAMETER num_ctx 32768
   PARAMETER temperature 0.8
   ```

2. Create your model:
   ```bash
   docker cp your-modelfile ollama:/root/.ollama/custom.modelfile
   docker exec ollama ollama create my-custom-model -f /root/.ollama/custom.modelfile
   ```

## Project Structure

```
auto-ollama/
├── setup.sh                  # Main setup script
├── Modelfile                 # Custom model configuration
├── check_model_status.sh     # Script to check model status
├── docker-compose.yml        # Docker configuration
├── ollama_data/              # Persistent Ollama data
│   ├── custom_entrypoint.sh  # Custom container startup script
│   ├── setup_custom_model.sh # Model setup script
│   └── fake_sys/             # AMD GPU detection fix
└── webui_data/               # Persistent Open WebUI data
```

## Advanced Configuration

### Changing GPU Parameters

Edit `docker-compose.yml` to modify GPU-related environment variables:

```yaml
environment:
  - HSA_OVERRIDE_GFX_VERSION=10.3.0  # Adjust for your GPU architecture
  - HSA_ENABLE_SDMA=1
  - OLLAMA_FLASH_ATTENTION=true
  - GPU_MAX_HEAP_SIZE=100
  - GPU_SINGLE_ALLOC_PERCENT=100
```

### Using Multiple GPUs

For systems with multiple GPUs, you can specify which ones to use:

```yaml
environment:
  - ROCR_VISIBLE_DEVICES=0,1  # Use first and second GPU
```

## Performance Tuning

For optimal performance:

1. **Increase RAM Allocation**: 
   - More RAM allows larger batches and better performance

2. **Balance CPU/GPU Usage**:
   ```yaml
   environment:
     - OLLAMA_NUM_PARALLEL=2  # Adjust based on CPU cores
   ```

3. **Adjust KV Cache Type**:
   ```yaml
   environment:
     - OLLAMA_KV_CACHE_TYPE=q4_0  # Options: f16, q8_0, q4_0, q4_K
   ```

## License

This project is released under the MIT License. See the LICENSE file for details.

## Acknowledgments

- [Ollama](https://github.com/ollama/ollama) for the core inference engine
- [Open WebUI](https://github.com/open-webui/open-webui) for the web interface
- [Qwen Team](https://github.com/QwenLM/Qwen) for the Qwen 2.5 models
- AMD for ROCm support