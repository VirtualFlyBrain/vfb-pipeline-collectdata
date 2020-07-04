FROM python:3.6

VOLUME /logs
VOLUME /out

ENV WORKSPACE=/opt/VFB
ENV VOLUMEDATA=/out

# ENV CHUNK_SIZE=1000
# ENV PING_SLEEP=120s
# ENV BUILD_OUTPUT=${WORKSPACE}/build.out

ENV PATH "/opt/VFB/:/opt/VFB/shacl/bin:$PATH"

ENV KBserver=http://192.168.0.1:7474
ENV KBuser=neo4j
ENV KBpassword=password

ENV GITBRANCH=kbold2new

RUN pip3 install wheel requests psycopg2 pandas base36

RUN apt-get -qq update || apt-get -qq update && \
apt-get -qq -y install git curl wget default-jdk pigz maven libpq-dev python-dev tree gawk

RUN mkdir $WORKSPACE

###### ROBOT ######
ENV ROBOT v1.6.0
ENV ROBOT_ARGS -Xmx20G
ARG ROBOT_JAR=https://github.com/ontodev/robot/releases/download/$ROBOT/robot.jar
ENV ROBOT_JAR ${ROBOT_JAR}
RUN wget $ROBOT_JAR -O $WORKSPACE/robot.jar && \
    wget https://raw.githubusercontent.com/ontodev/robot/$ROBOT/bin/robot -O $WORKSPACE/robot && \
    chmod +x $WORKSPACE/robot && chmod +x $WORKSPACE/robot.jar

###### SHACL ######
ENV SHACL_VERSION 1.3.2
ARG SHACL_ZIP=https://repo1.maven.org/maven2/org/topbraid/shacl/$SHACL_VERSION/shacl-$SHACL_VERSION-bin.zip
ENV SHACL_ZIP ${SHACL_ZIP}
RUN wget $SHACL_ZIP -O $WORKSPACE/shacl.zip && \
    unzip $WORKSPACE/shacl.zip -d $WORKSPACE && \
    mv $WORKSPACE/shacl-$SHACL_VERSION $WORKSPACE/shacl && \
    rm $WORKSPACE/shacl.zip && chmod +x $WORKSPACE/shacl/bin/shaclvalidate.sh && chmod +x $WORKSPACE/shacl/bin/shaclinfer.sh

RUN ls -l $WORKSPACE/shacl

###### VFB Neo4j Python Libraries ########
ENV PYTHONPATH=${WORKSPACE}/VFB_neo4j/src/
RUN cd "${WORKSPACE}" && git clone --quiet https://github.com/VirtualFlyBrain/VFB_neo4j.git && tree ${WORKSPACE}

###### Copy pipeline files ########
COPY process.sh $WORKSPACE/process.sh
RUN chmod +x $WORKSPACE/process.sh
COPY vfb*.txt $WORKSPACE/
COPY /sparql $WORKSPACE/sparql
COPY /shacl $WORKSPACE/shacl

CMD ["/opt/VFB/process.sh"]
