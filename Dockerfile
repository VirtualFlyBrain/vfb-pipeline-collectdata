FROM python:3.6

VOLUME /logs
VOLUME /out

ENV WORKSPACE=/opt/VFB
ENV VOLUMEDATA=/out
ENV VFB_OWL_VERSION=Current
ENV VFBOWLGZ=https://github.com/VirtualFlyBrain/VFB_owl/blob/master/src/owl/vfb.owl.gz?raw=true
ENV CHUNK_SIZE=1000
ENV PING_SLEEP=120s
ENV BUILD_OUTPUT=${WORKSPACE}/build.out

RUN pip3 install wheel
RUN pip3 install requests
RUN pip3 install psycopg2
RUN pip3 install pandas

RUN apt-get -qq update || apt-get -qq update && \
apt-get -qq -y install git curl wget default-jdk pigz maven libpq-dev python-dev tree gawk

ENV KBserver=http://192.168.0.1:7474

ENV KBuser=neo4j

ENV KBpassword=password

ENV GITBRANCH=kbold2new

ENV RUNSILENT=https://raw.githubusercontent.com/VirtualFlyBrain/pipeline/master/runsilent.sh

RUN wget -P ${WORKSPACE} ${RUNSILENT}

RUN wget -P ${WORKSPACE} https://raw.githubusercontent.com/ontodev/robot/master/bin/robot

RUN wget -P ${WORKSPACE} https://github.com/ontodev/robot/releases/download/v1.0.0/robot.jar

COPY process.sh /opt/VFB/process.sh

RUN chmod +x /opt/VFB/*.sh

RUN chmod +x /opt/VFB/robot

RUN echo -e "travis_fold:start:processLoad" && \
cd "${WORKSPACE}" && \
echo '** Git checkout VFB_neo4j **' && \
git clone --quiet https://github.com/VirtualFlyBrain/VFB_neo4j.git

RUN cd ${WORKSPACE} && \
echo -e "travis_fold:end:processLoad"

RUN echo -e "travis_fold:start:sourcetree" && tree ${WORKSPACE} && echo -e "travis_fold:end:sourcetree"

ENV PYTHONPATH=${WORKSPACE}/VFB_neo4j/src/

CMD ["/opt/VFB/process.sh"]
