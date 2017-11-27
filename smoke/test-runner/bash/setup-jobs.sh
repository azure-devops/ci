#!/bin/bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.
#===============================================================================
#          FILE:  setup-jobs.sh
# 
#   DESCRIPTION:  Create Jenkins jobs from XML definitions and trigger the build of the jobs.
# 
#       CREATED: 11/14/2017 07:36:53 AM UTC
#===============================================================================

set -x

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME="$(basename $0)"
source "$SCRIPT_DIR/lib.sh"

export JENKINS_URL="http://localhost:8080/"
export JENKINS_USERNAME="admin"

for f in $SCRIPT_DIR/../jobs/*.xml; do
    name=$(basename "$f")
    name="${name%.*}"
    "$SCRIPT_DIR/run-cli-command.sh" -c "create-job $name" <"$f"
    "$SCRIPT_DIR/run-cli-command.sh" -c "build $name"
done


