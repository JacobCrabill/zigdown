#!/bin/bash
SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))
HTML_DIR=$(realpath ${SCRIPT_DIR}/../test/html/)

cd ${HTML_DIR}
python3 -m http.server # Then navigate to localhost:8000:demo.html
