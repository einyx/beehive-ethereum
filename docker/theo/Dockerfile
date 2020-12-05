
FROM debian:stable-slim

RUN mkdir /opt/theo

ADD . /opt/theo

WORKDIR /opt/theo


RUN apt update && apt -y install python3 python3-pip libssl-dev


RUN pip3 install -r requirements.txt
