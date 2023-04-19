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
echo '** in full: **'
while read -r url_pattern; do
    echo $url_pattern
    if [[ "$url_pattern" == *"*"* ]]; then
        base_url="${url_pattern%/*}/"
        pattern="${url_pattern##*/}"
        page=$(curl -s "$base_url")
        file_list=$(echo "$page" | grep -o "href=\"$pattern\"" | sed 's/^href="//;s/"$//')

        for file in $file_list; do
            file_url="${base_url}${file}"
            wget -N -P "$VFB_DOWNLOAD_DIR" "$file_url"
        done
    else
        wget -N -P "$VFB_DOWNLOAD_DIR" "$url_pattern"
    fi
done < vfb_fullontologies.txt

echo '** in slices: **'
while read -r url_pattern; do
    echo $url_pattern
    if [[ "$url_pattern" == *"*"* ]]; then
        base_url="${url_pattern%/*}/"
        pattern="${url_pattern##*/}"
        page=$(curl -s "$base_url")
        file_list=$(echo "$page" | grep -o "href=\"$pattern\"" | sed 's/^href="//;s/"$//')

        for file in $file_list; do
            file_url="${base_url}${file}"
            wget -N -P "$VFB_SLICES_DIR" "$file_url"
        done
    else
        wget -N -P "$VFB_SLICES_DIR" "$url_pattern"
    fi
done < vfb_slices.txt

echo "VFBTIME:"
date

echo '** Exporting KB to OWL **'
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (c) REMOVE c.label_rdfs RETURN c"}]}' >> ${VFB_DEBUG_DIR}/neo4j_remove_rdfs_label.txt
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (p) WHERE EXISTS(p.label) SET p.label_rdfs=[] + p.label"}]}' >> ${VFB_DEBUG_DIR}/neo4j_change_label_to_rdfs.txt
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (n:Entity) WHERE exists(n.block) DETACH DELETE n"}]}' >> ${VFB_DEBUG_DIR}/neo4j_change_label_to_rdfs.txt
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH ()-[r]-() WHERE exists(r.block) DELETE r"}]}' >> ${VFB_DEBUG_DIR}/neo4j_change_label_to_rdfs.txt

python3 ${SCRIPTS}neo4j_kb_export.py ${KBserver} ${KBuser} ${KBpassword} ${KB_FILE}

echo "VFBTIME:"
date


if [ "$REMOVE_EMBARGOED_DATA" = true ]; then
  echo '** Deleting embargoed data.. **'
  robot query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/embargoed_datasets_${STAGING}.sparql ${VFB_FINAL}/embargoed_datasets.txt

  echo 'First 10 embargoed datasets: '
  head -10 ${VFB_FINAL}/embargoed_datasets.txt

  echo 'Embargoed datasets: select_embargoed_channels'
  robot query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/select_embargoed_channels_${STAGING}.sparql ${VFB_DOWNLOAD_DIR}/embargoed_channels.txt
  echo 'Embargoed datasets: select_embargoed_images'
  robot query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/select_embargoed_images_${STAGING}.sparql ${VFB_DOWNLOAD_DIR}/embargoed_images.txt
  echo 'Embargoed datasets: select_embargoed_datasets'
  robot query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/select_embargoed_datasets_${STAGING}.sparql ${VFB_DOWNLOAD_DIR}/embargoed_datasets.txt

  echo 'Embargoed data: Removing everything'
  cat ${VFB_DOWNLOAD_DIR}/embargoed_channels.txt ${VFB_DOWNLOAD_DIR}/embargoed_images.txt ${VFB_DOWNLOAD_DIR}/embargoed_datasets.txt | sort | uniq > ${VFB_FINAL}/remove_embargoed.txt
  robot remove --input ${KB_FILE} --term-file ${VFB_FINAL}/remove_embargoed.txt --output ${KB_FILE}.tmp.owl
  mv ${KB_FILE}.tmp.owl ${KB_FILE}

  echo "VFBTIME:"
  date
fi

echo 'Merging all input ontologies.'
cd $VFB_DOWNLOAD_DIR
for i in *.owl; do
    [ -f "$i" ] || break
    echo "Merging: "$i
    ${WORKSPACE}/robot merge --input $i -o "$i.tmp.owl" && mv "$i.tmp.owl" "$i"
done
for i in *.owl.gz; do
    [ -f "$i" ] || break
    echo "Merging: "$i
    ${WORKSPACE}/robot merge --input $i -o "$i.tmp.owl" && mv "$i.tmp.owl" "$i.owl"
done

echo 'Copy all OWL files to output directory..'
cp $VFB_DOWNLOAD_DIR/*.owl $VFB_FINAL
cp $VFB_DOWNLOAD_DIR/*.owl $VFB_DEBUG_DIR

echo 'Creating slices for external ontologies: Extracting seeds.'
cd $VFB_DOWNLOAD_DIR
for i in *.owl; do
    [ -f "$i" ] || break
    seedfile=$i"_terms.txt"
    echo "Extracting seed from: "$i
    ${WORKSPACE}/robot query -f csv -i $i --query ${SPARQL_DIR}/terms.sparql $seedfile
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

# echo 'Create debugging files for pipeline..'
# cd $VFB_DEBUG_DIR
# robot merge --inputs "*.owl" remove --axioms "disjoint" --output $VFB_FINAL_DEBUG/vfb-dependencies-merged.owl
# robot merge -i kb.owl -i fbbt.owl --output $VFB_FINAL_DEBUG/vfb-kb_fbbt.owl
# robot reason --reasoner ELK --input $VFB_FINAL_DEBUG/vfb-dependencies-merged.owl --output $VFB_FINAL_DEBUG/vfb-dependencies-reasoned.owl


if [ "$REMOVE_UNSAT_CAUSING_AXIOMS" = true ]; then
  echo 'Removing all possible sources for unsatisfiable classes and inconsistency...'
  cd $VFB_FINAL
  for i in *.owl; do
      [ -f "$i" ] || break
      echo "Processing: "$i
      ${WORKSPACE}/robot remove --input $i --term "http://www.w3.org/2002/07/owl#Nothing" --axioms logical --preserve-structure false \
        remove --axioms "${UNSAT_AXIOM_TYPES}" --preserve-structure false -o "$i.tmp.owl"
      mv "$i.tmp.owl" "$i"
  done
fi

echo 'Converting all OWL files to gzipped TTL'
cd $VFB_FINAL
for i in *.owl; do
    [ -f "$i" ] || break
    echo "Processing: "$i
    ${WORKSPACE}/robot convert --input $i -f ttl --output $i".ttl"
    if [ "$i" == "kb.owl" ] && [ "$VALIDATE" = true ]; then
      if [ "$VALIDATESHACL" = true ]; then
        echo "Validating KB with SHACL.."
        shaclvalidate.sh -datafile "$i.ttl" -shapesfile $WORKSPACE/shacl/kb.shacl > $VFB_FINAL/validation.txt
      fi
    fi
done


gzip -f *.ttl

echo "End: vfb-pipeline-collectdata"
echo "VFBTIME:"
date
echo "process complete"
