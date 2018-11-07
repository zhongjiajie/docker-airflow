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

ARG AIRFLOW_VERSION=1.10.0

# initial user script
COPY script/create_user.py /create_user.py

# use USER root to apt-get
USER root

RUN set -ex \
    # gcc libkrb5-dev build-essential for apache-airflow[kerberos]
    # todo python3-dev unknown
    && buildDeps=' \
        build-essential \
        gcc \
    ' \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        # todo have to test if it need or not
        libsasl2-dev \
        # https://github.com/dropbox/PyHive/issues/161
        libsasl2-modules \
        $buildDeps \
    # see https://github.com/apache/incubator-airflow/blob/master/setup.py for more detail
    && pip install apache-airflow[password,ssh,oracle,hdfs,elasticsearch,docker,kubernetes]==$AIRFLOW_VERSION \
    # pip install apache-airflow[kerberos] failed, but need tarift_sasl to connect hive metadata
    && pip install 'thrift_sasl>=0.2.0' \
    # install ipython to use `from Ipython import embed; embed()` to debug easier
    && pip install ipython \
        hdfs \
        pyarrow \
    # && pip install apache-airflow[all]==$AIRFLOW_VERSION \
    # NOTE!! TO BE DELETE
    # todo airflow 1.10 change pyhive to connect hiveserver2
    # import thrift_sasl usually fail, impyla need specific versions libraries
    # thrift<=0.10.0 thrift_sasl<=0.2.1 sasl<=0.2.1 impyla<=0.14.0
    # https://github.com/cloudera/impyla/issues/268
    # https://stackoverflow.com/questions/46573180/impyla-0-14-0-error-tsocket-object-has-no-attribute-isopen
    # && pip install thrift==0.9.3 thrift_sasl==0.2.1 \
    # && (pip uninstall -y thrift_sasl thrift sasl six && pip install thrift_sasl==0.2.1 thrift==0.10.0) \
    \
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

FROM airflow_package AS beeline
LABEL MAINTAINER=zhongjiajie955@hotmail.com

# beeline
ENV BEELINE_HOME /usr/local/beeline
ENV HIVE_VERSION 1.1.0
COPY beeline $BEELINE_HOME

RUN set -ex \
    # install beeline
    # use https://github.com/sutoiku/docker-beeline as example
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

# use https://github.com/docker-library/openjdk/blob/master/8/jre/slim/Dockerfile as example
FROM beeline AS jre
LABEL MAINTAINER=zhongjiajie955@hotmail.com

ENV JAVA_HOME /docker-java-home/jre

# ENV JAVA_VERSION 8u151
# ENV JAVA_DEBIAN_VERSION 8u151-b12-1~deb9u1

# see https://bugs.debian.org/775775
# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
# ENV CA_CERTIFICATES_JAVA_VERSION 20170531+nmu1

