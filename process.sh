#!/bin/bash

set -e

echo "process started"
echo "Start: vfb-pipeline-collectdata"
echo "VFBTIME:"
date

# Define and export necessary variables
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

# Update Neo4J VFB codebase
echo "** Updating Neo4J VFB codebase **"
cd $VFB_NEO4J_SRC
git pull origin master
git checkout ${GITBRANCH}
git pull origin ${GITBRANCH}
pip install -r requirements.txt

# Create temporary directories
echo "** Creating temporary directories.. **"
cd ${WORKSPACE}
ls -l $VFB_FINAL
rm -rf $VFB_FINAL/*
rm -rf $VFB_FULL_DIR $VFB_SLICES_DIR $VFB_DOWNLOAD_DIR $VFB_DEBUG_DIR $VFB_FINAL_DEBUG
mkdir $VFB_FULL_DIR $VFB_SLICES_DIR $VFB_DOWNLOAD_DIR $VFB_DEBUG_DIR $VFB_FINAL_DEBUG

# Minimum acceptable size (bytes) for a downloaded ontology. Anything smaller is treated
# as a failed/empty download. The smallest real source ontology (VFBext) is ~89KB, so 10KB
# is a safe floor. Override by setting MIN_FILE_SIZE in the environment.
MIN_FILE_SIZE=${MIN_FILE_SIZE:-10240}

# Backgrounded ROBOT jobs don't trip 'set -e', so failures are collected here and checked
# after each parallel stage instead of being silently ignored. Written under the persisted
# /out debug dir so the log survives the run as an artifact.
export ROBOT_ERROR_LOG=$VFB_FINAL_DEBUG/collectdata_robot_errors.log
: > "$ROBOT_ERROR_LOG"

# Wrapper that runs ROBOT and records a message (rather than aborting) if it fails, so that
# a failure inside a backgrounded '&' job is not lost.
run_robot() {
    if ! "${WORKSPACE}/robot" "$@"; then
        echo "ROBOT FAILED: robot $*" >> "$ROBOT_ERROR_LOG"
        return 1
    fi
}
export -f run_robot

# Abort the pipeline if any run_robot call has failed. Pass a stage name for the message.
check_robot_errors() {
    if [ -s "$ROBOT_ERROR_LOG" ]; then
        echo "ERROR: ROBOT command failure(s) detected during stage: ${1:-unknown}" >&2
        cat "$ROBOT_ERROR_LOG" >&2
        exit 1
    fi
}

# Fail if any *.owl / *.owl.gz file in the given directory is smaller than MIN_FILE_SIZE.
check_file_sizes() {
    local dir="$1"
    local undersized=0
    local f sz
    for f in "$dir"/*.owl "$dir"/*.owl.gz; do
        [ -f "$f" ] || continue
        sz=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
        if [ "$sz" -lt "$MIN_FILE_SIZE" ]; then
            echo "ERROR: $f is only $sz bytes (< ${MIN_FILE_SIZE}); likely a failed/empty download" >&2
            undersized=1
        fi
    done
    return $undersized
}

echo "VFBTIME:"
date

echo '** Downloading relevant ontologies.. **'
echo '** in full: **'

# Process each URL pattern in parallel
while read -r url_pattern; do
    echo "Processing: $url_pattern"
    if [[ "$url_pattern" == *"*"* ]]; then
        base_url="${url_pattern%/*}/"
        pattern="${url_pattern##*/}"
        pattern="${pattern//\*/.*}"
        page=$(curl -s "$base_url")
        file_list=$(echo "$page" | grep -Eo "href=\"$pattern\"" | sed 's/^href="//;s/"$//')

        for file in $file_list; do
            file_url="${base_url}${file}"
            wget -N -P "$VFB_DOWNLOAD_DIR" "$file_url" &
        done
    else
        wget -N -P "$VFB_DOWNLOAD_DIR" "$url_pattern" &
    fi
done < vfb_fullontologies.txt


echo '** in slices: **'

# Process each URL pattern in slices in parallel
while read -r url_pattern; do
    echo "Processing: $url_pattern"
    if [[ "$url_pattern" == *"*"* ]]; then
        base_url="${url_pattern%/*}/"
        pattern="${url_pattern##*/}"
        pattern="${pattern//\*/.*}"
        page=$(curl -s "$base_url")
        file_list=$(echo "$page" | grep -Eo "href=\"$pattern\"" | sed 's/^href="//;s/"$//')

        for file in $file_list; do
            file_url="${base_url}${file}"
            wget -N -P "$VFB_SLICES_DIR" "$file_url" &
        done
    else
        wget -N -P "$VFB_SLICES_DIR" "$url_pattern" &
    fi
