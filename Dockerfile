ARG BASE_IMAGE=opensuse/leap

FROM golang:1.14 as build
ARG USER="SUSE CFCIBot"
ARG EMAIL=ci-ci-bot@suse.de

ARG KUBECTL_VERSION=v1.18.2
ARG HELM_VERSION=3.0.3
ARG CREDHUB_VERSION=2.0.0
ARG KUBECTL_ARCH=linux-amd64
ARG JQ_VERSION=1.6
ARG KUBECTL_CHECKSUM=ed36f49e19d8e0a98add7f10f981feda8e59d32a8cb41a3ac6abdfb2491b3b5b3b6e0b00087525aa8473ed07c0e8a171ad43f311ab041dcc40f72b36fa78af95
ENV CGO_ENABLED=0
WORKDIR /brains
RUN git config --global user.name ${USER}
RUN git config --global user.email ${EMAIL}

RUN mkdir -p /brains/bin

RUN wget -O kubectl.tar.gz https://dl.k8s.io/$KUBECTL_VERSION/kubernetes-client-$KUBECTL_ARCH.tar.gz && \
    echo "$KUBECTL_CHECKSUM kubectl.tar.gz" | sha512sum --check --status && \
    tar xvf kubectl.tar.gz -C / && \
    cp -f /kubernetes/client/bin/kubectl /brains/bin/

RUN wget https://github.com/cloudfoundry-incubator/credhub-cli/releases/download/$CREDHUB_VERSION/credhub-linux-$CREDHUB_VERSION.tgz && \
    tar xfz ./credhub-linux-$CREDHUB_VERSION.tgz && \
    cp ./credhub /brains/bin/

RUN wget https://s3.amazonaws.com/cf-opensusefs2/cf-plugin-backup/cf-plugin-backup-1.0.4%2b18.gd7c4ed9.linux-amd64.tgz -O cf-plugin-backup.linux-amd64.tgz && \
    tar xfz ./cf-plugin-backup.linux-amd64.tgz && \
    cp ./cf-plugin-backup/cf-plugin-backup /brains/bin/

RUN wget 'https://packages.cloudfoundry.org/stable?release=linux64-binary&version=6.42.0&source=github-rel' -O cf-cli-amd64.tgz && \
    tar xfz ./cf-cli-amd64.tgz  && \
    cp ./cf /brains/bin/

RUN curl -L https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz | tar zx --strip-components 1 -C "/brains/bin/"
RUN curl -LO https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64 && mv jq-linux64 /brains/bin/jq && chmod +x /brains/bin/jq

ENV GOPATH=/brains
ADD . /brains
RUN  go install -ldflags="-X main.version=0.0.0" github.com/SUSE/testbrain
RUN  go install github.com/docker/distribution/cmd/registry
RUN  go install /brains/src/acceptance-tests-brain/test-resources/docker-uploader

FROM $BASE_IMAGE
RUN mkdir -p /brains/acceptance-tests-brain
RUN mkdir -p /brains/cf-acceptance-tests
RUN zypper in -y ruby mariadb-client redis zip unzip curl
COPY --from=build /brains/run.sh /bin/
RUN chmod +x /bin/run.sh
COPY --from=build /brains/bin/* /bin/
COPY --from=build /brains/src/* /brains/acceptance-tests-brain/
RUN mv /brains/acceptance-tests-brain/cloudfoundry/cf-acceptance-tests/ /brains/
RUN cf install-plugin -f /bin/cf-plugin-backup

ENTRYPOINT ["/bin/run.sh"]
