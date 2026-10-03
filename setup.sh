#!/bin/bash
set -Eeuo pipefail

trap 'echo; echo "ERROR: setup failed at line $LINENO."; exit 1' ERR

WORKSPACE="/workspace"
WOOSH_DIR="$WORKSPACE/Woosh"
STORYFX_DIR="$WORKSPACE/storyfx"
QWEN_DIR="$WORKSPACE/models/Qwen3.8-27B"

export HF_HOME="$WORKSPACE/huggingface_cache"
export HF_HUB_DOWNLOAD_TIMEOUT=120
export MAMBA_ROOT_PREFIX="$WORKSPACE/micromamba"
export MFA_ROOT_DIR="$WORKSPACE/mfa"

mkdir -p \
    "$HF_HOME" \
    "$MAMBA_ROOT_PREFIX" \
    "$MFA_ROOT_DIR" \
    "$WORKSPACE/models"

echo "========================================"
echo " StoryFX RunPod Setup"
echo "========================================"
echo "Persistent workspace: $WORKSPACE"
echo

echo "=== 1. Installing system dependencies ==="

apt-get update
apt-get install -y \
    git \
    git-lfs \
    gh \
    curl \
    ca-certificates \
    unzip \
    libsndfile1 \
    graphviz \
    ffmpeg \
    espeak-ng \
    wget \
    bzip2

git lfs install
echo


echo "=== 3. Setting up repositories ==="

cd "$WORKSPACE"

if [ -d "$WOOSH_DIR/.git" ]; then
    echo "Woosh repository already exists. Keeping existing checkout."
elif [ -e "$WOOSH_DIR" ]; then
    echo "ERROR: $WOOSH_DIR exists but is not a Git repository."
    echo "Move or remove it before rerunning setup."
    exit 1
else
    echo "Cloning Woosh..."
    git clone https://github.com/SonyResearch/Woosh.git "$WOOSH_DIR"
fi

if [ -d "$STORYFX_DIR/.git" ]; then
    echo "StoryFX repository already exists. Keeping existing checkout."
elif [ -e "$STORYFX_DIR" ]; then
    echo "ERROR: $STORYFX_DIR exists but is not a Git repository."
    echo "Move or remove it before rerunning setup."
    exit 1
else
    echo "Cloning StoryFX..."
    gh repo clone manchild-modeling/storyfx "$STORYFX_DIR"
fi

echo

echo "=== 4. Setting up Woosh Python environment ==="

python -m pip install --upgrade pip
python -m pip install --upgrade uv

cd "$WOOSH_DIR"
uv sync --extra cuda

uv pip install \
    --python "$WOOSH_DIR/.venv/bin/python" \
    ipykernel \
    ipywidgets

"$WOOSH_DIR/.venv/bin/python" -m ipykernel install \
    --user \
    --name woosh \
    --display-name "Python (Woosh)" \
    >/dev/null

echo "Woosh Jupyter kernel registered as: Python (Woosh)"
echo

echo "=== 5. Checking Woosh checkpoints ==="

checkpoint_ok() {
    local checkpoint_dir="$1"

    [ -f "$checkpoint_dir/config.yaml" ] &&
    compgen -G "$checkpoint_dir/*.safetensors" >/dev/null
}

if checkpoint_ok "$WOOSH_DIR/checkpoints/Woosh-Flow" &&
   checkpoint_ok "$WOOSH_DIR/checkpoints/Woosh-AE" &&
   checkpoint_ok "$WOOSH_DIR/checkpoints/TextConditionerA"; then

    echo "Required Woosh checkpoints already exist."

