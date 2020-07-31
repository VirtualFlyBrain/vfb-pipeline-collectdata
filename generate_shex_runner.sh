#!/bin/bash

set -e

echo "Generating shex runner"
WORSKPACE=~/pipeline/vfb-pipeline-collectdata
SHEX_VERSION=1.1
cd $WORSKPACE 
git clone https://github.com/iovka/shex-java.git
cd shex-java/shex
mvn clean package
mvn dependency:build-classpath -Dmdep.includeScope=runtime -Dmdep.outputFile=cp.txt
echo "done generating shex runner"
