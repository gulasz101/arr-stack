# ===========================================
# 🏴‍☠️ Arr Stack - Task Runner
# ===========================================
# Prerequisites: sops, age, docker, docker compose
# Usage: just <command>
# ===========================================

# Show available commands
default:
    @just --list

# Decrypt .env.sops → .env (requires age key at ~/.config/sops/age/keys.txt)
decrypt:
    sops -d --input-type dotenv --output-type dotenv .env.sops > .env
    @echo "✓ .env decrypted"

# Encrypt .env → .env.sops (requires .sops.yaml with your age public key)
encrypt:
    sops -e --input-type dotenv --output-type dotenv .env > .env.sops
    @echo "✓ .env.sops encrypted — safe to commit"

# Edit encrypted secrets in-place (sops handles decrypt/re-encrypt)
secrets:
    sops --input-type dotenv --output-type dotenv .env.sops

# Deploy: decrypt + start/update stack
deploy: decrypt
    docker compose up -d
    @echo "✓ Stack deployed"

# Update: pull latest images + redeploy
update: decrypt
    docker compose pull
    docker compose up -d
    @echo "✓ Stack updated"

# Show running containers
status:
    docker compose ps

# Show live logs (all containers)
logs:
    docker compose logs -f

# Show logs for a specific service: just log sonarr
log service:
    docker compose logs -f {{service}}

# Stop the stack
stop:
    docker compose down
    @echo "✓ Stack stopped"

# Hard reset: stop + remove volumes (WARNING: destroys config!)
reset:
    @echo "WARNING: This will destroy all container config data!"
    @read -p "Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
    docker compose down -v

# Pull latest code + redeploy (run on arr-box after git pull)
pull-deploy:
    git pull
    just deploy
