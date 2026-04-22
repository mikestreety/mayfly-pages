# mayfly

Scripts for managing DDEV preview environments on [mayfly.live](https://mayfly.live).

## preview.sh

Run from your TYPO3 project root to trigger deploys locally without going through GitLab CI.

Auto-detects the project name from `.ddev/config.yaml`, the current git branch, and your SSH key.

### One-liners

```bash
# deploy (default)
bash <(curl -fsSL mayfly.live/preview.sh)

# stop
bash <(curl -fsSL mayfly.live/preview.sh) stop

# import database
cat dump.sql | bash <(curl -fsSL mayfly.live/preview.sh) import-db
DB_FILE=dump.sql.gz bash <(curl -fsSL mayfly.live/preview.sh) import-db

# export database
bash <(curl -fsSL mayfly.live/preview.sh) export-db > dump.sql
DB_FILE=dump.sql bash <(curl -fsSL mayfly.live/preview.sh) export-db
```

### Save locally

```bash
curl -fsSL mayfly.live/preview.sh -o preview.sh && chmod +x preview.sh

./preview.sh deploy
./preview.sh stop
cat dump.sql | ./preview.sh import-db
DB_FILE=dump.sql.gz ./preview.sh import-db
./preview.sh export-db > dump.sql
DB_FILE=dump.sql ./preview.sh export-db
```
