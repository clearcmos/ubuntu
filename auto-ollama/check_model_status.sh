#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Checking Ollama model status...${NC}"

# Check if containers are running
if ! docker ps | grep -q ollama; then
  echo -e "${RED}Error: Ollama container is not running.${NC}"
  echo -e "${YELLOW}Try starting the containers with:${NC} docker-compose up -d"
  exit 1
fi

# First check if the API is responsive
if ! curl -s http://localhost:11434/api/tags >/dev/null; then
  echo -e "${YELLOW}Ollama API is not yet responding. The server might still be starting.${NC}"
  echo -e "${YELLOW}Try again in a few moments.${NC}"
  exit 0
fi

# Check the model setup log
echo -e "${YELLOW}Model setup log:${NC}"
docker exec ollama cat /root/.ollama/model_setup.log 2>/dev/null || echo -e "${YELLOW}No model setup log found yet.${NC}"

# Check if models are available
echo -e "\n${YELLOW}Available models:${NC}"
MODELS=$(curl -s http://localhost:11434/api/tags)
echo "$MODELS" | jq -r '.models[] | .name'

# Check if qwen-128k is available
if echo "$MODELS" | jq -r '.models[] | .name' | grep -q "qwen-128k"; then
  echo -e "\n${GREEN}Success!${NC} The qwen-128k model is available and ready to use."
else
  # Check if base model is available
  if echo "$MODELS" | jq -r '.models[] | .name' | grep -q "qwen2.5-coder:7b"; then
    echo -e "\n${YELLOW}Base model qwen2.5-coder:7b is downloaded, but custom qwen-128k is not yet ready.${NC}"
    echo -e "${YELLOW}The custom model might still be creating. Check back in a few minutes.${NC}"
  else
    echo -e "\n${YELLOW}Model download might still be in progress.${NC}"
    echo -e "${YELLOW}This can take several minutes depending on your internet connection.${NC}"
  fi
  
  # Check container logs for pull progress
  echo -e "\n${YELLOW}Recent Ollama logs:${NC}"
  docker logs ollama --tail 20
fi

echo -e "\n${YELLOW}To test the model, try:${NC}"
echo "curl -X POST http://localhost:11434/api/generate -d '{\"model\":\"qwen-128k\",\"prompt\":\"Hello!\"}'"