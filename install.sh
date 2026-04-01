#!/usr/bin/env bash

set -e

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="gity"

echo "Installing Gity..."

mkdir -p "$INSTALL_DIR"

if [ -f "./gity.sh" ]; then
    cp ./gity.sh "$INSTALL_DIR/$SCRIPT_NAME"
else
    curl -sSL "https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/gity.sh" -o "$INSTALL_DIR/$SCRIPT_NAME"
fi

chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

echo "Success! Installed to $INSTALL_DIR/$SCRIPT_NAME"
echo ""
echo "Please ensure $INSTALL_DIR is in your PATH."
echo "You can now run: gity"
