#!/bin/bash

set -e

echo "process started"
cd $WORKSPACE
if $VALIDATE; then 
	echo "Start validation"
	if $VALIDATESHEX; then
		SHEXCP="target/shexjava-core-$SHEX_VERSION.jar:"`cat cp.txt`
		java -cp $SHEXCP fr.inria.lille.shexjava.commandLine.Validate -s shex/kb.shex -d test.ttl
	fi
	if $VALIDATESHACL; then
		shaclvalidate.sh -datafile $VOLUMEDATA/test.ttl -shapesfile $WORKSPACE/shacl/kb.shacl > $VOLUMEDATA/validation.txt
	fi

echo "done"
