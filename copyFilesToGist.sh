#!/bin/bash

GIST_DIR=$1

if [ -z "$GIST_DIR" ]; then
  echo "No target directory supplied"
else
  sed 's/\.\.\/master\//https:\/\/github.com\/vossim\/dashing-jira-burndown\/raw\/master\//g' README.md > $GIST_DIR/README.md
  cp LICENSE $GIST_DIR
  cp jobs/* $GIST_DIR
  cp widgets/jira_burndown/* $GIST_DIR
fi
