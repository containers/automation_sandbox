# stable/Containerfile
#
# This image can be used to create a container image
# capable of safely running nested containers.
# The podman version and all dependencies will
# be installed as listed in the nvra.txt file.

ARG BASE_REGISTRY="registry.fedoraproject.org"
ARG BASE_NAMESPACE="/"
ARG BASE_IMGNAME="fedora"
ARG BASE_TAG="40"  # Do not modify manually, run maintain_packages.sh instead.
# Must run maintain_packages.sh following any changes to the two values below.
ARG INST_PKGS="podman fuse-overlayfs openssh openssh-clients"
ARG EXCL_PKGS="container-selinux"

FROM scratch as newimage

FROM ${BASE_REGISTRY}${BASE_NAMESPACE}${BASE_IMGNAME}:${BASE_TAG} as installation
RUN dnf makecache
# The mainline "fedora" and "update" repositories unfortunately prune
# older packages as newer packages are released.  Fortunately, all
# packages seem to remain available on the Koji build system for many
# years into the future.  Unfortunately koji can only download one package
# at a time.
ADD nvra.txt /var/cache/dnf/
RUN dnf --assumeyes --nodocs install koji && \
    cd /var/cache/dnf && \
    grep -Ev '^($| +|#+)' ./nvra.txt | \
        while read rpm_name_components; do \
            rpmname=$(tr -d '[:blank:]' <<<"$rpm_name_components") && \
            koji download-build --rpm $rpmname; \
        done
RUN --mount=type=bind,from=newimage,src=/,dst=/mnt/,rw \
    set -x && \
    cd /var/cache/dnf && \
    rpm -ivh --excludedocs --root=/mnt/ *.rpm

FROM installation as final
# Note: rpm --setcaps... needed due to Fedora (base) image builds
#       failing to record shadow-utils capabilties properly
#       on /usr/bin/new{u,g}idmap to `cap_set{u,g}id=ep`.
#       Verify with `rpm -V shadow-utils` (should be blank)
#       and `getcap <filename>` commands.
#
#       The bind mount from the installation stage is necessary to guarantee build order.
RUN rpm --setcaps shadow-utils 2>/dev/null

# Prevent nested containers from accessing the user-namespace
# assigned by default to a rootless user of the (outer) container image.
RUN set -x && \
    useradd podman && \
    echo -e "podman:1:999\npodman:1001:64535" > /etc/subuid; \
    echo -e "podman:1:999\npodman:1001:64535" > /etc/subgid;

# Pre-configure reasonable defaults for executing nested containers.
ADD ./containers.conf /etc/containers/containers.conf
ADD ./podman-containers.conf /home/podman/.config/containers/containers.conf

RUN set -x && \
    mkdir -p /home/podman/.local/share/containers && \
    chown podman:podman -R /home/podman && \
    chmod 644 /etc/containers/containers.conf

# Copy & modify the defaults to provide reference if runtime changes needed.
# Changes here are required for running with fuse-overlay storage inside container.
RUN set -x && \
    sed -e 's|^#mount_program|mount_program|g' \
           -e '/additionalimage.*/a "/var/lib/shared",' \
           -e 's|^mountopt[[:space:]]*=.*$|mountopt = "nodev,fsync=0"|g' \
           /usr/share/containers/storage.conf \
           > /etc/containers/storage.conf

# Setup internal Podman to pass subscriptions down from host to internal container
RUN printf '/run/secrets/etc-pki-entitlement:/run/secrets/etc-pki-entitlement\n/run/secrets/rhsm:/run/secrets/rhsm\n' > /etc/containers/mounts.conf

# Note VOLUME options must always happen after the chown call above
# RUN commands can not modify existing volumes
VOLUME /var/lib/containers
VOLUME /home/podman/.local/share/containers

# FIXME: Why is this necessary?
RUN set -x && \
    mkdir -p /var/lib/shared/overlay-images \
             /var/lib/shared/overlay-layers \
             /var/lib/shared/vfs-images \
             /var/lib/shared/vfs-layers && \
    touch /var/lib/shared/overlay-images/images.lock && \
    touch /var/lib/shared/overlay-layers/layers.lock && \
    touch /var/lib/shared/vfs-images/images.lock && \
    touch /var/lib/shared/vfs-layers/layers.lock

# FIXME: Why is this necessary?
ENV _CONTAINERS_USERNS_CONFIGURED=""
