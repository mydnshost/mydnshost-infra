FROM ubuntu:xenial

RUN apt-get clean && apt-get update \
    && apt-get install -y cron php7.0-cli mysql-client netcat-openbsd wget curl bind9utils composer \
    && rm -rf /var/lib/apt/lists/*

RUN mkfifo --mode 0666 /var/log/cron.log

# make pam_loginuid.so optional for cron
# see https://github.com/docker/docker/issues/5663#issuecomment-42550548
RUN sed --regexp-extended --in-place \
    's/^session\s+required\s+pam_loginuid.so$/session optional pam_loginuid.so/' \
    /etc/pam.d/cron

COPY start-cron /usr/sbin

CMD ["/usr/sbin/start-cron"]
