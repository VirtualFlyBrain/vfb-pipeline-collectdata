# vfb-pipeline-collectdata

The **data-collection stage** of the [Virtual Fly Brain](https://virtualflybrain.org) (VFB) pipeline.

VFB is a public knowledge base of *Drosophila* (fruit fly) neuroanatomy, integrating brain
images, neurons, anatomy ontologies and gene-expression data. This repository is a Dockerised
batch job that **gathers all the raw data VFB needs and turns it into a set of clean, validated
OWL/TTL ontology files** ready for the next stage of the pipeline (loading into the Neo4j graph /
triplestore that powers the website).

The entire process is orchestrated by [`process.sh`](process.sh), which runs as the container's
entrypoint.

## What the pipeline does

1. **Download source ontologies** in parallel, from two configuration lists:
   - [`vfb_fullontologies.txt`](vfb_fullontologies.txt) — ontologies pulled in *whole* (fly anatomy
     `fbbt`, development `fbdv`, and VFB-specific ontologies such as drivers, neurotransmitters,
     scRNAseq genes, neuron functions, etc.).
   - [`vfb_slices.txt`](vfb_slices.txt) — large external ontologies (`GO`, `SO`, `RO`, `DPO`,
     `NBO`, `FBbi`) that are **not** taken whole; only a relevant module is later extracted (step 5).

   URL entries may contain a `*` wildcard, in which case the matching files are discovered by
   scraping the directory listing (used for `VFB_scRNAseq_FBlc*`, `VFB_EPseq_PR*`).

2. **Remove embargoed / blocked data** from the live VFB knowledge base *before* export, by running
   Cypher statements against the Neo4j server (`KBserver`). This deletes non-production datasets and
   blocked images, channels and anatomical individuals, so private/embargoed data never leaves.

3. **Export the knowledge base to OWL** using `neo4j_kb_export.py` from the
   [`VFB_neo4j`](https://github.com/VirtualFlyBrain/VFB_neo4j) repo (cloned into the image), then
   `robot merge` the exported parts and relations into a single `kb.owl`.

4. **Merge** each downloaded ontology in place with ROBOT (resolving imports).

5. **Slice external ontologies** — collect the set of terms actually used across all data
   ([`sparql/terms.sparql`](sparql/terms.sparql)) into `seed.txt`, then use
   `robot extract --method BOT` to pull just the needed module out of each large ontology in
   `vfb_slices.txt`. This keeps the final output small.

6. **Strip axioms that can cause logical inconsistency** (when `REMOVE_UNSAT_CAUSING_AXIOMS=true`):
   removes `owl:Nothing`-entailing logical axioms plus the axiom types listed in
   `UNSAT_AXIOM_TYPES` (`DisjointClasses`, `DisjointUnion`, `DifferentIndividuals`,
   `DisjointObjectProperties`, `DisjointDataProperties`). Files matching an entry in
   [`vfb_skip_axiom_checks.txt`](vfb_skip_axiom_checks.txt) are exempted (entries may be glob
   patterns, e.g. `VFB_EPseq_PR*`).

7. **Validate and convert** — convert every OWL file to Turtle, validate `kb.owl` against the SHACL
   shapes in [`shacl/kb.shacl`](shacl/kb.shacl), then gzip everything.

The output, written to the container's `/out` volume, is a collection of gzipped `.ttl` ontology
files plus validation reports — the input for the downstream VFB pipeline that builds the graph
database.

## Validation

| Mechanism | Status | Target | Behaviour |
|---|---|---|---|
| SHACL (`shaclvalidate.sh` + [`shacl/kb.shacl`](shacl/kb.shacl)) | **Active** | `kb.owl` only | Writes a report to `/out/validation_kb.owl.txt`. The current shape (`vfb:DataSetCountShape`) is a smoke test: it asserts that at least one instance of `FBbt_00050095` (*adult ALad1 lineage clone*) exists — i.e. that the KB export is populated rather than empty/broken. (Despite the shape's name, the target is this specific anatomy class, not a dataset.) |
| Axiom removal (`robot remove`) | Active (`REMOVE_UNSAT_CAUSING_AXIOMS`) | all `.owl` | Proactively strips unsat-causing axioms rather than reporting them. |
| ShEx ([`shex/kb.shex`](shex/kb.shex)) | Dormant | — | A schema exists, but the ShEx validator build is commented out in the `Dockerfile` and it is not invoked by `process.sh`. |

> Note: the SHACL step is **non-blocking** — its output is redirected to a report file and does not
> fail the build on violations.

## Configuration

Behaviour is controlled by environment variables (defaults set in the [`Dockerfile`](Dockerfile)):

| Variable | Default | Purpose |
|---|---|---|
| `KBserver` | `http://192.168.0.1:7474` | Neo4j knowledge-base server URL |
| `KBuser` / `KBpassword` | `neo4j` / `password` | Neo4j credentials |
| `STAGING` | `prod` | Staging mode; in `dev`, datasets are only embargoed if not staged |
| `VALIDATE` / `VALIDATESHACL` / `VALIDATESHEX` | `true` | Validation switches (only SHACL is wired up) |
| `REMOVE_EMBARGOED_DATA` | `true` | Remove embargoed data |
| `REMOVE_UNSAT_CAUSING_AXIOMS` | `true` | Strip unsatisfiability-causing axioms |
| `UNSAT_AXIOM_TYPES` | see Dockerfile | Which axiom types to strip |
| `GITBRANCH` | `master` | Branch of `VFB_neo4j` to use |
| `ROBOT_JAVA_ARGS` | — | JVM args for ROBOT (e.g. `-Xmx11G`) |

### Configuration files

| File | Purpose |
|---|---|
| [`vfb_fullontologies.txt`](vfb_fullontologies.txt) | Ontologies downloaded in full |
| [`vfb_slices.txt`](vfb_slices.txt) | External ontologies from which only a module is extracted |
| [`vfb_skip_axiom_checks.txt`](vfb_skip_axiom_checks.txt) | Files (glob patterns allowed) exempted from axiom stripping |
| [`sparql/`](sparql) | SPARQL/Cypher queries for term extraction and embargo/block removal |
| [`shacl/kb.shacl`](shacl/kb.shacl), [`shex/kb.shex`](shex/kb.shex) | Validation schemas |

## Building and running

The [`Makefile`](Makefile) wraps the common Docker commands:

```bash
# Build the image
make docker-build            # no cache
make docker-build-use-cache  # with cache

# Run the pipeline (writes to OUTDIR, default ~/data/pipeline2)
make docker-run

# Publish to Docker Hub
make docker-publish
```

You can override `make` variables inline, e.g.:

```bash
make docker-run OUTDIR=/path/to/out PW=neo4j/secret KB=http://my-kb:7474
```

The image mounts two volumes: `/out` (output data) and `/logs`.

## Continuous integration

[`.github/workflows/docker-image.yml`](.github/workflows/docker-image.yml) builds the image on every
push and publishes it to Docker Hub as `virtualflybrain/vfb-pipeline-collectdata`, tagged with the
branch name.

## Tools used

- [ROBOT](http://robot.obolibrary.org/) — OWL/OBO manipulation (merge, extract, remove, convert)
- [TopBraid SHACL](https://github.com/TopQuadrant/shacl) — SHACL validation
- [`VFB_neo4j`](https://github.com/VirtualFlyBrain/VFB_neo4j) — knowledge-base export scripts
