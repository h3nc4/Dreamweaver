FROM debian:testing

RUN useradd -m h3nc4

RUN apt-get update && \
	apt-get install -y sudo git

RUN echo "h3nc4 ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/h3nc4

USER h3nc4

WORKDIR /home/h3nc4/dreamweaver
