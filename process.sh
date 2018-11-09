#!/bin/bash

echo "** Collecting Data **"

echo 'START' >> ${WORKSPACE}/tick.out
## tail -f ${WORKSPACE}/tick.out >&1 &>&1

cd ${WORKSPACE}/VFB_neo4j
git pull origin master
git checkout ${GITBRANCH}
git pull

cd ${WORKSPACE}

mkdir /tmp/vfb_fullontologies
mkdir /tmp/vfb_slices
mkdir /tmp/vfb_download

echo 'Downloading relevant ontologies... '
wget -N -P /tmp/vfb_download -i vfb_fullontologies.txt
wget -N -P /tmp/vfb_slices -i vfb_slices.txt


echo 'Exporting KB to OWL'
SCRIPTS=${WORKSPACE}/VFB_neo4j/src/uk/ac/ebi/vfb/neo4j/
ONT=/tmp/vfb_download/kb.owl
echo ''
echo -e "travis_fold:start:neo4j_kb_export"
echo '** Exporting KB to OWL **'
export BUILD_OUTPUT=${WORKSPACE}/KBValidate.out
${WORKSPACE}/runsilent.sh "python3 ${SCRIPTS}neo4j_kb_export.py ${KBserver} ${KBuser} ${KBpassword} ${ONT}"
cp $BUILD_OUTPUT /logs/
egrep 'Exception|Error|error|exception|warning' $BUILD_OUTPUT
echo -e "travis_fold:end:neo4j_kb_export"

echo 'Copy all OWL files to output directory..'
cp /tmp/vfb_download/*.owl /out

echo 'Creating slices for external ontologies: Extracting seeds'
cd /tmp/vfb_download
for i in *.owl; do
    [ -f "$i" ] || break
    seedfile=$i"_terms.txt"
    echo "Processing: "$i
    if [ "$i" == "kb.owl" ]; then
      grep -Eo '(http://purl.obolibrary.org/)[^[:space:]"]+' $i | sort | uniq > $seedfile
      # This is slightly hacky, but ROBOT is too slow on the KB, probably because it has to fire up the SPARQL engine
    else 
      ${WORKSPACE}/robot query -f csv -i $i --query ${WORKSPACE}/terms.sparql $seedfile
    fi
done

cat *_terms.txt | sort | uniq > /out/seed.txt


echo 'Creating slices for external ontologies: Extracting modules'
cd /tmp/vfb_slices
for i in *.owl; do
    [ -f "$i" ] || break
    echo "Processing: "$i
    mod=$i"_module.owl"
    ${WORKSPACE}/robot extract -i $i -T /out/seed.txt --method BOT -o $mod
    cp $mod /out
done

echo 'Converting all OWL files to gzipped TTL'
cd /out
for i in *.owl; do
    [ -f "$i" ] || break
    echo "Processing: "$i
    ${WORKSPACE}/robot convert --input $i --output $i".ttl"
done

gzip -f *.ttl
