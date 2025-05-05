#!/bin/bash

# Start Ollama server in the background
/bin/ollama serve &
OLLAMA_PID=$!

# Wait for Ollama server to be ready
echo "Waiting for Ollama server to start..."
while ! curl -s http://localhost:11434/api/tags >/dev/null; do
  sleep 2
done

# Run the custom model setup if default_model.txt doesn't exist
if [ ! -f "/root/.ollama/default_model.txt" ]; then
  echo "Setting up custom model..."
  echo "$(date) - Starting model download and creation" > /root/.ollama/model_setup.log
  bash /root/.ollama/setup_custom_model.sh &>> /root/.ollama/model_setup.log
  echo "$(date) - Model setup completed" >> /root/.ollama/model_setup.log
  echo "Model setup completed. You can check the status in /root/.ollama/model_setup.log"
else
  echo "Custom model already set up."
fi

# Wait for the Ollama process to finish
wait $OLLAMA_PID