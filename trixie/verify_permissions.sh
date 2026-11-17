#!/bin/bash
# Antigravity QC - Permission Verifier
# Rules: 
# - root:root
# - 600
# - /etc/NetworkManager/system-connections/*

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

STATUS=0

echo "Starting Permission Audit..."

for file in /etc/NetworkManager/system-connections/*; do
    if [ -f "$file" ]; then
        PERMS=$(stat -c "%a" "$file")
        OWNER=$(stat -c "%U:%G" "$file")
        
        if [ "$PERMS" != "600" ]; then
            echo -e "${RED}[FAIL]${NC} $file has permissions $PERMS (Expected 600)"
            STATUS=1
            # Attempt Fix
            chmod 600 "$file"
            echo "       Fixed."
        fi
        
        if [ "$OWNER" != "root:root" ]; then
            echo -e "${RED}[FAIL]${NC} $file is owned by $OWNER (Expected root:root)"
            STATUS=1
             # Attempt Fix
            chown root:root "$file"
             echo "       Fixed."
        fi
    fi
done

if [ $STATUS -eq 0 ]; then
    echo -e "${GREEN}[PASS]${NC} All profiles secure."
else
    echo -e "${RED}[WARN]${NC} Issues found and fixed."
fi

exit $STATUS
