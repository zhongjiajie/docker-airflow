# VERSION 1.9.0-1
# AUTHOR: Matthieu "Puckel_" Roisil
# DESCRIPTION: Basic Airflow container
# BUILD: docker build --rm -t puckel/docker-airflow .
# SOURCE: https://github.com/puckel/docker-airflow

FROM python:3.6-slim
MAINTAINER Puckel_

# Never prompts the user for choices on installation/configuration of packages
ENV DEBIAN_FRONTEND noninteractive
ENV TERM linux

# Airflow
ARG AIRFLOW_VERSION=1.9.0
ARG AIRFLOW_HOME=/usr/local/airflow

# Define en_US.
ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_MESSAGES en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Oracle
ENV ORACLE_INSTANTCLIENT_MAJOR 12.2
ENV ORACLE_INSTANTCLIENT_VERSION 12.2.0.1.0
ENV ORACLE /usr/lib/oracle
ENV ORACLE_HOME $ORACLE/$ORACLE_INSTANTCLIENT_MAJOR/client64

# Java home
ENV JAVA_HOME /usr/lib/jvm/java-8-oracle

RUN set -ex \
    && buildDeps=' \
        python3-dev \
        libkrb5-dev \
        libssl-dev \
        libffi-dev \
        build-essential \
        libblas-dev \
        liblapack-dev \
        libpq-dev \
        git \
        alien \
        gcc \
    ' \
    # only need in dev env
    && testDeps=' \
        iputils-ping \
        telnet \
        wget \
        vim \
        sudo \
    ' \
    # add Oracle java ppa and key
    && echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee /etc/apt/sources.list.d/webupd8team-java.list \
    && echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EEA14886 \
    \
    && apt-get update -yqq \
    # install oracle java
    && mkdir -p /usr/share/man/man1/ \
    && echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections \
    && echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections \
    && apt-get install -y oracle-java8-installer oracle-java8-set-default \
    \
    && apt-get install -yqq --no-install-recommends \
        $buildDeps \
        $testDeps \
        python3-pip \
        python3-requests \
        apt-utils \
        curl \
        rsync \
        netcat \
        locales \
        libsasl2-dev \
        libmysqlclient-dev \
        libaio1 \
    # install oracle db basic
    # todo last to change baidu yun pan
    && curl -L https://github.com/sergeymakinen/docker-oracle-instant-client/raw/assets/oracle-instantclient$ORACLE_INSTANTCLIENT_MAJOR-basic-$ORACLE_INSTANTCLIENT_VERSION-1.x86_64.rpm -o /oracle-basic.rpm \
    && curl -L https://github.com/sergeymakinen/docker-oracle-instant-client/raw/assets/oracle-instantclient$ORACLE_INSTANTCLIENT_MAJOR-devel-$ORACLE_INSTANTCLIENT_VERSION-1.x86_64.rpm -o /oracle-devel.rpm \
    && alien -i /oracle*.rpm \
    && echo "$ORACLE_HOME/lib/" > /etc/ld.so.conf.d/oracle.conf \
    && ldconfig \
    \
    # pypi tsinghua
    # && mkdir -p ~/.config/pip \
    # && echo "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple" >> ~/.config/pip/pip.conf \
    \
    && sed -i 's/^# en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/g' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && useradd -ms /bin/bash -d ${AIRFLOW_HOME} airflow \
    && echo "airflow:airflow" | chpasswd \
    && adduser airflow sudo \
    && python -m pip install -U pip setuptools wheel \
    && pip install Cython \
    && pip install pytz \
    && pip install pyOpenSSL \
    && pip install ndg-httpsclient \
    && pip install pyasn1 \
    && pip install apache-airflow[crypto,celery,postgres,hive,jdbc]==$AIRFLOW_VERSION \
    && pip install celery[redis]==4.0.2 \
    && pip install thrift_sasl mysqlclient cx_Oracle \
    ## import thrift_sasl usually fail
    && (python -c "import thrift_sasl" || pip uninstall -y thrift_sasl thrift sasl six && pip install thrift_sasl) \
    # && apt-get purge --auto-remove -yqq $buildDeps \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base \
        /oracle*.rpm \
        /var/cache/oracle-jdk8-installer

COPY script/entrypoint.sh /entrypoint.sh
COPY config/airflow.cfg ${AIRFLOW_HOME}/airflow.cfg

RUN chown -R airflow: ${AIRFLOW_HOME}

EXPOSE 8080 5555 8793

USER airflow
WORKDIR ${AIRFLOW_HOME}
ENTRYPOINT ["/entrypoint.sh"]