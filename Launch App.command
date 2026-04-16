#!/usr/bin/env bash
# Double-click this file in Finder to launch the Multimodal VQA app

# ── Go to project folder ──────────────────────────────────────────────────────
cd "$(dirname "$0")"

# ── Load API keys ─────────────────────────────────────────────────────────────
set -o allexport; source .env; set +o allexport

# ── Activate virtual environment ──────────────────────────────────────────────
source venv/bin/activate

# ── Index images if not already done ─────────────────────────────────────────
if [ ! -f "data/captions/captions.json" ]; then
    echo "🔍 Indexing images for the first time..."
    PYTHONPATH=. python src/pipeline.py --index --image-dir data/images
fi

# ── Git: commit & push changes ────────────────────────────────────────────────
git add -A
if ! git diff --cached --quiet; then
    git commit -m "auto: update $(date '+%Y-%m-%d %H:%M')"
    git push origin main && echo "✅ Pushed to GitHub"
fi

# ── Launch app & open browser ─────────────────────────────────────────────────
echo ""
echo "🚀 Launching Multimodal VQA at http://localhost:8501"
sleep 1 && open "http://localhost:8501" &
PYTHONPATH=. streamlit run app/app.py --server.port 8501
