#!/bin/bash

echo "🔧 Fixing TypeScript version for react-scripts..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Current TypeScript version:${NC}"
npx tsc --version 2>/dev/null || echo "TypeScript not installed"

echo -e "\n${YELLOW}Cleaning up...${NC}"
rm -rf node_modules package-lock.json
npm cache clean --force

echo -e "\n${YELLOW}Installing correct TypeScript version (4.9.5)...${NC}"
npm install --save-dev --save-exact typescript@4.9.5

echo -e "\n${YELLOW}Installing all dependencies...${NC}"
npm install

echo -e "\n${GREEN}Verifying installation:${NC}"
if npm ls typescript | grep -q "typescript@4.9.5"; then
    echo -e "${GREEN}✅ TypeScript 4.9.5 installed correctly${NC}"
else
    echo -e "${RED}❌ TypeScript installation failed${NC}"
    exit 1
fi

echo -e "\n${GREEN}✅ Fix complete!${NC}"
echo -e "${YELLOW}Now run:${NC}"
echo "  git add package.json package-lock.json"
echo "  git commit -m \"Fix TypeScript version to 4.9.5ct-scripts compatibility\""
echo "  git push"
