# DOCKER-VERSION 0.3.4
FROM        perl:latest
MAINTAINER  Robert Norris rob@eatenbyagrue.org

RUN curl -L http://cpanmin.us | perl - App::cpanminus
RUN cpanm Carton Starlet

RUN cachebuster=0811527 git clone http://github.com/robn/hopscotch.git
RUN cd hopscotch && carton install --deployment

EXPOSE 8080

WORKDIR hopscotch
CMD carton exec plackup -S Starlet --port 8080 ./hopscotch