RUN set -ex; \
	\
    # deal with slim variants not having man page directories (which causes "update-alternatives" to fail)
	if [ ! -d /usr/share/man/man1 ]; then \
		mkdir -p /usr/share/man/man1; \
	fi; \
	\
	apt-get update; \
	apt-get install -y \
		openjdk-8-jre-headless \
		ca-certificates-java \
	; \
	rm -rf /var/lib/apt/lists/*; \
	\
    # verify that "docker-java-home" returns what we expect
	[ "$(readlink -f "$JAVA_HOME")" = "$(docker-java-home)" ]; \
	\
    # update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
	update-alternatives --get-selections | awk -v home="$(readlink -f "$JAVA_HOME")" 'index($3, home) == 1 { $2 = "manual"; print | "update-alternatives --set-selections" }'; \
    # ... and verify that it actually worked for one of the alternatives we care about
	update-alternatives --query java | grep -q 'Status: manual'

FROM jre AS oracle_client
LABEL MAINTAINER=zhongjiajie955@hotmail.com

# Oracle client base
ENV ORACLE_INSTANTCLIENT_MAJOR 12.2
ENV ORACLE_INSTANTCLIENT_VERSION 12.2.0.1.0
ENV ORACLE /usr/lib/oracle
ENV ORACLE_HOME $ORACLE/$ORACLE_INSTANTCLIENT_MAJOR/client64

RUN set -ex \
    && buildDeps=' \
        alien \
        gcc \
    ' \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        $buildDeps \
        # is this for oracle client ?
        libaio1 \
    # install oracle db basic
    # todo last to change baidu yun pan
    && curl -L https://github.com/sergeymakinen/docker-oracle-instant-client/raw/assets/oracle-instantclient$ORACLE_INSTANTCLIENT_MAJOR-basic-$ORACLE_INSTANTCLIENT_VERSION-1.x86_64.rpm -o /oracle-basic.rpm \
    && curl -L https://github.com/sergeymakinen/docker-oracle-instant-client/raw/assets/oracle-instantclient$ORACLE_INSTANTCLIENT_MAJOR-devel-$ORACLE_INSTANTCLIENT_VERSION-1.x86_64.rpm -o /oracle-devel.rpm \
    && alien -i /oracle*.rpm \
    && echo "$ORACLE_HOME/lib/" > /etc/ld.so.conf.d/oracle.conf \
    && ldconfig \
    \
    && apt-get purge --auto-remove -yqq $buildDeps \
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

FROM oracle_client AS pre_datax
LABEL MAINTAINER=zhongjiajie955@hotmail.com

# ensure local python is preferred over distribution python
ENV PATH /usr/local/bin:$PATH

# http://bugs.python.org/issue19846
# > At the moment, setting "LANG=C" on a Linux system *fundamentally breaks Python 3*, and that's not OK.
ENV LANG C.UTF-8
# https://github.com/docker-library/python/issues/147
ENV PYTHONIOENCODING UTF-8

# runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
		ca-certificates \
		netbase \
	&& rm -rf /var/lib/apt/lists/*

ENV GPG_KEY C01E1CAD5EA2C4F0B8E3571504C367C218ADD4FF
ENV PYTHON_VERSION 2.7.15

RUN set -ex \
	\
	&& savedAptMark="$(apt-mark showmanual)" \
	&& apt-get update && apt-get install -y --no-install-recommends \
		dpkg-dev \
		gcc \
		libbz2-dev \
		libc6-dev \
		libdb-dev \
		libgdbm-dev \
		libncursesw5-dev \
		libreadline-dev \
		libsqlite3-dev \
		libssl-dev \
		make \
		tk-dev \
		wget \
		xz-utils \
		zlib1g-dev \
# as of Stretch, "gpg" is no longer included by default
		$(command -v gpg > /dev/null || echo 'gnupg dirmngr') \
	\
	&& wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
	&& wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
	&& gpg --batch --verify python.tar.xz.asc python.tar.xz \
	&& { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
	&& rm -rf "$GNUPGHOME" python.tar.xz.asc \
	&& mkdir -p /usr/src/python \
	&& tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
	&& rm python.tar.xz \
	\
	&& cd /usr/src/python \
	&& gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
	&& ./configure \
		--build="$gnuArch" \
		--enable-shared \
		--enable-unicode=ucs4 \
	&& make -j "$(nproc)" \
	&& make install \
	&& ldconfig \
	\
	&& apt-mark auto '.*' > /dev/null \
	&& apt-mark manual $savedAptMark \
	&& find /usr/local -type f -executable -not \( -name '*tkinter*' \) -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	&& apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
	&& rm -rf /var/lib/apt/lists/* \
	\
	&& find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests \) \) \
			-o \
			\( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
		\) -exec rm -rf '{}' + \
	&& rm -rf /usr/src/python \
	\
	&& python2 --version

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 18.1

RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends wget; \
	\
	wget -O get-pip.py 'https://bootstrap.pypa.io/get-pip.py'; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	python get-pip.py \
		--disable-pip-version-check \
		--no-cache-dir \
		"pip==$PYTHON_PIP_VERSION" \
	; \
	pip --version; \
	\
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests \) \) \
			-o \
			\( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
		\) -exec rm -rf '{}' +; \
	rm -f get-pip.py; \
    # set default python and pip version 3.6
    rm /usr/local/bin/pip; \
    rm /usr/local/bin/python; \
    ln -s /usr/local/bin/pip3 /usr/local/bin/pip; \
    ln -s /usr/local/bin/python3 /usr/local/bin/python

FROM pre_datax AS datax
LABEL MAINTAINER=zhongjiajie955@hotmail.com

RUN set -ex \
    && curl -o /tmp/datax.tar.gz -LO http://datax-opensource.oss-cn-hangzhou.aliyuncs.com/datax.tar.gz \
    && tar -zxvf /tmp/datax.tar.gz -C / \
    && rm -rf /tmp/*

FROM datax AS dev
LABEL MAINTAINER=zhongjiajie955@hotmail.comn

RUN set -ex \
    && devDeps=' \
        iputils-ping \
        telnet \
        wget \
        vim \
        sudo \
        ssh \
        less \
    ' \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        $devDeps \
    # change USER airflow password and make USER to sudo group
    && echo "airflow:airflow" | chpasswd \
    && adduser airflow sudo \
    \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

# use user airflow to connect postgres
USER airflow
ENTRYPOINT ["/entrypoint.sh"]
CMD ["webserver"]
