# VERSION 1.10.0-2
# AUTHOR: Matthieu "Puckel_" Roisil
# DESCRIPTION: Basic Airflow container
# BUILD: docker build --rm -t puckel/docker-airflow .
# SOURCE: https://github.com/puckel/docker-airflow

FROM python:3.6-slim AS puckel_airflow
LABEL maintainer="Puckel_"

# Never prompts the user for choices on installation/configuration of packages
ENV DEBIAN_FRONTEND noninteractive
ENV TERM linux

# Airflow
ARG AIRFLOW_VERSION=1.10.0
ARG AIRFLOW_HOME=/usr/local/airflow
ENV AIRFLOW_GPL_UNIDECODE yes

# Define en_US.
ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_MESSAGES en_US.UTF-8

RUN set -ex \
    && buildDeps=' \
        python3-dev \
        libkrb5-dev \
        libsasl2-dev \
        libssl-dev \
        libffi-dev \
        libblas-dev \
        liblapack-dev \
        libpq-dev \
        git \
    ' \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        $buildDeps \
        build-essential \
        python3-pip \
        python3-requests \
        mysql-client \
        mysql-server \
        default-libmysqlclient-dev \
        apt-utils \
        curl \
        rsync \
        netcat \
        locales \
    && sed -i 's/^# en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/g' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && useradd -ms /bin/bash -d ${AIRFLOW_HOME} airflow \
    && pip install -U pip setuptools wheel \
    && pip install Cython \
    && pip install pytz \
    && pip install pyOpenSSL \
    && pip install ndg-httpsclient \
    && pip install pyasn1 \
    && pip install apache-airflow[crypto,celery,postgres,hive,jdbc,mysql]==$AIRFLOW_VERSION \
    && pip install 'celery[redis]>=4.1.1,<4.2.0' \
    && apt-get purge --auto-remove -yqq $buildDeps \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

COPY script/entrypoint.sh /entrypoint.sh
COPY config/airflow.cfg ${AIRFLOW_HOME}/airflow.cfg

RUN chown -R airflow: ${AIRFLOW_HOME}

EXPOSE 8080 5555 8793

USER airflow
WORKDIR ${AIRFLOW_HOME}
ENTRYPOINT ["/entrypoint.sh"]
CMD ["webserver"]   # set default arg for entrypoint

FROM puckel_airflow AS airflow_package
LABEL MAINTAINER=zhongjiajie955@hotmail.com
USER root

RUN set -ex \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        # todo have to test if it need or not
        libsasl2-dev \
        # https://github.com/dropbox/PyHive/issues/161
        libsasl2-modules \
    # pypi from tsinghua to speed pip install
    # && mkdir -p ~/.config/pip \
    # && echo "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple" >> ~/.config/pip/pip.conf \
    \
    && pip install mysqlclient cx_Oracle paramiko\
    # todo airflow 1.10 change pyhive to connect hiveserver2
    # import thrift_sasl usually fail, impyla need specific versions libraries
    # thrift<=0.10.0 thrift_sasl<=0.2.1 sasl<=0.2.1 impyla<=0.14.0
    # https://github.com/cloudera/impyla/issues/268
    # https://stackoverflow.com/questions/46573180/impyla-0-14-0-error-tsocket-object-has-no-attribute-isopen
    && pip install thrift==0.9.3 thrift_sasl==0.2.1 \
    # && (pip uninstall -y thrift_sasl thrift sasl six && pip install thrift_sasl==0.2.1 thrift==0.10.0) \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

FROM airflow_package AS beeline
LABEL MAINTAINER=zhongjiajie955@hotmail.com

# beeline
ENV BEELINE_HOME /usr/local/beeline
ENV HIVE_VERSION 1.1.0
COPY beeline $BEELINE_HOME

RUN set -ex \
    # install beeline
    # https://github.com/sutoiku/docker-beeline
    && mkdir -p $BEELINE_HOME/lib $BEELINE_HOME/conf \
    && echo "$HIVE_VERSION" > $BEELINE_HOME/lib/hive.version \
    && curl -L http://central.maven.org/maven2/org/apache/hive/hive-beeline/$HIVE_VERSION/hive-beeline-$HIVE_VERSION.jar -o $BEELINE_HOME/lib/hive-beeline-$HIVE_VERSION.jar \
    && curl -L http://central.maven.org/maven2/org/apache/hive/hive-jdbc/$HIVE_VERSION/hive-jdbc-$HIVE_VERSION-standalone.jar -o $BEELINE_HOME/lib/hive-jdbc-$HIVE_VERSION-standalone.jar \
    && curl -L http://central.maven.org/maven2/commons-cli/commons-cli/1.2/commons-cli-1.2.jar -o $BEELINE_HOME/lib/commons-cli-1.2.jar \
    && curl -L http://central.maven.org/maven2/org/apache/hadoop/hadoop-common/2.7.3/hadoop-common-2.7.3.jar -o $BEELINE_HOME/lib/hadoop-common-2.7.3.jar \
    && curl -L http://central.maven.org/maven2/jline/jline/2.12/jline-2.12.jar -o $BEELINE_HOME/lib/jline-2.12.jar \
    && curl -L http://central.maven.org/maven2/net/sf/supercsv/super-csv/2.2.0/super-csv-2.2.0.jar -o $BEELINE_HOME/lib/super-csv-2.2.0.jar \
    && ln -s $BEELINE_HOME/beeline /usr/bin/beeline \
    && chmod +x /usr/bin/beeline

FROM beeline AS java
LABEL MAINTAINER=zhongjiajie955@hotmail.com

# Java
ENV JAVA_HOME /usr/lib/jvm/java-8-oracle

FROM java AS oracle_client
LABEL MAINTAINER=zhongjiajie955@hotmail.com

# Oracle client base
ENV ORACLE_INSTANTCLIENT_MAJOR 12.2
ENV ORACLE_INSTANTCLIENT_VERSION 12.2.0.1.0
ENV ORACLE /usr/lib/oracle
ENV ORACLE_HOME $ORACLE/$ORACLE_INSTANTCLIENT_MAJOR/client64

RUN set -ex \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        # 这个是干什么用的 是 oracle client 么
        libaio1 \
        alien \
        gcc \
    # install oracle db basic
    # todo last to change baidu yun pan
    && curl -L https://github.com/sergeymakinen/docker-oracle-instant-client/raw/assets/oracle-instantclient$ORACLE_INSTANTCLIENT_MAJOR-basic-$ORACLE_INSTANTCLIENT_VERSION-1.x86_64.rpm -o /oracle-basic.rpm \
    && curl -L https://github.com/sergeymakinen/docker-oracle-instant-client/raw/assets/oracle-instantclient$ORACLE_INSTANTCLIENT_MAJOR-devel-$ORACLE_INSTANTCLIENT_VERSION-1.x86_64.rpm -o /oracle-devel.rpm \
    && alien -i /oracle*.rpm \
    && echo "$ORACLE_HOME/lib/" > /etc/ld.so.conf.d/oracle.conf \
    && ldconfig \
    \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base \
        /oracle*.rpm
        # /var/cache/oracle-jdk8-installer

FROM oracle_client AS dev
LABEL MAINTAINER=zhongjiajie955@hotmail.com

RUN set -ex \
    && testDeps=' \
        iputils-ping \
        telnet \
        wget \
        vim \
        sudo \
        ssh \
    ' \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        $testDeps \
    # change USER airflow password and make USER to sudo group
    && echo "airflow:airflow" | chpasswd \
    && adduser airflow sudo \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

USER airflow