else
    echo "One or more Woosh checkpoints are missing."
    echo "Downloading only the T2A assets needed by StoryFX..."

    if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI authentication required for Woosh release download."
    gh auth login
    fi
    
    DOWNLOAD_DIR="$WOOSH_DIR/.checkpoint_downloads"
    mkdir -p "$DOWNLOAD_DIR"

    gh release download v1.0.0 \
        --repo SonyResearch/Woosh \
        --dir "$DOWNLOAD_DIR" \
        --pattern 'Woosh-Flow.zip' \
        --pattern 'Woosh-AE.zip' \
        --pattern 'TextConditionerA.zip' \
        --clobber



    for archive in "$DOWNLOAD_DIR"/*.zip; do
        echo "Extracting $(basename "$archive")..."
        unzip -o "$archive" -d "$WOOSH_DIR"
    done

    rm -rf "$DOWNLOAD_DIR"
fi

for component in Woosh-Flow Woosh-AE TextConditionerA; do
    if ! checkpoint_ok "$WOOSH_DIR/checkpoints/$component"; then
        echo "ERROR: Woosh checkpoint verification failed for $component."
        echo "Expected config.yaml and at least one .safetensors file in:"
        echo "$WOOSH_DIR/checkpoints/$component"
        exit 1
    fi
done

echo "Woosh checkpoints verified."
echo

echo "=== 6. Setting up Micromamba ==="

if command -v micromamba >/dev/null 2>&1; then
    echo "Micromamba executable already installed."
else
    echo "Installing Micromamba..."

    TMP_DIR="$(mktemp -d)"

    curl -Ls \
        https://micro.mamba.pm/api/micromamba/linux-64/latest \
        | tar -xj -C "$TMP_DIR" bin/micromamba

    install -m 755 \
        "$TMP_DIR/bin/micromamba" \
        /usr/local/bin/micromamba

    rm -rf "$TMP_DIR"
fi

micromamba --version
echo

echo "=== 7. Setting up Montreal Forced Aligner ==="

if [ -x "$MAMBA_ROOT_PREFIX/envs/mfa_env/bin/mfa" ]; then
    echo "Persistent MFA environment already exists."
else
    echo "Creating persistent MFA environment..."

    micromamba create -y \
        -n mfa_env \
        -c conda-forge \
        python=3.10 \
        montreal-forced-aligner
fi

echo "MFA version:"
micromamba run -n mfa_env mfa version
echo

echo "=== 8. Checking MFA models ==="

if micromamba run -n mfa_env \
    mfa model inspect acoustic english_us_arpa \
    >/dev/null 2>&1; then

    echo "MFA acoustic model english_us_arpa already exists."
else
    echo "Downloading MFA acoustic model..."
    micromamba run -n mfa_env \
        mfa model download acoustic english_us_arpa
fi

if micromamba run -n mfa_env \
    mfa model inspect dictionary english_us_arpa \
    >/dev/null 2>&1; then

    echo "MFA dictionary english_us_arpa already exists."
else
    echo "Downloading MFA dictionary..."
    micromamba run -n mfa_env \
        mfa model download dictionary english_us_arpa
fi

echo "MFA models verified."
echo

echo "=== 9. Installing Hugging Face CLI ==="

python -m pip install --upgrade \
    transformers \
    accelerate \
    safetensors \
    huggingface_hub \
    hf_xet \
    praatio

python -m pip install -U \
    "flash-linear-attention[cuda]"

python -m pip install -U \
    git+https://github.com/Dao-AILab/causal-conv1d.git \
    --no-build-isolation

hf --help >/dev/null
echo

echo "=== 10. Downloading / verifying Qwen3.8-27B ==="

mkdir -p "$QWEN_DIR"

hf download \
    Qwen/Qwen3.8-27B \
    --local-dir "$QWEN_DIR"

if [ ! -f "$QWEN_DIR/config.json" ] ||
   [ ! -f "$QWEN_DIR/model.safetensors.index.json" ]; then

    echo "ERROR: Qwen download verification failed."
    exit 1
fi

SHARD_COUNT="$(find "$QWEN_DIR" -maxdepth 1 \
    -name 'model-*-of-*.safetensors' | wc -l)"

echo "Qwen model shards found: $SHARD_COUNT"

if [ "$SHARD_COUNT" -lt 18 ]; then
    echo "ERROR: Expected 18 Qwen safetensor shards, but found $SHARD_COUNT."
    exit 1
fi

echo "Qwen3.8-27B verified."
echo

echo "=== 11. Saving StoryFX environment variables ==="

ENV_FILE="$WORKSPACE/storyfx_env.sh"

cat > "$ENV_FILE" <<'EOF'
export HF_HOME="/workspace/huggingface_cache"
export HF_HUB_DOWNLOAD_TIMEOUT=120
export MAMBA_ROOT_PREFIX="/workspace/micromamba"
export MFA_ROOT_DIR="/workspace/mfa"
EOF

chmod 600 "$ENV_FILE"

if ! grep -Fq 'source /workspace/storyfx_env.sh' /root/.bashrc; then
    echo 'source /workspace/storyfx_env.sh' >> /root/.bashrc
fi

echo "Environment file written to: $ENV_FILE"
echo

echo "========================================"
echo " Setup Complete"
echo "========================================"
echo

echo "Repositories:"
echo "  StoryFX: $STORYFX_DIR"
echo "  Woosh:   $WOOSH_DIR"
echo

echo "Persistent model/environment locations:"
echo "  Qwen:       $QWEN_DIR"
echo "  Woosh:      $WOOSH_DIR/checkpoints"
echo "  MFA env:    $MAMBA_ROOT_PREFIX/envs/mfa_env"
echo "  MFA models: $MFA_ROOT_DIR"
echo

echo "Disk usage:"
du -sh \
    "$QWEN_DIR" \
    "$WOOSH_DIR" \
    "$MAMBA_ROOT_PREFIX" \
    "$MFA_ROOT_DIR" \
    2>/dev/null || true

echo
df -h "$WORKSPACE"

echo
echo "For Woosh notebooks, select the Jupyter kernel:"
echo "  Python (Woosh)"