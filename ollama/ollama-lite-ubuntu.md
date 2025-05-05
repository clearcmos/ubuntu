# ollama-lite: Lightweight Ollama CLI Tool

A minimalist tool for using Ollama models with reduced parameters for faster responses to simple queries.

## Overview

ollama-lite is designed for quick, lightweight interactions with Ollama models while using significantly lower context windows and memory requirements compared to the full Ollama setup. It's ideal for simple tasks like generating commit messages, code reviews, or quick questions that don't need large context.

## Installation

1. Ensure you have Ollama installed
2. Make the script executable:
   ```bash
   chmod +x /home/username/ollama/ollama-lite.py
   ```
3. Optionally, create an alias in your shell config:
   ```bash
   echo 'alias ollama-lite="/path/to/ollama-lite.py"' >> ~/.bashrc
   source ~/.bashrc
   ```

## Usage

### Basic Usage

```bash
./ollama-lite.py "your prompt here"
```

### Options

- `--model` or `-m`: Specify which model to use (default: qwen2.5-coder:7b)
- `--context` or `-c`: Set context window size (default: 4096)
- `--pipe` or `-p`: Read input from pipe

### Examples

1. Generate a commit message:
   ```bash
   git --no-pager diff --cached --stat | ./ollama-lite.py --pipe "write a concise one liner commit message for these changes. only one line in your response:"
   ```

2. Code review:
   ```bash
   cat myfile.py | ./ollama-lite.py --pipe "review this code and suggest improvements"
   ```

3. Using a different model with smaller context:
   ```bash
   ./ollama-lite.py --model llama3 --context 2048 "explain how virtual memory works"
   ```

## Performance Considerations

- The script uses a 4K context window by default (vs 128K in full setup)
- Reduces environment variable settings to minimize memory usage
- Lacks features like streaming responses but executes much faster
- Perfect for quick queries that don't require deep context

## Troubleshooting

If you encounter issues:

1. Ensure Ollama service is running (`ollama serve`)
2. Verify your model is available (`ollama list`)
3. Try reducing the context size further for very memory-constrained systems
4. For complex tasks with large contexts, consider using the full Ollama setup

## License

Same as Ollama project