done < vfb_slices.txt



echo '** Downloads called. **'

echo "VFBTIME:"
date

echo '** Removing embargoed data directly from KB before export **'
echo 'Non Production Datasets:'
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (d:DataSet) WHERE not d.production=[True] OPTIONAL MATCH (d)<-[:has_source]-(i:Individual)OPTIONAL MATCH (i)<-[:depicts]-(ic:Individual) DETACH DELETE ic DETACH DELETE i DETACH DELETE d"}]}'
echo 'Blocked Images:'
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (:DataSet)<-[:has_source]-(i:Individual)<-[:depicts]-(ic:Individual)-[r:in_register_with]->(tc:Template) WHERE exists(r.block) DELETE r"}]}'
echo 'Blocked Channel:'
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (:DataSet)<-[:has_source]-(i:Individual)<-[:depicts]-(ic:Individual) WHERE exists(ic.block) DETACH DELETE ic"}]}'
echo 'Blocked Anatomical Individuals:'
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (:DataSet)<-[:has_source]-(i:Individual) WHERE exists(i.block) OPTIONAL MATCH (i)<-[:depicts]-(ic:Individual) DETACH DELETE ic DETACH DELETE i"}]}'
echo 'Clean Channels/Individuals with no Image:'
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (:DataSet)<-[:has_source]-(i:Individual)<-[:depicts]-(ic:Individual) WHERE NOT (ic)-[:in_register_with]->(:Template) DETACH DELETE ic DETACH DELETE i"}]}'

# echo "VFBTIME:"
# date

echo '** Exporting KB to OWL **'
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (c) REMOVE c.label_rdfs RETURN c.iri"}]}' >> ${VFB_DEBUG_DIR}/neo4j_remove_rdfs_label.txt
curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (p) WHERE EXISTS(p.label) SET p.label_rdfs=[] + p.label"}]}' >> ${VFB_DEBUG_DIR}/neo4j_change_label_to_rdfs.txt
# curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH (n:Entity) WHERE exists(n.block) DETACH DELETE n"}]}' >> ${VFB_DEBUG_DIR}/neo4j_change_label_to_rdfs.txt
# curl -i -X POST ${KBserver}/db/data/transaction/commit -u ${KBuser}:${KBpassword} -H 'Content-Type: application/json' -d '{"statements": [{"statement": "MATCH ()-[r]-() WHERE exists(r.block) DELETE r"}]}' >> ${VFB_DEBUG_DIR}/neo4j_change_label_to_rdfs.txt

echo "VFBTIME:"
date

echo '** Merging parts into KB_parts.OWL **'
cat ${SCRIPTS}neo4j_kb_export.py 
python3 ${SCRIPTS}neo4j_kb_export.py ${KBserver} ${KBuser} ${KBpassword} ${KB_FILE}
# Initialize the command
cmd="robot merge"

# Loop over kb_part_*.owl files and add them to the command with -i
for file in "$VFB_DOWNLOAD_DIR"/kb_part_*.owl; do
    cmd="$cmd -i $file"
done

# Add the output file argument
cmd="$cmd -o "$VFB_DOWNLOAD_DIR"/kb_part.owl"

# Execute the constructed command
echo $cmd
eval $cmd
rm -fv $VFB_DOWNLOAD_DIR/kb_part_*.owl

echo "VFBTIME:"
date
echo '** Merging rels into KB_rels.OWL **'

# Initialize the command
cmd="robot merge"

# Loop over kb_rels_*.owl files and add them to the command with -i
for file in "$VFB_DOWNLOAD_DIR"/kb_rels_*.owl; do
    cmd="$cmd -i $file"
done

# Add the output file argument
cmd="$cmd -o "$VFB_DOWNLOAD_DIR"/kb_rels.owl"

# Execute the constructed command
echo $cmd
eval $cmd
rm -fv $VFB_DOWNLOAD_DIR/kb_rels_*.owl
echo "VFBTIME:"
date

echo "VFBTIME:"
date
echo '** Merging into KB.OWL **'

# Initialize the command
cmd="robot merge"

# Loop over kb_*.owl files and add them to the command with -i
for file in "$VFB_DOWNLOAD_DIR"/kb_*.owl; do
    cmd="$cmd -i $file"
done

# Add the output file argument
cmd="$cmd -o ${KB_FILE}"

