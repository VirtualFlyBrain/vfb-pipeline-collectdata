#!/bin/bash

VFB_FULL_DIR=/tmp/vfb_fullontologies
VFB_SLICES_DIR=/tmp/vfb_slices
VFB_DOWNLOAD_DIR=/tmp/vfb_download
VFB_DEBUG_DIR=/tmp/vfb_debugging
VFB_FINAL=/out
VFB_FINAL_DEBUG=/out/vfb_debugging
SCRIPTS=${WORKSPACE}/VFB_neo4j/src/uk/ac/ebi/vfb/neo4j/
KB_FILE=$VFB_DOWNLOAD_DIR/kb.owl
VFB_NEO4J_SRC=${WORKSPACE}/VFB_neo4j

set -e

export ROBOT_JAVA_ARGS=${ROBOT_ARGS}

echo "** Collecting Data! **"

echo 'START' >> ${WORKSPACE}/tick.out
## tail -f ${WORKSPACE}/tick.out >&1 &>&1

echo "Updateing Neo4J VFB codebase"
cd $VFB_NEO4J_SRC
git pull origin master
git checkout ${GITBRANCH}
git pull

echo "Creating temporary directories.."
cd ${WORKSPACE}
ls -l $VFB_FINAL
rm -rf $VFB_FINAL/*
rm -rf $VFB_FULL_DIR $VFB_SLICES_DIR $VFB_DOWNLOAD_DIR $VFB_DEBUG_DIR $VFB_FINAL_DEBUG
mkdir $VFB_FULL_DIR $VFB_SLICES_DIR $VFB_DOWNLOAD_DIR $VFB_DEBUG_DIR $VFB_FINAL_DEBUG

echo 'Downloading relevant ontologies.. '
wget -N -P $VFB_DOWNLOAD_DIR -i vfb_fullontologies.txt
wget -N -P $VFB_SLICES_DIR -i vfb_slices.txt

echo '** Exporting KB to OWL **'
python3 ${SCRIPTS}neo4j_kb_export.py ${KBserver} ${KBuser} ${KBpassword} ${KB_FILE}

echo 'Copy all OWL files to output directory..'
cp $VFB_DOWNLOAD_DIR/*.owl $VFB_FINAL
cp $VFB_DOWNLOAD_DIR/*.owl $VFB_DEBUG_DIR

echo 'Creating slices for external ontologies: Extracting seeds'
cd $VFB_DOWNLOAD_DIR
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

cat *_terms.txt | sort | uniq > ${VFB_FINAL}/seed.txt

echo 'Creating slices for external ontologies: Extracting modules'
cd $VFB_SLICES_DIR
for i in *.owl; do
    [ -f "$i" ] || break
    echo "Processing: "$i
    mod=$i"_module.owl"
    ${WORKSPACE}/robot extract -i $i -T ${VFB_FINAL}/seed.txt --method BOT -o $mod
    cp $mod $VFB_FINAL
		cp $mod $VFB_DEBUG_DIR
done

echo 'Create debugging files for pipeline..'
cd $VFB_DEBUG_DIR
robot -vv merge --inputs "*.owl" remove --axioms "disjoint" --output $VFB_FINAL_DEBUG/vfb-dependencies-merged.owl
robot -vv reason --reasoner ELK --input $VFB_FINAL_DEBUG/vfb-dependencies-merged.owl --output $VFB_FINAL_DEBUG/vfb-dependencies-reasoned.owl

echo 'Converting all OWL files to gzipped TTL'
cd $VFB_FINAL
for i in *.owl; do
    [ -f "$i" ] || break
    echo "Processing: "$i
    ${WORKSPACE}/robot remove --input $i --axioms disjoint convert --output $i".ttl"
done

gzip -f *.ttl

echo "process complete"
