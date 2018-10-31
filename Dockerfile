######################################
## r-base
######################################
FROM nvidia/cuda:9.0-cudnn7-devel-ubuntu16.04 as r-basics

# https://hub.docker.com/r/nvidia/cuda/

LABEL maintainer="Jared P. Lander <packages@jaredlander.com>"

ARG R_VERSION
ARG BUILD_DATE
ENV DEBIAN_FRONTEND=noninteractive \
    R_VERSION=${R_VERSION:-3.5.1-1xenial}

## Prepare R installation from 
RUN sh -c 'echo "deb http://cloud.r-project.org/bin/linux/ubuntu xenial-cran35/" >> /etc/apt/sources.list' \
    && gpg --keyserver keyserver.ubuntu.com --recv-key E084DAB9 \
    && gpg -a --export E084DAB9 | apt-key add - \
    # install needed linux libraries
    && apt-get update \
    && apt-get upgrade -y -q \
    && apt-get install -y --no-install-recommends \
    libxml2-dev \
    libxt-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    imagemagick \
    tzdata \
    locales \
    && locale-gen en_US.UTF-8 \
    # configure time zone
    && ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime \
    && dpkg-reconfigure --frontend noninteractive tzdata \
    && unset -v DEBIAN_FRONTEND \
    # install R
    && apt-get update \
    && apt-get upgrade -y -q \
    && apt-get install -y --no-install-recommends \
    r-base=3.5.1-1xenial \
    r-base-dev=3.5.1-1xenial

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

CMD [ "R" ]

######################################
## Tidyverse
######################################
FROM r-basics as r-tidyverse

RUN R -e "install.packages('tidyverse')"

######################################
## Stan
######################################
FROM r-basics as r-stan

RUN R -e "install.packages('rstanarm', repos = 'https://cloud.r-project.org/', dependencies=TRUE)"

######################################
## Tidymodels
######################################
FROM r-basics as r-tidymodels

RUN R -e "install.packages('tidymodels')"

######################################
## Time series
######################################
FROM r-basics as r-timeseries

RUN R -e "install.packages(c('forecast', 'prophet', 'xts', 'tsibble', 'dygraphs', 'prophet', 'fable', 'hts', 'thief'))"

######################################
## xgboost
######################################
FROM r-basics as r-xgboost

RUN apt-get update \
    && apt-get upgrade -y -q \
    && apt-get install -y --no-install-recommends \
    git \
    wget \
    # instal DiagrammeR for viewing trees
    && R -e "install.packages(c('DiagrammeR'))" \
    # get cmake 
    && wget -O makebuilder.sh https://cmake.org/files/v3.12/cmake-3.12.3-Linux-x86_64.sh \
    && sh ./makebuilder.sh --skip-license --prefix=/usr/local/ \
    && git clone --recursive https://github.com/dmlc/xgboost \
    && mkdir xgboost/build

WORKDIR xgboost/build
# make xgboost with GPU
RUN cmake .. -DUSE_CUDA=ON -DR_LIB=ON \ 
    && make install -j
WORKDIR /

######################################
## catboost
######################################
FROM r-basics as r-catboost

RUN R -e "install.packages('devtools')" -e "devtools::install_url('https://github.com/catboost/catboost/releases/download/v0.10.3/catboost-R-Linux-0.10.3.tgz', args = c('--no-multiarch'))"

######################################
## glmnet
######################################
FROM r-basics as r-glmnet

RUN R -e "install.packages('glmnet')"

######################################
## network
######################################
FROM r-basics as r-network

RUN R -e "install.packages(c('igraph', 'threejs'))"

######################################
## tidytext
######################################
FROM r-basics as r-tidytext

RUN R -e "install.packages(c('tidytext'))"

######################################
## optimization
######################################
FROM r-basics as r-optim

RUN R -e "install.packages(c('ROI', 'ROI.plugin.glpk', 'ompr', 'ompr.roi', 'quadprog', 'optimization'))"

######################################
## extras
######################################
FROM r-basics as r-extras

RUN R -e "install.packages(c('coefplot', 'dygraphs', 'here', 'threejs', 'leaflet', 'leaflet.extras', 'flexdashboard', 'crosstalk', 'DT'))"

######################################
## RStudio
######################################
FROM r-basics as rstudio

ARG RSTUDIO_VERSION
ENV PATH=/usr/lib/rstudio-server/bin:$PATH