# Execute the constructed command
echo $cmd
eval $cmd
rm -fv $VFB_DOWNLOAD_DIR/kb_*.owl
echo "VFBTIME:"
date



# if [ "$REMOVE_EMBARGOED_DATA" = true ]; then
#   echo '** Deleting embargoed data.. **'
#   robot -vvv query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/embargoed_datasets_${STAGING}.sparql ${VFB_FINAL}/embargoed_datasets.txt

#   echo 'First 10 embargoed datasets: '
#   head -10 ${VFB_FINAL}/embargoed_datasets.txt

#   echo 'Embargoed datasets: select_embargoed_channels'
#   robot query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/select_embargoed_channels_${STAGING}.sparql ${VFB_DOWNLOAD_DIR}/embargoed_channels.txt &
#   echo 'Embargoed datasets: select_embargoed_images'
#   robot query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/select_embargoed_images_${STAGING}.sparql ${VFB_DOWNLOAD_DIR}/embargoed_images.txt &
#   echo 'Embargoed datasets: select_embargoed_datasets'
#   robot query -f csv -i ${KB_FILE} --query ${SPARQL_DIR}/select_embargoed_datasets_${STAGING}.sparql ${VFB_DOWNLOAD_DIR}/embargoed_datasets.txt &
#   wait
  
#   echo 'Embargoed data: Removing everything'
#   cat ${VFB_DOWNLOAD_DIR}/embargoed_channels.txt ${VFB_DOWNLOAD_DIR}/embargoed_images.txt ${VFB_DOWNLOAD_DIR}/embargoed_datasets.txt | sort | uniq > ${VFB_FINAL}/remove_embargoed.txt
#   robot remove --input ${KB_FILE} --term-file ${VFB_FINAL}/remove_embargoed.txt --output ${KB_FILE}.tmp.owl && mv ${KB_FILE}.tmp.owl ${KB_FILE} &
#   echo "VFBTIME:"
#   date
# fi

# Wait for all background jobs to complete
wait

echo '** Checking downloaded ontology file sizes.. **'
check_file_sizes "$VFB_DOWNLOAD_DIR" || { echo "Aborting: undersized/empty download(s) detected."; exit 1; }
check_file_sizes "$VFB_SLICES_DIR"   || { echo "Aborting: undersized/empty download(s) detected."; exit 1; }

echo 'Merging input ontologies that declare owl:imports (files with no imports are left as-is).'
cd $VFB_DOWNLOAD_DIR
for i in *.owl; do
    [ -f "$i" ] || break
    if grep -qE 'owl:imports|owl#imports' "$i"; then
        echo "Merging (has imports): $i"
        run_robot merge --input "$i" -o "$i.tmp.owl" && mv -v "$i.tmp.owl" "$i" && echo "Finished: $i" &
    else
        echo "Skipping merge (no imports): $i"
    fi
done
for i in *.owl.gz; do
    [ -f "$i" ] || break
    echo "Merging: $i"
    run_robot merge --input "$i" -o "$i.tmp.owl" && mv -v "$i.tmp.owl" "$i.owl" && echo "Finished: $i" &
done
wait
check_robot_errors "merge"

