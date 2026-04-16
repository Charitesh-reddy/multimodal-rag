#!/usr/bin/env bash
# =============================================================================
# run.sh — One-click launcher for Multimodal VQA RAG
#
# What it does:
#   1. Loads API keys from .env
#   2. Activates the virtual environment
#   3. Installs / upgrades dependencies if needed
#   4. Indexes images (skips if already indexed)
#   5. Commits & pushes all source changes to GitHub
#   6. Launches the Streamlit app
# =============================================================================

set -e  # exit immediately on any error

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 0. Resolve project root ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
log "Project root: $SCRIPT_DIR"

# ── 1. Load .env ─────────────────────────────────────────────────────────────
if [ -f ".env" ]; then
    log "Loading environment from .env …"
    set -o allexport
    source .env
    set +o allexport
    ok ".env loaded"
else
    err ".env file not found. Create one with GEMINI_API_KEY and GOOGLE_API_KEY."
fi

# Validate API key exists
if [ -z "${GEMINI_API_KEY}" ] && [ -z "${GOOGLE_API_KEY}" ]; then
    err "No API key found in .env. Add GEMINI_API_KEY=<your_key>"
fi
ok "API key detected"

# ── 2. Activate venv ─────────────────────────────────────────────────────────
if [ ! -d "venv" ]; then
    log "Creating virtual environment …"
    python3 -m venv venv
fi

log "Activating virtual environment …"
source venv/bin/activate
ok "venv active — $(python --version)"

# ── 3. Install / upgrade dependencies ────────────────────────────────────────
log "Checking dependencies …"
pip install -q -r requirements.txt

# Fix known incompatible packages
pip show docx &>/dev/null && pip uninstall -q -y docx && pip install -q python-docx
pip show torchvision &>/dev/null || pip install -q torchvision

ok "Dependencies ready"

# ── 4. Index images (only if not already indexed) ────────────────────────────
CHROMA_DIR="data/chroma_db"
IMAGE_DIR="${IMAGE_DIR:-data/images}"

INDEX_COUNT=0
if [ -d "$CHROMA_DIR" ]; then
    INDEX_COUNT=$(find "$CHROMA_DIR" -name "*.parquet" 2>/dev/null | wc -l | tr -d ' ')
fi

if [ "$INDEX_COUNT" -gt 0 ] && [ "${FORCE_REINDEX:-false}" != "true" ]; then
    ok "Index already exists ($INDEX_COUNT shard(s)) — skipping. Set FORCE_REINDEX=true to rebuild."
else
    if [ -d "$IMAGE_DIR" ] && [ "$(ls -A "$IMAGE_DIR" 2>/dev/null)" ]; then
        log "Indexing images from $IMAGE_DIR …"
        REINDEX_FLAG=""
        [ "${FORCE_REINDEX:-false}" = "true" ] && REINDEX_FLAG="--reindex"
        PYTHONPATH=. python src/pipeline.py --index --image-dir "$IMAGE_DIR" $REINDEX_FLAG
        ok "Indexing complete"
    else
        warn "No images found in $IMAGE_DIR — skipping indexing. Add images to use RAG search."
    fi
fi

# ── 5. Git — commit & push source changes ────────────────────────────────────
log "Syncing code to GitHub …"

# Stage everything except what's in .gitignore
git add -A

# Only commit if there are staged changes
if git diff --cached --quiet; then
    ok "Nothing new to commit — repo already up to date"
else
    COMMIT_MSG="auto: update $(date '+%Y-%m-%d %H:%M:%S')"
    git commit -m "$COMMIT_MSG"
    log "Committed: $COMMIT_MSG"

    if git push origin main 2>&1; then
        ok "Pushed to origin/main"
    else
        warn "Push failed (check credentials / network). Continuing to launch app …"
    fi
fi

# ── 6. Launch Streamlit ──────────────────────────────────────────────────────
PORT="${STREAMLIT_PORT:-8501}"
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  🧠  Multimodal VQA — launching on port $PORT${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PYTHONPATH=. streamlit run app/app.py \
    --server.address 0.0.0.0 \
    --server.port "$PORT"