# get wget and gdebi
## Download and install RStudio server & dependencies
## Attempts to get detect latest version, otherwise falls back to version given in $VER
## Symlink pandoc, pandoc-citeproc so they are available system-wide
# copied from https://github.com/rocker-org/rocker-versioned/tree/master/rstudio/3.5.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    file \
    git \
    libapparmor1 \
    libcurl4-openssl-dev \
    libedit2 \
    libssl-dev \
    lsb-release \
    psmisc \
    python-setuptools \
    sudo \
    wget \
    # get necessary libs
    && wget -O libssl1.0.0.deb http://ftp.debian.org/debian/pool/main/o/openssl/libssl1.0.0_1.0.1t-1+deb8u8_amd64.deb \
    && dpkg -i libssl1.0.0.deb \
    && rm libssl1.0.0.deb\ 
    # get rstudio server
    && RSTUDIO_LATEST=$(wget --no-check-certificate -qO- https://s3.amazonaws.com/rstudio-server/current.ver) \
    && [ -z "$RSTUDIO_VERSION" ] && RSTUDIO_VERSION=$RSTUDIO_LATEST || true \
    && wget -q http://download2.rstudio.org/rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
    && dpkg -i rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
    && rm rstudio-server-*-amd64.deb \
    ## Symlink pandoc & standard pandoc templates for use system-wide
    && ln -s /usr/lib/rstudio-server/bin/pandoc/pandoc /usr/local/bin \
    && ln -s /usr/lib/rstudio-server/bin/pandoc/pandoc-citeproc /usr/local/bin \
    && git clone https://github.com/jgm/pandoc-templates \
    && mkdir -p /opt/pandoc/templates \
    && cp -r pandoc-templates*/* /opt/pandoc/templates && rm -rf pandoc-templates* \
    && mkdir /root/.pandoc && ln -s /opt/pandoc/templates /root/.pandoc/templates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/ \
    ## RStudio wants an /etc/R, will populate from $R_HOME/etc
    && mkdir -p /etc/R \
    ## Write config files in $R_HOME/etc
    && echo '\n\
    \n# Configure httr to perform out-of-band authentication if HTTR_LOCALHOST \
    \n# is not set since a redirect to localhost may not work depending upon \
    \n# where this Docker container is running. \
    \nif(is.na(Sys.getenv("HTTR_LOCALHOST", unset=NA))) { \
    \n  options(httr_oob_default = TRUE) \
    \n}' >> /usr/lib/R/etc/Rprofile.site \
    && echo "PATH=${PATH}" >> /usr/lib/R/etc/Renviron \
    ## Need to configure non-root user for RStudio
    && useradd rstudio \
    && echo "rstudio:rstudio" | chpasswd \
    && mkdir /home/rstudio \
    && chown rstudio:rstudio /home/rstudio \
    && addgroup rstudio staff \
    ## Prevent rstudio from deciding to use /usr/bin/R if a user apt-get installs a package
    && echo 'rsession-which-r=/usr/bin/R' >> /etc/rstudio/rserver.conf \
    ## use more robust file locking to avoid errors when using shared volumes:
    && echo 'lock-type=advisory' >> /etc/rstudio/file-locks \
    ## configure git not to request password each time
    && git config --system credential.helper 'cache --timeout=3600' \
    && git config --system push.default simple \
    ## Set up S6 init system
    && wget -P /tmp/ https://github.com/just-containers/s6-overlay/releases/download/v1.11.0.1/s6-overlay-amd64.tar.gz \
    && tar xzf /tmp/s6-overlay-amd64.tar.gz -C / \
    && mkdir -p /etc/services.d/rstudio \
    && echo '#!/usr/bin/with-contenv bash \
    \n exec /usr/lib/rstudio-server/bin/rserver --server-daemonize 0' \
    > /etc/services.d/rstudio/run \
    && echo '#!/bin/bash \
    \n rstudio-server stop' \
    > /etc/services.d/rstudio/finish

COPY userconf.sh /etc/cont-init.d/userconf

## running with "-e ADD=shiny" adds shiny server
COPY add_shiny.sh /etc/cont-init.d/add

COPY pam-helper.sh /usr/lib/rstudio-server/bin/pam-helper

COPY user-settings /home/rstudio/.rstudio/monitored/user-settings/
# No chown will cause "RStudio Initalization Error"
# "Error occurred during the transmission"; RStudio will not load.
RUN chown -R rstudio:rstudio /home/rstudio/.rstudio

EXPOSE 8787

CMD ["/init"]

######################################
## ML
######################################
FROM rstudio as r-ml

COPY --from=r-tidyverse /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-stan /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-tidymodels /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-timeseries /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-xgboost /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-catboost /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-glmnet /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-tidytext /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-network /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-optim /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/
COPY --from=r-extras /usr/local/lib/R/site-library/ /usr/local/lib/R/site-library/

######################################
## Tensorflow
######################################
# This must be installed on top of the r-ml image because the underlying libraries
# (TensorFlow, Keras) must onto the image.

# install pip and then install virtualenv from pip then tensorflow related stuff
RUN apt-get update \
    && apt-get upgrade -y -q \
    && apt-get install -y --no-install-recommends \
    python3-dev \
    python3-pip \
    && pip3 install --upgrade pip \
    && hash -r \
    && pip3 install --upgrade setuptools \
    && pip3 install --upgrade tensorflow-gpu keras \
    # install the tensorflow package and then use that to install keras
    && R -e "install.packages(c('tensorflow', 'keras'))" 
#-e "keras::install_keras(tensorflow = 'gpu')"
