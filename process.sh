#!/bin/bash

echo "** Collecting Data **"

echo 'START' >> ${WORKSPACE}/tick.out
## tail -f ${WORKSPACE}/tick.out >&1 &>&1

cd ${WORKSPACE}/VFB_neo4j
git pull origin master
git checkout ${GITBRANCH}
git pull

cd ${WORKSPACE}

echo 'Downloading VFB.owl... '
wget -O /out/vfb.owl.gz ${VFBOWLGZ}
yes | gunzip /out/vfb.owl.gz

ls -l /out
echo ''
SCRIPTS=${WORKSPACE}/VFB_neo4j/src/uk/ac/ebi/vfb/neo4j/
ONT=/out/kb.owl
echo ''
echo -e "travis_fold:start:neo4j_kb_export"
echo '** Transform old KB according to new schema **'
export BUILD_OUTPUT=${WORKSPACE}/KBValidate.out
${WORKSPACE}/runsilent.sh "python3 ${SCRIPTS}neo4j_kb_export.py ${KBserver} ${KBuser} ${KBpassword} ${ONT}"
cp $BUILD_OUTPUT /logs/
egrep 'Exception|Error|error|exception|warning' $BUILD_OUTPUT
echo -e "travis_fold:end:neo4j_kb_export"

cd /out

# The following for loop writes the load commands into the RDF4J setup script
for i in *.owl; do
    [ -f "$i" ] || break

    ${WORKSPACE}/robot convert --input $i --output $i".ttl"
done

gzip -f *.ttl
