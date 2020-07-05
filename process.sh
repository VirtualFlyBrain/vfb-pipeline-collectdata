#!/bin/bash

set -e

echo "process started"
echo "Start: vfb-pipeline-collectdata"
echo "VFBTIME:"
date

VFB_FULL_DIR=/tmp/vfb_fullontologies
VFB_SLICES_DIR=/tmp/vfb_slices
VFB_DOWNLOAD_DIR=/tmp/vfb_download
VFB_DEBUG_DIR=/tmp/vfb_debugging
VFB_FINAL=/out
VFB_FINAL_DEBUG=/out/vfb_debugging
SCRIPTS=${WORKSPACE}/VFB_neo4j/src/uk/ac/ebi/vfb/neo4j/
SPARQL_DIR=${WORKSPACE}/sparql
SHACL_DIR=${WORKSPACE}/shacl
KB_FILE=$VFB_DOWNLOAD_DIR/kb.owl
VFB_NEO4J_SRC=${WORKSPACE}/VFB_neo4j


export ROBOT_JAVA_ARGS=${ROBOT_ARGS}

echo "** Collecting Data! **"

echo 'START' >> ${WORKSPACE}/tick.out
## tail -f ${WORKSPACE}/tick.out >&1 &>&1

echo "** Updateing Neo4J VFB codebase **"
cd $VFB_NEO4J_SRC
git pull origin master
git checkout ${GITBRANCH}
git pull

echo "** Creating temporary directories.. **"
cd ${WORKSPACE}
ls -l $VFB_FINAL
rm -rf $VFB_FINAL/*
rm -rf $VFB_FULL_DIR $VFB_SLICES_DIR $VFB_DOWNLOAD_DIR $VFB_DEBUG_DIR $VFB_FINAL_DEBUG
mkdir $VFB_FULL_DIR $VFB_SLICES_DIR $VFB_DOWNLOAD_DIR $VFB_DEBUG_DIR $VFB_FINAL_DEBUG

echo "VFBTIME:"
date

echo '** Downloading relevant ontologies.. **'
wget -N -P $VFB_DOWNLOAD_DIR -i vfb_fullontologies.txt
wget -N -P $VFB_SLICES_DIR -i vfb_slices.txt

echo "VFBTIME:"
date

echo '** Exporting KB to OWL **'
python3 ${SCRIPTS}neo4j_kb_export.py ${KBserver} ${KBuser} ${KBpassword} ${KB_FILE}

echo "VFBTIME:"
date

echo '** Deleting embargoes data.. **'
robot query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/embargoed_datasets.sparql ${VFB_FINAL}/embargoed_datasets.txt

echo 'Embargoed datasets: '
head -10 ${VFB_FINAL}/embargoed_datasets.txt

robot query -i ${KB_FILE} --update ${SPARQL_DIR}/delete_embargoed_channels.ru --output ${KB_FILE}.tmp.owl
mv ${KB_FILE}.tmp.owl ${KB_FILE}
robot query -i ${KB_FILE} --update ${SPARQL_DIR}/delete_embargoed_images.ru --output ${KB_FILE}.tmp.owl
mv ${KB_FILE}.tmp.owl ${KB_FILE}
robot query -i ${KB_FILE} --update ${SPARQL_DIR}/delete_embargoed_datasets.ru --output ${KB_FILE}.tmp.owl
mv ${KB_FILE}.tmp.owl ${KB_FILE}

echo "VFBTIME:"
date

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
      ${WORKSPACE}/robot query -f csv -i $i --query ${SPARQL_DIR}/terms.sparql $seedfile
    fi
done

cat *_terms.txt | sort | uniq > ${VFB_FINAL}/seed.txt

echo "VFBTIME:"
date

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

echo "VFBTIME:"
date

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
    if [ "$i" == "kb.owl" ]; then
      echo "Validating KB.."
      shaclvalidate.sh -datafile $i".ttl" -shapesfile $WORKSPACE/shacl/kb.shacl > $VFB_FINAL/validation.txt
    fi
done

gzip -f *.ttl

echo "End: vfb-pipeline-collectdata"
echo "VFBTIME:"
date
echo "process complete"