echo 'Copy all OWL files to output directory..'
cp $VFB_DOWNLOAD_DIR/*.owl $VFB_FINAL &
cp $VFB_DOWNLOAD_DIR/*.owl $VFB_DEBUG_DIR &

echo 'Creating slices for external ontologies: Extracting seeds.'
cd $VFB_DOWNLOAD_DIR
for i in *.owl; do
    [ -f "$i" ] || break
    seedfile=$i"_terms.txt"
    echo "Extracting seed from: $i to $seedfile"
    [ ! -f "$seedfile" ] || break
    run_robot query -f csv -i "$i" --query ${SPARQL_DIR}/terms.sparql "$seedfile"  && echo "Finished: $i" &
done
wait
check_robot_errors "seed extraction"

cat *_terms.txt | sort | uniq > ${VFB_FINAL}/seed.txt

echo "VFBTIME:"
date

echo 'Creating slices for external ontologies: Extracting modules'
cd $VFB_SLICES_DIR
for i in *.owl; do
    [ -f "$i" ] || break
    echo "Processing: $i"
    mod=$i"_module.owl"
    run_robot extract -i "$i" -T ${VFB_FINAL}/seed.txt --method BOT -o "$mod" && cp "$mod" $VFB_FINAL && cp "$mod" $VFB_DEBUG_DIR && echo "Finished: $i" &
done

wait
check_robot_errors "module extraction"

# VFB uses 'is allele of' (GENO:0000408) more broadly than GENO's asserted domain
# (GENO:0000481 'genomic feature') allows, so strip that ObjectPropertyDomain axiom from
# the GENO module before it is loaded. Leaves the property declaration and all other axioms
# intact; a no-op if the module doesn't contain the axiom.
GENO_MODULE=geno.owl_module.owl
if [ -f "$GENO_MODULE" ]; then
    echo "Removing 'is allele of' (GENO:0000408) domain assertion from $GENO_MODULE"
    run_robot remove --input "$GENO_MODULE" \
        --term http://purl.obolibrary.org/obo/GENO_0000408 \
        --axioms ObjectPropertyDomain \
        --preserve-structure false \
        -o "$GENO_MODULE.tmp.owl" \
      && mv -v "$GENO_MODULE.tmp.owl" "$GENO_MODULE" \
      && cp "$GENO_MODULE" $VFB_FINAL \
      && cp "$GENO_MODULE" $VFB_DEBUG_DIR
    check_robot_errors "geno domain removal"
fi

echo "VFBTIME:"
date

# Uncomment the following block if debugging files are needed
# echo 'Create debugging files for pipeline..'
# cd $VFB_DEBUG_DIR
# robot merge --inputs "*.owl" remove --axioms "disjoint" --output $VFB_FINAL_DEBUG/vfb-dependencies-merged.owl
# robot merge -i kb.owl -i fbbt.owl --output $VFB_FINAL_DEBUG/vfb-kb_fbbt.owl
# robot reason --reasoner ELK --input $VFB_FINAL_DEBUG/vfb-dependencies-merged.owl --output $VFB_FINAL_DEBUG/vfb-dependencies-reasoned.owl

if [ "$REMOVE_UNSAT_CAUSING_AXIOMS" = true ]; then
  echo 'Removing all possible sources for unsatisfiable classes and inconsistency...'
  cd $VFB_FINAL

  # Define the function to process each OWL file
  process_owl_file() {
    local owl_file="$1"

    echo "Processing: $owl_file"

    # Check if the file should be skipped (entries may be glob patterns, e.g. VFB_EPseq_PR*)
    while read -r url_pattern; do
      [ -z "$url_pattern" ] && continue
      if [[ "$owl_file" == $url_pattern ]]; then
        echo "Skipping $owl_file"
        return
      fi
    done < ${WORKSPACE}/vfb_skip_axiom_checks.txt

    # Remove axioms
    for axiom_type in $UNSAT_AXIOM_TYPES; do
      echo "Removing $axiom_type axioms from $owl_file"
      if run_robot remove --input "$owl_file" --term "http://www.w3.org/2002/07/owl#Nothing" --axioms logical --preserve-structure false \
        remove --axioms $axiom_type --preserve-structure false -o "$owl_file.tmp.owl"; then
        mv "$owl_file.tmp.owl" "$owl_file"
      fi
    done
    echo "Finished: $owl_file"
  }

  # Export the function so it can be used in subshells
  export -f process_owl_file

  # Process each OWL file in parallel
  for i in *.owl; do
    [ -f "$i" ] || continue
    process_owl_file "$i" &
  done

  # Wait for all background jobs to complete
  wait
  check_robot_errors "axiom removal"
fi

# Function to handle conversion and validation
process_owl_file() {
    local owl_file="$1"
    local ttl_file="${owl_file%.owl}.ttl"

    echo "Processing: $owl_file"
    run_robot convert --check false --input "$owl_file" -f ttl --output "$ttl_file"

    # Perform validation if conditions are met
    if [ "$owl_file" == "kb.owl" ] && [ "$VALIDATE" = true ] && [ "$VALIDATESHACL" = true ]; then
        echo "Validating KB with SHACL for $ttl_file.."
        shaclvalidate.sh -datafile "$ttl_file" -shapesfile $WORKSPACE/shacl/kb.shacl > "$VFB_FINAL/validation_$owl_file.txt"
    fi

    # Gzip the TTL file after validation
    gzip -f "$ttl_file"
}

echo 'Converting all OWL files to gzipped TTL'
cd $VFB_FINAL
# Loop through each OWL file and process it in parallel
for owl_file in *.owl; do
    [ -f "$owl_file" ] || continue
    # Run the process in a subshell and put it in the background
    (process_owl_file "$owl_file") &
done

# Wait for all background processes to complete
wait
check_robot_errors "convert"

gzip -f *.ttl || :

echo "End: vfb-pipeline-collectdata"
echo "VFBTIME:"
date
echo "process complete"
