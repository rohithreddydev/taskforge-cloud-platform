#!/bin/bash

echo "🔧 Fixing missing yaml dependency..."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
rm -rf node_modules package-lock.json
npm cache clean --force

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
npm install

# Explicitly install yaml if needed
echo -e "${YELLOW}Ensuring yaml is installed...${NC}"
npm install --save-dev yaml@2.8.2

# Verify
echo -e "${YELLOW}Verifying installation...${NC}"
if npm list yaml | grep -q "yaml@2.8.2"; then
    echo -e "${GREEN}✅ yaml@2.8.2 installed successfully${NC}"
else
    echo "❌ yaml installation failed"
    exit 1
fi

echo -e "${GREEN}✅ Fix complete!${NC}"
echo -e "${YELLOW}Now run:${NC}"
echo "  git add package.json package-lock.json"
echo "  git commit -m \"Regenerate lock file with yaml dependency\""
echo "  git push"
