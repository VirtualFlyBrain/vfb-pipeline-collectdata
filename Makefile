test: 
	
# Building docker image
VERSION = "v0.0.6" 
IM=matentzn/vfb-pipeline-collectdata
PW=neo4j/neo
OUTDIR=/data/pipeline2

docker-build:
	@docker build --no-cache -t $(IM):$(VERSION) . \
	&& docker tag $(IM):$(VERSION) $(IM):latest
	
docker-build-use-cache:
	@docker build -t $(IM):$(VERSION) . \
	&& docker tag $(IM):$(VERSION) $(IM):latest

docker-run:
	docker run --volume $(OUTDIR):/out --env=KBpassword=$(PW) $(IM)

docker-clean:
	docker kill $(IM) || echo not running ;
	docker rm $(IM) || echo not made 

docker-publish-no-build:
	@docker push $(IM):$(VERSION) \
	&& docker push $(IM):latest
	
docker-publish: docker-build-use-cache
	@docker push $(IM):$(VERSION) \
	&& docker push $(IM):latest