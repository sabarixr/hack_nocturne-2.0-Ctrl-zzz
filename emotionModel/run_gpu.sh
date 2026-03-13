#!/bin/bash
# Helper script to run commands with GPU support enabled via pip-installed CUDA libraries

# Find the venv python
PYTHON_BIN="venv/bin/python"

if [ ! -f "$PYTHON_BIN" ]; then
    echo "Error: Virtual environment not found at 'venv'. Please create it first."
    exit 1
fi

# Construct LD_LIBRARY_PATH from nvidia pip packages
NVIDIA_PATH=$($PYTHON_BIN -c 'import os; import nvidia; print(os.path.dirname(nvidia.__file__))')
LIB_PATHS=$($PYTHON_BIN -c "import os; base='$NVIDIA_PATH'; libs=[os.path.join(base, d, 'lib') for d in os.listdir(base) if os.path.isdir(os.path.join(base, d, 'lib'))]; print(':'.join(libs))")

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$LIB_PATHS
# Optimize oneDNN
export TF_ENABLE_ONEDNN_OPTS=0

# Run the provided command
if [ $# -eq 0 ]; then
    echo "Usage: ./run_gpu.sh <python_command>"
    echo "Example: ./run_gpu.sh -m emotion_pipeline.train"
else
    $PYTHON_BIN "$@"
fi
