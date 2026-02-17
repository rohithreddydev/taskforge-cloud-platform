#!/bin/bash

echo "🔧 Fixing import paths..."

# Check if app.js exists
if [ -f "src/app.js" ]; then
    echo "Found src/app.js"
    
    # Update imports in test files
    sed -i '' 's/from '\''\.\/App'\''/from '\''\.\/app'\''/g' src/App.test.js
    sed -i '' 's/from '\''\.\/App'\''/from '\''\.\/app'\''/g' src/index.js
    
    echo "✅ Updated imports to use ./app"
fi

# Check if App.js exists
if [ -f "src/App.js" ]; then
    echo "Found src/App.js"
    
    # Update imports in test files
    sed -i '' 's/from '\''\.\/app'\''/from '\''\.\/App'\''/g' src/App.test.js
    sed -i '' 's/from '\''\.\/app'\''/from '\''\.\/App'\''/g' src/index.js
    
    echo "✅ Updated imports to use ./App"
fi

# Run tests to verify
npm test -- --watchAll=false

echo "✅ Fix complete!"
